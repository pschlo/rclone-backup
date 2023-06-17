# rclone-backup
Creates `restic` backups from `rclone` remotes



## Usage

```bash
$ ./backup.sh [--config rclone-config] [--script restic-script] rclone-remote-path restic-repo-path
```

Before you can run the script, you need to set up an `rclone` remote that serves as the backup source. Set up a remote in the default config file by typing `rclone config`, or in a custom config file by typing `rclone --config /path/to/rclone.conf config` .



## Example

* If the `rclone` remote is configured in the default config and you just want to do a plain backup:

    ```bash
    $ ./backup.sh my-onedrive:foo/bar ~/backups/onedrive_backup
    ```

    This will perform a normal backup. Note that unless you told `restic` how to find the repository password, e.g. by setting an environment variable, you will be prompted for it.

* If you have a custom `rclone` config somewhere:

    ```bash
    $ ./backup.sh --config /path/to/rclone.conf my-onedrive:foo/bar ~/backups/onedrive_backup
    ```
    or
    
    ```bash
    $ export RCLONE_CONFIG=/path/to/rclone.conf
    $ ./backup.sh my-onedrive:foo/bar ~/backups/onedrive_backup
    ```
    
* You can also use your own `restic` backup script. Note that `RESTIC_REPOSITORY` will already be set:

    ```bash
    $ ./backup.sh --script run-backup.sh my-onedrive:foo/bar ~/backups/onedrive_backup
    ```

* If your `restic` repository is also on a remote location:

    ```bash
    $ ./backup.sh my-onedrive:foo/bar rclone:backup-server:backups/onedrive_backup
    ```

    In this example, a second `rclone` remote `backup-server` has been configured beforehand.
