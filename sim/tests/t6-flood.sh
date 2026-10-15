#!/bin/sh
# T6: does a flood from a corporate host slow a legitimate clinician? STUB PROFILE ONLY.
# Needs the stub started with STUB_DELAY and STUB_CONCURRENCY set.
LLM=10.30.0.10
FLOOD=${FLOOD:-100}
body='{"messages":[{"role":"user","content":"ping"}]}'
lat() { docker exec clinician curl -s -m 90 -o /dev/null -w '%{http_code} %{time_total}s\n' -H 'Content-Type: application/json' -d "$body" http://$LLM:8000/v1/chat/completions; }
trap 'docker exec corp-ws pkill curl 2>/dev/null; echo "(flood stopped)"' EXIT
docker exec clinician wg-quick up /etc/wg0.conf >/dev/null 2>&1; sleep 1
echo "--- before the flood (3 clinician requests: status and seconds) ---"
for i in 1 2 3; do lat; done
echo "--- flood from corp-ws: $FLOOD parallel requests ---"
docker exec -d corp-ws sh -c "for i in \$(seq 1 $FLOOD); do curl -s -m 90 -o /dev/null -H 'Content-Type: application/json' -d '{\"messages\":[{\"role\":\"user\",\"content\":\"flood\"}]}' http://10.30.0.10:8000/v1/chat/completions & done; wait"
sleep 2
echo "--- during the flood (3 clinician requests) ---"
for i in 1 2 3; do lat; done
echo "--- waiting 60 s for the queue to drain ---"
sleep 60
echo "--- after the flood (3 clinician requests) ---"
for i in 1 2 3; do lat; done
