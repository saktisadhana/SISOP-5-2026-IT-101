/*
 * fuse_hello.c - Simple "Hello World" FUSE filesystem
 *
 * When mounted, creates a single file /hello.txt containing "Hello from FUSE!\n"
 *
 * Usage:
 *   mkdir -p /mnt/hello
 *   ./fuse_hello /mnt/hello
 *   cat /mnt/hello/hello.txt    -> "Hello from FUSE!"
 *   fusermount -u /mnt/hello    -> unmount
 */

#define FUSE_USE_VERSION 26

#include <fuse.h>
#include <stdio.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <stdlib.h>

static const char *hello_content = "Hello from FUSE!\n";
static const char *hello_filename = "hello.txt";

static int fuse_getattr(const char *path, struct stat *st) {
    memset(st, 0, sizeof(struct stat));

    if (strcmp(path, "/") == 0) {
        st->st_mode  = S_IFDIR | 0755;
        st->st_nlink = 2;
    } else if (strcmp(path + 1, hello_filename) == 0) {
        st->st_mode  = S_IFREG | 0444;
        st->st_nlink = 1;
        st->st_size  = strlen(hello_content);
    } else {
        return -ENOENT;
    }
    return 0;
}

static int fuse_readdir(const char *path, void *buf, fuse_fill_dir_t filler,
                        off_t offset, struct fuse_file_info *fi) {
    (void) offset; (void) fi;

    if (strcmp(path, "/") != 0)
        return -ENOENT;

    filler(buf, ".",           NULL, 0);
    filler(buf, "..",          NULL, 0);
    filler(buf, hello_filename, NULL, 0);
    return 0;
}

static int fuse_open(const char *path, struct fuse_file_info *fi) {
    if (strcmp(path + 1, hello_filename) != 0)
        return -ENOENT;
    if ((fi->flags & O_ACCMODE) != O_RDONLY)
        return -EACCES;
    return 0;
}

static int fuse_read(const char *path, char *buf, size_t size, off_t offset,
                     struct fuse_file_info *fi) {
    (void) fi;

    if (strcmp(path + 1, hello_filename) != 0)
        return -ENOENT;

    size_t len = strlen(hello_content);
    if ((size_t)offset >= len)
        return 0;
    if (offset + size > len)
        size = len - offset;

    memcpy(buf, hello_content + offset, size);
    return size;
}

static struct fuse_operations ops = {
    .getattr = fuse_getattr,
    .readdir = fuse_readdir,
    .open    = fuse_open,
    .read    = fuse_read,
};

int main(int argc, char *argv[]) {
    printf("FarewellOS FUSE Hello - mounting at %s\n",
           argc > 1 ? argv[1] : "(no mountpoint given)");
    return fuse_main(argc, argv, &ops, NULL);
}
