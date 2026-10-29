#!/bin/sh
# S5 to S8: attacker positions that the other scripts do not cover. Run from sim/ with the stack up
# (stub profile, baseline or MFA=totp). Prints evidence, does not assert.
# Each scenario ASSUMES the node is already compromised (root on it). It does not test how.
cd "$(dirname "$0")/.." || exit 1
. ./tests/common.sh
BASE="dc=chuv-sim,dc=local"
vpn_down

echo "== S5 compromised directory: attacker with admin rights on the directory adds an account"
docker exec -e LDAPTLS_REQCERT=never directory sh -c "printf 'dn: uid=attacker,ou=people,$BASE\nobjectClass: inetOrgPerson\nuid: attacker\ncn: attacker\nsn: attacker\nuserPassword: Evil-Pass-1\n' | ldapadd -x -H ldaps://127.0.0.1 -D cn=admin,$BASE -w AdminSimPass-1" >/dev/null 2>&1 \
  && echo "account 'attacker' created in the directory" || echo "could not create the account (check that the stack is up)"
echo "-- login as 'attacker' from the clinician host, which holds a valid device certificate"
if docker exec -e VPN_USER=attacker -e VPN_PASS=Evil-Pass-1 clinician sh /roles/vpn-up.sh >/dev/null 2>&1; then
  echo "-> tunnel UP: the gateway accepts any account the directory vouches for"
  docker exec clinician $CU -s -m 8 $URL/v1/models | head -c 100; echo
else
  echo "-> tunnel DOWN (with MFA=totp expected: the gateway has no TOTP seed for this account)"
  docker exec vpn-gateway tail -n 2 /var/log/vpn-auth.log
fi
vpn_down
echo "-- same account, no device certificate (expected: no tunnel)"
docker exec -e VPN_USER=attacker -e VPN_PASS=Evil-Pass-1 -e VPN_CERT=none clinician sh /roles/vpn-up.sh >/dev/null 2>&1 \
  && echo "-> tunnel UP" || echo "-> tunnel DOWN"
vpn_down
docker exec -e LDAPTLS_REQCERT=never directory sh -c "ldapdelete -x -H ldaps://127.0.0.1 -D cn=admin,$BASE -w AdminSimPass-1 uid=attacker,ou=people,$BASE" >/dev/null 2>&1 \
  && echo "(account 'attacker' removed)"
echo "note: the directory does not hold the TOTP seeds, the gateway does (see S4)"
echo

echo "== S6 compromised LLM host: what can it reach from the clinical segment"
docker exec meditron-llm sh -c 'echo "ip_forward=$(cat /proc/sys/net/ipv4/ip_forward)"; ip route'
docker exec meditron-llm sh -c '
for t in "10.20.0.5 636 directory" "10.20.0.20 22 corp-ws" "10.10.0.2 22 vpn-gateway" "172.20.0.10 22 clinician" "1.1.1.1 443 internet"; do
  set -- $t
  nc -z -w2 $1 $2 && echo "open    $3 ($1:$2)" || echo "blocked $3 ($1:$2)"
done'
echo "-- material on the host"
docker exec meditron-llm sh -c 'ls /pki/llm; echo "server key readable by the process: yes (it terminates TLS)"'
echo "note: with the rcp profile the egress network gives the host a route out, so 'internet' may be open"
echo "note: that the host sees prompts in clear follows from it terminating TLS, it is not tested separately"
echo

echo "== S7 compromised firewalls: rules are the only barrier"
echo "-- corp-fw: before (decoy port 8001 from corp-ws)"
docker exec corp-ws sh -c 'nc -z -w2 10.30.0.10 8001 && echo "open 8001" || echo "blocked 8001"'
docker exec corp-fw iptables -I FORWARD 1 -j ACCEPT
echo "-- corp-fw: after the attacker inserts an ACCEPT rule"
docker exec corp-ws sh -c 'for p in 22 8001 5432; do nc -z -w2 10.30.0.10 $p && echo "open $p" || echo "blocked $p"; done'
docker exec corp-fw iptables -D FORWARD -j ACCEPT
echo "-- dmz-fw: gateway's own address pinging the directory, before (only LDAPS 636 is allowed for it)"
docker exec vpn-gateway sh -c "ping -c1 -W2 10.20.0.5 >/dev/null 2>&1 && echo 'reply' || echo 'no reply'"
docker exec dmz-fw iptables -I FORWARD 1 -j ACCEPT
echo "-- dmz-fw: after the attacker inserts an ACCEPT rule"
docker exec vpn-gateway sh -c "ping -c1 -W2 10.20.0.5 >/dev/null 2>&1 && echo 'reply' || echo 'no reply'"
docker exec dmz-fw iptables -D FORWARD -j ACCEPT
echo "note: the LLM has no return route to the DMZ, so the gateway's own address cannot reach it even with dmz-fw open. This is a side effect of the routing, not a designed control"
echo "(rules restored)"
echo

echo "== S8 VPN service from the external zone: exposure and a malformed-packet probe (not an exploit)"
docker exec vpn-gateway sh -c 'openvpn --version | head -n1'
echo "-- 300 random UDP packets to 1194 from an unauthenticated host"
docker exec clinician sh -c 'i=0; while [ $i -lt 300 ]; do head -c 64 /dev/urandom; i=$((i+1)); done | timeout 20 nc -u -w1 172.20.0.2 1194' >/dev/null 2>&1
docker exec vpn-gateway sh -c 'pidof openvpn >/dev/null && echo "openvpn still running" || echo "openvpn NOT running"'
vpn_up && echo "legitimate login still works afterwards" || echo "legitimate login FAILED afterwards"
vpn_down
echo "note: a missing result here does not show the software is free of vulnerabilities, check the version above against published CVEs"