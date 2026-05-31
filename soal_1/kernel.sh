#!/bin/bash
set -e

apt update
apt install -y build-essential bc bison flex libssl-dev libelf-dev

# GCC 15+ defaults to C23 which breaks Linux 6.1.x headers (bool/false become keywords).
# A wrapper script that forces gnu11 is the only reliable fix for ALL sub-builds
# (EFI stub and realmode use their own Makefiles that don't read KCFLAGS).
cat > /tmp/gcc-gnu11 << 'WRAPPER'
#!/bin/bash
exec gcc -std=gnu11 "$@"
WRAPPER
chmod +x /tmp/gcc-gnu11

wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.1.tar.xz || { echo "Download failed!"; exit 1; }
tar -xf linux-6.1.1.tar.xz
cd linux-6.1.1

make ARCH=x86_64 CC=/tmp/gcc-gnu11 x86_64_defconfig

# Disable WERROR so warnings from newer GCC don't fail the build
./scripts/config --disable WERROR
# Enable FUSE filesystem (built-in) for task 10
./scripts/config --enable FUSE_FS
# Accept defaults for any new config options (non-interactive)
make ARCH=x86_64 CC=/tmp/gcc-gnu11 olddefconfig

make ARCH=x86_64 CC=/tmp/gcc-gnu11 -j$(nproc) bzImage

mv arch/x86/boot/bzImage ../osboot/
cd ..
rm -rf linux-6.1.1 linux-6.1.1.tar.xz
