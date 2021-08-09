#!/bin/bash

set -e

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

# TTY handling
FG_TTY=$(fgconsole || echo 0)
TTY=$(tty | sed -n "s|/dev/tty\(.*\)|\1|p")
if [ -n "${TTY}" ] && (( ${FG_TTY} != ${TTY} )); then
	chvt ${TTY}
	reset
fi

# Tee output to syslog
exec 1> >(logger -st "riasc-update") 2>&1

# Detect distro
if [ -f /etc/os-release ]; then # freedesktop.org and systemd
	. /etc/os-release
	OS=$NAME
	VER=$VERSION_ID
elif type lsb_release >/dev/null 2>&1; then # linuxbase.org
	OS=$(lsb_release -si)
	VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then # For some versions of Debian/Ubuntu without lsb_release command
	. /etc/lsb-release
	OS=${DISTRIB_ID}
	VER=${DISTRIB_RELEASE}
else
	die "Failed to determine Linux distribution"
fi

# Detect architecture
case $(uname -m) in
	aarch64) ARCH="arm64" ;;
	armv*)   ARCH="arm" ;;
	x86_64)  ARCH="amd64" ;;
esac

# Wait for internet connectivity
log "Wait for internet connectivity"
SERVER="https://github.com"
TIMEOUT=600
COUNTER=0
while (( COUNTER++ < TIMEOUT )) && ! wget --no-check-certificate --quiet --output-document=/dev/null ${SERVER}; do
    echo "Waiting for network..."
    sleep 1
done
if (( COUNTER == TIMEOUT )); then
	die "Failed to get internet connectivity. Aborting"
fi

# Force time-sync via HTTP if NTP time-sync fails
if ! timeout 10 /usr/lib/systemd/systemd-time-wait-sync 2&>1 > /dev/null; then
	log "Falling back to HTTP time-synchronization as NTP is broken"
	date -s "$(curl -s --head http://google.com | grep ^Date: | sed 's/Date: //g')"
fi

# Installing yq
if ! command -v yq &> /dev/null; then
	log "Installing yq"

	YQ_BINARY="yq_linux_${ARCH}"
	YQ_VERSION="v4.7.0"
	YQ_URL="https://github.com/mikefarah/yq/releases/download/${YQ_VERSION}/${YQ_BINARY}"

	wget --quiet ${YQ_URL}
	chmod +x ${YQ_BINARY}
	mv ${YQ_BINARY} /usr/local/bin/yq
fi

# Installing required packages
log "Installing required packages"
if ! command -v ansible &> /dev/null; then
	case ${OS} in
		Fedora|CentOS|'Red Hat Enterprise Linux')
			yum --quiet --yes install ansible git htpdate
			;;

		Debian|Ubuntu|'Raspbian GNU/Linux')
			apt-get -qq update
			apt-get -qq install ansible git htpdate
			;;
	esac
fi

# Find configuration file
if [ -z "${CONFIG_FILE}" ]; then
	for DIR in /boot /etc .; do
		if [ -f "${DIR}/riasc.yaml" ]; then
			CONFIG_FILE="${DIR}/riasc.yaml"
			break
		fi
	done
fi

# Validate config
log "Validating config file..."
if ! config true > /dev/null; then
	die "Failed to parse config file: ${CONFIG_FILE}"
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

# Import GPG keys for verifying Ansible commits
log "Importing GPG keys for verify Ansible commits"
KEYS=$(config '.ansible.keys | join(" ")')
KEYSERVER=$(config '.ansible.keyserver')
if [ -d /boot/keys/ ]; then
	gpg --import /boot/keys/*
fi
for KEY in ${KEYS}; do
	timeout ${TIMEOUT} gpg --keyserver ${KEYSERVER} --recv-keys ${KEY} || \
	wget --timeout=${TIMEOUT} --quiet --output-document=- https://keys.openpgp.org/vks/v1/by-fingerprint/${KEY} | gpg --import || \
	warn "Failed to fetch key ${KEY}"
done

# Gather Ansible options
ANSIBLE_EXTRA_VARS="$(config --tojson --indent 0 .ansible.variables)"
ANSIBLE_OPTS=" --url $(config .ansible.url)"
ANSIBLE_OPTS+=" --inventory $(config .ansible.inventory)"
ANSIBLE_OPTS+=" $(config '.ansible.extra_args // [ ] | join(" ")')"

if [ $(config '.ansible.verify_commit // true') == "true" ]; then
	ANSIBLE_OPTS+="--verify-commit"
fi

# Run Ansible playbook
log "Running Ansible playbook..."
ANSIBLE_FORCE_COLOR=1 \
ansible-pull ${ANSIBLE_OPTS} --extra-vars "${ANSIBLE_EXTRA_VARS}" $(config '.ansible.playbook // "site.yml"')

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
