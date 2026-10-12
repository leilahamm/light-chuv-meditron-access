#!/bin/sh
# Generates the long-lived WireGuard credentials once. Static keys play the role of the
# client certificate in a perimeter VPN: whoever holds the key gets in, no posture check.
set -e
cd /wg
[ -f done ] && exit 0
umask 077
wg genkey | tee gw.key  | wg pubkey > gw.pub
wg genkey | tee cli.key | wg pubkey > cli.pub
touch done
echo "[vpn-init] keys generated"
