#!/bin/sh
# OpenVPN auth-user-pass-verify (via-env). Checks the named account against the directory over
# LDAPS. With MFA=totp the password field carries "<password><6-digit code>" and the code is
# checked first. Every attempt is logged with user and result (H.TEC.23).
export LDAPTLS_CACERT=/pki/pub/ca.crt
BASE="dc=chuv-sim,dc=local"
user="${username:-}"
pass="${password:-}"

log() {
  line="$(date '+%Y-%m-%dT%H:%M:%S') vpn-auth user=${user:-?} cn=${common_name:-?} src=${untrusted_ip:-?} $*"
  echo "$line" >> /var/log/vpn-auth.log
  echo "$line" > /proc/1/fd/1 2>/dev/null || true
}
fail() { log "result=FAIL reason=$1"; exit 1; }

# the user name goes into an LDAP DN, so only plain characters are accepted
case "$user" in
  ""|*[!A-Za-z0-9._-]*) fail "bad-username" ;;
esac
[ -n "$pass" ] || fail "empty-password"

if [ "${MFA:-none}" = "totp" ]; then
  code="${pass#"${pass%??????}"}"
  pass="${pass%??????}"
  case "$code" in
    [0-9][0-9][0-9][0-9][0-9][0-9]) ;;
    *) fail "totp-format" ;;
  esac
  seed=$(cat "/pki/gw/totp-$user" 2>/dev/null) || fail "no-totp-seed"
  ok=0
  now=$(date +%s)
  for off in -30 0 30; do
    exp=$(oathtool --totp -b "$seed" -N "$(date -u -d "@$((now + off))" '+%Y-%m-%d %H:%M:%S UTC')" 2>/dev/null)
    [ "$exp" = "$code" ] && ok=1
  done
  [ "$ok" = 1 ] || fail "totp-wrong"
fi

ldapwhoami -x -o nettimeout=5 -H ldaps://10.20.0.5 \
  -D "uid=$user,ou=people,$BASE" -w "$pass" >/dev/null 2>&1
rc=$?
case $rc in
  0)  log "result=OK"; exit 0 ;;
  49) fail "bad-password-or-locked" ;;
  *)  fail "directory-error-$rc" ;;
esac
