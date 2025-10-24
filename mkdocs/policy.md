# Policy layout

Per-user policy: /etc/zfs-helper/policy.d/<username>/

Files:
- units.list
- mount.list, unmount.list, snapshot.list, rollback.list, create.list, destroy.list
- rename.from.list, rename.to.list
- share.list, setprop.list, setprop.values.list

Rules are merged: any allow rule that matches grants permission. Absence of allow = deny.

Best practice: keep per-user directories tidy and only include entries for that user (or `*`) to avoid accidental grants.