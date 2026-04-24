#!/bin/bash
set -euo pipefail

# Runs as root inside the container. Sets up the firewall (needs
# CAP_NET_ADMIN), then drops to the unprivileged dev user and execs
# claude. The uid change from root -> dev clears kernel capabilities
# from the process's permitted set, so any prompt-injection-driven
# subprocess Claude launches cannot re-open iptables.

/usr/local/bin/init-firewall.sh

WORKSPACE="${WORKSPACE:-/workspace}"
PROMPT="${*:-}"

# Optional model pin. If CLAUDE_MODEL is set (e.g. "claude-opus-4-6[1m]"),
# launch claude with --model that value; otherwise let the CLI pick its
# default.
CLAUDE_MODEL_ARG=""
if [ -n "${CLAUDE_MODEL:-}" ]; then
    CLAUDE_MODEL_ARG="--model $(printf '%q' "$CLAUDE_MODEL")"
fi

cd "$WORKSPACE"

# Drop to the unprivileged dev user. We use setpriv instead of su
# because su is a setuid binary blocked by --security-opt=no-new-privileges.
# setpriv uses capabilities directly (CAP_SETUID/CAP_SETGID granted to
# the root entrypoint), so it works under no-new-privileges. Once the
# uid changes to dev, the kernel clears the capability sets — Claude
# can't touch iptables.
DEV_UID=$(id -u dev)
DEV_GID=$(id -g dev)

# Build a clean environment matching what su -l would provide.
CLEAN_ENV=(env -i
    HOME=/home/dev USER=dev LOGNAME=dev SHELL=/bin/bash
    "TERM=${TERM:-xterm}"
    "PATH=/home/dev/.claude/local/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
)

if [ -n "$PROMPT" ]; then
    QUOTED_PROMPT=$(printf '%q' "$PROMPT")
    exec setpriv --reuid="$DEV_UID" --regid="$DEV_GID" --init-groups \
        "${CLEAN_ENV[@]}" \
        bash -l -c "cd '$WORKSPACE' && exec claude --dangerously-skip-permissions $CLAUDE_MODEL_ARG $QUOTED_PROMPT"
else
    exec setpriv --reuid="$DEV_UID" --regid="$DEV_GID" --init-groups \
        "${CLEAN_ENV[@]}" \
        bash -l -c "cd '$WORKSPACE' && exec claude --dangerously-skip-permissions $CLAUDE_MODEL_ARG"
fi
