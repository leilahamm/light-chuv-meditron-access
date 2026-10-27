#!/bin/sh
# One-shot PKI for the simulation. The CA key lives only in this container's temp dir and is
# discarded, so no running node can mint certificates. Each node gets its own volume:
#   pki-pub  CA certificate (public)           pki-gw   gateway key/cert + TOTP seeds
#   pki-cli  client cert/key + TOTP seed       pki-llm  LLM server key/cert (TLS)
#   pki-dir  directory server key/cert (LDAPS)
set -e
[ -f /pki/pub/done ] && exit 0
umask 077
W=$(mktemp -d); cd "$W"

openssl req -x509 -newkey rsa:2048 -nodes -keyout ca.key -out ca.crt -days 825 \
  -subj "/CN=CNA Sim CA" -addext "basicConstraints=critical,CA:TRUE" 2>/dev/null

mk() { # name cn eku san ca.crt ca.key
  openssl req -newkey rsa:2048 -nodes -keyout "$1.key" -out "$1.csr" -subj "/CN=$2" 2>/dev/null
  { echo "basicConstraints=CA:FALSE"; echo "keyUsage=critical,digitalSignature,keyEncipherment"; echo "extendedKeyUsage=$3"; } > "$1.ext"
  if [ -n "$4" ]; then echo "subjectAltName=$4" >> "$1.ext"; fi
  openssl x509 -req -in "$1.csr" -CA "$5" -CAkey "$6" -CAcreateserial -out "$1.crt" \
    -days 825 -extfile "$1.ext" 2>/dev/null
}

mk gw  vpn-gateway        serverAuth "" ca.crt ca.key
mk cli clinician-device-01 clientAuth "" ca.crt ca.key
mk llm meditron-llm       serverAuth "IP:10.30.0.10,DNS:meditron-llm" ca.crt ca.key
mk dir directory          serverAuth "IP:10.20.0.5,DNS:directory" ca.crt ca.key

# a certificate with the same name but from a different CA, to prove the gateway rejects it
openssl req -x509 -newkey rsa:2048 -nodes -keyout rogue-ca.key -out rogue-ca.crt -days 825 \
  -subj "/CN=Rogue CA" -addext "basicConstraints=critical,CA:TRUE" 2>/dev/null
mk rogue clinician-device-01 clientAuth "" rogue-ca.crt rogue-ca.key

# TOTP seed for the second-factor variant (MFA=totp). Fixed so the test accounts are reproducible.
SEED=JBSWY3DPEHPK3PXP

cp ca.crt /pki/pub/
cp gw.crt gw.key /pki/gw/
echo "$SEED" > /pki/gw/totp-dr.martin
echo "$SEED" > /pki/gw/totp-dr.lockout
echo "$SEED" > /pki/gw/totp-dr.lockout
cp cli.crt cli.key rogue.crt rogue.key /pki/cli/
echo "$SEED" > /pki/cli/totp-secret
cp llm.crt llm.key /pki/llm/
cp dir.crt dir.key /pki/dir/
touch /pki/pub/done
rm -rf "$W"
echo "[pki-init] CA, gateway, client, LLM and directory certificates created"