#!/bin/bash

set -e

CONFIG_FILE=${CONFIG_FILE:-/boot/riasc.yaml}

# We disable SSL verification for all commands and rely on PGP signatures
# As some setup will boot up with a wrong system time which
# will result cause in all certs to fail verification as they appear to
# be expired.
WGET_OPTS="--no-check-certificate --quiet"
APT_OPTS="--option Acquire::https::Verify-Peer=false -qq"
YUM_OPTS="--setopt=sslverify=false --quiet --yes"

# Tee output to syslog
exec 1> >(logger -st "riasc-update") 2>&1

# TTY handling
FG_TTY=$(fgconsole)
TTY=$(tty | sed -n "s|/dev/tty\(.*\)|\1|p")
if [ -n "${TTY}" ] && (( ${FG_TTY} != ${TTY} )); then
	chvt ${TTY}
	reset
fi

# Helper functions
function config() {
	[ -f ${CONFIG_FILE} ] && yq eval "$@" ${CONFIG_FILE}
}

function log() {
	echo
	echo -e "\e[32m###\e[0m $1"
}

function warn() {
	echo -e "\e[33m#\e[0m $1"
}

function die() {
	echo -e "\e[31m#\e[0m $1"
	exit -1
}

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
	OS=${DISTRIB_ID}
	VER=${DISTRIB_RELEASE}
else
	die "Failed to determine distro"
fi

# Detect architecture
case $(uname -m) in
	aarch64) ARCH="arm64" ;;
	armv*)   ARCH="arm" ;;
	x86_64)  ARCH="amd64" ;;
esac

# Validate config
if ! yq eval true ${CONFIG_FILE} > /dev/null; then
	die "Failed to parse config file: ${CONFIG_FILE}"
fi

# Wait for internet connectivity
SERVER="https://github.com"
TIMEOUT=600
COUNTER=0
while (( COUNTER++ < TIMEOUT )) && ! wget ${WGET_OPTS} --output-document=/dev/null ${SERVER}; do
    echo "Waiting for network..."
    sleep 1
done
if (( COUNTER == TIMEOUT )); then
	die "Failed to get internet connectivity. Aborting"
fi

log "Starting RIasC update at $(date)"

# Update system hostname to match Ansible inventory
HOSTNAME=$(config .hostname)

log "Updating hostname to: ${HOSTNAME}"
echo ${HOSTNAME} > /etc/hostname
sed -ie "s/raspberrypi/${HOSTNAME}/g" /etc/hosts
hostnamectl set-hostname ${HOSTNAME}

log "Renewing DHCP lease to reflect new hostname"
dhclient -r

# Install yq
if ! command -v yq &> /dev/null; then
	log "Installing yq"
	YQ_BINARY="yq_linux_${ARCH}"
	YQ_VERSION="v4.7.0"
	YQ_CHECKSUM="ec857c8240fda5782c3dd75b54b93196fa496a9bcf7c76979bb192b38f76da31"
	YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"

	wget ${WGET_OPTS} ${YQ_URL} -O /usr/local/bin/yq
 	echo "${YQ_CHECKSUM} /usr/local/bin/yq" | sha256sum --check --quiet || exit -1
	chmod +x /usr/local/bin/yq
fi

# Install Ansible
log "Installing required packages"
if ! command -v ansible &> /dev/null; then
	case ${OS} in
		Fedora|CentOS|'Red Hat Enterprise Linux')
			yum ${YUM_OPTS} install ansible git
			;;

		Debian|Ubuntu|'Raspbian GNU/Linux')
			apt-get ${APT_OPTS} update
			apt-get ${APT_OPTS} install ansible git
			;;
	esac
fi

# Import GPG keys for verifying Ansible commits
log "Importing GPG keys for verify Ansible commits"
KEYS = $(config '.ansible.keys | join(" ")')
KEYSERVER = $(config '.ansible.keyserver')
gpg --import /boot/keys/*
for KEY in ${KEYS} do
	gpg --keyserver ${KEYSERVER} --recv-keys ${KEY} || warn "Failed to fetch key ${KEY}"
done

# Run Ansible playbook
log "Running Ansible playbook..."
ANSIBLE_FORCE_COLOR=1 \
ansible-pull \
	--verify-commit \
	--url $(config .ansible.url) \
	--extra-vars $(config --tojson --indent 0 .ansible.variables) \
	--inventory $(config .ansible.inventory) \
	$(config '.ansible.extra_args // [ ] | join(" ")') \
	$(config '.ansible.playbook')

# Print node details
log "Node details:"
echo
echo "Operating System: ${OS}"
echo "Operating System Version: ${VER}"
echo "Architecture: ${ARCH}"
echo "Hostname: ${HOSTNAME}"
echo
echo "Full config:"
config --colors '... comments=""'

log "Finished RIasC update successfully at $(date)!"

if [ -n "${TTY}" ]; then
	echo ""
	echo "Please press a key to return to the login..."
	read

	chvt ${FG_TTY}
fi
