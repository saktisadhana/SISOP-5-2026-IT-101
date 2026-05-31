#!/bin/bash
set -e

apt update
apt install -y libnewt-dev busybox-static

# File harus SUDO
if [ "$EUID" -ne 0 ]; then
  echo "do sudo ./single.sh u silly"
  exit 1
fi

rm -rf rootfs

mkdir -p rootfs/{bin,sbin,usr/bin,dev,proc,sys,etc,tmp,root}

cp /bin/busybox rootfs/bin/
chroot rootfs /bin/busybox --install -s

cp -a /dev/{null,console,tty,zero} rootfs/dev/

# Compile FUSE hello program if source exists
if [ -f "fuse_hello.c" ]; then
    apt-get install -y libfuse-dev 2>/dev/null | tail -1
    gcc -o fuse_hello fuse_hello.c $(pkg-config fuse --cflags) $(pkg-config fuse --libs) 2>/dev/null && \
        echo "fuse_hello compiled OK" || echo "fuse_hello compile failed"
fi

# Bundle FUSE binary + required shared libraries into rootfs
if [ -f "fuse_hello" ]; then
    mkdir -p rootfs/lib/x86_64-linux-gnu rootfs/lib64 rootfs/mnt/fuse

    # Our FUSE demo program
    cp fuse_hello rootfs/bin/

    # Dynamic linker
    cp /lib64/ld-linux-x86-64.so.2 rootfs/lib64/ 2>/dev/null || true

    # libfuse
    LIBFUSE=$(find /lib /usr/lib -name "libfuse.so.2.*" 2>/dev/null | head -1)
    [ -n "$LIBFUSE" ] && cp "$LIBFUSE" rootfs/lib/x86_64-linux-gnu/ && \
        ln -sf "$(basename "$LIBFUSE")" rootfs/lib/x86_64-linux-gnu/libfuse.so.2

    # libc
    LIBC=$(find /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu -name "libc.so.6" 2>/dev/null | head -1)
    [ -n "$LIBC" ] && cp "$LIBC" rootfs/lib/x86_64-linux-gnu/

    # fusermount (needed to unmount FUSE filesystems, must be setuid)
    FUSERMOUNT=$(which fusermount 2>/dev/null || which fusermount3 2>/dev/null)
    [ -n "$FUSERMOUNT" ] && cp "$FUSERMOUNT" rootfs/bin/ && \
        chmod u+s rootfs/bin/"$(basename "$FUSERMOUNT")"

    # /dev/fuse character device (required by FUSE kernel driver)
    mknod rootfs/dev/fuse c 10 229 2>/dev/null || true
fi

# DNS resolver
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > rootfs/etc/resolv.conf

# TLS bypass for wget
echo "check_certificate = off" > rootfs/etc/wgetrc

# 'party' package manager - Alpine apk-based, named 'party' per spec
cat << 'PARTY' > rootfs/bin/party
#!/bin/sh
REPO="https://dl-cdn.alpinelinux.org/alpine/v3.19/main/x86_64"
usage() { echo "Usage: party install <pkg> | party update"; }
case "$1" in
    install)
        shift
        for pkg in "$@"; do
            echo "[party] Installing $pkg..."
            pkg_file=$(wget -q "${REPO}/" -O- 2>/dev/null | grep -o "${pkg}-[^'\"]*\.apk" | head -1)
            [ -z "$pkg_file" ] && echo "[party] Package $pkg not found." && continue
            wget -q "${REPO}/${pkg_file}" -O /tmp/${pkg}.apk && \
                tar -xzf /tmp/${pkg}.apk -C / 2>/dev/null && \
                echo "[party] $pkg installed." || echo "[party] Failed to install $pkg"
            rm -f /tmp/${pkg}.apk
        done
        ;;
    update)
        echo "[party] Fetching package index..."
        wget -q "${REPO}/APKINDEX.tar.gz" -O /tmp/APKINDEX.tar.gz && \
            echo "[party] Index updated." || echo "[party] Update failed."
        ;;
    *) usage ;;
esac
PARTY
chmod +x rootfs/bin/party

cat << 'EOF' > rootfs/init
#!/bin/sh
mount -t proc none /proc 2>/dev/null || true
mount -t sysfs none /sys 2>/dev/null || true
mount -t devtmpfs none /dev 2>/dev/null || true

# Enable SysRq so poweroff/reboot work
echo 1 > /proc/sys/kernel/sysrq

# Network fully in background - shell appears instantly
( ip link set lo up; ip link set eth0 up; udhcpc -i eth0 -t 3 -q ) >/dev/null 2>&1 &

exec /bin/sh
EOF

# Custom poweroff/halt/reboot using SysRq (works without ACPI)
printf '#!/bin/sh\necho 1 > /proc/sys/kernel/sysrq\necho o > /proc/sysrq-trigger\n' > rootfs/bin/poweroff
printf '#!/bin/sh\necho 1 > /proc/sys/kernel/sysrq\necho o > /proc/sysrq-trigger\n' > rootfs/bin/halt
printf '#!/bin/sh\necho 1 > /proc/sys/kernel/sysrq\necho b > /proc/sysrq-trigger\n' > rootfs/bin/reboot
chmod +x rootfs/bin/poweroff rootfs/bin/halt rootfs/bin/reboot

chmod +x rootfs/init

cd rootfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../osboot/single.gz
cd ..
rm -rf rootfs