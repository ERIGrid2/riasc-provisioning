#!/bin/bash

IMAGE_FILE="2021-03-04-raspios-buster-armhf-lite"
IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-03-25/${IMAGE_FILE}.zip"

MOUNT_DIR="$(pwd)/mount"
BOOT_DIR="${MOUNT_DIR}/boot"

# Download image
[ -f ${IMAGE_FILE}.zip ] || wget ${IMAGE_URL}

# Unzip image
[ -f ${IMAGE_FILE}.img ] || unzip ${IMAGE_FILE}.zip

guestfish <<EOF
add ${IMAGE_FILE}.img
run
list-filesystems
mount /dev/sda2 /
df-h
copy-in rootfs/etc/ rootfs/usr/ /
ln-sf /etc/systemd/system/first-boot.service /etc/systemd/system/sysinit.target.wants/first-boot.service
EOF
