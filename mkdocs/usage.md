# Usage Guide

This guide walks through common usage patterns and real-world examples of ZFS Helper.

## Basic Workflow

### 1. User Setup

First, ensure the user is properly configured:

```bash
# Add user to zfshelper group (as root)
sudo usermod -aG zfshelper alice

# User must log out and back in
exit
# ... log back in ...

# Verify group membership
groups
# Should show: alice ... zfshelper
```

### 2. Policy Configuration

Create policy files for the user:

```bash
# Create policy directory (as root)
sudo mkdir -p /etc/zfs-helper/policy.d/alice

# Allow backup services
echo "backup@*.service" | sudo tee /etc/zfs-helper/policy.d/alice/units.list

# Allow snapshots of user's datasets
echo "alice tank/home/alice" | sudo tee /etc/zfs-helper/policy.d/alice/snapshot.list
echo "alice tank/home/alice/**" | sudo tee -a /etc/zfs-helper/policy.d/alice/snapshot.list
```

### 3. Create User Service

Create a systemd user service that uses ZFS Helper:

```bash
# Create user systemd directory
mkdir -p ~/.config/systemd/user

# Create backup service
cat > ~/.config/systemd/user/backup@.service << 'EOF'
[Unit]
Description=Snapshot before job %i

[Service]
Type=oneshot
ExecStart=/bin/sh -c 'zfs-helperctl snapshot tank/home/${USER}@%i'
EOF

# Reload systemd
systemctl --user daemon-reload
```

### 4. Use the Service

```bash
# Create a snapshot
systemctl --user start backup@pre-upgrade

# Check if it worked
zfs list -t snapshot | grep pre-upgrade
```

## Common Use Cases

### Container Volume Management

Use ZFS Helper to manage container volumes with Podman Quadlets:

```bash
# Policy for container management
echo "container@*.service" | sudo tee -a /etc/zfs-helper/policy.d/alice/units.list
echo "alice tank/containers/alice/**" | sudo tee /etc/zfs-helper/policy.d/alice/mount.list
echo "alice tank/containers/alice/**" | sudo tee /etc/zfs-helper/policy.d/alice/snapshot.list
echo "alice tank/containers/alice/**" | sudo tee /etc/zfs-helper/policy.d/alice/create.list
```

Example container service:
```bash
cat > ~/.config/systemd/user/container@.service << 'EOF'
[Unit]
Description=Container %i with ZFS volume
After=zfs-helper.socket

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/zfs-helperctl create tank/containers/${USER}/%i
ExecStartPre=/usr/bin/zfs-helperctl mount tank/containers/${USER}/%i
ExecStart=/usr/bin/podman run -d --name %i -v /tank/containers/${USER}/%i:/data alpine:latest sleep infinity
ExecStop=/usr/bin/podman stop %i
ExecStopPost=/usr/bin/podman rm %i
ExecStopPost=/usr/bin/zfs-helperctl unmount tank/containers/${USER}/%i

[Install]
WantedBy=default.target
EOF
```

### Backup Workflows

Automated backup with snapshots:

```bash
cat > ~/.config/systemd/user/daily-backup.service << 'EOF'
[Unit]
Description=Daily backup with snapshot

[Service]
Type=oneshot
ExecStart=/bin/bash -c '
  SNAPSHOT="tank/home/${USER}@daily-$(date +%%Y%%m%%d)"
  zfs-helperctl snapshot "$SNAPSHOT"
  # Add your backup commands here
  rsync -av /home/${USER}/ /backup/location/
'
EOF

cat > ~/.config/systemd/user/daily-backup.timer << 'EOF'
[Unit]
Description=Run daily backup

[Timer]
OnCalendar=daily
Persistent=true

[Install]
WantedBy=timers.target
EOF

# Enable the timer
systemctl --user enable --now daily-backup.timer
```

### Development Environment Management

Quickly create and destroy development datasets:

```bash
# Policy for development
echo "alice tank/dev/**" | sudo tee /etc/zfs-helper/policy.d/alice/create.list
echo "alice tank/dev/**" | sudo tee /etc/zfs-helper/policy.d/alice/destroy.list
echo "alice tank/dev/**" | sudo tee /etc/zfs-helper/policy.d/alice/mount.list
echo "alice tank/dev/**" | sudo tee /etc/zfs-helper/policy.d/alice/snapshot.list

# Development project service
cat > ~/.config/systemd/user/dev-env@.service << 'EOF'
[Unit]
Description=Development environment for %i

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStartPre=/usr/bin/zfs-helperctl create tank/dev/${USER}/%i
ExecStartPre=/usr/bin/zfs-helperctl mount tank/dev/${USER}/%i
ExecStart=/bin/bash -c 'echo "Development environment ready at /tank/dev/${USER}/%i"'
ExecStop=/usr/bin/zfs-helperctl unmount tank/dev/${USER}/%i
ExecStopPost=/usr/bin/zfs-helperctl destroy tank/dev/${USER}/%i

[Install]
WantedBy=default.target
EOF
```

## Advanced Patterns

### Rollback on Failure

Service that automatically rolls back on failure:

```bash
cat > ~/.config/systemd/user/safe-update.service << 'EOF'
[Unit]
Description=Safe update with automatic rollback

[Service]
Type=oneshot
ExecStartPre=/usr/bin/zfs-helperctl snapshot tank/home/${USER}@pre-update
ExecStart=/path/to/your/update-script.sh
ExecStopPost=/bin/bash -c '
  if [ "$SERVICE_RESULT" != "success" ]; then
    echo "Update failed, rolling back..."
    zfs-helperctl rollback tank/home/${USER}@pre-update
  fi
'
EOF
```

### Property Management

Dynamically adjust dataset properties:

```bash
# Policy for property changes
echo "alice tank/home/alice/**" | sudo tee /etc/zfs-helper/policy.d/alice/setprop.list
echo "canmount=on" | sudo tee /etc/zfs-helper/policy.d/alice/setprop.values.list
echo "canmount=noauto" | sudo tee -a /etc/zfs-helper/policy.d/alice/setprop.values.list

# Service to toggle auto-mounting
cat > ~/.config/systemd/user/toggle-automount@.service << 'EOF'
[Unit]
Description=Toggle automount for dataset %i

[Service]
Type=oneshot
ExecStart=/bin/bash -c '
  CURRENT=$(zfs get -H -o value canmount %i)
  if [ "$CURRENT" = "on" ]; then
    zfs-helperctl setprop %i canmount noauto
  else
    zfs-helperctl setprop %i canmount on
  fi
'
EOF
```

## Monitoring and Logging

### Check Service Status

```bash
# Check if zfs-helper daemon is running
sudo systemctl status zfs-helper.socket
sudo systemctl status zfs-helper.service

# View recent logs
sudo journalctl -u zfs-helper.service -n 50

# Follow logs in real-time
sudo journalctl -u zfs-helper.service -f
```

### User Service Debugging

```bash
# Check user service status
systemctl --user status backup@pre-upgrade

# View user service logs
journalctl --user -u backup@pre-upgrade

# Test zfs-helperctl directly (from within a service context)
systemd-run --user --wait zfs-helperctl snapshot tank/home/$USER@test
```

## Troubleshooting

### Common Issues

**Permission Denied**
```bash
# Check group membership
groups

# Check policy files exist
ls -la /etc/zfs-helper/policy.d/$USER/

# Check service name matches policy
grep "$(systemctl --user show -p Id --value)" /etc/zfs-helper/policy.d/$USER/units.list
```

**Command Not Found**
```bash
# Ensure zfs-helper-client is installed
dpkg -l | grep zfs-helper-client

# Check PATH includes /usr/bin
echo $PATH
```

**Service Won't Start**
```bash
# Check systemd user session is running
systemctl --user status

# Check socket is accessible
ls -la /run/zfs-helper.sock

# Test socket connectivity
echo '{"action":"snapshot","target":"test"}' | socat - UNIX-CONNECT:/run/zfs-helper.sock
```

## Best Practices

1. **Test policies in dry-run mode** before applying
2. **Use specific dataset patterns** rather than overly broad wildcards
3. **Monitor logs regularly** for security events
4. **Keep policies minimal** - grant only necessary permissions
5. **Document your services** and their ZFS requirements
6. **Use meaningful snapshot names** with timestamps
7. **Clean up test datasets** and snapshots regularly

## Security Considerations

- Always run from systemd user services, never from interactive shells
- Regularly audit policy files for unnecessary permissions
- Monitor zfs-helper logs for unusual activity
- Keep ZFS Helper and client tools updated
- Use specific dataset paths rather than wildcards when possible
- Consider using separate ZFS pools for different security domains