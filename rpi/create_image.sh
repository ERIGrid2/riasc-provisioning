#!/bin/bash

set -e

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
pushd ${SCRIPT_PATH}

# Settings
HOSTNAME="${1:-riasc-agent}"
TOKEN="${2:-XXXXX}"

IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/${IMAGE_FILE}.zip"

IMAGE_FILE="2021-05-07-raspios-buster-armhf-lite"
RIASC_IMAGE_FILE="$(date +%Y-%m-%d)-riasc-raspios-buster-armhf-lite"

function check_command() {
	if ! command -v $1 &> /dev/null; then
		echo "$1 could not be found"
		exit
	fi
}

# Show config
echo "Using hostname: ${HOSTNAME}"
echo "Using token: ${TOKEN}"

# Check that required commands exist
echo "Check if required commands are installed..."
check_command guestfish
check_command wget
check_command unzip
check_command zip

# Download image
if [ ! -f ${IMAGE_FILE}.zip ]; then
	echo "Downloading image.."
	wget ${IMAGE_URL}
fi

# Unzip image
if [ ! -f ${IMAGE_FILE}.img ]; then
	echo "Unzipping image..."
	unzip ${IMAGE_FILE}.zip
fi

cp ${IMAGE_FILE}.img ${RIASC_IMAGE_FILE}.img

# Prepare config
cp ../common/riasc.yaml riasc.yaml
sed -i \
	-e "s/XXXXX/${TOKEN}/g" \
	-e "s/riasc-agent/${HOSTNAME}/g" \
	riasc.yaml

# Prepare systemd-timesyncd config
cat > fallback-ntp.conf <<EOF
[Time]
FallbackNTP=pool.ntp.org
EOF

# Download PGP keys for verifying Ansible Git commits
mkdir -p keys
wget -P keys https://keys.openpgp.org/vks/v1/by-fingerprint/09BE3BAE8D55D4CD8579285A9675EAC34897E6E2 # Steffen Vogel (RWTH)

# Patching image
echo "Patching image with guestfish..."
guestfish <<EOF
echo "Loading image..."
add ${RIASC_IMAGE_FILE}.img

echo "Start virtual environment..."
run

echo "Available filesystems:"
list-filesystems

echo "Mounting filesystems..."
mount /dev/sda2 /
mount /dev/sda1 /boot

echo "Available space:"
df-h

echo "Copy files into image..."
copy-in rootfs/etc/ /
copy-in riasc.yaml /boot

mkdir-p /etc/systemd/timesyncd.conf.d/
copy-in fallback-ntp.conf /etc/systemd/timesyncd.conf.d/

mkdir-p /usr/local/bin
copy-in ../common/riasc-update.sh /usr/local/bin/
chmod 755 /usr/local/bin/riasc-update.sh

copy-in keys/ /boot/keys/

echo "Enable SSH on boot..."
touch /boot/ssh

echo "Setting hostname..."
write /etc/hostname "${HOSTNAME}"

echo "Enable systemd risac-update service..."
ln-sf /etc/systemd/system/risac-update.service /etc/systemd/system/multi-user.target.wants/riasc-update.service
EOF

# Zip image
echo "Zipping image..."
rm -f ${RIASC_IMAGE_FILE}.zip
zip ${RIASC_IMAGE_FILE}.zip ${RIASC_IMAGE_FILE}.img

echo "Please write the new image to an SD card:"
echo "  dd bs=1M if=${RIASC_IMAGE_FILE}.img of=/dev/sdX"
