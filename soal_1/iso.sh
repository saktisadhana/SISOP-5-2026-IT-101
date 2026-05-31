#!/bin/bash
set -e

# File harus SUDO
if [ "$EUID" -ne 0 ]; then
  echo "do sudo ./iso.sh u silly"
  exit 1
fi

apt update
apt install -y grub-common grub-pc-bin xorriso mtools grub-efi-amd64-bin

# Check required files
if [ ! -f "osboot/bzImage" ]; then
    echo "Error: osboot/bzImage not found! Run kernel.sh first."
    exit 1
fi
if [ ! -f "osboot/single.gz" ]; then
    echo "Error: osboot/single.gz not found! Run osboot/single.sh first."
    exit 1
fi
if [ ! -f "osboot/multi.gz" ]; then
    echo "Error: osboot/multi.gz not found! Run multi.sh first."
    exit 1
fi

# Create ISO directory structure
mkdir -p iso/boot/grub

# Copy kernel + both filesystems into the ISO
cp osboot/bzImage iso/boot/
cp osboot/single.gz iso/boot/
cp osboot/multi.gz iso/boot/

# GRUB boot menu - loads both single and multi filesystem
cat << 'EOF' > iso/boot/grub/grub.cfg
set timeout=10
set default=0

menuentry "Farewell - Single User Mode" {
    linux /boot/bzImage single console=ttyS0 console=tty0 root=/dev/ram0 rw
    initrd /boot/single.gz
}

menuentry "Farewell - Multi User Mode" {
    linux /boot/bzImage console=ttyS0 console=tty0 root=/dev/ram0 rw
    initrd /boot/multi.gz
}
EOF

# Build the bootable ISO
echo "Building osboot/farewell.iso..."
grub-mkrescue -o osboot/farewell.iso iso/ || { echo "ISO creation failed!"; exit 1; }

rm -rf iso/
echo "Done! File: osboot/farewell.iso"
