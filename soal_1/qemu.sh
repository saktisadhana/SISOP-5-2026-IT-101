#!/bin/bash
set -e

# File harus SUDO
if [ "$EUID" -ne 0 ]; then
  echo "do sudo ./qemu.sh [--single|--multi|--all]"
  exit 1
fi

apt install -y qemu-system-x86 2>/dev/null || apt install -y qemu-system-x86_64 2>/dev/null || true

case "$1" in
    --single)
        echo "Booting Single-User filesystem directly..."
        qemu-system-x86_64 \
            -kernel osboot/bzImage \
            -initrd osboot/single.gz \
            -append "single console=ttyS0 console=tty0 root=/dev/ram0 rw" \
            -m 512M \
            -nographic \
            -net nic,model=virtio \
            -net user
        ;;
    --multi)
        echo "Booting Multi-User filesystem directly..."
        qemu-system-x86_64 \
            -kernel osboot/bzImage \
            -initrd osboot/multi.gz \
            -append "console=ttyS0 console=tty0 root=/dev/ram0 rw" \
            -m 512M \
            -nographic \
            -net nic,model=virtio \
            -net user
        ;;
    --all)
        echo "Booting from farewell.iso (GRUB menu)..."
        qemu-system-x86_64 \
            -cdrom osboot/farewell.iso \
            -m 512M \
            -nographic \
            -net nic,model=virtio \
            -net user \
            -boot d
        ;;
    *)
        echo "Usage: sudo ./qemu.sh [OPTION]"
        echo ""
        echo "  --single   Boot single-user filesystem directly"
        echo "  --multi    Boot multi-user filesystem directly"
        echo "  --all      Boot from osboot/farewell.iso (choose single/multi via GRUB)"
        exit 1
        ;;
esac
