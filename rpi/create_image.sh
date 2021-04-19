#!/bin/bash

# Settings
HOSTNAME="${1:-riasc-agent}"

IMAGE_FILE="2021-03-04-raspios-buster-armhf-lite"
IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-03-25/${IMAGE_FILE}.zip"

RIASC_IMAGE_FILE=${IMAGE_FILE/raspios/riasc-raspios}

MOUNT_DIR="$(pwd)/mount"
BOOT_DIR="${MOUNT_DIR}/boot"

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

# Patching image
echo "Patching image with guestfish..."
guestfish <<EOF
echo "Loading image..."
add ${IMAGE_FILE}.img

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
copy-in rootfs/etc/ rootfs/usr/ /
copy-in riasc.yaml /boot

echo "Enable SSH on boot..."
touch /boot/ssh

echo "Setting hostname..."
write /etc/hostname "${HOSTNAME}"

echo "Enable systemd risac-update service..."
ln-sf /etc/systemd/system/risac-update.service /etc/systemd/system/multi-user.target.wants/risac-update.service
EOF

# Zip image
echo "Zipping image..."
zip ${RIASC_IMAGE_FILE}.zip ${IMAGE_FILE}.img
