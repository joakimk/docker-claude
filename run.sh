#!/bin/bash
set -euo pipefail

# Launch Claude Code in a hardened, firewalled container.
#
# Reads `docker-claude.config` from the project root (override with
# DOCKER_CLAUDE_CONFIG env var). Credentials are kept in a per-project
# `.docker-claude/` dir — log in once per project, persisted across runs.
#
# See docker-claude/README.md for full usage.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIG_FILE="${DOCKER_CLAUDE_CONFIG:-$PROJECT_DIR/docker-claude.config}"

# --- Defaults (all overridable via the config file) ---

# Image name for the Claude container.
IMAGE_NAME="docker-claude-$(basename "$PROJECT_DIR")"

# Base image that Claude layers on top of. Should include whatever
# toolchain the project needs. Either a public image (debian, python,
# rust, node, ...) or a locally-built project image (see
# BASE_IMAGE_CONTEXT below).
BASE_IMAGE="debian:bookworm-slim"

# If set, run.sh runs `docker build` against this path to produce
# BASE_IMAGE before building the Claude layer. Useful when BASE_IMAGE
# is a project-owned image (e.g. the one your Makefile already
# builds). Leave empty for public images.
BASE_IMAGE_CONTEXT=""

# Path (relative to BASE_IMAGE_CONTEXT) of the Dockerfile used to
# build the base image. Default `Dockerfile`.
BASE_IMAGE_DOCKERFILE="Dockerfile"

# Outbound allow-list (space-separated). Minimum is api.anthropic.com
# so Claude can talk to its API.
ALLOWED_DOMAINS="api.anthropic.com sentry.io"

# Prompt sent to Claude on launch when no CLI argument is passed.
CLAUDE_PROMPT=""

# Workspace mount. Default is the project dir → /workspace read-write.
WORKSPACE_MOUNT="$PROJECT_DIR:/workspace"
WORKSPACE_PATH="/workspace"

# Resource caps. Override via config if your project needs more.
MEMORY_LIMIT="8g"
PIDS_LIMIT="4096"
CPU_LIMIT=""  # empty = no explicit limit

# Extra arguments appended to `docker run` (array). Useful for
# project-specific mounts (e.g. data dirs) or env vars.
EXTRA_DOCKER_ARGS=()

# Allow a config file to populate these values. The config is plain
# bash; treat it as trusted project code.
if [ -f "$CONFIG_FILE" ]; then
    # shellcheck disable=SC1090
    source "$CONFIG_FILE"
else
    echo "warning: no $CONFIG_FILE found — using defaults" >&2
fi

# --- CLI arg parsing ---

REBUILD=""
PROMPT_FROM_CLI=""
for arg in "$@"; do
    case "$arg" in
        --rebuild) REBUILD="yes" ;;
        --help|-h)
            cat <<EOF
Usage: docker-claude/run.sh [--rebuild] ["prompt"]

  --rebuild    Rebuild the container image before running.
  "prompt"     Optional prompt to send Claude on launch (overrides
               CLAUDE_PROMPT from the config).

Config:      $CONFIG_FILE
Base image:  $BASE_IMAGE
Image:       $IMAGE_NAME
Allowed:     $ALLOWED_DOMAINS
EOF
            exit 0 ;;
        *) PROMPT_FROM_CLI="$arg" ;;
    esac
done
[ -n "$PROMPT_FROM_CLI" ] && CLAUDE_PROMPT="$PROMPT_FROM_CLI"

# --- Per-project isolated Claude state ---
#
# Mounts a project-local dir as /home/dev/.claude inside the
# container. First run: you'll log in. Subsequent runs: creds persist
# here and NOT in your host ~/.claude, so one project's compromise
# can't leak other projects' Claude sessions.
CLAUDE_STATE_DIR="$PROJECT_DIR/.docker-claude"
mkdir -p "$CLAUDE_STATE_DIR/home"
# ~/.claude.json is Claude Code's project metadata file. If it doesn't
# exist yet, `touch` it so the bind mount resolves to a file not a
# dir.
[ -e "$CLAUDE_STATE_DIR/claude.json" ] || echo '{}' > "$CLAUDE_STATE_DIR/claude.json"

# --- Build base image (if the config says we own it) ---

if [ -n "$BASE_IMAGE_CONTEXT" ]; then
    if [ "$REBUILD" = "yes" ] || ! docker image inspect "$BASE_IMAGE" >/dev/null 2>&1; then
        echo "==> Building base image $BASE_IMAGE from $BASE_IMAGE_CONTEXT..."
        docker build \
            -f "$BASE_IMAGE_CONTEXT/$BASE_IMAGE_DOCKERFILE" \
            -t "$BASE_IMAGE" \
            "$BASE_IMAGE_CONTEXT"
    fi
fi

# --- Build Claude image ---

if [ "$REBUILD" = "yes" ] || ! docker image inspect "$IMAGE_NAME" >/dev/null 2>&1; then
    echo "==> Building $IMAGE_NAME (FROM $BASE_IMAGE)..."
    docker build \
        --build-arg "BASE_IMAGE=$BASE_IMAGE" \
        --build-arg "HOST_UID=$(id -u)" \
        --build-arg "HOST_GID=$(id -g)" \
        -t "$IMAGE_NAME" \
        "$SCRIPT_DIR"
fi

# --- Run ---

echo "==> Starting $IMAGE_NAME (firewall will lock down to: $ALLOWED_DOMAINS)"

DOCKER_ARGS=(
    --rm -it
    --network=bridge
    # Drop every capability, then re-add only what the entrypoint needs:
    #   NET_ADMIN  — init-firewall.sh programs iptables
    #   SETUID/GID — setpriv drops root→dev after firewall setup
    # Once the uid changes to dev, the kernel clears the permitted cap
    # set, so Claude and anything it spawns cannot re-open iptables.
    --cap-drop=ALL
    --cap-add=NET_ADMIN
    --cap-add=SETUID
    --cap-add=SETGID
    # Block setuid/setgid/fscaps from elevating privileges.
    --security-opt=no-new-privileges
    --pids-limit="$PIDS_LIMIT"
    --memory="$MEMORY_LIMIT"
    -e CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=true
    -e ALLOWED_DOMAINS="$ALLOWED_DOMAINS"
    -e WORKSPACE="$WORKSPACE_PATH"
    -v "$WORKSPACE_MOUNT"
    -v "$CLAUDE_STATE_DIR/home:/home/dev/.claude"
    -v "$CLAUDE_STATE_DIR/claude.json:/home/dev/.claude.json"
    -w "$WORKSPACE_PATH"
)

[ -n "$CPU_LIMIT" ] && DOCKER_ARGS+=(--cpus="$CPU_LIMIT")

# Append project-specific extras last.
if [ "${#EXTRA_DOCKER_ARGS[@]}" -gt 0 ]; then
    DOCKER_ARGS+=("${EXTRA_DOCKER_ARGS[@]}")
fi

exec docker run "${DOCKER_ARGS[@]}" "$IMAGE_NAME" "$CLAUDE_PROMPT"
