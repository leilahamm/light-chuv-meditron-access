#!/bin/sh
# Firewall between the DMZ and the corporate segment. The gateway itself may only talk to the
# directory (LDAPS). Traffic from the VPN address pool, which means an authenticated tunnel, is
# let into the corporate side, where corp-fw applies the last filter before the clinical segment.
set -e
. /roles/lib.sh
DMZ=$(iface_for 10.10.0.); CORP=$(iface_for 10.20.0.)
ip route add 10.99.0.0/24 via 10.10.0.2        # tunnel addresses live behind the gateway
ip route add 10.30.0.0/24 via 10.20.0.254      # clinical segment is behind corp-fw
iptables -F; iptables -t nat -F
iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -i "$DMZ" -o "$CORP" -s 10.10.0.2 -d 10.20.0.5 -p tcp --dport 636 -j ACCEPT
iptables -A FORWARD -i "$DMZ" -o "$CORP" -s 10.99.0.0/24 -j ACCEPT
iptables -A FORWARD -j LOG --log-prefix "dmz-fw DROP: " --log-level 4
echo "[dmz-fw] rules loaded (dmz=$DMZ corp=$CORP)"
iptables -S FORWARD
exec sleep infinity
