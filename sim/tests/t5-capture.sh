#!/bin/sh
# T5: are prompts readable after the VPN tunnel ends? Run from sim/ with the stack up.
CANARY="T5-CANARY-patient-Jane-Doe-chest-pain"
LLM=10.30.0.10
docker exec clinician wg-quick up /etc/wg0.conf >/dev/null 2>&1; sleep 1
docker exec -d corp-fw sh -c 'timeout 40 tcpdump -l -i any -nn -A -s0 "tcp port 8000" > /tmp/t5-inner.txt 2>/dev/null'
docker exec -d clinician sh -c 'timeout 40 tcpdump -l -i eth0 -nn -A -s0 "udp port 51820" > /tmp/t5-outer.txt 2>/dev/null'
sleep 3
docker exec clinician curl -s -m 60 -H 'Content-Type: application/json' \
  -d "{\"messages\":[{\"role\":\"user\",\"content\":\"$CANARY\"}]}" \
  http://$LLM:8000/v1/chat/completions >/dev/null
sleep 3
docker exec corp-fw pkill tcpdump; docker exec clinician pkill tcpdump; sleep 1
outer=$(docker exec clinician grep -c "$CANARY" /tmp/t5-outer.txt)
inner=$(docker exec corp-fw grep -c "$CANARY" /tmp/t5-inner.txt)
echo "Marker found on the outer VPN leg (clinician eth0, WireGuard): $outer  (expected 0)"
echo "Marker found after the tunnel (corp-fw, plain HTTP):           $inner  (expected 1 or more)"
echo "--- sample of what an on-path host reads after the tunnel ---"
docker exec corp-fw grep -m1 "$CANARY" /tmp/t5-inner.txt
