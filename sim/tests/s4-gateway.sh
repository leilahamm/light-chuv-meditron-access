#!/bin/sh
# S4: what an attacker with a shell on the VPN gateway gets. Run from sim/ with the stack up.
# This assumes the gateway is already compromised. It does not test how the attacker got in.
cd "$(dirname "$0")/.." || exit 1
. ./tests/common.sh
CANARY="S4-CANARY-patient-John-Roe-diabetes-review"
vpn_up; sleep 1
echo "== S4 compromised VPN gateway"
echo "-- reach with the gateway's own address (expected: blocked by dmz-fw)"
docker exec vpn-gateway $CU -s -m 5 $URL/v1/models | head -c 120; echo "[exit code above is empty = blocked]"
echo "-- reach with the tunnel address as source (the DMZ rule trusts the whole tunnel pool)"
docker exec vpn-gateway $CU -s -m 8 --interface 10.99.0.1 $URL/v1/models | head -c 120; echo
echo "-- ports reachable from the tunnel address"
docker exec vpn-gateway sh -c "for p in 22 8000 8001 5432; do nc -z -w2 -s 10.99.0.1 $LLM \$p && echo \"open \$p\" || echo \"blocked \$p\"; done"
echo "-- visibility: traffic seen on the gateway's tun0 interface (after the VPN decrypts it)"
docker exec -d vpn-gateway sh -c 'timeout 20 tcpdump -l -i tun0 -nn -A -s0 "tcp port 8000" > /tmp/s4.txt 2>/dev/null'
sleep 2
docker exec clinician $CU -s -m 60 -H 'Content-Type: application/json' \
  -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$CANARY\"}]}" $URL/v1/chat/completions >/dev/null
sleep 3; docker exec vpn-gateway pkill tcpdump; sleep 1
n=$(docker exec vpn-gateway grep -c "$CANARY" /tmp/s4.txt)
echo "prompt marker readable on the gateway: $n  (expected 0 with TLS on the LLM, 1+ with LLM_TLS=off)"
echo "-- secrets held by the gateway"
docker exec vpn-gateway sh -c 'ls /pki/gw; test -w /usr/local/bin/auth-ldap.sh && echo "auth script is writable: a root attacker can harvest cleartext passwords at every login"'
