# Installation

ZFS Helper can be installed using Debian packages or from source. The Debian package method is recommended for most users.

## Prerequisites

- **Operating System**: Linux with systemd ≥ 240
- **ZFS**: OpenZFS installed (`zfsutils-linux` package)
- **Root privileges**: Required for installing system services

## Method 1: Debian Packages (Recommended)

### Add the APT Repository

First, add the ZFS Helper APT repository:

```bash
curl -fsSL https://akarasulu.github.io/zfs-helper/apt/repo-setup.sh | sudo bash
```

### Install the Packages

```bash
sudo apt update
sudo apt install zfs-helper zfs-helper-client
```

This installs:
- `zfs-helper`: Core daemon and systemd units
- `zfs-helper-client`: Client tools (`zfs-helperctl`) and examples

If you try to install the package and get this error then you need to install ZFS and its utilities first:

```bash
vagrant@debian12:~$ sudo apt-get install zfs-helper
Reading package lists... Done
Building dependency tree... Done
Reading state information... Done
Some packages could not be installed. This may mean that you have
requested an impossible situation or if you are using the unstable
distribution that some required packages have not yet been created
or been moved out of Incoming.
The following information may help to resolve the situation:

The following packages have unmet dependencies:
 zfs-helper : Depends: zfsutils-linux but it is not installable
              Recommends: zfs-helper-client but it is not going to be installed
E: Unable to correct problems, you have held broken packages.
```

### Verification

Check that the service is running:

```bash
sudo systemctl status zfs-helper.socket
sudo systemctl status zfs-helper.service
```

## Method 2: Manual Installation

If you prefer to install from source or the packages aren't available for your distribution:

### Download and Extract

```bash
# Download from GitHub releases
git clone https://github.com/akarasulu/zfs-helper
cd zfs-helper

# Example installation for a user with specific permissions
sudo bash install-zfs-helper.sh \
  --user $USER \
  --unit-globs 'backup@*.service' \
  --mount-globs 'tank/home/'"$USER"'*' \
  --snapshot-globs 'tank/home/'"$USER"',tank/home/'"$USER"'/*' \
  --rollback-globs 'tank/home/'"$USER"',tank/home/'"$USER"'/*' \
  --create-globs 'tank/scratch/*' \
  --destroy-globs 'tank/scratch/*' \
  --rename-from-globs 'tank/data/tmp-*' \
  --rename-to-globs 'tank/data/archive/*' \
  --setprop-globs 'tank/home/'"$USER"'*' \
  --setprop-values 'canmount=on,canmount=noauto,sharenfs=on,sharenfs=off,mountpoint:/home/'"$USER"'*' \
  --share-globs 'tank/home/'"$USER"'*'
```

The installer:

- Creates the `zfshelper` group
- Installs daemon and client tools
- Sets up systemd units
- Creates policy directory structure
- Enables and starts the socket service

## Post-Installation Setup

### Add Users to the Group

User scoped services running as unprivileged users must be added to the `zfshelper` group:

```bash
sudo usermod -aG zfshelper username
```

**Important**: Users must log out and back in to pick up the new group membership.

### Configure Policies

Create policy files for each user under `/etc/zfs-helper/policy.d/username/`. See the [Policy](policy.md) documentation for details.

### Test the Installation

As a user in the `zfshelper` group, from within a systemd user service:

```bash
# This should be run from a systemd user service, not directly from shell
zfs-helperctl snapshot tank/home/$USER@test
```

## Troubleshooting

### Service Not Starting

Check the service logs:

```bash
sudo journalctl -u zfs-helper.service -f
```

### Permission Denied

Ensure:

1. User is in the `zfshelper` group
2. User has logged out and back in
3. Command is run from an authorized systemd user service
4. Policy files are configured correctly

## Next Steps

After installation, configure policies for your users and services. See the [Policy Documentation](policy.md) for detailed configuration instructions.
