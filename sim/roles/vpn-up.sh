#!/bin/sh
# Bring the VPN up from this host (the clinician, or any other host that holds the material).
# Overridable through the environment, used by the tests:
#   VPN_USER, VPN_PASS   account (default: the clinician's)
#   VPN_CERT             cli (default), rogue (certificate from another CA) or none
#   VPN_TOTP             force a TOTP code (MFA=totp only)
U="${VPN_USER:-dr.martin}"
P="${VPN_PASS:-Clinician-Pass-1}"
C="${VPN_CERT:-cli}"

sh /roles/vpn-down.sh
mkdir -p /etc/openvpn
cat > /etc/openvpn/client.conf <<CONF
client
dev tun
proto udp
remote 172.20.0.2 1194
nobind
persist-key
persist-tun
ca /pki/pub/ca.crt
remote-cert-tls server
data-ciphers AES-256-GCM
tls-version-min 1.2
reneg-sec 0
explicit-exit-notify 1
verb 3
CONF

if [ "${MFA:-none}" = "totp" ]; then
  code="${VPN_TOTP:-$(oathtool --totp -b "$(cat /pki/cli/totp-secret)")}"
  P="$P$code"
fi
umask 077
printf '%s\n%s\n' "$U" "$P" > /tmp/vpn-auth

CERTOPT=""
if [ "$C" != "none" ]; then CERTOPT="--cert /pki/cli/$C.crt --key /pki/cli/$C.key"; fi
# shellcheck disable=SC2086
openvpn --config /etc/openvpn/client.conf $CERTOPT \
  --auth-user-pass /tmp/vpn-auth \
  --daemon --writepid /run/openvpn-client.pid --log /var/log/openvpn-client.log

i=0
while [ $i -lt 15 ]; do
  if ip -o -4 addr show 2>/dev/null | grep -q ' 10\.99\.0\.'; then exit 0; fi
  pid=$(cat /run/openvpn-client.pid 2>/dev/null)
  if [ -n "$pid" ] && ! kill -0 "$pid" 2>/dev/null; then break; fi
  sleep 1
  i=$((i + 1))
done
echo "[vpn-up] tunnel did not come up:" >&2
tail -n 4 /var/log/openvpn-client.log >&2 || true
sh /roles/vpn-down.sh
exit 1
