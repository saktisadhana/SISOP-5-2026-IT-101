#!/bin/bash
set -e

apt update
apt install -y libnewt-dev busybox-static

# File harus SUDO
if [ "$EUID" -ne 0 ]; then
  echo "do sudo ./multi.sh u silly"
  exit 1
fi

# Bersihkan rootfs lama
rm -rf rootfs

# Buat struktur direktori sesuai spek
mkdir -p rootfs/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,etc,tmp,root,home/{henn,hann,viii,kids}}

# Use official static busybox without PAM to avoid login hang
if [ ! -f "busybox-musl" ]; then
    echo "Downloading PAM-free busybox..."
    wget -qO busybox-musl https://busybox.net/downloads/binaries/1.35.0-x86_64-linux-musl/busybox
    chmod +x busybox-musl
fi
cp busybox-musl rootfs/bin/busybox
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

    cp fuse_hello rootfs/bin/
    cp /lib64/ld-linux-x86-64.so.2 rootfs/lib64/ 2>/dev/null || true

    LIBFUSE=$(find /lib /usr/lib -name "libfuse.so.2.*" 2>/dev/null | head -1)
    [ -n "$LIBFUSE" ] && cp "$LIBFUSE" rootfs/lib/x86_64-linux-gnu/ && \
        ln -sf "$(basename "$LIBFUSE")" rootfs/lib/x86_64-linux-gnu/libfuse.so.2

    LIBC=$(find /lib/x86_64-linux-gnu /usr/lib/x86_64-linux-gnu -name "libc.so.6" 2>/dev/null | head -1)
    [ -n "$LIBC" ] && cp "$LIBC" rootfs/lib/x86_64-linux-gnu/

    FUSERMOUNT=$(which fusermount 2>/dev/null || which fusermount3 2>/dev/null)
    [ -n "$FUSERMOUNT" ] && cp "$FUSERMOUNT" rootfs/bin/ && \
        chmod u+s rootfs/bin/"$(basename "$FUSERMOUNT")"

    mknod rootfs/dev/fuse c 10 229 2>/dev/null || true
fi

#
#  INIT - multi-user mode via /sbin/init  #
#
cat << 'EOF' > rootfs/init
#!/bin/sh
mount -t proc none /proc 2>/dev/null || true
mount -t sysfs none /sys 2>/dev/null || true
mount -t devtmpfs none /dev 2>/dev/null || true

exec /sbin/init
EOF
chmod +x rootfs/init

# Buat file auth
touch rootfs/etc/passwd
touch rootfs/etc/shadow
touch rootfs/etc/group
touch rootfs/etc/fstab
chmod 600 rootfs/etc/shadow

# Create var dirs + login tracking files (busybox login needs these to not hang)
mkdir -p rootfs/var/run rootfs/var/log rootfs/var/lib
touch rootfs/var/run/utmp
touch rootfs/var/log/wtmp
touch rootfs/var/log/lastlog
chmod 664 rootfs/var/run/utmp rootfs/var/log/wtmp rootfs/var/log/lastlog

# Root user
echo "root:x:0:0:root:/root:/bin/sh" > rootfs/etc/passwd
echo "root:x:0:" > rootfs/etc/group

# Primary groups + access tier groups:
#   g_hann(2003): henn, hann       -> full access to /home/hann
#   g_viii(2002): henn, hann, viii -> full access to /home/viii
#   g_kids(2001): henn, hann, viii, kids -> full access to /home/kids
cat >> rootfs/etc/group << 'GROUP'
henn:x:1001:
hann:x:1002:
viii:x:1003:
kids:x:1004:
g_hann:x:2003:henn,hann
g_viii:x:2002:henn,hann,viii
g_kids:x:2001:henn,hann,viii,kids
GROUP

# Users: henn(1001), hann(1002), viii(1003), kids(1004)
cat >> rootfs/etc/passwd << 'PASSWD'
henn:x:1001:1001:henn:/home/henn:/bin/sh
hann:x:1002:1002:hann:/home/hann:/bin/sh
viii:x:1003:1003:viii:/home/viii:/bin/sh
kids:x:1004:1004:kids:/home/kids:/bin/sh
PASSWD

# Generate MD5 password hashes at build time (MD5 supported by all busybox versions)
hash_root=$(openssl passwd -1 -salt "sysop01" "root123")
hash_henn=$(openssl passwd -1 -salt "sysop02" "henn123")
hash_hann=$(openssl passwd -1 -salt "sysop03" "hann123")
hash_viii=$(openssl passwd -1 -salt "sysop04" "viii123")
hash_kids=$(openssl passwd -1 -salt "sysop05" "kids123")

# Write shadow with real password hashes (format: user:hash:lastchg:min:max:warn:::)
cat > rootfs/etc/shadow << SHADOW
root:${hash_root}:19900:0:99999:7:::
henn:${hash_henn}:19900:0:99999:7:::
hann:${hash_hann}:19900:0:99999:7:::
viii:${hash_viii}:19900:0:99999:7:::
kids:${hash_kids}:19900:0:99999:7:::
SHADOW
chmod 640 rootfs/etc/shadow


#
#  ACCESS CONTROL  #
#
# /root: root only (700)
chmod 700 rootfs/root
chown 0:0 rootfs/root

# /home/henn: only henn + root (700) - hann,viii,kids cannot access
chown 1001:1001 rootfs/home/henn
chmod 700 rootfs/home/henn

# /home/hann: henn+hann full (770, group=g_hann), viii+kids: no access (other=0)
chown 1002:2003 rootfs/home/hann
chmod 770 rootfs/home/hann

# /home/viii: henn+hann+viii full (770, group=g_viii), kids: no access (other=0)
chown 1003:2002 rootfs/home/viii
chmod 770 rootfs/home/viii

# /home/kids: all users full (770, group=g_kids), other=0
chown 1004:2001 rootfs/home/kids
chmod 770 rootfs/home/kids

# /tmp: full access for all users (sticky bit)
chmod 1777 rootfs/tmp

# DNS resolver
printf "nameserver 8.8.8.8\nnameserver 1.1.1.1\n" > rootfs/etc/resolv.conf

# Hostname (shows as prompt prefix)
echo "farewell" > rootfs/etc/hostname

# Hosts file - prevents login from hanging on DNS lookup
printf "127.0.0.1\tlocalhost farewell\n::1\t\tlocalhost\n" > rootfs/etc/hosts

# NSSwitch - use files only, prevents NIS/LDAP timeout
printf "passwd:    files\nshadow:    files\ngroup:     files\nhosts:     files\n" > rootfs/etc/nsswitch.conf

# TLS bypass for wget
echo "check_certificate = off" > rootfs/etc/wgetrc

# Network init script - runs on boot via inittab sysinit
mkdir -p rootfs/etc/init.d
cat << 'NETINIT' > rootfs/etc/init.d/network
#!/bin/sh
( ip link set lo up; ip link set eth0 up; udhcpc -i eth0 -t 3 -q ) >/dev/null 2>&1 &
NETINIT
chmod +x rootfs/etc/init.d/network

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

#
#  LOGIN BANNER via /etc/profile  #
#
cat << 'EOF' > rootfs/etc/profile
#!/bin/sh
cat << 'BANNER'

 .8888b                                                dP dP  .oo.  .d
88   "                                                88 88 dP" "d8P
88aaa  .d8888b. 88d888b. .d8888b. dP  dP  dP .d8888b. 88 88
88     88'  `88 88'  `88 88ooood8 88  88  88 88ooood8 88 88
88     88.  .88 88       88.  ... 88.88b.88' 88.  ... 88 88
dP     `88888P8 dP       `88888P' 8888P Y8P  `88888P' dP dP

 .oo.  .d                              dP
dP" "d8P                               88
          88d888b. .d8888b. 88d888b. d8888P dP    dP
          88'  `88 88'  `88 88'  `88   88   88    88
          88.  .88 88.  .88 88         88   88.  .88
          88Y888P' `88888P8 dP         dP   `8888P88
          88                                     .88
          dP                                 d8888P

BANNER
echo "Welcome, $(whoami)."
echo ""
EOF

#
#  INITTAB - TTY login prompt  #
#
cat << 'EOF' > rootfs/etc/inittab
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev
::sysinit:/etc/init.d/network
ttyS0::respawn:/sbin/getty -L 115200 ttyS0 vt100
tty0::respawn:/sbin/getty -L 115200 tty0 vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
EOF

# Custom poweroff/halt/reboot using SysRq (works without ACPI)
printf '#!/bin/sh\necho 1 > /proc/sys/kernel/sysrq\necho o > /proc/sysrq-trigger\n' > rootfs/bin/poweroff
printf '#!/bin/sh\necho 1 > /proc/sys/kernel/sysrq\necho o > /proc/sysrq-trigger\n' > rootfs/bin/halt
printf '#!/bin/sh\necho 1 > /proc/sys/kernel/sysrq\necho b > /proc/sysrq-trigger\n' > rootfs/bin/reboot
chmod +x rootfs/bin/poweroff rootfs/bin/halt rootfs/bin/reboot


#
#  FINAL PACKAGING  #
#
cd rootfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../osboot/multi.gz
cd ..
rm -rf rootfs
