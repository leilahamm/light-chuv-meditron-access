#!/bin/sh
# T5: are prompts readable after the VPN tunnel ends? Run from sim/ with the stack up.
# Default (LLM_TLS=on): unreadable on both legs. Plaintext variant: LLM_TLS=off docker compose ... up -d
cd "$(dirname "$0")/.." || exit 1
. ./tests/common.sh
CANARY="T5-CANARY-patient-Jane-Doe-chest-pain"
vpn_up; sleep 1
docker exec -d corp-fw sh -c 'timeout 40 tcpdump -l -i any -nn -A -s0 "tcp port 8000" > /tmp/t5-inner.txt 2>/dev/null'
docker exec -d clinician sh -c 'timeout 40 tcpdump -l -i eth0 -nn -A -s0 "udp port 1194" > /tmp/t5-outer.txt 2>/dev/null'
sleep 3
docker exec clinician $CU -s -m 60 -H 'Content-Type: application/json' \
  -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$CANARY\"}]}" $URL/v1/chat/completions >/dev/null
sleep 3
docker exec corp-fw pkill tcpdump; docker exec clinician pkill tcpdump; sleep 1
outer=$(docker exec clinician grep -c "$CANARY" /tmp/t5-outer.txt)
inner=$(docker exec corp-fw grep -c "$CANARY" /tmp/t5-inner.txt)
echo "LLM scheme: $SCHEME"
echo "Marker on the outer VPN leg (clinician eth0, OpenVPN):  $outer  (expected 0)"
echo "Marker after the tunnel (corp-fw): $inner  (expected 0 with TLS, 1 or more with plain HTTP)"
[ "$inner" -gt 0 ] && docker exec corp-fw grep -m1 "$CANARY" /tmp/t5-inner.txt
exit 0
