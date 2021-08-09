#!/bin/bash

set -e

# Helper functions
function log() {
	echo
	echo -e "\e[32m###\e[0m $1"
}

# Find configuration file
if [ -z "${CONFIG_FILE}" ]; then
	for DIR in /boot /etc .; do
		if [ -f "${DIR}/riasc.yaml" ]; then
			CONFIG_FILE="${DIR}/riasc.yaml"
			break
		fi
	done
fi

# Hacky way of getting configured hostname as we dont have yq here yet (no network)
HOSTNAME=$(sed -n -e 's/#.*//;s/^hostname: \(.*\)/\1/p' ${CONFIG_FILE})

log "Setting system hostname from RIasC configuration file"

log "Updating hostname to: ${HOSTNAME}"

# Fix for broken permissions
# See: https://github.com/coreos/bugs/issues/941#issuecomment-151674260
chown root:root /etc

hostnamectl set-hostname ${HOSTNAME}
sed -ie "s/raspberrypi/${HOSTNAME}/g" /etc/hosts
