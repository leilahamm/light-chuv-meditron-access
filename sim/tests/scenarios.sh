#!/bin/sh
# Threat-model scenarios for the perimeter-VPN baseline. Prints evidence, does not assert.
docker exec clinician wg-quick down /etc/wg0.conf >/dev/null 2>&1   # original device goes offline
echo "== S1 stolen credential: a second host with a copy of the clinician key gets the same access"
docker run --rm --network sim_external-net --cap-add NET_ADMIN --device /dev/net/tun \
  -v sim_wg:/wg:ro -v "$(pwd)/roles:/roles:ro" cna-sim-node sh -c '
  cat > /etc/wg0.conf <<C
[Interface]
Address = 10.99.0.2/24
PrivateKey = $(cat /wg/cli.key)
[Peer]
PublicKey = $(cat /wg/gw.pub)
Endpoint = 172.20.0.2:51820
AllowedIPs = 10.20.0.0/24, 10.30.0.0/24
C
  wg-quick up /etc/wg0.conf >/dev/null 2>&1 && curl -s -m 8 http://10.30.0.10:8000/v1/models && echo && echo "-> LLM reachable with copied key, no device check"'
echo; echo "== S2 compromised corp workstation: lateral movement toward the clinical segment"
docker exec corp-ws sh -c 'for p in 22 80 443 8000 8001 5432; do nc -z -w2 10.30.0.10 $p && echo "open $p" || echo "blocked $p"; done'
echo; echo "== S3 what the LLM can attribute: source address seen for a clinician request"
docker exec clinician curl -s -m 8 http://10.30.0.10:8000/v1/models >/dev/null
docker logs --tail 3 meditron-llm 2>&1
echo "-> the endpoint sees only the firewall address, individual users are not distinguishable at network level"
