# ZFS Helper Client Examples

This directory contains example systemd user service files that demonstrate how to use zfs-helper from unprivileged user services.

## backup@.service

A template service that creates snapshots before performing operations. This is useful for backup workflows where you want to snapshot datasets before modifications.

### Usage

1. Copy the service to your user systemd directory:
   ```bash
   mkdir -p ~/.config/systemd/user
   cp /usr/share/doc/zfs-helper-client/examples/user/backup@.service ~/.config/systemd/user/
   ```

2. Reload systemd and start the service:
   ```bash
   systemctl --user daemon-reload
   systemctl --user start backup@pre-upgrade
   ```

This will create a snapshot named "pre-upgrade" of the dataset configured for your user.

## Prerequisites

1. **Group membership**: Add your user to the zfshelper group:
   ```bash
   sudo usermod -aG zfshelper $USER
   ```
   
2. **Policy configuration**: Create policy files in `/etc/zfs-helper/policy.d/$USER/`:
   - `units.list` - List allowed service patterns (e.g., `backup@*.service`)
   - `snapshot.list` - List datasets the user can snapshot (e.g., `$USER tank/home/$USER`)
   - Other operation lists as needed

3. **Re-login**: Log out and back in to pick up the new group membership.

## Policy Example

For a user named "alice" to use the backup service:

```bash
# Create policy directory
sudo mkdir -p /etc/zfs-helper/policy.d/alice

# Allow backup services
echo "backup@*.service" | sudo tee /etc/zfs-helper/policy.d/alice/units.list

# Allow snapshots of user's home dataset
echo "alice tank/home/alice" | sudo tee /etc/zfs-helper/policy.d/alice/snapshot.list
```

## See Also

- zfs-helperctl(1) - Client command reference
- zfs-helper(8) - Daemon documentation and policy format