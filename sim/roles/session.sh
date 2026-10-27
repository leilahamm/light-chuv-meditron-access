#!/bin/sh
# OpenVPN client-connect / client-disconnect hook. Maps each VPN address to the account and
# certificate that holds it, so a source address seen later (for example in the LLM log) can be
# attributed to a user.
line="$(date '+%Y-%m-%dT%H:%M:%S') vpn-session event=${script_type:-?} user=${username:-?} cn=${common_name:-?} real_ip=${trusted_ip:-?} vpn_ip=${ifconfig_pool_remote_ip:-?}"
echo "$line" >> /var/log/vpn-sessions.log
echo "$line" > /proc/1/fd/1 2>/dev/null || true
exit 0
