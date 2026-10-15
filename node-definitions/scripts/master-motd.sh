#!/usr/bin/env bash
set -e

MOTD_FILE="/etc/motd"
JOIN_CMD=$(sudo grep -A 1 "kubeadm join" /var/log/cloud-init-output.log | grep -vE "sudo|LIMA" | tail -n 2 | head -n 3)

sudo tee $MOTD_FILE > /dev/null <<EOF
#############################################################
#                                                           #
#          ----- Welcome to k8s Master node -----           #
#                                                           #
#############################################################
#  Run this on your nodes to join them to the cluster       #
#  and add "--control-plane" for Master nodes!              #
#############################################################

sudo $JOIN_CMD
EOF

sudo echo 'cat /etc/motd' | sudo tee -a /etc/profile
