#!/bin/sh
# Internal firewall. Corporate -> LLM inference port only, default deny everything else.
set -e
. /roles/lib.sh
CORP=$(iface_for 10.20.0.); CLIN=$(iface_for 10.30.0.)
iptables -F; iptables -t nat -F
iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "$CORP" -o "$CLIN" -d 10.30.0.10 -p tcp --dport 8000 -j ACCEPT
iptables -A FORWARD -j LOG --log-prefix "corp-fw DROP: " --log-level 4
# the LLM sees the firewall as source, so it needs no return route into corp-net
iptables -t nat -A POSTROUTING -o "$CLIN" -j MASQUERADE
echo "[corp-fw] rules loaded (corp=$CORP clinical=$CLIN)"
iptables -S FORWARD
exec sleep infinity
