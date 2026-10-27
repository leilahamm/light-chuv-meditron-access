#!/bin/sh
# Internal firewall. Corporate -> LLM inference port only, default deny everything else.
# No NAT: the LLM sees the real source address (a corporate host or a VPN address).
set -e
. /roles/lib.sh
CORP=$(iface_for 10.20.0.); CLIN=$(iface_for 10.30.0.)
ip route add 10.99.0.0/24 via 10.20.0.253      # replies to tunnel clients go back via the DMZ firewall
ip route add 10.10.0.0/24 via 10.20.0.253
iptables -F; iptables -t nat -F
iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "$CORP" -o "$CLIN" -d 10.30.0.10 -p tcp --dport 8000 -j ACCEPT
iptables -A FORWARD -j LOG --log-prefix "corp-fw DROP: " --log-level 4
echo "[corp-fw] rules loaded (corp=$CORP clinical=$CLIN)"
iptables -S FORWARD
exec sleep infinity
