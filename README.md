# serve-rclone-mount

`rclone` can mount remote file locations on the local machine. This is very useful, because programs can then interact with the remote files just like with local files. However:

1. having a remote location mounted in the system all the time might be impractical if only a single process needs the mount
2. after issuing `rclone mount`, it takes some unknown time before the mount actually becomes available

This script is a *wrapper* around arbitrary programs to provide them with read-only *remote files*. It performs the following steps:

1. **set up** a mount in a temporary directory and wait for it to become available
2. **execute** the program in the mount directory
3. **wait** for it to finish
4. **close** the mount

In this repository you can also find an example script `backup.sh` that uses `serve-rclone-mount`. Using the backup program `restic`, it creates a backup of a remote location.



## Usage

```bash
$ ./serve-rclone-mount.sh [[rclone-flags...] --] <rclone-remote-path> <program> [program-args...]
```

When specifying rclone mount flags, make sure to finish them with a `--`. Otherwise, `serve-rclone-mount` does not know where the flags end.

## Examples

```bash
$ ./serve-rclone-mount.sh my-onedrive:foo/bar my-program -a --arg2 arg3
```

This will mount `my-onedrive:foo/bar` as read-only and execute `my-program -a --arg2 arg3` in the mount directory.

```bash
$ ./serve-rclone-mount.sh --config /path/to/rclone.conf -- my-onedrive:foo/bar my-program -a --arg2 arg3
```

This will do the same, but read the remote configuration from `/path/to/rclone.conf` instead of the default config.



## backup.sh

This script uses the tool `restic` to create a backup of a remote location. The backup is stored in a restic repository. To run the script, you need:

1. a `rclone` remote that serves as the backup source. Set up a remote in the default config file by typing `rclone config`, or in a custom config file by typing `rclone --config /path/to/rclone.conf config` .
2. a `restic` repository. Enter `restic init` to create one.

### Usage

```bash
$ ./backup.sh <rclone-remote-path> <restic-repository-path>
```


### Examples

* If the rclone remote is configured in the default config and you just want to do a plain backup:

    ```bash
    $ ./rclone-backup.sh my-onedrive:foo/bar ~/backups/onedrive_backup
    ```

    Note that unless you told restic how to find the repository password, e.g. by setting an environment variable, you will be prompted for it.

* If you have a custom rclone config somewhere, you can enter

    ```bash
    $ export RCLONE_CONFIG=/path/to/rclone.conf
    ```
    
    before running the backup script
    
* If your restic repository is also on a remote location:

    ```bash
    $ ./rclone-backup.sh my-onedrive:foo/bar rclone:backup-server:backups/onedrive_backup
    ```

    In this example, a second rclone remote `backup-server` has been configured beforehand.
