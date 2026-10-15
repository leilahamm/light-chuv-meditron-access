#!/bin/sh
# S4: what an attacker with a shell on the VPN gateway gets. Run from sim/ with the stack up.
# This assumes the gateway is already compromised. It does not test how the attacker got in.
CANARY="S4-CANARY-patient-John-Roe-diabetes-review"
LLM=10.30.0.10
docker exec clinician wg-quick up /etc/wg0.conf >/dev/null 2>&1; sleep 1
echo "== S4 compromised VPN gateway"
echo "-- reach: the gateway queries the LLM with no credential"
docker exec vpn-gateway curl -s -m 8 http://$LLM:8000/v1/models | head -c 120; echo
echo "-- ports reachable from the gateway"
docker exec vpn-gateway sh -c "for p in 22 8000 8001 5432; do nc -z -w2 $LLM \$p && echo \"open \$p\" || echo \"blocked \$p\"; done"
echo "-- visibility: decrypted clinician traffic seen on the gateway's wg0 interface"
docker exec -d vpn-gateway sh -c 'timeout 20 tcpdump -l -i wg0 -nn -A -s0 "tcp port 8000" > /tmp/s4.txt 2>/dev/null'
sleep 2
docker exec clinician curl -s -m 60 -H 'Content-Type: application/json' \
  -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$CANARY\"}]}" \
  http://$LLM:8000/v1/chat/completions >/dev/null
sleep 3; docker exec vpn-gateway pkill tcpdump; sleep 1
docker exec vpn-gateway grep -m1 "$CANARY" /tmp/s4.txt || echo "marker NOT seen"
echo "-- persistence: the attacker registers their own VPN peer"
key=$(docker exec vpn-gateway sh -c 'wg genkey | wg pubkey')
docker exec vpn-gateway wg set wg0 peer "$key" allowed-ips 10.99.0.99/32
docker exec vpn-gateway wg show wg0 peers | grep -c "$key" | sed 's/^/new peer registered (1 = yes): /'
docker exec vpn-gateway wg set wg0 peer "$key" remove
echo "(test peer removed again)"
