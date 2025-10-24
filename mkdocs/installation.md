# Installation

Prereqs:
- systemd (installer checks minimum version)
- root privileges to install systemd units and binaries

Run the installer (example):

```bash
sudo bash install-zfs-helper.sh --user $USER ...
```

The installer performs a systemd version check and will abort if the host systemd is too old.