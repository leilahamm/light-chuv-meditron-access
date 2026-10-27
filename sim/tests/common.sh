# shared by the test scripts (sourced). Run them from the sim/ directory on the host.
LLM=10.30.0.10
if [ "$(docker exec meditron-llm printenv LLM_TLS 2>/dev/null)" = "off" ]; then
  SCHEME=http; CA=""
else
  SCHEME=https; CA="--cacert /pki/pub/ca.crt"
fi
URL="$SCHEME://$LLM:8000"
# curl line usable inside a container: $(cu) -s ... $URL/v1/models
CU="curl $CA"
vpn_up()   { docker exec "$@" clinician sh /roles/vpn-up.sh >/dev/null 2>&1; }
vpn_down() { docker exec clinician sh /roles/vpn-down.sh >/dev/null 2>&1; }
