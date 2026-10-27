# One small image shared by every node. The role of each container is set by the
# script mounted at /roles/<role>.sh, so the simulation builds once and fast.
FROM alpine:3.20
RUN apk add --no-cache \
      iproute2 iproute2-tc iptables curl bind-tools jq python3 busybox-extras tcpdump \
      openvpn openssl \
      openldap openldap-back-mdb openldap-overlay-ppolicy openldap-clients \
      oath-toolkit-oathtool
CMD ["sleep", "infinity"]
