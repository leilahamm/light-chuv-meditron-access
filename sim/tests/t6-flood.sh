#!/bin/sh
# T6: does a flood from a corporate host slow a legitimate clinician? STUB PROFILE ONLY.
LLM=10.30.0.10
body='{"messages":[{"role":"user","content":"ping"}]}'
lat() { docker exec clinician curl -s -m 30 -o /dev/null -w '%{http_code} %{time_total}s\n' -H 'Content-Type: application/json' -d "$body" http://$LLM:8000/v1/chat/completions; }
docker exec clinician wg-quick up /etc/wg0.conf >/dev/null 2>&1; sleep 1
echo "--- before the flood (5 clinician requests: status and seconds) ---"
for i in 1 2 3 4 5; do lat; done
echo "--- flood from corp-ws: 5 rounds of 300 parallel requests ---"
docker exec -d corp-ws sh -c 'for r in 1 2 3 4 5; do for i in $(seq 1 300); do curl -s -m 30 -o /dev/null -H "Content-Type: application/json" -d "{\"messages\":[{\"role\":\"user\",\"content\":\"flood\"}]}" http://10.30.0.10:8000/v1/chat/completions & done; wait; done'
sleep 2
echo "--- during the flood (5 clinician requests) ---"
for i in 1 2 3 4 5; do lat; done
sleep 25
echo "--- after the flood (3 clinician requests) ---"
for i in 1 2 3; do lat; done
