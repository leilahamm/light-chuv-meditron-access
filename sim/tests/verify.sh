#!/bin/sh
# Reachability matrix for the baseline. Run from the sim/ directory on the host:  ./tests/verify.sh
# Each line states what the assumptions say SHOULD happen, then checks it.
pass=0; fail=0
t() { # name, expected(allow|deny), container, command...
  name=$1; want=$2; c=$3; shift 3
  if docker exec "$c" "$@" >/dev/null 2>&1; then got=allow; else got=deny; fi
  if [ "$got" = "$want" ]; then pass=$((pass+1)); r=PASS; else fail=$((fail+1)); r=FAIL; fi
  printf '%-4s %-62s expected=%s got=%s\n' "$r" "$name" "$want" "$got"
}
LLM=10.30.0.10
chat='{"messages":[{"role":"user","content":"ping"}]}'
post() { curl -s -m 6 -f -H 'Content-Type: application/json' -d "$chat" http://$LLM:8000/v1/chat/completions; }

echo "== zone 1: external / clinician (before and after tunnel)"
docker exec clinician wg-quick down /etc/wg0.conf >/dev/null 2>&1
t "no tunnel: clinician cannot reach corp-ws"          deny  clinician ping -c1 -W2 10.20.0.20
t "no tunnel: clinician cannot reach LLM inference"    deny  clinician curl -s -m 4 -f http://$LLM:8000/v1/models
t "no tunnel: gateway TCP/22 closed"                   deny  clinician nc -z -w2 172.20.0.2 22
docker exec clinician wg-quick up /etc/wg0.conf >/dev/null 2>&1; sleep 2
echo "== zone 2: DMZ gateway, authenticated corporate segment"
t "tunnel: clinician reaches gateway (10.99.0.1)"      allow clinician ping -c1 -W2 10.99.0.1
t "tunnel: clinician reaches corp-ws (corp segment)"   allow clinician ping -c1 -W2 10.20.0.20
echo "== zone 3: restricted clinical segment"
t "tunnel: clinician -> LLM inference :8000"           allow clinician curl -s -m 8 -f http://$LLM:8000/v1/models
t "tunnel: clinician -> LLM chat completion"           allow clinician sh -c "curl -s -m 60 -f -H 'Content-Type: application/json' -d '$chat' http://$LLM:8000/v1/chat/completions"
t "tunnel: clinician -> LLM admin decoy :8001 blocked" deny  clinician curl -s -m 4 -f http://$LLM:8001/
t "tunnel: clinician ping LLM blocked (no ICMP rule)"  deny  clinician ping -c1 -W2 $LLM
t "corp-ws -> LLM inference :8000"                     allow corp-ws curl -s -m 8 -f http://$LLM:8000/v1/models
t "corp-ws -> LLM admin decoy :8001 blocked"           deny  corp-ws curl -s -m 4 -f http://$LLM:8001/
t "corp-ws ping LLM blocked"                           deny  corp-ws ping -c1 -W2 $LLM
t "LLM cannot initiate to corp-ws (clinical->corp)"    deny  meditron-llm ping -c1 -W2 10.20.0.20
echo; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
