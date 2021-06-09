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

# Wait for internet connectivity
SERVER="https://fein-aachen.org"
TIMEOUT=10
COUNTER=0
while (( COUNTER < TIMEOUT )) && ! wget -q -O /dev/null ${SERVER}; do
    echo "Waiting for network..."
    sleep 1
    (( COUNTER++ ))
done

if (( COUNTER == TIMEOUT )); then
	echo -e "Failed to get internet connectivity. Aborting"
	exit -1
fi

echo ""
echo "#########################"
echo "# Starting RIasC update #"
echo "#########################"
echo ""


# Install yq
if ! command -v yq &> /dev/null; then
	YQ_BINARY="yq_linux_${ARCH}"
	YQ_VERSION="v4.7.0"
	YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"

	wget -q ${YQ_URL} -O /usr/local/bin/yq
	chmod +x /usr/local/bin/yq
fi

# Install Ansible
echo "Installing required packages"
if ! command -v ansible &> /dev/null; then
	case ${OS} in
		Fedora|CentOS|'Red Hat Enterprise Linux')
			yum install -qy ansible git
			;;

		Debian|Ubuntu|'Raspbian GNU/Linux')
			apt-get update -qq
			apt-get install -qq ansible git
			;;
	esac
fi

# Update system hostname to match Ansible inventory
HOSTNAME=$(config .hostname)
echo "Updating hostname to: ${HOSTNAME}"
echo ${HOSTNAME} > /etc/hostname
sed -ie "s/raspberrypi/${HOSTNAME}/g" /etc/hosts
hostnamectl set-hostname ${HOSTNAME}


# Run Ansible playbook
ansible-pull \
	--accept-host-key \
	--url $(config .ansible.url) \
	--extra-vars $(config --tojson --indent 0 .ansible.variables) \
	--inventory $(config .ansible.inventory) \
	$(config '.ansible.extra_args // [ ] | join(" ")') \
	$(config .ansible.playbook)

# Print node details
echo "Operating System: ${OS}"
echo "Operating System Version: ${VER}"
echo "Architecture: ${ARCH}"
echo "Hostname: ${HOSTNAME}"
echo "Full config:"
config .

echo ""
echo "########################################"
echo "# RIasC update completed successfully! #"
echo "########################################"
echo ""
