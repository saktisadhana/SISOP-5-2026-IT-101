# SISOP-5-2026-IT-101

## Identitas Praktikan

| Nama                     | NRP        | Kode Asisten | Kelas |
| ------------------------ | ---------- | ------------ | ----- |
| Putu Putra Sakti Sadhana | 5027251101 | NINN         | A     |

## Reporting

### Soal 1

Di soal ini aku diminta buat bikin satu sistem operasi minimal berbasis **Linux Kernel** yang bisa berjalan dalam dua mode: **Single User** dan **Multi User**. Terus kita juga disuruh buat gabungin keduanya ke dalam satu **ISO bootable** yang dilengkapi pake menu GRUB, dan Ngejalanin semuanya pake emulator **QEMU**.

Terdapat lima script utama yang dibikin:

- `kernel.sh` - download dan compile Linux Kernel jadi `bzImage`.
- `single.sh` - bikin root filesystem single-user pake BusyBox.
- `multi.sh` - bikin root filesystem multi-user pake sistem login dan manajemen user.
- `iso.sh` - gabungin kernel dan kedua rootfs jadi satu file ISO bootable pake GRUB.
- `qemu.sh` - Ngejalanin sistem di QEMU pake argumen `--single`, `--multi`, atau `--all`.

#### Pembahasan

##### kernel.sh

Script ini fungsinya buat download source code Linux kernel versi 6.1.1 dari kernel.org, mengkonfigurasinya, dan compile jadi file `bzImage`.

```bash
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.1.1.tar.xz
tar -xf linux-6.1.1.tar.xz
cd linux-6.1.1
make ARCH=x86_64 CC=/tmp/gcc-gnu11 x86_64_defconfig
```

- `wget` download source tarball kernel dari server resmi kernel.org.
- `tar -xf` mengekstrak archive `.tar.xz`. Flag `-x` = extract, `-f` = baca dari file.
- `ARCH=x86_64` ngasih tau sistem build bahwa target arsitektur adalah 64-bit x86. Tanpa ini, Makefile kernel mungkin mencoba build Buat arsitektur host yang nggak diinginkan, atau nggak bisa menemukan konfigurasi yang benar.
- `x86_64_defconfig` itu preset konfigurasi default yang sudah teruji Buat arsitektur x86_64. Target ini ngasilin file `.config` berisi ratusan opsi kernel pake nilai-nilai yang masuk akal, jadinya nggak perlu mengisi satu per satu dari nol.
- `CC=/tmp/gcc-gnu11` menentukan compiler yang dipake. Bukan `gcc` biasa, melainkan wrapper script yang kita buat sendiri di bawah.

Sempet ada Kendala / Error pas ngerjain, yaitu GCC versi 15+ secara default pake standar C23, yang menyebabkan konflik pake header kernel Linux 6.1.x (Soalnya `bool` dan `false` jadi keyword reserved di C23 sementara kernel masih mendefinisikannya sendiri). Solusinya sih membuat wrapper script yang memaksa compiler pake standar `gnu11`.

```bash
cat > /tmp/gcc-gnu11 << 'WRAPPER'
#!/bin/bash
exec gcc -std=gnu11 "$@"
WRAPPER
chmod +x /tmp/gcc-gnu11
```

- `cat > /tmp/gcc-gnu11 << 'WRAPPER' ... WRAPPER` adalah heredoc. Semua teks antara dua tanda `WRAPPER` ditulis langsung ke file `/tmp/gcc-gnu11`. Tanda kutip tunggal di `'WRAPPER'` penting: ia mencegah shell mengekspansi variabel seperti `$@` di dalam heredoc, jadinya string `"$@"` ditulis apa adanya ke file.
- `exec gcc -std=gnu11 "$@"` - `exec` menggantikan proses shell saat ini pake proses `gcc`, jadinya nggak ada fork dan overhead minimal. `-std=gnu11` memaksa GCC pake standar GNU C11. `"$@"` meneruskan semua argumen yang diterima wrapper tanpa modifikasi, jadinya seluruh argumen build asli (flag, nama file, dsb.) tetap sampai ke `gcc`.
- Wrapper dibikin di `/tmp` biar bisa diakses dari semua sub-direktori selama kompilasi. Kernel Linux punya ratusan sub-Makefile yang masing-masing memanggil compiler secara independen, jadinya kita butuh path absolut yang universal.

```bash
./scripts/config --disable WERROR
./scripts/config --enable FUSE_FS
make ARCH=x86_64 CC=/tmp/gcc-gnu11 olddefconfig
make ARCH=x86_64 CC=/tmp/gcc-gnu11 -j$(nproc) bzImage
```

- `--disable WERROR` - mematikan opsi yang ngubah warning compiler jadi error. GCC versi baru ngasilin warning baru yang nggak ada di versi lama, jadinya tanpa flag ini build bisa gagal hanya Soalnya warning yang nggak kritis.
- `--enable FUSE_FS` - mengaktifkan dukungan FUSE (Filesystem in Userspace) langsung ke dalam kernel (built-in), bukan sebagai modul terpisah. Ini diperlukan biar program FUSE bisa berjalan di dalam QEMU tanpa perlu `modprobe`.
- `olddefconfig` - baca `.config` yang ada dan mengisi nilai default Buat opsi-opsi baru (akibat perubahan kita di atas) tanpa membuka interface interaktif menuconfig.
- `-j$(nproc)` - kompilasi paralel pake semua core CPU yang tersedia. `nproc` mengembalikan jumlah logical processor. Tanpa ini, kompilasi berjalan single-threaded dan bisa memakan waktu lebih dari satu jam.
- `bzImage` - target build yang ngasilin compressed kernel image yang siap di-boot oleh bootloader.

Abis kompilasi selesai, file `bzImage` dipindahkan ke direktori `osboot/`.

##### single.sh

Script ini bikin **root filesystem mode single user** pake **BusyBox** sebagai penyedia semua utilitas Unix. Dalam mode ini sistem langsung masuk ke shell tanpa proses login apapun.

###### Struktur Direktori rootfs

```bash
mkdir -p rootfs/{bin,sbin,usr/bin,dev,proc,sys,etc,tmp,root}
cp /bin/busybox rootfs/bin/
chroot rootfs /bin/busybox --install -s
```

- `mkdir -p rootfs/{bin,sbin,usr/bin,dev,proc,sys,etc,tmp,root}` - brace expansion membuat banyak subdirektori sekaligus. Flag `-p` membuat parent directory kalau belum ada dan nggak error kalau direktori sudah ada. Struktur ini meniru layout FHS (Filesystem Hierarchy Standard):
  - `bin/` - binary executable esensial seperti `ls`, `cp`, `sh`, `mount`
  - `sbin/` - binary Buat administrasi sistem: `reboot`, `getty`, `ip`
  - `usr/bin/` - binary non-esensial Buat user
  - `dev/` - device files (null, tty, console, fuse, dsb.)
  - `proc/` - mount point Buat procfs, tempat kernel mengekspos informasi proses
  - `sys/` - mount point Buat sysfs, tempat kernel mengekspos informasi hardware
  - `etc/` - file konfigurasi sistem
  - `tmp/` - file sementara
  - `root/` - home directory Buat user root

- `cp /bin/busybox rootfs/bin/` - copy binary BusyBox dari sistem host ke dalam rootfs. BusyBox adalah satu binary tunggal (~1MB) yang menggantikan lebih dari 300 utilitas Unix standar.

- `chroot rootfs /bin/busybox --install -s` - Ngejalanin BusyBox di dalam environment rootfs yang baru (`chroot` = change root, ngubah direktori root sementara Buat proses ini). `--install -s` meminta BusyBox membuat **symlink** dari setiap nama perintah yang didukung ke binary BusyBox itu sendiri. Jadi `rootfs/bin/ls` adalah symlink ke `/bin/busybox`. Saat BusyBox dipanggil melalui symlink, ia baca nama yang dipakai (via `argv[0]`) dan Ngejalanin fungsi yang sesuai. Flag `-s` = create symlinks (bukan copy).

```bash
cp -a /dev/{null,console,tty,zero} rootfs/dev/
```

- `cp -a` copy pake mempertahankan semua atribut: permission, ownership, timestamps, dan yang paling penting - **tipe file**. Device file di `/dev/` bukan file biasa melainkan character device atau block device yang punya major dan minor number. Tanpa `-a`, `cp` biasa akan gagal atau copy file kosong.
- `/dev/null` - membuang semua data yang ditulis ke sini, mengembalikan EOF saat dibaca. Program sering nulis output yang nggak diinginkan ke `/dev/null`.
- `/dev/console` - terminal konsol utama sistem.
- `/dev/tty` - terminal yang sedang aktif Buat proses pemanggil.
- `/dev/zero` - ngasilin byte `0x00` tanpa henti saat dibaca.

###### File `init`

File `init` itu program pake **PID 1** - program pertama yang dijalankan oleh kernel Abis selesai boot. Kernel secara hardcoded mencari `/init` (atau `/sbin/init`, `/etc/init`, `/bin/init`) dan menjalankannya. kalau nggak ada yang ditemukan, kernel akan `kernel panic: not syncing: No working init found`.

```bash
cat << 'EOF' > rootfs/init
#!/bin/sh
mount -t proc none /proc 2>/dev/null || true
mount -t sysfs none /sys 2>/dev/null || true
mount -t devtmpfs none /dev 2>/dev/null || true

exec /bin/sh
EOF
chmod +x rootfs/init
```

- `cat << 'EOF' > rootfs/init` - heredoc yang nulis multi-line string ke file. Tanda kutip tunggal di `'EOF'` mencegah shell mengekspansi variabel di dalam heredoc.

- `mount -t proc none /proc` - mount **procfs**:
  - `-t proc` = tipe filesystem adalah `proc` (pseudo-filesystem yang hanya ada di memori)
  - `none` = nggak ada block device fisik yang di-mount (procfs nggak butuh storage)
  - `/proc` = mount point tujuan
  - Tanpa ini, `cat /proc/cpuinfo`, `ps`, dan banyak utilitas sistem nggak akan berfungsi Soalnya kernel nggak bisa mengekspos informasi proses.

- `mount -t sysfs none /sys` - mount **sysfs**, filesystem yang mengekspos informasi tentang device, driver, dan subsistem kernel. Diperlukan biar `/sys/class/net/` dan sejenisnya bisa diakses Buat konfigurasi jaringan.

- `mount -t devtmpfs none /dev` - mount **devtmpfs**, filesystem yang secara otomatis membuat device node saat driver mendeteksi hardware baru. Tanpa ini, hanya device yang kita salin secara manual (null, tty, console, zero) yang tersedia.

- `2>/dev/null` - redirect stderr ke `/dev/null` biar error message nggak tampil. Berguna Soalnya di beberapa konfigurasi QEMU, beberapa filesystem sudah ter-mount oleh kernel sebelum init dijalankan.

- `|| true` - kalau perintah gagal (exit code non-zero), jalankan `true` yang selalu sukses. Ini mencegah script berhenti Soalnya salah satu mount gagal, misalnya kalau sudah ter-mount.

- `exec /bin/sh` - menggantikan proses init saat ini pake shell `/bin/sh` pake `exec` (nggak fork). Soalnya `exec` menggantikan proses tanpa membuat child baru, shell yang berjalan tetap punya **PID 1**. Ini krusial: kernel memantau PID 1, kalau PID 1 mati maka kernel panic.

- `chmod +x rootfs/init` - memberikan izin eksekusi. File apapun yang akan dijalankan sebagai program **wajib** punya bit executable (`x`). Tanpa ini, kernel gagal Ngejalanin init dan terjadi kernel panic.

###### Package Manager `party`

Sesuai permintaan soal, satu package manager sederhana bernama `party` juga dibundle ke dalam rootfs. Package manager ini mengambil package dari Alpine Linux repository pake `wget`.

```bash
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
```

- Alpine Linux dipilih sebagai repository Soalnya package-nya bersifat minimal dan nggak bergantung banyak pada library dinamis, cocok Buat initramfs minimalis.
- `wget -q "${REPO}/" -O-` download halaman index HTML repository secara silent (`-q`) dan output ke stdout (`-O-`).
- `grep -o "${pkg}-[^'\"]*\.apk"` mengekstrak nama file `.apk` dari HTML. Pattern `[^'\"]*` berarti "karakter apapun selain tanda kutip tunggal atau ganda" - ini memotong nama file tepat sebelum tanda kutip penutup atribut HTML.
- `tar -xzf /tmp/${pkg}.apk -C /` mengekstrak package Alpine (format tar.gz) langsung ke root filesystem (`-C /`).

###### Packaging rootfs jadi initramfs

Terakhir, tinggal bungkus semua isi direktori `rootfs` jadi file `single.gz`.

```bash
cd rootfs
find . -print0 | cpio --null -ov --format=newc | gzip -9 > ../osboot/single.gz
cd ..
rm -rf rootfs
```

- `find . -print0` - mencari semua file dan direktori secara rekursif di direktori saat ini. Flag `-print0` memisahkan nama file pake karakter null (`\0`) alih-alih newline, biar nama file yang mengandung spasi atau karakter khusus nggak rusak saat di-pipe.

- `cpio --null -ov --format=newc`:
  - `--null` - baca nama file yang dipisahkan null (sesuai pake `find -print0`)
  - `-o` - mode output (create archive)
  - `-v` - verbose, tampilkan setiap file yang diproses
  - `--format=newc` - gunakan format "new ASCII" (SVR4 without CRC). Format ini adalah **satu-satunya** format cpio yang didukung oleh kernel Linux sebagai initramfs.

- `gzip -9` - kompres archive cpio pake level kompresi maksimum. Level 9 = file paling kecil, proses paling lama. Buat initramfs, ukuran kecil penting Soalnya seluruhnya harus dimuat ke RAM.

- `> ../osboot/single.gz` - output ke file `single.gz`. Nama harus diakhiri `.gz` biar kernel mengenalinya sebagai gzip-compressed cpio archive.

##### multi.sh

Script ini bikin **root filesystem mode multi-user** yang jauh lebih kompleks. Beda sama single user, mode ini pake `/sbin/init` (dari BusyBox) sebagai manajer inisialisasi yang akan baca `/etc/inittab` Buat menampilkan prompt login di terminal.

###### Struktur User dan Group

Sistem multi-user yang dibikin punya empat user pake hirarki akses yang bertingkat:

```bash
mkdir -p rootfs/{bin,sbin,usr/bin,usr/sbin,dev,proc,sys,etc,tmp,root,home/{henn,hann,viii,kids}}
```

Direktori tambahan dibanding single user:
- `usr/sbin/` - binary administrasi tambahan
- `home/henn`, `home/hann`, `home/viii`, `home/kids` - direktori home Buat masing-masing user sesuai spesifikasi soal.

Data user disimpen di `/etc/passwd` dan password terenkripsi di `/etc/shadow`.

```
henn:x:1001:1001:henn:/home/henn:/bin/sh
hann:x:1002:1002:hann:/home/hann:/bin/sh
viii:x:1003:1003:viii:/home/viii:/bin/sh
kids:x:1004:1004:kids:/home/kids:/bin/sh
```

Format `/etc/passwd` terdiri dari **tujuh field** yang dipisahkan titik dua (`:`). Ambil baris `henn` sebagai contoh:

```
henn : x  : 1001 : 1001 : henn : /home/henn : /bin/sh
 ①    ②     ③      ④      ⑤         ⑥            ⑦
```

| # | Field | Isi di baris `henn` | Pembahasan |
|---|-------|---------------------|-----------|
| ① | Username | `henn` | Nama yang diketik saat prompt `login:`. Harus unik di sistem. |
| ② | Password | `x` | Bukan password sesungguhnya. Nilai `x` berarti password tersimpan terenkripsi di `/etc/shadow`. Sebelum shadow password ada, hash password disimpan langsung di sini, tapi Soalnya `/etc/passwd` bisa dibaca siapapun, ini nggak aman. |
| ③ | UID | `1001` | **User ID** - angka unik yang mengidentifikasi user di level kernel. UID 0 = root (superuser pake akses penuh). UID 1–999 biasanya dicadangkan Buat system accounts. UID ≥ 1000 Buat user manusia biasa. kita mulai dari 1001 biar nggak bentrok pake system accounts. `henn`=1001, `hann`=1002, `viii`=1003, `kids`=1004 - setiap user bisa UID unik yang increment. |
| ④ | GID | `1001` | **Primary Group ID** - grup utama user. Angka 1001 merujuk ke entry di `/etc/group` yang punya GID 1001, yaitu grup primer bernama `henn`. Konvensi umum di Linux: setiap user punya grup primer sendiri pake GID yang sama persis pake UID-nya. |
| ⑤ | GECOS | `henn` | Field komentar opsional Buat informasi tambahan (nama lengkap, nomor telepon, dsb.). Di sini cukup nama user saja. |
| ⑥ | Home directory | `/home/henn` | Direktori yang jadi working directory saat user login. Shell akan `cd` ke sini otomatis Abis login berhasil. |
| ⑦ | Login shell | `/bin/sh` | Program yang dijalankan Abis login. `/bin/sh` adalah BusyBox ash shell. kalau diisi `/sbin/nologin`, user nggak bisa login interaktif (biasanya Buat service accounts). |

###### Sistem Group Buat Access Control

Biar aksesnya bisa beda-beda tiap user, aku pake grup tambahan selain grup primer masing-masing user.

```bash
cat >> rootfs/etc/group << 'GROUP'
g_hann:x:2003:henn,hann
g_viii:x:2002:henn,hann,viii
g_kids:x:2001:henn,hann,viii,kids
GROUP
```

Format `/etc/group` terdiri dari **empat field** dipisahkan titik dua. Contoh `g_hann:x:2003:henn,hann`:

| # | Field | Isi | Pembahasan |
|---|-------|-----|-----------|
| ① | Group name | `g_hann` | Nama grup. Prefiks `g_` Buat membedakan dari grup primer user. |
| ② | Password | `x` | Group password, jarang dipake. `x` berarti gunakan `/etc/gshadow`. |
| ③ | GID | `2003` | Group ID unik. kita pilih range 2001–2003 biar nggak bentrok pake GID primer user (1001–1004) maupun system groups (0–999). |
| ④ | Members | `henn,hann` | Daftar username yang jadi anggota grup ini, dipisahkan koma. |

Hierarki akses yang dibangun:

| Grup | GID | Anggota | Tujuan |
|------|-----|---------|--------|
| `g_hann` | 2003 | henn, hann | Mengizinkan henn+hann mengakses `/home/hann` |
| `g_viii` | 2002 | henn, hann, viii | Mengizinkan henn+hann+viii mengakses `/home/viii` |
| `g_kids` | 2001 | henn, hann, viii, kids | Mengizinkan semua user mengakses `/home/kids` |

`henn` adalah user pake akses tertinggi Soalnya masuk ke semua grup akses. `kids` hanya ada di `g_kids` jadinya hanya bisa mengakses `/home/kids`.

###### Permission Direktori Home

Permission tiap home directory di-set pake `chown` dan `chmod` Buat mencerminkan hirarki akses tersebut.

```bash
# /home/henn: private, hanya henn sendiri yang bisa masuk
chown 1001:1001 rootfs/home/henn
chmod 700 rootfs/home/henn

# /home/hann: henn dan hann bisa masuk (via grup g_hann)
chown 1002:2003 rootfs/home/hann
chmod 770 rootfs/home/hann

# /home/viii: henn, hann, dan viii bisa masuk (via grup g_viii)
chown 1003:2002 rootfs/home/viii
chmod 770 rootfs/home/viii

# /home/kids: semua user bisa masuk (via grup g_kids)
chown 1004:2001 rootfs/home/kids
chmod 770 rootfs/home/kids
```

**`chown ANGKA:ANGKA`** - ngubah kepemilikan direktori. kita pake angka numerik (bukan nama seperti `henn`) Soalnya perintah ini dijalankan di **sistem host** yang nggak mengenal user `henn`. Angka ini harus persis sama pake UID/GID yang kita definisikan di dalam rootfs. Format: `pemilik:grup_pemilik`.

Contoh `chown 1002:2003 rootfs/home/hann`:
- Pemilik direktori = UID 1002 = user `hann`
- Grup pemilik = GID 2003 = grup `g_hann` (yang anggotanya adalah henn dan hann)

**`chmod NNN`** - ngatur permission pake **notasi oktal**. Setiap digit adalah bitmask tiga bit yang merepresentasikan kombinasi read (`r=4`), write (`w=2`), execute (`x=1`):

```
chmod  7   7   0
       │   │   └── Other  (semua user lain): 0 = no permission
       │   └────── Group  (anggota grup pemilik): 7 = rwx
       └────────── Owner  (pemilik): 7 = rwx
```

Rincian setiap direktori:

| Direktori | chown | chmod | Efek |
|-----------|-------|-------|------|
| `/home/henn` | `1001:1001` | `700` | Hanya `henn` (owner) yang bisa masuk. Grup dan other nggak punya akses. |
| `/home/hann` | `1002:2003` | `770` | `hann` (owner) dan semua anggota `g_hann` (henn, hann) bisa masuk. Other nggak bisa. |
| `/home/viii` | `1003:2002` | `770` | `viii` (owner) dan semua anggota `g_viii` (henn, hann, viii) bisa masuk. `kids` nggak bisa. |
| `/home/kids` | `1004:2001` | `770` | `kids` (owner) dan semua anggota `g_kids` (semua user) bisa masuk. |

Mengapa `770` dan bukan `777`? Digit ketiga `0` (other = no permission) memastikan hanya user yang **secara eksplisit** ada di grup akses yang bisa masuk. kalau ada user tambahan yang dibikin di terus hari, mereka otomatis nggak punya akses kecuali ditambahkan ke grup yang sesuai.

###### File `init` dan `inittab`

Beda sama single user, file `init` pada mode multi-user hanya bertugas melakukan mount filesystem virtual lalu mendelegasikan segalanya ke `/sbin/init`.

```bash
cat << 'EOF' > rootfs/init
#!/bin/sh
mount -t proc none /proc 2>/dev/null || true
mount -t sysfs none /sys 2>/dev/null || true
mount -t devtmpfs none /dev 2>/dev/null || true

exec /sbin/init
EOF
chmod +x rootfs/init
```

- `exec /sbin/init` - menggantikan proses shell pake `/sbin/init` dari BusyBox. BusyBox init itu implementasi minimalis dari System V init yang baca `/etc/inittab`.

`/sbin/init` terus baca `/etc/inittab` Buat mengetahui apa yang harus dijalankan.

```bash
cat << 'EOF' > rootfs/etc/inittab
::sysinit:/bin/mount -t proc proc /proc
::sysinit:/bin/mount -t sysfs sysfs /sys
::sysinit:/bin/mount -t devtmpfs devtmpfs /dev
::sysinit:/etc/init.d/network
::respawn:/sbin/getty -L 115200 tty0 vt100
::ctrlaltdel:/sbin/reboot
::shutdown:/bin/umount -a -r
EOF
```

Format setiap baris inittab: `id:runlevel:action:process`. Di BusyBox init, `id` dan `runlevel` dikosongkan jadinya format yang terlihat adalah `::action:process`.

Pembahasan setiap baris:
- `::sysinit:/bin/mount -t proc proc /proc` - jalankan mount proc sekali saat inisialisasi sistem. `sysinit` dijalankan sebelum proses lain, berurutan dari atas ke bawah.
- `::sysinit:/etc/init.d/network` - jalankan script network Buat setup interface jaringan (lo, eth0) dan DHCP.
- `::respawn:/sbin/getty -L 115200 tty0 vt100` - jalankan `getty` dan **ulangi otomatis** kalau `getty` berakhir. Ini yang membuat prompt login terus muncul Abis logout.
  - `getty` (get tty) - menginisialisasi terminal dan menampilkan prompt `login:`.
  - `-L` - mode local line (tanpa modem handshaking).
  - `115200` - baud rate terminal (Buat virtual terminal di QEMU, ini hanya setting nominal).
  - `tty0` - terminal konsol utama.
  - `vt100` - tipe terminal, menentukan escape sequences Buat kontrol kursor.
- `::ctrlaltdel:/sbin/reboot` - jalankan `reboot` saat Ctrl+Alt+Del ditekan.
- `::shutdown:/bin/umount -a -r` - saat shutdown, unmount semua filesystem. `-a` = all, `-r` = remount read-only kalau unmount gagal.

##### iso.sh

Script ini ngegabungin `bzImage`, `single.gz`, dan `multi.gz` jadi satu file ISO bootable pake **GRUB** sebagai bootloader.

```bash
mkdir -p iso/boot/grub
cp osboot/bzImage iso/boot/
cp osboot/single.gz iso/boot/
cp osboot/multi.gz iso/boot/
```

Struktur direktori `iso/boot/grub/` wajib ada Soalnya itulah lokasi yang dicari `grub-mkrescue` Buat menemukan `grub.cfg`.

```bash
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

grub-mkrescue -o osboot/farewell.iso iso/
```

- `set timeout=10` - tunggu 10 detik di menu sebelum boot otomatis ke entry default. kalau user menekan ENTER atau tombol arah, timer dibatalkan.
- `set default=0` - entry ke-0 (pertama, Single User Mode) dipilih kalau timeout habis.
- `menuentry "nama" { ... }` - satu pilihan di menu GRUB.
- `linux /boot/bzImage ...` - muat kernel pake kernel command line berikut ini:
  - `single` (hanya Single User) - ngasih tau init bahwa ini single-user boot.
  - `console=ttyS0` - arahkan output kernel ke serial port. Di QEMU `-nographic`, serial port tampil di terminal host.
  - `console=tty0` - juga tampilkan ke konsol VGA.
  - `root=/dev/ram0` - root filesystem berada di RAM disk.
  - `rw` - mount root dalam mode read-write.
- `initrd /boot/single.gz` - muat initramfs ke memori sebelum kernel dijalankan.
- `grub-mkrescue -o osboot/farewell.iso iso/` - membuat ISO bootable yang menyertakan GRUB binary secara otomatis.

##### qemu.sh

Script ini dibikin biar gampang pas Ngejalanin QEMU pake tiga mode yang bisa dipilih melalui argumen command line.

```bash
case "$1" in
    --single)
        qemu-system-x86_64 \
            -kernel osboot/bzImage \
            -initrd osboot/single.gz \
            -append "single console=ttyS0 console=tty0 root=/dev/ram0 rw" \
            -m 512M -nographic -net nic,model=virtio -net user
        ;;
    --multi)
        qemu-system-x86_64 \
            -kernel osboot/bzImage \
            -initrd osboot/multi.gz \
            -append "console=ttyS0 console=tty0 root=/dev/ram0 rw" \
            -m 512M -nographic -net nic,model=virtio -net user
        ;;
    --all)
        qemu-system-x86_64 \
            -cdrom osboot/farewell.iso \
            -m 512M -nographic -net nic,model=virtio -net user \
            -boot d
        ;;
esac
```

- `-kernel osboot/bzImage` - memuat kernel langsung tanpa bootloader. QEMU punya built-in loader yang melewati BIOS dan langsung Ngejalanin kernel.
- `-initrd osboot/single.gz` - muat initramfs ke memori. QEMU naruh di alamat memori tertentu dan memberikan informasinya ke kernel.
- `-append "..."` - kernel command line, sama persis seperti yang ditulis di `grub.cfg`.
- `-m 512M` - alokasikan 512MB RAM Buat VM. Harus cukup Buat kernel + initramfs yang didekompresi + proses yang berjalan.
- `-nographic` - nonaktifkan emulasi GPU, semua output ke terminal. Keluar pake `Ctrl+A` lalu `X`.
- `-net nic,model=virtio` - buat network card virtual pake driver `virtio` yang efisien (guest tahu ia di dalam VM jadinya nggak perlu mensimulasikan hardware NIC penuh).
- `-net user` - gunakan user-mode networking: QEMU sendiri yang berfungsi sebagai NAT router dan DHCP server, tanpa perlu konfigurasi jaringan khusus di host.
- `-cdrom osboot/farewell.iso` + `-boot d` - mount ISO sebagai CD-ROM dan boot dari sana (Buat mode `--all` pake menu GRUB).

#### Output

1. Ngejalanin `kernel.sh` (kompilasi kernel)

   *(Di output bakal keliatan proses `make` yang compile kernel Linux, diakhiri pake path bzImage yang berhasil dibikin)*

2. Ngejalanin `single.sh`

   *(Di output bakal keliatan instalasi BusyBox dan proses `cpio` yang mengemas rootfs jadi `single.gz`)*

3. Ngejalanin `multi.sh`

   *(Di output bakal keliatan pembuatan user/group dan proses packaging rootfs multi-user jadi `multi.gz`)*

4. Booting Single User Mode (`sudo ./qemu.sh --single`)

   *(Sistem langsung masuk ke shell `/ #` tanpa prompt login)*

5. Booting Multi User Mode (`sudo ./qemu.sh --multi`)

   *(Sistem menampilkan prompt login. Login sebagai `henn` pake password `henn123` berhasil masuk ke `/home/henn`)*

6. Pengujian access control

   *(User `kids` mencoba `cd /home/henn` dan mendapat `Permission denied`. User `henn` bisa mengakses semua direktori home)*

7. Ngejalanin `iso.sh` dan booting dari ISO (`sudo ./qemu.sh --all`)

   *(Muncul menu GRUB pake dua pilihan: "Farewell - Single User Mode" dan "Farewell - Multi User Mode")*

#### Kendala / Error

Ada masalah pas kompilasi kernel. GCC versi 15 yang terpasang di sistem pake standar C23 secara default, yang menyebabkan error `error: 'bool' is not a type` pada header kernel Linux 6.1.x. Solusinya sih membuat wrapper script `/tmp/gcc-gnu11` yang memaksa GCC pake standar `gnu11`. Wrapper harus di `/tmp` biar path-nya bisa diakses secara konsisten dari seluruh sub-Makefile dalam tree kernel.

---

### Soal 2

Di soal ini aku diminta buat membuat satu **sistem operasi sederhana** dari nol pake **Assembly (NASM)** dan **C (BCC)** yang berjalan di atas emulator **Bochs**. Sistem operasi ini punya satu shell interaktif yang bisa menerima dan memproses beberapa perintah.

Terdapat tiga file utama yang dibikin:

- `bootloader.asm` - MBR bootloader yang memuat kernel dari disk ke memori.
- `kernel.asm` - Helper functions assembly (`putInMemory` dan `getChar`).
- `kernel.c` - Logika utama kernel (shell dan semua perintah) dalam bahasa C.

#### Pembahasan

##### bootloader.asm

Bootloader itu program **512-byte** yang ditempatkan di sektor pertama disk (**MBR, Master Boot Record**). Saat komputer dinyalakan, BIOS melakukan POST, lalu baca 512 byte pertama dari boot device dan naruh di alamat memori `0x7C00`, terus melompat ke sana.

```asm
bits 16
org 0x7C00

jmp start
nop

KERNEL_SEGMENT equ 0x1000
KERNEL_SECTORS equ 15
```

- `bits 16` - nyuruh NASM biar mengompilasi semua kode sebagai instruksi **16-bit real mode**. Saat komputer baru booting, CPU selalu berada dalam mode ini demi kompatibilitas pake program DOS. Dalam real mode, hanya ada akses ke 1MB memori dan nggak ada proteksi memori atau virtual address.

- `org 0x7C00` - ngasih tau NASM bahwa program ini akan dimuat di offset `0x7C00` dari awal segment. NASM pake informasi ini Buat menghitung alamat absolut dari semua label dan variabel. Tanpa `org`, kalau ada label seperti `msg` yang ingin kita akses, NASM akan menghitung alamatnya mulai dari 0, padahal di memori ia berada di `0x7C00 + offset`. Ini akan ngasilin alamat yang salah.

- `jmp start` - lompat ke label `start` melewati area konstanta di bawahnya. Instruksi ini ada di byte-byte pertama MBR Buat menghindari CPU mengeksekusi data konstanta sebagai kode.

- `nop` - "no operation", instruksi yang nggak melakukan apapun tapi memakan 1 byte dan 1 siklus clock. Di sini dipake Buat padding biar area kode selaras.

- `KERNEL_SEGMENT equ 0x1000` - mendefinisikan konstanta bernilai `0x1000`. Konstanta ini dipake sebagai segment address tujuan Buat menaruh kernel. Dalam real mode, alamat fisik = `segment * 16 + offset`, jadinya `0x1000:0x0000` = alamat fisik `0x10000` = 64KB dari awal memori. Dipilih Soalnya cukup jauh dari bootloader di `0x7C00` dan area BIOS di bawah `0x500`.

- `KERNEL_SECTORS equ 15` - kernel akan dibaca dari disk sebanyak 15 sektor = 15 × 512 = 7680 bytes. Angka ini harus cukup besar Buat menampung binary kernel hasil linker.

```asm
start:

    cli

    xor ax, ax
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x7C00

    sti
```

- `cli` - **Clear Interrupt Flag**. Menonaktifkan hardware interrupt sementara. Di CPU x86, ada register khusus bernama EFLAGS (atau FLAGS di 16-bit) yang menyimpan berbagai flag status. Bit IF (Interrupt Flag) mengontrol apakah CPU merespons hardware interrupt atau nggak. `cli` mengeset IF = 0, jadinya interrupt timer, keyboard, dll nggak akan mengganggu kode kita. Ini penting saat ngatur segment registers Soalnya operasi tersebut melibatkan beberapa instruksi dan interrupt yang datang di tengah-tengah bisa menyebabkan state nggak konsisten.

- `xor ax, ax` - melakukan operasi XOR antara register AX pake dirinya sendiri, ngasilin 0. Ini cara yang lumayan efisien Buat mengeset register ke 0. Instruksi `xor ax, ax` lebih pendek dalam encoding mesin (2 byte) dibanding `mov ax, 0` (3 byte) dan lebih cepat di beberapa CPU.

- `mov ds, ax` - **copy nilai AX (=0) ke register DS**. `mov` adalah instruksi "move" yang copy data dari sumber (kanan) ke tujuan (kiri). Di sini, kita **nggak bisa langsung** nulis `mov ds, 0` Soalnya arsitektur x86 nggak memperbolehkan load konstanta langsung ke segment register. kita harus melalui general purpose register (seperti AX) sebagai perantara. DS = Data Segment, dipake secara implisit Buat semua akses data biasa.

- `mov es, ax` - copy AX (=0) ke register ES (Extra Segment). dipake Buat operasi string dan buffer tertentu.

- `mov ss, ax` - copy AX (=0) ke register SS (Stack Segment). SS menentukan di segment mana stack berada. Mengeset ke 0 berarti stack berada di segment yang sama pake kode bootloader kita.

- `mov sp, 0x7C00` - copy nilai `0x7C00` ke register SP (Stack Pointer). Stack di x86 **tumbuh ke bawah** (dari alamat tinggi ke rendah). pake mengeset SP ke `0x7C00`, kita menempatkan stack tepat di awal kode bootloader. Setiap kali kita `push` data, SP berkurang (mis. dari `0x7C00` ke `0x7BFE`, dst.), jadinya stack tumbuh ke arah memori rendah dan nggak menabrak kode bootloader.

- `sti` - **Set Interrupt Flag**. Mengaktifkan kembali hardware interrupt Abis segment registers selesai dikonfigurasi.

```asm
    ; load kernel into 0x1000:0000

    mov ax, KERNEL_SEGMENT
    mov es, ax

    xor bx, bx

    mov ah, 0x02
    mov al, KERNEL_SECTORS
    mov ch, 0x00
    mov cl, 0x02
    mov dh, 0x00

    ; IMPORTANT:
    ; BIOS already gives boot drive in DL
    ; DO NOT overwrite DL

    int 0x13

    jc disk_error
```

Bagian ini buat ngebaca kernel dari disk ke memori pake **BIOS Interrupt 0x13** (Disk I/O Services).

- `mov ax, KERNEL_SEGMENT` - copy konstanta `0x1000` ke AX. kita butuh nilai ini di AX sebagai perantara sebelum naruh ke ES.
- `mov es, ax` - mengeset ES = 0x1000. Ini adalah segment address tujuan pembacaan disk. Sama seperti sebelumnya, nggak bisa langsung `mov es, 0x1000`.
- `xor bx, bx` - mengeset BX = 0. BX adalah offset dalam segment ES tempat data disk akan ditulis. ES:BX = `0x1000:0x0000` = alamat fisik `0x10000`.

Sebelum memanggil `int 0x13`, kita harus mengisi register pake parameter yang tepat:

| Register | Nilai | Makna |
|----------|-------|-------|
| `AH` | `0x02` | Nomor fungsi BIOS: "Read Sectors from Drive" |
| `AL` | 15 (`KERNEL_SECTORS`) | Jumlah sektor yang akan dibaca |
| `CH` | `0x00` | Cylinder number (track). 0 = track terluar disk |
| `CL` | `0x02` | Sector number. **Dimulai dari 1** (bukan 0). Sektor 1 = MBR (sudah terpakai bootloader), sektor 2 ke atas = isi kernel |
| `DH` | `0x00` | Head number. 0 = sisi pertama disk |
| `DL` | (nggak diubah) | Drive number. BIOS mengisi ini pake nomor drive yang kita boot. `0x00` = floppy A:. Jangan ditimpa! |
| `ES:BX` | `0x1000:0x0000` | Alamat buffer tujuan pembacaan |

- `mov ah, 0x02` - mengeset byte tinggi dari AX. Register AX dalam 16-bit terbagi jadi dua bagian 8-bit: **AH** (byte tinggi, bit 15–8) dan **AL** (byte rendah, bit 7–0). `mov ah, 0x02` hanya ngubah byte tinggi tanpa ngubah AL.
- `mov al, KERNEL_SECTORS` - mengeset byte rendah AX = 15.
- `mov ch, 0x00` - mengeset byte tinggi CX = 0 (cylinder 0).
- `mov cl, 0x02` - mengeset byte rendah CX = 2 (mulai dari sektor 2).
- `mov dh, 0x00` - mengeset byte tinggi DX = 0 (head 0).

- `int 0x13` - memanggil **BIOS interrupt 0x13**. `int` adalah instruksi "interrupt" yang mentransfer kontrol ke handler interrupt yang terdaftar di IVT (Interrupt Vector Table) di alamat `0x0000:0x0000`. Entry ke-19 (0x13 = desimal 19) menunjuk ke kode BIOS Buat disk service. BIOS baca sektor dari disk dan naruh di ES:BX.

- `jc disk_error` - **Jump if Carry**. Abis `int 0x13` selesai, BIOS mengeset **Carry Flag** (CF) di register FLAGS kalau operasi gagal. `jc` = "jump if carry flag = 1". kalau berhasil, CF = 0 dan eksekusi lanjut ke baris berikutnya. kalau gagal, CF = 1 dan kita melompat ke `disk_error`.

```asm
    cli

    ; kernel segments

    mov ax, KERNEL_SEGMENT
    mov ds, ax
    mov es, ax

    ; safe stack

    mov ax, 0x9000
    mov ss, ax

    mov sp, 0xFFFF
    mov bp, 0xFFFF

    sti

    ; TRUE FAR JMP

    push word KERNEL_SEGMENT
    push word 0x0000
    retf
```

Abis kernel berhasil di-load, tinggal disiapin environment-nya sebelum melompat ke kernel:

- `cli` - nonaktifkan interrupt lagi Soalnya kita akan ngubah SS dan SP.

- `mov ax, KERNEL_SEGMENT` lalu `mov ds, ax` dan `mov es, ax` - set DS dan ES ke segment kernel (`0x1000`). Ini memastikan bahwa Abis kita jump ke kernel, akses data pake segment yang benar (segment yang sama pake tempat kernel dimuat).

- `mov ax, 0x9000` lalu `mov ss, ax` - mengeset stack segment ke `0x9000`. `0x9000:0xFFFF` = alamat fisik `0x9FFFF` ≈ 640KB. Ini adalah ujung "conventional memory" (area memori yang aman Buat program user sebelum area BIOS di 640KB ke atas). Stack dialihkan ke sini biar nggak menimpa kernel yang baru dimuat di `0x10000`.

- `mov sp, 0xFFFF` - Stack Pointer = 0xFFFF. Stack tumbuh ke bawah, jadi kita mulai dari ujung segment.

- `mov bp, 0xFFFF` - **Base Pointer** juga diset ke 0xFFFF. BP biasanya dipake sebagai frame pointer dalam fungsi C. Mengeset ke nilai yang sama pake SP memastikan nggak ada stack frame "orphan" dari bootloader yang bisa mengganggu konvensi calling C.

- `push word KERNEL_SEGMENT` - **push** nilai `KERNEL_SEGMENT` (0x1000) ke stack. Instruksi `push` pertama-tama mengurangi SP sebesar 2 (Soalnya `word` = 2 byte), terus nulis nilai ke alamat `SS:SP`. Abis ini, stack berisi `0x1000` di posisi teratas.

- `push word 0x0000` - push nilai 0x0000 ke stack. Stack sekarang (dari atas ke bawah): `0x0000`, `0x1000`.

- `retf` - **Return Far**. Instruksi ini melakukan kebalikan dari far call: baca **dua word dari stack**: pertama offset (0x0000), terus segment (0x1000). Lalu melompat ke alamat `segment:offset` = `0x1000:0x0000`. CPU sekarang mengeksekusi kode yang ada di `0x1000:0x0000` = awal kernel. Penggunaan `retf` sebagai pengganti `jmp far` adalah trik yang lebih portable dan lebih reliable di berbagai emulator dan hardware nyata.

```asm
disk_error:

    mov si, msg

.print:

    lodsb
    or al, al
    jz $

    mov ah, 0x0E
    mov bh, 0x00
    int 0x10

    jmp .print

msg db 'DISK ERROR',0
```

Error handler ini buat nampilin pesan "DISK ERROR" pake BIOS interrupt 0x10 (Video Service):

- `mov si, msg` - copy alamat label `msg` ke register SI (Source Index). SI dipake sebagai pointer ke string yang akan dicetak.

- `lodsb` - **Load String Byte**. baca satu byte dari alamat `DS:SI` ke register AL, terus otomatis menambah SI sebesar 1. Ini instruksi string khusus x86 yang memudahkan iterasi byte per byte melalui array/string.

- `or al, al` - melakukan OR bitwise antara AL pake dirinya sendiri. Hasil OR nggak berubah, tapi operasi ini mengeset **Zero Flag** (ZF) kalau AL = 0. Ini cara umum Buat "cek apakah AL = 0" tanpa ngubah nilai AL. `cmp al, 0` juga bisa dipake tapi `or al, al` lebih pendek.

- `jz $` - **Jump if Zero**. kalau ZF = 1 (AL = 0, artinya kita sudah mencapai null terminator string), lompat ke `$`. Di NASM, `$` berarti "alamat instruksi ini sendiri" - jadi `jz $` adalah infinite loop. Ini menghentikan CPU di sini (hang) Abis pesan selesai ditampilkan.

- `mov ah, 0x0E` - fungsi BIOS video 0x0E = "Teletype Output" (cetak karakter dan geser kursor).

- `mov bh, 0x00` - page number = 0 (halaman video aktif).

- `int 0x10` - panggil BIOS Video Service. pake AH=0x0E dan AL=karakter, BIOS mencetak karakter AL ke layar.

- `msg db 'DISK ERROR',0` - mendefinisikan string "DISK ERROR" di memori, diakhiri byte 0 (null terminator). `db` = "define byte", mendefinisikan sekuens byte di memori.

```asm
times 510-($-$$) db 0
dw 0xAA55
```

- `$` = alamat instruksi/data saat ini (current position).
- `$$` = alamat awal section/file.
- `$-$$` = jumlah byte yang sudah ditulis sejauh ini (ukuran kode + data).
- `510-($-$$)` = berapa byte tersisa sampai posisi 510.
- `times N db 0` - tulis byte `0x00` sebanyak N kali. Ini mengisi sisa ruang MBR pake nol sampai byte ke-510.
- `dw 0xAA55` - tulis word `0xAA55` (2 byte) sebagai dua byte terakhir MBR di posisi 510-511. Ini adalah **boot signature** wajib. BIOS memeriksa dua byte terakhir: kalau `0x55` di offset 510 dan `0xAA` di offset 511 (perhatikan urutan: little-endian, byte rendah dulu), baru sektor ini dianggap MBR valid dan dieksekusi.

##### kernel.asm

File ini menyediakan dua fungsi assembly yang diperlukan oleh `kernel.c`. Soalnya BCC (Bruce's C Compiler) pake **16-bit cdecl calling convention**, argumen fungsi di-push ke stack oleh caller dalam urutan **terbalik** (argumen terakhir di-push duluan), dan diakses di dalam fungsi melalui base pointer.

```asm
bits 16

global _start
global _putInMemory
global _getChar
extern _main
```

- `bits 16` - sama seperti di bootloader, ngasih tau NASM Buat compile sebagai kode 16-bit.

- `global _start` - **mengeksport** simbol `_start` jadinya bisa dilihat dan dirujuk dari file object lain saat proses linking. Tanpa `global`, simbol hanya visible di file assembly ini sendiri.

- `global _putInMemory` dan `global _getChar` - mengeksport fungsi-fungsi helper ini biar `kernel.c` bisa memanggilnya. Konvensi penamaan di BCC: nama fungsi C `putInMemory` diubah jadi simbol assembly `_putInMemory` (ditambah underscore di depan).

- `extern _main` - mendeklarasikan bahwa simbol `_main` **didefinisikan di file lain** (yaitu `kernel.c`, yang dikompilasi oleh BCC). `extern` ngasih tau assembler bahwa referensi ke `_main` harus diselesaikan oleh linker (`ld86`) saat gabungin semua file object.

```asm
_start:

    cli

    mov ax, cs
    mov ds, ax
    mov es, ax

    sti

    call _main

.hang:
    jmp .hang
```

- `_start:` - label yang menandai entry point program. Saat bootloader melakukan far jump ke `0x1000:0x0000`, eksekusi dimulai dari sini.

- `cli` - nonaktifkan interrupt sementara Buat setup segment registers yang aman.

- `mov ax, cs` - **menyimpan nilai CS ke AX**. Ya, ini benar-benar copy isi register CS ke dalam register AX. CS (Code Segment) adalah segment register yang menunjuk ke segment di mana kode yang sedang dieksekusi berada. Saat bootloader melakukan far jump ke `0x1000:0x0000`, CPU otomatis mengeset CS = `0x1000`. kita perlu nilai ini Buat ngatur DS dan ES biar sama pake CS.

- `mov ds, ax` - **copy nilai AX (=0x1000) ke DS** (Data Segment). Sama seperti sebelumnya, nggak bisa langsung `mov ds, cs` - arsitektur x86 nggak mengizinkan transfer langsung antara dua segment register. Harus melalui general purpose register sebagai relay. Mengeset DS = CS = 0x1000 memastikan bahwa saat kode C di kernel.c mengakses variabel global atau data, ia pake segment yang benar (0x1000), yaitu tempat kernel dimuat.

- `mov es, ax` - copy AX (=0x1000) ke ES (Extra Segment). ES dipake Buat beberapa operasi, termasuk yang akan kita gunakan di `_putInMemory`.

- `sti` - aktifkan kembali interrupt.

- `call _main` - memanggil fungsi `main()` dari `kernel.c`. `call` adalah instruksi yang:
  1. Menyimpan alamat instruksi berikutnya (alamat return) ke stack pake cara push.
  2. Melompat ke alamat `_main`.
  Saat `main()` selesai (return), CPU mengambil alamat return dari stack dan melanjutkan eksekusi dari sini (yaitu baris `.hang`).

- `.hang: jmp .hang` - loop tak terbatas. Label `.hang` diawali titik jadinya bersifat **lokal** (hanya visible di dalam scope yang sama, nggak bentrok pake label `hang` di file lain). Baris `jmp .hang` melompat kembali ke dirinya sendiri terus-menerus. Ini mencegah CPU mengeksekusi memori acak di luar kode program kalau `main()` pernah return (yang seharusnya nggak terjadi Soalnya `main()` punya `while(1)`).

```asm
_putInMemory:
    push bp
    mov bp, sp

    push ds

    mov ax, [bp+4]
    mov si, [bp+6]
    mov cl, [bp+8]

    mov ds, ax
    mov [si], cl

    pop ds

    pop bp
    ret
```

Fungsi ini dipanggil dari C sebagai `putInMemory(segment, address, character)`. Di 16-bit cdecl, saat fungsi dipanggil, stack frame terlihat seperti ini (gambar saat kita sudah dalam fungsi, Abis `push bp` dan `mov bp, sp`):

```
Alamat lebih tinggi
+─────────────┐
│ character   │  [bp+8]  ← argumen ke-3 (dipush terakhir, paling atas)
+─────────────+
│ address     │  [bp+6]  ← argumen ke-2
+─────────────+
│ segment     │  [bp+4]  ← argumen ke-1 (dipush pertama)
+─────────────+
│ return addr │  [bp+2]  ← alamat return (disimpan oleh instruksi `call`)
+─────────────+
│ saved BP    │  [bp+0]  ← BP lama yang kita simpan dengan `push bp`
+─────────────┘  ← sp dan bp menunjuk ke sini setelah `mov bp, sp`
Alamat lebih rendah
```

- `push bp` - menyimpan nilai BP lama ke stack. Ini adalah konvensi wajib: kita harus menyimpan dan memulihkan BP biar caller nggak kehilangan frame pointer-nya.

- `mov bp, sp` - **copy SP (Stack Pointer) ke BP (Base Pointer)**. Abis instruksi ini, BP "membekukan" posisi puncak stack saat ini. Dari titik ini, kita bisa mengakses argumen fungsi pake offset tetap dari BP tanpa khawatir SP berubah akibat push/pop berikutnya di dalam fungsi.

- `push ds` - menyimpan DS lama ke stack. kita akan ngubah DS Buat akses ke segment berbeda, dan harus memulihkannya sebelum return biar caller nggak rusak.

- `mov ax, [bp+4]` - baca **word** dari alamat `SS:BP+4` (argumen `segment`) ke AX. Tanda kurung siku `[...]` berarti "baca dari memori di alamat ini". Di 16-bit, satu word = 2 byte = ukuran default Buat `mov`. Soalnya int dalam BCC 16-bit adalah 2 byte, `segment` tersimpan sebagai word.

- `mov si, [bp+6]` - baca argumen `address` ke register SI (Source Index). SI akan dipake sebagai offset dalam operasi penulisan memori.

- `mov cl, [bp+8]` - baca argumen `character` ke register CL. CL adalah byte rendah dari register CX (8-bit). `char` dalam C adalah 1 byte, tapi BCC mem-push-nya sebagai word (2 byte) ke stack, jadinya kita baca satu byte pake `cl`.

- `mov ds, ax` - **mengeset DS = nilai segment** yang dikirim sebagai argumen. Ini adalah inti dari fungsi ini: ngubah segment yang diakses. Sekarang semua akses memori melalui DS pake segment baru ini.

- `mov [si], cl` - nulis byte CL ke alamat `DS:SI`. Kombinasi ini adalah alamat fisik `DS * 16 + SI`. Buat video memory VGA: `DS = 0xB800`, jadinya alamat fisik = `0xB800 * 16 + SI = 0xB8000 + SI`.

- `pop ds` - memulihkan DS ke nilai aslinya. **Wajib** dilakuin sebelum return biar caller tetap bisa mengakses datanya sendiri.

- `pop bp` - memulihkan BP ke nilai lama. **Wajib** dilakuin Soalnya kita simpan di awal.

- `ret` - **return**: ambil alamat return dari stack (yang disimpan oleh `call`) dan lompat ke sana. Ini mengembalikan kontrol ke kode C yang memanggil fungsi ini.

```asm
; implement this
_getChar:
    xor ah, ah      ; AH=0 = "tunggu keypress"
    int 0x16        ; BIOS keyboard interrupt
    ; AL sekarang berisi ASCII char yang ditekan
    xor ah, ah      ; bersihkan AH (return value = AX)
    ret
```

- `xor ah, ah` - mengeset AH = 0. Register AX terdiri dari AH (byte tinggi, bit 15–8) dan AL (byte rendah, bit 7–0). `xor ah, ah` hanya ngubah byte tinggi tanpa menyentuh AL. AH = 0 diperlukan Buat memilih fungsi 0x00 dari interrupt 0x16.

- `int 0x16` - memanggil **BIOS Interrupt 0x16** (Keyboard Services). pake AH = 0 (fungsi "Wait for Keypress and Read Character"), BIOS akan **memblokir** - CPU berhenti di sini dan menunggu sampai ada tombol ditekan. Abis tombol ditekan, BIOS mengisi:
  - `AL` = kode ASCII karakter yang ditekan (contoh: 'A' = 65 = 0x41, 'a' = 97 = 0x61, Enter = 13 = 0x0D)
  - `AH` = scan code keyboard (nomor fisik tombol, berbeda dari kode ASCII)

- `xor ah, ah` (kedua) - membersihkan AH Abis interrupt. Dalam konvensi 16-bit cdecl, nilai return fungsi disimpan di register **AX**. kalau kita langsung return, AX akan berisi gabungan scan code (di AH) dan ASCII code (di AL), yang bukan yang kita inginkan. pake mengeset AH = 0, nilai AX jadi `0x00XX` di mana XX = ASCII code, jadinya caller (kode C) mendapatkan nilai integer yang benar.

- `ret` - return ke caller.

##### kernel.c

Ini file utama dari OS-nya. Soalnya dikompilasi pake **BCC** (bukan GCC), beberapa keterbatasan penting harus diperhatikan:

- nggak ada standard library (`printf`, `malloc`, `strlen` nggak tersedia).
- nggak ada operator division (`/`) dan modulo (`%`) secara langsung (harus diimplementasikan manual atau dihindari).
- Semua fungsi harus dideklarasikan sebelum dipake.

###### State Global dan Video Memory

```c
int cursor = 0;
char color = 0x07;

void putInMemory(int segment, int address, char character);
int getChar();
```

- `int cursor = 0` - posisi karakter berikutnya di layar. Layar VGA text mode berukuran **80 kolom × 25 baris = 2000 karakter**. Cursor 0 = pojok kiri atas, cursor 79 = ujung kanan baris pertama, cursor 80 = awal baris kedua, dst. hingga cursor 1999 = pojok kanan bawah.

- `char color = 0x07` - atribut warna teks saat ini. Byte warna VGA punya format:

  ```
  Bit:  7    6    5    4    3    2    1    0
       BL   BR   BG   BB   FR   FG   FB   FI
       └──── Background (4 bit) ────┘  └──── Foreground (4 bit) ────┘
  ```

  Nilai `0x07` = `0000 0111` biner:
  - Background (bit 7–4) = `0000` = hitam
  - Foreground (bit 3–0) = `0111` = abu-abu terang
  
  Bit ke-3 dari foreground adalah **intensity bit**: kalau aktif (1), warna jadi terang. Bit 2, 1, 0 adalah R, G, B.

- Deklarasi `void putInMemory(...)` dan `int getChar()` tanpa body - ini adalah **forward declaration**. BCC memerlukan fungsi dideklarasikan sebelum dipanggil. Soalnya implementasi ada di `kernel.asm`, kita hanya deklarasikan prototipenya di sini dan linker (`ld86`) yang akan menghubungkan keduanya.

###### Fungsi Layar

```c
void printChar(char c) {
    putInMemory(0xB800, cursor * 2,     c);
    putInMemory(0xB800, cursor * 2 + 1, color);
    cursor++;
}
```

VGA text mode menyimpan setiap karakter sebagai **dua byte berurutan** di memori mulai dari alamat fisik `0xB8000`:

```
Offset:  0      1      2      3      4      5  ...
Data:   [ch0] [col0] [ch1] [col1] [ch2] [col2] ...
```

- Karakter ke-N: byte data = offset `N * 2`, byte warna = offset `N * 2 + 1`
- `putInMemory(0xB800, cursor * 2, c)` - nulis karakter `c` ke video memory di posisi `cursor`
- `putInMemory(0xB800, cursor * 2 + 1, color)` - nulis atribut warna ke byte berikutnya
- `cursor++` - geser posisi ke karakter berikutnya

```c
void newline() {
    int col = cursor - (cursor / 80) * 80;
    int spaces = 80 - col;
    int i;
    for (i = 0; i < spaces; i++) {
        printChar(' ');
    }
}
```

- `cursor / 80` - menghitung nomor baris saat ini (pembagian integer, sisanya dibuang).
- `(cursor / 80) * 80` - posisi kursor di awal baris saat ini.
- `cursor - (cursor / 80) * 80` - kolom saat ini. Ini ekuivalen dari `cursor % 80` tapi **tanpa operator `%`**, Soalnya operator modulo dilarang sesuai batasan soal.
- `80 - col` - jumlah spasi yang perlu ditulis Buat mencapai akhir baris. pake mencetak spasi hingga akhir baris, kursor otomatis pindah ke awal baris berikutnya (Soalnya setiap `printChar` menambah `cursor` sebesar 1).

###### Utilitas String (tanpa stdlib)

Soalnya nggak ada standard library, semua fungsi string diimplementasikan manual.

```c
int strcmp(char *a, char *b) {
    while (*a && *b && *a == *b) { a++; b++; }
    return (*a == '\0' && *b == '\0');
}
```

- Perhatikan: fungsi ini **membalik semantik** dari `strcmp` standard library! `strcmp` standar mengembalikan 0 kalau sama. Di sini mengembalikan **1 kalau sama** dan **0 kalau berbeda**. Ini sengaja biar bisa dipake langsung di kondisi `if (strcmp(cmd, "check"))`.
- Loop berlanjut selama kedua pointer belum mencapai null terminator dan karakter yang ditunjuk sama.
- Return `(*a == '\0' && *b == '\0')` - return 1 (true) hanya kalau keduanya sudah habis pada waktu yang sama, artinya string sama panjang dan semua karakter cocok.

```c
int atoi(char *s) {
    int result = 0;
    int neg = 0;
    if (*s == '-') { neg = 1; s++; }
    while (*s >= '0' && *s <= '9') {
        result = result * 10 + (*s - '0');
        s++;
    }
    return neg ? -result : result;
}
```

- `*s - '0'` - mengkonversi karakter digit ASCII ke nilai integer. ASCII '0'=48, '1'=49, ..., '9'=57. Jadi '5' - '0' = 5.
- `result * 10 + digit` - bikin integer digit demi digit. Contoh Buat "123": `0*10+1=1`, `1*10+2=12`, `12*10+3=123`.

```c
void intToString(int n, char *buf) {
    char tmp[12];
    int i = 0;
    int j = 0;

    if (n < 0) {
        buf[j++] = '-';
        n = -n;
    }

    if (n == 0) {
        buf[j++] = '0';
        buf[j] = '\0';
        return;
    }

    while (n > 0) {
        tmp[i++] = '0' + (n - (n / 10) * 10); /* n % 10 without % */
        n = n / 10;
    }

    /* reverse into buf */
    while (i > 0) {
        buf[j++] = tmp[--i];
    }
    buf[j] = '\0';
}
```

- `n - (n / 10) * 10` - ekuivalen dari `n % 10` tanpa operator `%`. Substitusi aljabar: `a % b = a - (a/b)*b`. Ini mengekstrak digit terakhir (ones digit) dari `n`.
- Digit diextract dari yang terkecil (ones, tens, hundreds, ...) dan disimpan ke array sementara `tmp` dalam urutan terbalik.
- Loop kedua membalik `tmp` ke dalam `buf` biar urutan angka benar.
- `char tmp[12]` - cukup Buat integer 16-bit: maksimum 5 digit + tanda minus + null terminator.

###### Shell Utama dan Perintah

Fungsi `main()` berisi infinite loop yang terus baca input dan memproses perintah.

```c
void main() {
    char cmd[64];
    char numBuf[12];
    int  a, b, result;

    clearScreen();

    printString("Welcome to Assistant's Last Gift");
    newline();
    printString("type 'help'");
    newline();
    newline();

    while (1) {
        printString("> ");
        readString(cmd);
        newline();

        /* ── check ── */
        if (strcmp(cmd, "check")) {
            printString("ok");

        /* ── add <a> <b> ── */
        } else if (startsWith(cmd, "add ")) {
            char *p = skipWord(cmd);   /* skip "add" */
            a = atoi(p);
            p = skipWord(p);           /* skip first number */
            b = atoi(p);
            result = a + b;
            intToString(result, numBuf);
            printString(numBuf);

        /* ── sub <a> <b> ── */
        } else if (startsWith(cmd, "sub ")) {
            char *p = skipWord(cmd);
            a = atoi(p);
            p = skipWord(p);
            b = atoi(p);
            result = a - b;
            intToString(result, numBuf);
            printString(numBuf);

        /* ── fac <n> ── */
        } else if (startsWith(cmd, "fac ")) {
            char *p = skipWord(cmd);
            a = atoi(p);
            result = factorial(a);
            if (result < 0 || result == 0) {
                printString("know your limit little bro.");
            } else {
                intToString(result, numBuf);
                printString(numBuf);
            }

        /* ── season <name> ── */
        } else if (startsWith(cmd, "season ")) {
            char *p = skipWord(cmd);
            if (strcmp(p, "winter")) {
                color = 0x09; /* bright blue */
                printString("winter mode");
            } else if (strcmp(p, "spring")) {
                color = 0x0A; /* bright green */
                printString("spring mode");
            } else if (strcmp(p, "summer")) {
                color = 0x0E; /* yellow */
                printString("summer mode");
            } else if (strcmp(p, "fall")) {
                color = 0x0C; /* bright red / orange */
                printString("fall mode");
            } else if (strcmp(p, "radiant")) {
                color = 0x0D; /* bright magenta / pink */
                printString("radiant mode");
            } else {
                printString("unknown season");
            }

        /* ── triangle <n> ── */
        } else if (startsWith(cmd, "triangle ")) {
            char *p = skipWord(cmd);
            a = atoi(p);
            printTriangle(a);

        /* ── clear ── */
        } else if (strcmp(cmd, "clear")) {
            clearScreen();

        /* ── help ── */
        } else if (strcmp(cmd, "help")) {
            printString("check add sub fac season triangle clear about");

        /* ── about ── */
        } else if (strcmp(cmd, "about")) {
            printString("Assistant's Last Gift - Final Challenge OS");

        } else {
            printString("unknown command");
        }

        newline();
    }
}
```

- `char cmd[64]` - buffer Buat input user. Dalam 16-bit mode, stack banget terbatas, jadi 64 byte sudah cukup Buat semua perintah yang didukung.
- `startsWith(cmd, "add ")` - cek apakah `cmd` diawali prefix `"add "`. Spasi Abis "add" penting Buat membedakan perintah dari argumen.
- `skipWord(cmd)` - lewati kata pertama ("add") dan spasi di belakangnya, kembalikan pointer ke karakter setelahnya (yaitu angka pertama).
- Perintah `season` ngubah variabel global `color`. Setiap `printChar` berikutnya akan pake warna baru ini.

Nilai `color` Buat setiap season pake 4 bit foreground VGA:

| Season | Nilai | Biner | Warna |
|--------|-------|-------|-------|
| default | `0x07` | `0000 0111` | Abu-abu terang |
| `winter` | `0x09` | `0000 1001` | Biru terang |
| `spring` | `0x0A` | `0000 1010` | Hijau terang |
| `summer` | `0x0E` | `0000 1110` | Kuning |
| `fall` | `0x0C` | `0000 1100` | Merah terang |
| `radiant` | `0x0D` | `0000 1101` | Magenta/Pink |

Bit ke-3 (intensity bit, nilai 8) menyalakan versi terang dari warna. Bit 2/1/0 = R/G/B.

Perintah `fac <n>` menghitung faktorial pake deteksi overflow:

```c
int factorial(int n) {
    int result = 1;
    int i;
    for (i = 2; i <= n; i++) {
        result = result * i;
        if (result < 0) return -1; /* overflow sentinel */
    }
    return result;
}
```

- BCC ngasilin `int` berukuran **16-bit bertanda**. Range: -32768 hingga 32767.
- `7! = 5040` masih dalam range (< 32767).
- `8! = 40320 > 32767` → overflow. Saat overflow pada signed integer, nilai "wrap around" jadi negatif. Kondisi ini kita deteksi pake `if (result < 0)`.
- Loop mulai dari 2 Soalnya mengalikan pake 1 nggak ngubah hasil, dan nilai awal `result = 1` sudah menangani `0!` dan `1!`.

Perintah `triangle <n>` mencetak segitiga siku-siku:

```c
void printTriangle(int n) {
    int row, col;
    for (row = 1; row <= n; row++) {
        for (col = 0; col < row; col++) {
            printChar('x');
        }
        newline();
    }
}
```

- Baris pertama mencetak 1 karakter `x`, baris kedua 2, dst. hingga baris ke-n mencetak n karakter.

#### Pembahasan Build Process (Makefile)

```makefile
prepare:
	dd if=/dev/zero of=floppy.img bs=512 count=2880

bootloader:
	nasm -f bin bootloader.asm -o bootloader.bin
	dd if=bootloader.bin of=floppy.img bs=512 count=1 conv=notrunc

kernel:
	nasm -f as86 kernel.asm -o kernel-asm.o
	bcc -ansi -c kernel.c -o kernel.o
	ld86 -0 -o kernel.bin -d kernel-asm.o kernel.o
	dd if=kernel.bin of=floppy.img bs=512 seek=1 conv=notrunc

build: prepare bootloader kernel

run:
	bochs -f bochsrc.txt
```

- `dd if=/dev/zero of=floppy.img bs=512 count=2880` - membuat disk image kosong berukuran 1.44MB (floppy standar). `dd` = disk/data duplicator. `if` = input file (`/dev/zero` ngasilin nol terus-menerus). `of` = output file. `bs=512` = block size 512 byte. `count=2880` = 2880 blok × 512 byte = 1,474,560 bytes = 1.44MB.

- `nasm -f bin bootloader.asm -o bootloader.bin` - kompilasi bootloader ke **raw binary** (`-f bin`). Output itu file binary yang langsung berisi instruksi mesin tanpa header atau format tambahan.

- `dd if=bootloader.bin of=floppy.img bs=512 count=1 conv=notrunc` - tulis bootloader ke sektor pertama disk image. `count=1` = hanya 1 blok (512 byte = tepat ukuran MBR). `conv=notrunc` = jangan truncate output file (penting biar isi floppy.img lainnya nggak terhapus).

- `nasm -f as86 kernel.asm -o kernel-asm.o` - kompilasi `kernel.asm` ke format object **as86** (format object 16-bit yang dipake oleh toolchain `bcc`/`ld86`). Beda sama `-f bin`, format object masih mengandung informasi simbol dan relokasi Buat diproses linker.

- `bcc -ansi -c kernel.c -o kernel.o` - kompilasi `kernel.c` ke format object as86 pake BCC. `-ansi` = gunakan standar ANSI C. `-c` = hanya kompilasi, jangan link. ngasilin `kernel.o`.

- `ld86 -0 -o kernel.bin -d kernel-asm.o kernel.o` - link semua object file jadi satu binary. `-0` = target adalah segmented 16-bit model. `-d` = hapus header ld86 dari output (header ini nggak dibutuhin dan akan merusak eksekusi kalau disertakan). Urutan file penting: `kernel-asm.o` berisi `_start`, jadinya harus di-link pertama biar `_start` berada di awal binary.

- `dd if=kernel.bin of=floppy.img bs=512 seek=1 conv=notrunc` - tulis kernel mulai dari sektor **ke-2** (`seek=1` = skip 1 blok dari awal = mulai dari blok ke-2). Sektor 1 sudah dipakai bootloader.

#### Output

1. Ngejalanin `make build`

   *(Di output bakal keliatan proses nasm, bcc, ld86, dan dd yang nulis bootloader dan kernel ke floppy.img)*

2. Ngejalanin `bochs -f bochsrc.txt`

   *(Bochs muncul dan layar menampilkan banner "Welcome to Assistant's Last Gift")*

3. Perintah `check`

   *(Menampilkan `ok`)*

4. Perintah `add 15 27`

   *(Menampilkan `42`)*

5. Perintah `sub 100 37`

   *(Menampilkan `63`)*

6. Perintah `fac 7`

   *(Menampilkan `5040`)*

7. Perintah `fac 8`

   *(Menampilkan `know your limit little bro.` Soalnya 8! = 40320 overflow integer 16-bit)*

8. Perintah `season winter`

   *(Teks berubah jadi biru terang)*

9. Perintah `season radiant`

   *(Teks berubah jadi magenta/pink)*

10. Perintah `triangle 4`

    *(Menampilkan segitiga siku-siku 4 baris dari karakter `x`)*

11. Perintah `clear`

    *(Layar dibersihkan dan kursor kembali ke pojok kiri atas)*

#### Kendala / Error

Sempet error pas mau jalanin Bochs Abis kompilasi berhasil. Bochs nggak bisa menemukan file ROM BIOS Soalnya path di `bochsrc.txt` nggak sesuai pake instalasi Bochs di sistem. Solusinya sih menyesuaikan path `romimage` dan `vgaromimage` di `bochsrc.txt` pake hasil perintah `find /usr -name "BIOS-bochs-latest" 2>/dev/null`. Path berbeda-beda tergantung cara instalasi Bochs (via apt, compile manual, dsb.) jadinya perlu disesuaikan per sistem.
