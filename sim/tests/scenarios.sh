#!/bin/sh
# Threat-model scenarios for the perimeter-VPN baseline. Prints evidence, does not assert.
cd "$(dirname "$0")/.." || exit 1
. ./tests/common.sh
vpn_down
echo "== S1 stolen credentials: a second host holding the clinician's certificate, key and password"
run_s1() { # $1 = password, $2 = 1 if the TOTP seed (second factor, on the phone) is stolen too
  docker run --rm --network sim_external-net --cap-add NET_ADMIN --device /dev/net/tun \
  -v sim_pki-pub:/pki/pub:ro -v sim_pki-cli:/pki/all:ro -v "$(pwd)/roles:/roles:ro" \
  -e MFA="$(docker exec vpn-gateway printenv MFA)" -e VPN_PASS="$1" -e SEED="$2" cna-sim-node sh -c "
  mkdir -p /pki/cli && cp /pki/all/cli.crt /pki/all/cli.key /pki/cli/
  [ \"\$SEED\" = 1 ] && cp /pki/all/totp-secret /pki/cli/
  if sh /roles/vpn-up.sh 2>/dev/null; then $CU -s -m 8 $URL/v1/models | head -c 120; echo; echo '-> LLM reachable, no device check'
  else echo '-> no tunnel'; fi"; }
echo "-- certificate + key stolen, password unknown"
run_s1 wrong-password 0
echo "-- certificate + key + password stolen (laptop stolen, phone not)"
run_s1 Clinician-Pass-1 0
echo "-- certificate + key + password + TOTP seed stolen (laptop and phone)"
run_s1 Clinician-Pass-1 1
echo
echo "== S2 compromised corp workstation: lateral movement toward the clinical segment"
docker exec corp-ws sh -c 'for p in 22 80 443 8000 8001 5432; do nc -z -w2 10.30.0.10 $p && echo "open $p" || echo "blocked $p"; done'
echo "-- and toward the directory (corp segment is flat):"
docker exec corp-ws sh -c 'nc -z -w2 10.20.0.5 636 && echo "open 636 (directory)" || echo "blocked 636"'
echo
echo "== S3 attribution: what the LLM sees versus what the gateway knows"
vpn_up
docker exec clinician $CU -s -m 8 $URL/v1/models >/dev/null
echo "-- LLM log (last line):"; docker logs --tail 3 meditron-llm 2>&1 | grep 'src=' | tail -1
echo "-- gateway session log (last connect):"; docker exec vpn-gateway grep client-connect /var/log/vpn-sessions.log | tail -1
echo "-> the LLM sees only the tunnel address; the user is identified by joining it with the gateway log"
