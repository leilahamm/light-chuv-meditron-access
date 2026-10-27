#!/bin/sh
# Add WAN-like delay and loss on the clinician's uplink, so latency is not that of a local bridge.
# Usage: ./tests/netem.sh on [delay] [jitter] [loss]   |   ./tests/netem.sh off
# Defaults are placeholders for a mobile link. Replace them with measured values before drawing conclusions.
case "$1" in
  on)  docker exec clinician tc qdisc replace dev eth0 root netem delay "${2:-60ms}" "${3:-20ms}" loss "${4:-0.5%}" && echo "netem on" ;;
  off) docker exec clinician tc qdisc del dev eth0 root 2>/dev/null; echo "netem off" ;;
  *)   echo "usage: $0 on [delay] [jitter] [loss] | off"; exit 1 ;;
esac
