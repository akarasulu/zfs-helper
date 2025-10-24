# Quick Start Guide

Get ZFS Helper running in 5 minutes with this step-by-step guide.

## Prerequisites

- Linux system with systemd ≥ 240
- OpenZFS installed (`zfsutils-linux`)
- At least one ZFS pool available
- Root access for installation

## Step 1: Install ZFS Helper

### Option A: Debian Packages (Recommended)

```bash
# Add the repository
curl -fsSL https://akarasulu.github.io/zfs-helper/apt/repo-setup.sh | sudo bash

# Install packages
sudo apt update
sudo apt install zfs-helper zfs-helper-client
```

### Option B: Manual Installation

```bash
# Download and extract
wget https://github.com/akarasulu/zfs-helper/archive/main.tar.gz
tar -xf main.tar.gz
cd zfs-helper-main

# Run installer
sudo bash install-zfs-helper.sh --user $USER \
  --unit-globs 'backup@*.service' \
  --snapshot-globs 'tank/home/'"$USER"'*'
```

## Step 2: Configure a User

```bash
# Add yourself to the zfshelper group
sudo usermod -aG zfshelper $USER

# Log out and back in to pick up group membership
exit
# ... log back in ...

# Verify group membership
groups | grep zfshelper
```

## Step 3: Create Basic Policies

```bash
# Create policy directory
sudo mkdir -p /etc/zfs-helper/policy.d/$USER

# Allow backup services
echo "backup@*.service" | sudo tee /etc/zfs-helper/policy.d/$USER/units.list

# Allow snapshots (adjust dataset path as needed)
echo "$USER tank/home/$USER" | sudo tee /etc/zfs-helper/policy.d/$USER/snapshot.list
echo "$USER tank/home/$USER/**" | sudo tee -a /etc/zfs-helper/policy.d/$USER/snapshot.list
```

## Step 4: Create a Test Service

```bash
# Create systemd user directory
mkdir -p ~/.config/systemd/user

# Create a simple backup service
cat > ~/.config/systemd/user/backup@.service << 'EOF'
[Unit]
Description=Create snapshot %i

[Service]
Type=oneshot
ExecStart=/usr/bin/zfs-helperctl snapshot tank/home/${USER}@%i
EOF

# Reload systemd
systemctl --user daemon-reload
```

## Step 5: Test It

```bash
# Create a snapshot
systemctl --user start backup@quickstart-test

# Check if it worked
zfs list -t snapshot | grep quickstart-test

# Check service status
systemctl --user status backup@quickstart-test
```

## Step 6: Verify Logs

```bash
# Check zfs-helper daemon logs
sudo journalctl -u zfs-helper.service -n 10

# Check user service logs
journalctl --user -u backup@quickstart-test
```

If everything worked, you should see:
- A new snapshot named `tank/home/$USER@quickstart-test`
- Success logs in both the daemon and user service
- No error messages

## Next Steps

Now that ZFS Helper is working:

1. **Read the [Usage Guide](usage.md)** for more examples
2. **Configure more policies** in `/etc/zfs-helper/policy.d/$USER/`
3. **Create more services** for your specific needs
4. **Review security** in the [Policy Documentation](policy.md)

## Troubleshooting

### "Permission denied" errors
- Ensure you're in the `zfshelper` group: `groups`
- Check you logged out and back in after adding the group
- Verify policy files exist: `ls /etc/zfs-helper/policy.d/$USER/`

### "Service not found" errors
- Ensure zfs-helper-client is installed: `which zfs-helperctl`
- Check the daemon is running: `sudo systemctl status zfs-helper.socket`

### "Dataset not allowed" errors
- Check your dataset path in the policy files
- Verify the dataset exists: `zfs list`
- Ensure the policy pattern matches your dataset

### Still stuck?
Check the [Usage Guide](usage.md) for more detailed troubleshooting steps.