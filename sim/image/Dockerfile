# One small image shared by every node. The role of each container is set by the
# script mounted at /roles/<role>.sh, so the simulation builds once and fast.
FROM alpine:3.20
RUN apk add --no-cache iproute2 iptables wireguard-tools curl bind-tools jq python3 busybox-extras tcpdump
CMD ["sleep", "infinity"]
