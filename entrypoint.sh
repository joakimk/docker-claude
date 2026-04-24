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

# Build the claude argument array. Values are passed as positional
# parameters to bash -c so they're never subject to word-splitting or
# glob expansion inside the shell string.
CLAUDE_ARGS=(--dangerously-skip-permissions)
if [ -n "${CLAUDE_MODEL:-}" ]; then
    CLAUDE_ARGS+=(--model "$CLAUDE_MODEL")
fi
if [ -n "$PROMPT" ]; then
    CLAUDE_ARGS+=("$PROMPT")
fi

# The inner script receives $1=workspace, $2..N=claude args.  Using
# positional parameters avoids quoting pitfalls with bash -c strings.
# shellcheck disable=SC2016  # single quotes intentional: $1/$@ expand inside bash -c
exec setpriv --reuid="$DEV_UID" --regid="$DEV_GID" --init-groups \
    "${CLEAN_ENV[@]}" \
    bash -l -c 'cd "$1" && shift && exec claude "$@"' _ "$WORKSPACE" "${CLAUDE_ARGS[@]}"
