# Policy Configuration

ZFS Helper uses a policy-based authorization system to control which users and services can perform ZFS operations on specific datasets. This provides fine-grained security while maintaining ease of administration.

## Policy Directory Structure

Per-user policy configuration is stored under:
```
/etc/zfs-helper/policy.d/<username>/
```

Each user directory can contain the following policy files:

### Service Authorization

**`units.list`** - Glob patterns for allowed systemd user unit names
```
backup@*.service
sync.service
container-*.service
```

### Dataset Operation Lists

Dataset-scoped lists that expect one entry per line in the format:
```
<user> <dataset-glob>
```

**Available operation files:**
- `mount.list` - Datasets the user can mount
- `unmount.list` - Datasets the user can unmount (optional - inherits from mount.list if not present)
- `snapshot.list` - Datasets the user can snapshot
- `rollback.list` - Datasets the user can rollback
- `create.list` - Datasets the user can create
- `destroy.list` - Datasets the user can destroy
- `rename.from.list` - Source datasets for rename operations
- `rename.to.list` - Target datasets for rename operations
- `share.list` - Datasets the user can share
- `setprop.list` - Datasets where the user can set properties

### Property Value Constraints

**`setprop.values.list`** - Allowed property values for setprop operations
```
canmount=on
canmount=noauto
canmount=off
sharenfs=on
sharenfs=off
mountpoint:/home/alice*
mountpoint:/var/lib/containers*
```

## User and Dataset Matching

### User Specifications
- Use the literal username: `alice`
- Use wildcard for any zfshelper member: `*`

### Dataset Glob Patterns
ZFS Helper uses gitignore-style wildcards:
- `*` - Matches within a single dataset component
- `**` - Matches across dataset components
- `?` - Matches a single character

**Examples:**
```
alice tank/home/alice/**     # Alice can access any dataset under her home
*     tank/projects/shared/*  # Any user can access shared project datasets
bob   tank/backup/bob         # Bob can access his specific backup dataset
```

## Complete Policy Example

Here's a complete policy setup for user "alice":

### `/etc/zfs-helper/policy.d/alice/units.list`
```
backup@*.service
container@*.service
sync.service
```

### `/etc/zfs-helper/policy.d/alice/mount.list`
```
alice tank/home/alice
alice tank/home/alice/**
*     tank/shared/*
```

### `/etc/zfs-helper/policy.d/alice/snapshot.list`
```
alice tank/home/alice
alice tank/home/alice/**
alice tank/backup/alice/**
```

### `/etc/zfs-helper/policy.d/alice/create.list`
```
alice tank/scratch/*
alice tank/home/alice/tmp/*
```

### `/etc/zfs-helper/policy.d/alice/destroy.list`
```
alice tank/scratch/*
alice tank/home/alice/tmp/*
```

### `/etc/zfs-helper/policy.d/alice/setprop.list`
```
alice tank/home/alice/**
```

### `/etc/zfs-helper/policy.d/alice/setprop.values.list`
```
canmount=on
canmount=noauto
mountpoint:/home/alice*
sharenfs=off
```

## Policy Rules and Logic

### Authorization Flow
1. **Group membership**: User must be in `zfshelper` group
2. **Service origin**: Must be called from authorized systemd user service
3. **Unit authorization**: Service name must match patterns in `units.list`
4. **Operation authorization**: Dataset must match patterns in operation-specific list
5. **Value constraints**: For setprop, values must match `setprop.values.list`

### Deny-by-Default
- Absence of an allow rule = deny
- Empty policy files = no permissions
- Missing operation files = no permissions for that operation

### Rule Merging
- Any matching allow rule grants permission
- Multiple matching rules don't conflict
- More specific rules don't override broader ones

## Policy Management Best Practices

### Security Guidelines
1. **Principle of least privilege**: Grant minimal necessary permissions
2. **User-specific directories**: Keep policies focused on individual users
3. **Regular audits**: Review and update policies periodically
4. **Test changes**: Use `apply-delegation.py --dry-run` to preview changes

### Organization Tips
1. **Consistent naming**: Use clear, descriptive dataset names
2. **Logical grouping**: Group related datasets under common prefixes
3. **Documentation**: Comment policy decisions in separate documentation
4. **Version control**: Track policy changes in git

## Policy Synchronization

ZFS Helper policies can be synchronized with native ZFS delegation using the `apply-delegation.py` tool:

### Preview Changes
```bash
sudo /usr/sbin/apply-delegation.py --dry-run
```

### Apply Changes
```bash
sudo /usr/sbin/apply-delegation.py
```

### Important Notes
- The script manages a focused set of permissions
- Operations that OpenZFS refuses to delegate are skipped but reported
- Avoid running for datasets that don't exist yet
- Wildcards resolve only to present dataset names

## Troubleshooting Policies

### Permission Denied Errors
1. Check user is in `zfshelper` group: `groups username`
2. Verify service name matches `units.list` patterns
3. Confirm dataset matches operation-specific list
4. For setprop, verify value is in `setprop.values.list`

### Policy Not Taking Effect
1. Restart the zfs-helper service: `sudo systemctl restart zfs-helper.service`
2. Check policy file syntax and permissions
3. Verify policy directory ownership: `ls -la /etc/zfs-helper/policy.d/`

### Debugging
Check the service logs for detailed authorization decisions:
```bash
sudo journalctl -u zfs-helper.service -f
```

All authorization decisions are logged in structured JSON format with clear ALLOW/DENY/ERROR reasons.