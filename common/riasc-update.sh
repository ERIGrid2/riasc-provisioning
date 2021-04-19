#!/bin/bash

set -e

# Detect distro
if [ -f /etc/os-release ]; then
	# freedesktop.org and systemd
	. /etc/os-release
	OS=$NAME
	VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then
	# linuxbase.org
	OS=$(lsb_release -si)
	VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
	# For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	OS=$DISTRIB_ID
	VER=$DISTRIB_RELEASE
else
	echo -e "Failed to determine distro"
	exit -1
fi

# Detect architecture
case $(uname -m) in
	aarch64) ARCH="arm64" ;;
	armv*)   ARCH="arm" ;;
	x86_64)  ARCH="amd64" ;;
esac

# Helper functions
function config() {
	CONFIG_FILE=/boot/riasc.yaml

	[ -f ${CONFIG_FILE} ] && yq eval "$@" ${CONFIG_FILE}
}

# Install yq
if ! command -v yq &> /dev/null; then
	YQ_BINARY="yq_linux_${ARCH}"
	YQ_VERSION="v4.7.0"
	YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"

	wget ${YQ_URL} -O /usr/local/bin/yq
	chmod +x /usr/local/bin/yq
fi

# Install Ansible
if ! command -v ansible &> /dev/null; then
	case ${OS} in
		Fedora|CentOS|Red Hat Enterprise Linux)
			yum install -y ansible git
			;;

		Debian|Ubuntu)
			apt-get update
			apt-get install -y ansible git
			;;
	esac
fi

# Update system hostname to match Ansible inventory
config .hostname > /etc/hostname

EXTRA_VARS=

# Run Ansible playbook
ansible-pull \
	--accept-host-key \
	--url $(config .ansible.url) \
	--extra-vars $(config --tojson --indent 0 .ansible.variables) \
	--inventory $(config .ansible.inventory) \
	$(config '.ansible.extra_args // [ ] | join(" ")') \
	$(config .ansible.playbook)

echo "RIasC update completed."
