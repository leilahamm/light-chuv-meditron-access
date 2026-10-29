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
reset_lock() { # clear the lockout state of the test account so the script can be rerun
  for a in pwdAccountLockedTime pwdFailureTime; do
    docker exec -e LDAPTLS_REQCERT=never directory sh -c "printf 'dn: uid=dr.lockout,ou=people,$LDAPBASE\nchangetype: modify\ndelete: $a\n' | ldapmodify -x -H ldaps://127.0.0.1 -D cn=admin,$LDAPBASE -w AdminSimPass-1" >/dev/null 2>&1
  done
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
# Failed logins go straight to the gateway's login check, so all 5 land inside the 60 s failure window
# (5 full VPN attempts can take longer than that and the failures then expire).
# With MFA=totp the login check reads the code first, so a failed login must carry a valid code
# and a wrong password to reach the directory and count as a failure there.
for i in 1 2 3 4 5; do
  docker exec -e common_name=clinician-device-01 -e untrusted_ip=172.20.0.10 vpn-gateway sh -c '
    pw=bad
    if [ "${MFA:-none}" = totp ]; then pw="bad$(oathtool --totp -b "$(cat /pki/gw/totp-dr.lockout 2>/dev/null || cat /pki/gw/totp-dr.martin)")"; fi
    username=dr.lockout password="$pw" sh /usr/local/bin/auth-ldap.sh' >/dev/null 2>&1
done
t "5 failed logins lock the account (correct password denied)" deny clinician env VPN_USER=dr.lockout VPN_PASS=Lockout-Pass-1 sh /roles/vpn-up.sh
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
# first chat call after start-up can be slow or fail against the real model (cold start on RCP).
# Do it once, show the status and time, so a failure below can be read against it.
echo "-- warm-up chat request (informational, not counted)"
docker exec clinician sh -c "$CU -s -m 90 -o /dev/null -w 'warm-up: HTTP %{http_code} in %{time_total}s\n' -H 'Content-Type: application/json' -d '$chat' $URL/v1/chat/completions" || echo "warm-up: no answer"
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

echo "== logging (H.TEC.23): the LLM sees the tunnel address, the gateway maps it to a user"
t "LLM log shows a tunnel source address (no NAT)"         allow host sh -c "docker logs meditron-llm 2>&1 | grep -q 'src=10.99.0.'"
t "gateway session log maps the tunnel address to the user" allow vpn-gateway grep -q 'event=client-connect user=dr.martin' /var/log/vpn-sessions.log
echo; echo "passed=$pass failed=$fail"; [ "$fail" -eq 0 ]