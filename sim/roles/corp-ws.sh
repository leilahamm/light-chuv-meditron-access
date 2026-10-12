#!/bin/sh
ip route add 10.30.0.0/24 via 10.20.0.254
exec sleep infinity
