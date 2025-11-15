#!/bin/bash
# patroni-bootstrap.sh
# Usage: sudo /usr/local/bin/patroni-bootstrap.sh <node-id> <host-ip>
NODE_ID="$1"
HOST_IP="$2"
if [ -z "$NODE_ID" ] || [ -z "$HOST_IP" ]; then
  echo "Usage: $0 <node-id> <host-ip>"
  exit 1
fi
sed -e "s/{{NODE_ID}}/$NODE_ID/g" -e "s/{{HOST_IP}}/$HOST_IP/g" /etc/patroni.yml.template > /etc/patroni.yml
systemctl daemon-reload
systemctl enable patroni
systemctl start patroni
