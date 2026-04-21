#!/bin/bash
set -euo pipefail

# Restricts outbound network to a configurable allow-list.
#
# Reads ALLOWED_DOMAINS from env (space-separated). Resolves each via
# dig and adds individual iptables ACCEPT rules for the resulting IPs;
# everything else outbound is rejected. Also allows: DNS (resolver),
# loopback, the container's default gateway (so NAT out works), and
# established/related return traffic.
#
# Adapted from https://github.com/anthropics/claude-code/blob/main/.devcontainer/init-firewall.sh
# Requires CAP_NET_ADMIN.

ALLOWED_DOMAINS="${ALLOWED_DOMAINS:-api.anthropic.com sentry.io}"

# Split space-separated domains into an array.
read -ra DOMAINS <<< "$ALLOWED_DOMAINS"

# 1. Capture Docker's embedded-DNS NAT rules before flushing so we can
#    restore them; without this, getent/dig inside the container stop
#    resolving once we set default-drop.
DOCKER_DNS_RULES=$(iptables-save -t nat | grep "127\.0\.0\.11" || true)

iptables -F
iptables -X
iptables -t nat -F
iptables -t nat -X
iptables -t mangle -F
iptables -t mangle -X

if [ -n "$DOCKER_DNS_RULES" ]; then
    echo "Restoring Docker DNS rules..."
    iptables -t nat -N DOCKER_OUTPUT 2>/dev/null || true
    iptables -t nat -N DOCKER_POSTROUTING 2>/dev/null || true
    echo "$DOCKER_DNS_RULES" | xargs -L 1 iptables -t nat
else
    echo "No Docker DNS rules to restore"
fi

# Allow DNS and loopback before locking down.
iptables -A OUTPUT -p udp --dport 53 -j ACCEPT
iptables -A INPUT  -p udp --sport 53 -j ACCEPT
iptables -A INPUT  -i lo -j ACCEPT
iptables -A OUTPUT -o lo -j ACCEPT

# Resolve allow-list domains to IPs and add individual iptables rules.
for domain in "${DOMAINS[@]}"; do
    echo "Resolving $domain..."
    ips=$(dig +noall +answer A "$domain" | awk '$4 == "A" {print $5}')
    if [ -z "$ips" ]; then
        echo "WARNING: Failed to resolve $domain, skipping"
        continue
    fi
    while read -r ip; do
        if [[ ! "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
            echo "ERROR: Invalid IP from DNS for $domain: $ip"
            exit 1
        fi
        echo "  Allowing $ip ($domain)"
        iptables -A OUTPUT -d "$ip" -j ACCEPT
    done <<< "$ips"
done

# Allow the container's default gateway only (not the full /24 like
# the upstream example). Docker bridge-networked containers route
# outbound through this one host; other IPs on the bridge subnet
# shouldn't be reachable.
GATEWAY_IP=$(ip route | awk '/default/ {print $3; exit}')
if [ -z "$GATEWAY_IP" ]; then
    echo "ERROR: Failed to detect default gateway"
    exit 1
fi
echo "Gateway: $GATEWAY_IP"
iptables -A INPUT  -s "$GATEWAY_IP" -j ACCEPT
iptables -A OUTPUT -d "$GATEWAY_IP" -j ACCEPT

iptables -P INPUT   DROP
iptables -P FORWARD DROP
iptables -P OUTPUT  DROP

iptables -A INPUT  -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A OUTPUT -m state --state ESTABLISHED,RELATED -j ACCEPT

iptables -A OUTPUT -j REJECT --reject-with icmp-admin-prohibited

echo ""
echo "Firewall configured. Verifying..."

if curl --connect-timeout 5 https://example.com >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - reached https://example.com"
    exit 1
else
    echo "  PASS: example.com blocked"
fi

# Pick the first allowed domain and confirm it's reachable (sanity check
# that we didn't over-block). If the first domain is something that
# doesn't serve on 443, the user can set ALLOWED_DOMAINS_VERIFY_URL.
VERIFY_URL="${ALLOWED_DOMAINS_VERIFY_URL:-https://$(echo "$ALLOWED_DOMAINS" | awk '{print $1}')}"
if ! curl --connect-timeout 5 "$VERIFY_URL" >/dev/null 2>&1; then
    echo "ERROR: Firewall verification failed - unable to reach $VERIFY_URL"
    exit 1
else
    echo "  PASS: $VERIFY_URL reachable"
fi

echo "Firewall ready."
