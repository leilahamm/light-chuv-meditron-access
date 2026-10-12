# helper: name of the interface that holds an address in a given prefix
iface_for() { ip -o -4 addr show | awk -v p="$1" '$4 ~ "^"p {print $2; exit}'; }
