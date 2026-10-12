#!/bin/sh
# DMZ VPN gateway. Perimeter model: authenticate once (key), then the tunnel gets the
# corporate segment. No MFA, no device posture, no re-verification.
set -e
. /roles/lib.sh
EXT=$(iface_for 172.20.0.); CORP=$(iface_for 10.20.0.)

cat > /etc/wg0.conf <<CONF
[Interface]
Address = 10.99.0.1/24
ListenPort = 51820
PrivateKey = $(cat /wg/gw.key)
[Peer]
PublicKey = $(cat /wg/cli.pub)
AllowedIPs = 10.99.0.2/32
CONF

if ip link add wg0 type wireguard 2>/dev/null; then
  ip link del wg0
  wg-quick up /etc/wg0.conf
else
  echo "[vpn-gateway] no kernel WireGuard, falling back to userspace wireguard-go"
  apk add --no-cache wireguard-go >/dev/null
  WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go wg-quick up /etc/wg0.conf
fi

# routes to the clinical zone go through the internal firewall
ip route add 10.30.0.0/24 via 10.20.0.254

iptables -F; iptables -t nat -F
iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i "$EXT" -p udp --dport 51820 -j ACCEPT          # only the VPN port is exposed
iptables -A INPUT -i wg0 -p icmp -j ACCEPT
# once authenticated, tunnel traffic is treated as corporate (network-position trust)
iptables -A FORWARD -i wg0 -o "$CORP" -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -t nat -A POSTROUTING -o "$CORP" -j MASQUERADE
echo "[vpn-gateway] up. ext=$EXT corp=$CORP"
exec sleep infinity
