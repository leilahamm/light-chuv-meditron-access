#!/bin/sh
# Take the VPN down on this host and wait until the tunnel interface is gone.
if [ -f /run/openvpn-client.pid ]; then
  kill "$(cat /run/openvpn-client.pid)" 2>/dev/null || true
  rm -f /run/openvpn-client.pid
fi
pkill openvpn 2>/dev/null || true
i=0
while [ $i -lt 8 ]; do
  ip link show tun0 >/dev/null 2>&1 || exit 0
  sleep 1
  i=$((i + 1))
done
exit 0
