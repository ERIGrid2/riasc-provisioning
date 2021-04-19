#!/bin/sh

# Settings
CONFIG_FILE=/boot/riasc.yaml
EXTRA_VARS_FILE=/tmp/extra_vars.yml

YQ_BINARY=yq_linux_arm64
YQ_VERSION=v4.6.3

# Functions
function config() {
	[ -f ${CONFIG_FILE} ] && yq eval ".$1" ${CONFIG_FILE}
}

# Install yq
wget https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY} -O /usr/local/bin/yq
chmod +x /usr/local/bin/yq

# Install Ansible
apt update
apt install ansible

# Run Ansible Playbook
yq eval .variables ${CONFIG_FILE} ${EXTRA_VARS_FILE}

ansible-pull \
	--accept-host-key \
	--url https://github.com/erigrid2/k3s-ansible \
	--extra-vars @${EXTRA_VARS_FILE} \
	--inventory inventory/
	mobile-unit.yml


systemd reboot
