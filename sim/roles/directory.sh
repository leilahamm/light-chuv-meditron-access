#!/bin/sh
# Hospital directory. Stands in for Active Directory: named accounts (H.TEC.19, 20),
# password policy with lockout after 5 failures in 60 s for 20 min (H.TEC.17 g),
# LDAPS only (H.TEC.12). Bind attempts are logged by slapd (H.TEC.23).
set -e
# replies to the DMZ gateway and to tunnel clients go back through the DMZ firewall
ip route add 10.10.0.0/24 via 10.20.0.253
ip route add 10.99.0.0/24 via 10.20.0.253


mkdir -p /run/openldap /var/lib/openldap/openldap-data /etc/openldap
cat > /etc/openldap/slapd.conf <<'CONF'
include /etc/openldap/schema/core.schema
include /etc/openldap/schema/cosine.schema
include /etc/openldap/schema/inetorgperson.schema
pidfile /run/openldap/slapd.pid
argsfile /run/openldap/slapd.args
modulepath /usr/lib/openldap
moduleload back_mdb.so
moduleload ppolicy.so
TLSCACertificateFile /pki/pub/ca.crt
TLSCertificateFile /pki/dir/dir.crt
TLSCertificateKeyFile /pki/dir/dir.key

access to attrs=userPassword,pwdFailureTime,pwdAccountLockedTime
    by anonymous auth
    by * none
access to * by * read

database mdb
maxsize 104857600
suffix "dc=chuv-sim,dc=local"
rootdn "cn=admin,dc=chuv-sim,dc=local"
rootpw AdminSimPass-1
directory /var/lib/openldap/openldap-data
index objectClass eq

overlay ppolicy
ppolicy_default "cn=default,ou=policies,dc=chuv-sim,dc=local"
ppolicy_use_lockout
CONF

if [ ! -f /var/lib/openldap/openldap-data/data.mdb ]; then
  slapadd -f /etc/openldap/slapd.conf -l /roles/seed.ldif
fi
echo "[directory] up, LDAPS on 636, plain LDAP not offered"
# -d 256 keeps slapd in the foreground and logs every connection, bind and result to docker logs
exec slapd -d 256 -f /etc/openldap/slapd.conf -h "ldaps://0.0.0.0:636/"