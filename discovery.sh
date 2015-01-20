#!/bin/sh

ADDR="10.91.11.202"
sudo mount -o remount,rw /dev/mapper/atomicos-root /usr/
cat <<EOF > /usr/lib/systemd/system/etcd.service
[Unit]
Description=etcd

[Service]
Environment=ETCD_DATA_DIR=/var/lib/etcd
Environment=ETCD_NAME=%m
ExecStart=/bin/etcd \
  -addr=${ADDR}:4001 \
  -peer-addr=${ADDR}:7001 \
Restart=always
RestartSec=10s
EOF
systemctl daemon-reload
systemctl restart etcd.service
systemctl status etcd.service