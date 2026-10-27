#!/bin/sh
# DMZ VPN gateway (OpenVPN). Authentication: client certificate from the hospital CA, plus a named
# account checked against the directory (plus a TOTP code when MFA=totp). After that the tunnel is
# routed toward the corporate segment: network-position trust, no posture check, no
# re-verification (reneg-sec 0). The client address is NOT hidden by NAT, so downstream logs
# show the VPN address.
set -e
. /roles/lib.sh
EXT=$(iface_for 172.20.0.); DMZ=$(iface_for 10.10.0.)

install -m 755 /roles/auth-ldap.sh /usr/local/bin/auth-ldap.sh
install -m 755 /roles/session.sh /usr/local/bin/session.sh
mkdir -p /etc/openvpn
cat > /etc/openvpn/server.conf <<'CONF'
port 1194
proto udp
dev tun
topology subnet
server 10.99.0.0 255.255.255.0
ca /pki/pub/ca.crt
cert /pki/gw/gw.crt
key /pki/gw/gw.key
dh none
remote-cert-tls client
verify-client-cert require
data-ciphers AES-256-GCM
tls-version-min 1.2
reneg-sec 0
keepalive 10 60
persist-key
persist-tun
script-security 3
auth-user-pass-verify /usr/local/bin/auth-ldap.sh via-env
client-connect /usr/local/bin/session.sh
client-disconnect /usr/local/bin/session.sh
push "route 10.20.0.0 255.255.255.0"
push "route 10.30.0.0 255.255.255.0"
status /var/log/openvpn-status.log 5
verb 3
CONF
echo "setenv MFA ${MFA:-none}" >> /etc/openvpn/server.conf

# everything behind the gateway is reached through the DMZ firewall
ip route add 10.20.0.0/24 via 10.10.0.254
ip route add 10.30.0.0/24 via 10.10.0.254

iptables -F; iptables -t nat -F
iptables -P INPUT DROP; iptables -P FORWARD DROP; iptables -P OUTPUT ACCEPT
iptables -A INPUT -i lo -j ACCEPT
iptables -A INPUT -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A INPUT -i "$EXT" -p udp --dport 1194 -j ACCEPT          # only the VPN port is exposed
iptables -A INPUT -i tun+ -p icmp -j ACCEPT
# once authenticated, tunnel traffic is forwarded into the DMZ and on to the corporate side
iptables -A FORWARD -i tun+ -o "$DMZ" -j ACCEPT
iptables -A FORWARD -m state --state ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -j LOG --log-prefix "vpn-gateway DROP: " --log-level 4
echo "[vpn-gateway] up. ext=$EXT dmz=$DMZ mfa=${MFA:-none}"
exec openvpn --config /etc/openvpn/server.conf
