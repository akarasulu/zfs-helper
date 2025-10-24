# ZFS Helper

A Linux OpenZFS delegation helper service for secure unprivileged ZFS operations.

## Overview

ZFS Helper allows unprivileged systemd user-scoped services to securely request ZFS operations (mount, snapshot, rollback, create, destroy, rename, setprop, and share) on specific datasets and snapshots via a privileged socket-activated helper daemon, following a fine-grained user, operation, and delegate service policy.

The privileged gateway service securely overcomes delegation limitations resulting from ZFS ports to Linux. The full gambit of ZFS features like delegated mounting, zero cost snapshots and rollback can be used to control and manage service storage volumes. It is especially useful for container engines like Podman, and its volume Quadlets to maintain data integrity across reboots and abrupt shutdowns.

## Key Features

- **AF_UNIX + SO_PEERCRED**: kernel-authenticated peer PID/UID/GID
- **Enforces user-service origin**: systemd user cgroup check
- **Group-based access control**: requires callers to belong to the `zfshelper` group
- **Per-user authorized unit allowlist**: glob patterns supported
- **Per-action dataset allowlists**: keyed by `<user> <glob>` entries with gitignore-style wildcards (`*`, `?`, `**`)
- **Automatic ownership harmonisation**: dataset creates/renames and snapshot creates chown mount trees to the caller's UID + primary GID
- **Comprehensive audit logging**: clear structured journald logs with ALLOW/DENY/ERROR reasons in JSON format

## Supported Operations

- `mount` / `unmount` - Mount and unmount ZFS datasets
- `snapshot` - Create ZFS snapshots
- `rollback` - Rollback to ZFS snapshots
- `create` / `destroy` - Create and destroy ZFS datasets
- `rename` - Rename ZFS datasets
- `setprop` - Set ZFS properties (`mountpoint`/`canmount`/`sharenfs`)
- `share` - Share ZFS datasets (limited implementation)

## Getting Started

Ready to try ZFS Helper? Check out the [Installation](installation.md) guide to get started, then review the [Policy](policy.md) documentation to configure permissions for your users and services.

For the latest updates and changes, see our [Release Notes](release.md).