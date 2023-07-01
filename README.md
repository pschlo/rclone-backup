# serve-fuse-mount

This script temporarily provides a mount to a program. It performs the following steps:

1. **set up** a mount in a temporary directory and wait for it to become available
2. **execute** the program in the mount directory
3. **wait** for it to finish
4. **close** the mount
5. **return** the exit code of the executed program

> **NOTE:** currently, the mount process is killed if the mount point cannot be unmounted. This may lead to data loss for mount processes using a write cache.



## Usage

```bash
$ ./serve-mount <mount-command> [<options>] -- <program-command>
```

`mount-command` must contain the placeholder argument `MOUNTPOINT`, which will automatically be replaced with the actual mount point.



## Example

```bash
$ ./serve-mount rclone mount my-cloud: MOUNTPOINT -- ls -l
```

This will mount the rclone remote `my-cloud` under a temporary mountpoint, execute `ls -l`  there, and then unmount `my-cloud` again. If you find this command too long and messy, you can also write this as:

```bash
$ ./serve-mount \
>     rclone mount my-cloud: MOUNTPOINT \
>     -- \
>     ls -l
```

The output will be something like:

```
mounting in temporary folder
mount successful
launching ls

total 1
drwxr-xr-x 1 user user   0 Jul  1 19:32 pictures
drwxr-xr-x 1 user user   0 Jun 20 12:21 projects
-rw-r--r-- 1 user user 140 Jun 27 17:59 notes.txt

program has finished with code 0
waiting for mount 1918@tmp.tcGOND2WhQ to stop
mount 1918@tmp.tcGOND2WhQ stopped
```



## Convenience Scripts

In this repository you can also find `serve-rclone-mount.sh` and `serve-bindfs-mount.sh`, which are small convenience wrappers around `serve-mount.sh` for `restic` or `bindfs` mounts. They both use a syntax defined by `serve-custom-mount.sh` and are used as follows:

```bash
$ ./serve-***-mount <source> [<options> --] <program-command>
```

The example from before could thus also be written as:

```bash
$ ./serve-rclone-mount my-cloud: ls -l
```



## ToDo

* extend readme
* add option to change behavior if `umount` fails (e.g. a timeout before mount process is killed)