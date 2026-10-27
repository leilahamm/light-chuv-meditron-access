#!/bin/sh
# The LLM replies straight to the real source (corporate host or VPN address) through corp-fw.
# ip_forward stays 0 (set in compose): no routing between the LLM's interfaces (H.TEC.13).
# "No way out": the stub has no default route. The rcp profile may only leave via llm-egress.
set -e
ip route add 10.20.0.0/24 via 10.30.0.254
ip route add 10.99.0.0/24 via 10.30.0.254
if [ "$LLM_MODE" = "rcp" ]; then
  ip route replace default via 172.21.0.1
else
  ip route del default 2>/dev/null || true
fi
exec python3 /llm/server.py