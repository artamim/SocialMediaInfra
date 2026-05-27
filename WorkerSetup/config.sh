#!/bin/bash

sudo kubeadm join --config join.yml

CONFIG_FILE="/var/lib/kubelet/config.yaml"

# Append the 3 lines at the end
cat <<EOF | sudo tee -a $CONFIG_FILE > /dev/null

# Added settings
rotateCertificates: true
serverTLSBootstrap: true
cgroupDriver: systemd
EOF

sudo systemctl daemon-reload
sudo systemctl restart kubelet