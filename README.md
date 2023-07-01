# serve-fuse-mount

This script temporarily provides a mount to a program.



## Usage

```bash
$ ./serve-mount.sh mount-command -- program-command
```

`mount-command` must contain the placeholder argument `MOUNTPOINT`, which will automatically be replaced with the actual mount point.



## Examples

```bash
$ ./serve-mount.sh rclone mount my-cloud: MOUNTPOINT -- ls -l
```

This will mount the rclone remote `my-cloud` under a temporary mountpoint, execute `ls -l`  there, and then unmount `my-cloud` again. If you find this command too long and messy, you can also write this as:

```bash
$ ./serve-mount.sh \
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

