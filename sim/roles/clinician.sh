#!/bin/sh
# Simulated mobile clinician device, external zone. Connects at start; the tests reconnect with
# /roles/vpn-up.sh and /roles/vpn-down.sh.
i=0
while [ $i -lt 3 ]; do
  if sh /roles/vpn-up.sh; then echo "[clinician] tunnel up"; break; fi
  i=$((i + 1)); sleep 2
done
[ $i -lt 3 ] || echo "[clinician] tunnel NOT up (see /var/log/openvpn-client.log)"
exec sleep infinity
