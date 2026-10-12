#!/bin/sh
set -e
cat > /etc/wg0.conf <<CONF
[Interface]
Address = 10.99.0.2/24
PrivateKey = $(cat /wg/cli.key)
[Peer]
PublicKey = $(cat /wg/gw.pub)
Endpoint = 172.20.0.2:51820
# routes pushed by the VPN: corporate and clinical address space
AllowedIPs = 10.20.0.0/24, 10.30.0.0/24, 10.99.0.1/32
PersistentKeepalive = 15
CONF
chmod 600 /etc/wg0.conf
if ip link add wg0 type wireguard 2>/dev/null; then
  ip link del wg0; wg-quick up /etc/wg0.conf
else
  apk add --no-cache wireguard-go >/dev/null
  WG_QUICK_USERSPACE_IMPLEMENTATION=wireguard-go wg-quick up /etc/wg0.conf
fi
echo "[clinician] tunnel up"
exec sleep infinity
