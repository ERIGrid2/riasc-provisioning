#!/bin/bash

set -e

SCRIPT_PATH=$(dirname $(realpath "${BASH_SOURCE[0]}"))
pushd ${SCRIPT_PATH}

# Settings
NODENAME="${NODENAME:-riasc-agent}"
TOKEN="${TOKEN:-XXXXX}"

FLAVOR=${FLAVOR:-erigrid}

case ${FLAVOR} in
	edgeflex)
		OS="ubuntu"
		;;

	erigrid)
		OS="raspios"
		;;
esac

case ${OS} in
	ubuntu)
		IMAGE_FILE="ubuntu-20.04.2-preinstalled-server-arm64+raspi"
		IMAGE_SUFFIX="img.xz"
		IMAGE_URL="https://cdimage.ubuntu.com/releases/20.04.2/release/${IMAGE_FILE}.${IMAGE_SUFFIX}"
		;;

	raspios)
		IMAGE_FILE="2021-05-07-raspios-buster-armhf-lite"
		IMAGE_SUFFIX="zip"
		IMAGE_URL="https://downloads.raspberrypi.org/raspios_lite_armhf/images/raspios_lite_armhf-2021-05-28/${IMAGE_FILE}.${IMAGE_SUFFIX}"
		;;
esac

RIASC_IMAGE_FILE="$(date +%Y-%m-%d)-riasc-${OS}"

function check_command() {
	if ! command -v $1 &> /dev/null; then
		echo "$1 could not be found"
		exit
	fi
}

# Show config
echo "Using hostname: ${NODENAME}"
echo "Using token: ${TOKEN}"

# Check that required commands exist
echo "Check if required commands are installed..."
check_command guestfish
check_command wget
check_command unzip
check_command zip
check_command xz
# dnf install guestfs-tools wget zip xz
# apt-get install libguestfs-tools wget unzip zip xz-utils

# Download image
if [ ! -f ${IMAGE_FILE}.${IMAGE_SUFFIX} ]; then
	echo "Downloading image..."
	wget ${IMAGE_URL}
fi

# Unzip image
if [ ! -f ${IMAGE_FILE}.img ]; then
	echo "Unzipping image..."
	case ${IMAGE_SUFFIX} in
		img.xz)
			unxz --keep --threads=0 ${IMAGE_FILE}.${IMAGE_SUFFIX}
			;;
		zip)
			unzip ${IMAGE_FILE}.${IMAGE_SUFFIX}
			;;
	esac
fi

echo "Copying image..."
cp ${IMAGE_FILE}.img ${RIASC_IMAGE_FILE}.img

# Prepare config
case ${FLAVOR} in
	erigrid)
		CONFIG_FILE="riasc.yaml"
		;;
	*)
		CONFIG_FILE="riasc.${FLAVOR}.yaml"
		;;
esac
cp ../common/${CONFIG_FILE} riasc.yaml

# Patch config
sed -i \
	-e "s/XXXXX/${TOKEN}/g" \
	-e "s/riasc-agent/${NODENAME}/g" \
	riasc.yaml

# Prepare systemd-timesyncd config
cat > fallback-ntp.conf <<EOF
[Time]
FallbackNTP=pool.ntp.org
EOF

# Download PGP keys for verifying Ansible Git commits
echo "Download PGP keys..."
mkdir -p keys
wget -O keys/steffen-vogel.asc https://keys.openpgp.org/vks/v1/by-fingerprint/09BE3BAE8D55D4CD8579285A9675EAC34897E6E2 # Steffen Vogel (RWTH)

# Patching image
cat <<EOF > patch.fish
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
copy-in ../common/riasc-update.sh ../common/riasc-set-hostname.sh /usr/local/bin/
glob chmod 755 /usr/local/bin/riasc-*.sh

copy-in keys/ /boot/

echo "Enable SSH on boot..."
touch /boot/ssh

echo "Setting hostname..."
write /etc/hostname "${NODENAME}"

echo "Enable systemd risac services..."
ln-sf /etc/systemd/system/risac-update.service /etc/systemd/system/multi-user.target.wants/riasc-update.service
ln-sf /etc/systemd/system/risac-set-hostname.service /etc/systemd/system/multi-user.target.wants/riasc-set-hostname.service

echo "Disable daily APT timers"
rm /etc/systemd/system/timers.target.wants/apt-daily-upgrade.timer
rm /etc/systemd/system/timers.target.wants/apt-daily.timer
EOF

if [ "${FLAVOR}" = "edgeflex" -a "${OS}" = "ubuntu" ]; then
cat <<EOF >> patch.fish
echo "Disable Grub boot"
write-append /boot/usercfg.txt "[all]\ninitramfs initrd.img followkernel\nkernel=vmlinuz\n"
EOF
fi

echo "Patching image with guestfish..."
guestfish < patch.fish

# Zip image
echo "Zipping image..."
rm -f ${RIASC_IMAGE_FILE}.zip
zip ${RIASC_IMAGE_FILE}.zip ${RIASC_IMAGE_FILE}.img

echo "Please write the new image to an SD card:"
echo "  dd bs=1M if=${RIASC_IMAGE_FILE}.img of=/dev/sdX"
