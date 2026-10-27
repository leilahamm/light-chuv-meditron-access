#!/bin/sh
# Reachability and authentication matrix for the baseline. Run from sim/:  ./tests/verify.sh
# Each line states what the assumptions say SHOULD happen, then checks it.
cd "$(dirname "$0")/.." || exit 1
. ./tests/common.sh
pass=0; fail=0
t() { # name, expected(allow|deny), container ("host" = run on the host), command...
  name=$1; want=$2; c=$3; shift 3
  if [ "$c" = host ]; then "$@" >/dev/null 2>&1 && got=allow || got=deny
  else docker exec "$c" "$@" >/dev/null 2>&1 && got=allow || got=deny; fi
  if [ "$got" = "$want" ]; then pass=$((pass+1)); r=PASS; else fail=$((fail+1)); r=FAIL; fi
  printf '%-4s %-66s expected=%s got=%s\n' "$r" "$name" "$want" "$got"
}
chat='{"messages":[{"role":"user","content":"ping"}]}'
LDAPBASE="dc=chuv-sim,dc=local"
reset_lock() { # lockout state is operational data and cannot be edited: delete and re-add the test account
  docker exec -e LDAPTLS_REQCERT=never directory sh -c "
    ldapdelete -x -H ldaps://127.0.0.1 -D cn=admin,$LDAPBASE -w AdminSimPass-1 uid=dr.lockout,ou=people,$LDAPBASE
    printf 'dn: uid=dr.lockout,ou=people,$LDAPBASE\\nobjectClass: inetOrgPerson\\nuid: dr.lockout\\ncn: Dr Lockout (test account)\\nsn: Lockout\\nuserPassword: Lockout-Pass-1\\n' | ldapadd -x -H ldaps://127.0.0.1 -D cn=admin,$LDAPBASE -w AdminSimPass-1" >/dev/null 2>&1
}
echo "mfa=$(docker exec vpn-gateway printenv MFA)  llm-scheme=$SCHEME"
reset_lock; vpn_down

echo "== zone 1: external. Without a tunnel nothing internal is reachable"
t "no tunnel: clinician cannot reach corp-ws"              deny  clinician ping -c1 -W2 10.20.0.20
t "no tunnel: clinician cannot reach LLM inference"        deny  clinician $CU -s -m 4 -f $URL/v1/models
t "no tunnel: only the VPN port is exposed (tcp/22 closed)" deny clinician nc -z -w2 172.20.0.2 22

echo "== machine and user identity at the gateway (H.TEC.11, 19, 20)"
t "no client certificate: no tunnel"                       deny  clinician env VPN_CERT=none sh /roles/vpn-up.sh
t "certificate from another CA: no tunnel"                 deny  clinician env VPN_CERT=rogue sh /roles/vpn-up.sh
t "valid certificate, wrong password: no tunnel"           deny  clinician env VPN_PASS=wrong-password sh /roles/vpn-up.sh
t "valid certificate, unknown user: no tunnel"             deny  clinician env VPN_USER=nobody sh /roles/vpn-up.sh
if [ "$(docker exec vpn-gateway printenv MFA)" = totp ]; then
  t "MFA variant: password with wrong TOTP code: no tunnel" deny  clinician env VPN_TOTP=000000 sh /roles/vpn-up.sh
fi
t "named account works before any failure (dr.lockout)"    allow clinician env VPN_USER=dr.lockout VPN_PASS=Lockout-Pass-1 sh /roles/vpn-up.sh
vpn_down
# failed logins go through the gateway's own login script: same directory path, about 1 s each,
# so all five fall inside the 60 s counting window of the policy
LOGIN="env MFA=none username=dr.lockout common_name=lockout-test untrusted_ip=172.20.0.10 /usr/local/bin/auth-ldap.sh"
for i in 1 2 3 4 5; do docker exec vpn-gateway env password=bad $LOGIN >/dev/null 2>&1; done
t "5 failed logins lock the account (correct password denied)" deny vpn-gateway env password=Lockout-Pass-1 $LOGIN
t "failed logins are logged with user and source"          allow vpn-gateway grep -q 'user=dr.lockout.*result=FAIL' /var/log/vpn-auth.log
reset_lock

echo "== zone 2: DMZ gateway, authenticated corporate segment"
vpn_up || echo "(!) clinician login failed, the next lines will fail"
sleep 1
t "tunnel: clinician reaches the gateway (10.99.0.1)"      allow clinician ping -c1 -W2 10.99.0.1
t "tunnel: clinician reaches corp-ws (corp segment)"       allow clinician ping -c1 -W2 10.20.0.20
t "successful login is logged with user and certificate"   allow vpn-gateway grep -q 'user=dr.martin cn=clinician-device-01.*result=OK' /var/log/vpn-auth.log
t "DMZ: gateway reaches the directory over LDAPS only"     allow vpn-gateway nc -z -w2 10.20.0.5 636
t "DMZ: gateway cannot reach corp-ws (dmz-fw)"             deny  vpn-gateway ping -c1 -W2 10.20.0.20
t "DMZ: gateway cannot reach the LLM from its own address" deny  vpn-gateway $CU -s -m 4 -f $URL/v1/models

echo "== zone 3: restricted clinical segment"
t "tunnel: clinician -> LLM inference :8000"               allow clinician $CU -s -m 8 -f $URL/v1/models
t "tunnel: clinician -> LLM chat completion"               allow clinician sh -c "$CU -s -m 60 -f -H 'Content-Type: application/json' -d '$chat' $URL/v1/chat/completions"
t "tunnel: clinician -> LLM admin decoy :8001 blocked"     deny  clinician curl -s -m 4 -f http://$LLM:8001/
t "tunnel: clinician ping LLM blocked (no ICMP rule)"      deny  clinician ping -c1 -W2 $LLM
t "corp-ws -> LLM inference :8000"                         allow corp-ws $CU -s -m 8 -f $URL/v1/models
t "corp-ws -> LLM admin decoy :8001 blocked"               deny  corp-ws curl -s -m 4 -f http://$LLM:8001/
t "corp-ws ping LLM blocked"                               deny  corp-ws ping -c1 -W2 $LLM
t "LLM cannot initiate to corp-ws (clinical -> corp)"      deny  meditron-llm ping -c1 -W2 10.20.0.20
t "LLM does not route between its interfaces (ip_forward=0)" allow meditron-llm grep -qx 0 /proc/sys/net/ipv4/ip_forward
if [ "$SCHEME" = https ]; then
  t "LLM endpoint is TLS: plain HTTP on 8000 does not answer" deny clinician curl -s -m 4 -f http://$LLM:8000/v1/models
fi

if [ "$(docker exec meditron-llm printenv LLM_MODE)" = stub ]; then
  t "clinical segment has no way out (LLM cannot reach the internet)" deny meditron-llm ping -c1 -W2 1.1.1.1
fi
echo "== logging (H.TEC.23): the LLM sees the tunnel address, the gateway maps it to a user"
t "LLM log shows a tunnel source address (no NAT)"         allow host sh -c "docker logs meditron-llm 2>&1 | grep -q 'src=10.99.0.'"
t "gateway session log maps the tunnel address to the user" allow vpn-gateway grep -q 'event=client-connect user=dr.martin' /var/log/vpn-sessions.log
echo; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]
