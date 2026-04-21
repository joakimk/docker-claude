#!/bin/bash
set -euo pipefail

# Print Claude Code session-limit utilization for the current OAuth
# account. Reads the access token from ~/.claude/.credentials.json and
# hits the unofficial /api/oauth/usage endpoint (same data the CLI UI
# renders).
#
# Usage:
#   docker-claude/usage.sh            # prints 5-hour utilization (e.g. 37)
#   docker-claude/usage.sh --seven    # prints 7-day utilization
#   docker-claude/usage.sh --json     # prints full JSON response
#
# Exits non-zero on missing credentials, HTTP errors, or parse
# failures. The access token never appears on stdout.

CREDS="${CLAUDE_CREDS:-$HOME/.claude/.credentials.json}"
URL="https://api.anthropic.com/api/oauth/usage"
BETA_HEADER="oauth-2025-04-20"

mode="five"
for arg in "$@"; do
    case "$arg" in
        --seven) mode="seven" ;;
        --json)  mode="json" ;;
        --help|-h)
            sed -n '4,14p' "$0" | sed 's/^# \{0,1\}//'
            exit 0 ;;
        *) echo "unknown arg: $arg" >&2; exit 2 ;;
    esac
done

if [ ! -r "$CREDS" ]; then
    echo "error: credentials not readable at $CREDS" >&2
    exit 1
fi

# Extract accessToken without leaking it. The credentials file is a
# small, flat JSON blob — a conservative grep+sed is enough and avoids
# depending on jq.
token=$(grep -oE '"accessToken"[[:space:]]*:[[:space:]]*"[^"]+"' "$CREDS" \
        | head -1 \
        | sed -E 's/.*"accessToken"[[:space:]]*:[[:space:]]*"([^"]+)".*/\1/')

if [ -z "$token" ]; then
    echo "error: claudeAiOauth.accessToken not found in $CREDS" >&2
    exit 1
fi

response=$(curl -sS --max-time 10 \
    -H "Authorization: Bearer $token" \
    -H "anthropic-beta: $BETA_HEADER" \
    -H "Accept: application/json" \
    "$URL") || {
        echo "error: request to $URL failed" >&2
        exit 1
    }

case "$mode" in
    json)
        printf '%s\n' "$response"
        ;;
    five)
        echo "$response" \
            | grep -oE '"five_hour"[[:space:]]*:[[:space:]]*\{[^}]*"utilization"[[:space:]]*:[[:space:]]*[0-9.]+' \
            | grep -oE '[0-9.]+$'
        ;;
    seven)
        echo "$response" \
            | grep -oE '"seven_day"[[:space:]]*:[[:space:]]*\{[^}]*"utilization"[[:space:]]*:[[:space:]]*[0-9.]+' \
            | grep -oE '[0-9.]+$'
        ;;
esac
