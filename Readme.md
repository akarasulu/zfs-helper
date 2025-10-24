# Zfs Helper

>**COPIED FROM**: [gh-repos](https://akarasulu.github.io/gh-repos/) for APT repo hosting on GitHub Pages

A Linux OpenZFS delegation helper service.

## TL;DR Description

Unprivileged systemd user-scoped services securely request ZFS operations (mount, snapshot, rollback, create, destroy, rename, setprop, and share) on specific datasets and snapshots via a privileged socket-activated helper daemon, following a fine-grained user, operation, and delegate service policy.

The privileged gateway service securely overcomes delegation limitations resulting from ZFS ports to Linux. The full gambit of ZFS features like delegated mounting, zero cost snapshots and rollback can be used to control and manage service storage volumes. It is especially useful for container engines like Podman, and its volume Quadlets to maintain data integrity across reboots and abrupt shutdowns.

## Quick Start

<!-- TODO: add howto that installs and uses it with an unprivileged podman container service to mount and use a volume -->

## Features

- AF_UNIX + SO_PEERCRED: kernel-authenticated peer PID/UID/GID
- Enforces **user-service** origin (systemd user cgroup check)
- Requires callers to belong to the `zfshelper` group
- Per-user **authorized unit** allowlist (glob patterns supported)
- Per-action **dataset** allowlists keyed by `<user> <glob>` entries with gitignore-style wildcards (`*`, `?`, `**`)
- Automatic ownership harmonisation: dataset creates/renames and snapshot creates chown mount trees to the caller's UID + primary GID
- Actions: `mount`, `unmount` (implicit permission via mount list unless `unmount.list` exists), `snapshot`, `rollback`, `create`, `destroy`, `rename`, `setprop` (`mountpoint`/`canmount`/`sharenfs`), `share` (`share` and `sharenfs` not implemented and may be removed)
- Clear structured journald logs with ALLOW/DENY/ERROR reasons in json format

## Layout

- `install-zfs-helper.sh` - installer (idempotent)
- `sbin/zfs-helper.py` - daemon (privileged service driver)
- `sbin/apply-delegation.py` - synchronizes (as much as is possible) zfs-helper policies with delegated ZFS permissions
- `pkgs/zfs-helper-client/usr/bin/zfs-helperctl` - client CLI (used by user-scoped services)
- `systemd/zfs-helper.socket` & `systemd/zfs-helper.service` - systemd units
- `examples/user/backup@.service` - demonstrates user-scoped service access to zfs-helper
- `policy/` - example policy files to seed installations

## Quick start

### Debian Package Installation (Recommended)

```bash
# Add repository and install
curl -fsSL https://akarasulu.github.io/zfs-helper/apt/repo-setup.sh | sudo bash
sudo apt update
sudo apt install zfs-helper zfs-helper-client

# Add user to group and configure policies
sudo usermod -aG zfshelper $USER
# Create policy files under /etc/zfs-helper/policy.d/$USER/
# See Installation documentation for details
```

### Manual Installation

```bash
# Unpack
tar -xf zfs-helper.tar.gz
cd zfs-helper

# Install (example values; adjust to taste)
sudo bash install-zfs-helper.sh --user $USER   --unit-globs 'backup@*.service'   --mount-globs 'tank/home/'"$USER"'*'   --snapshot-globs 'tank/home/'"$USER"',tank/home/'"$USER"'/*'   --rollback-globs 'tank/home/'"$USER"',tank/home/'"$USER"'/*'   --create-globs 'tank/scratch/*'   --destroy-globs 'tank/scratch/*'   --rename-from-globs 'tank/data/tmp-*'   --rename-to-globs 'tank/data/archive/*'   --setprop-globs 'tank/home/'"$USER"'*'   --setprop-values 'canmount=on,canmount=noauto,sharenfs=on,sharenfs=off,mountpoint:/home/'"$USER"'*'   --share-globs 'tank/home/'"$USER"'*'

# Re-login (to pick up zfshelper group), or newgrp zfshelper

# Use the example user service:
mkdir -p ~/.config/systemd/user
cp examples/user/backup@.service ~/.config/systemd/user/
systemctl --user daemon-reload
systemctl --user start backup@pre-upgrade

# Observe logs
journalctl -u zfs-helper.service -n 100 --no-pager
```

## Policy directory

Per-user policy lives under: `/etc/zfs-helper/policy.d/<username>/`

- `units.list` - glob list of allowed user unit names (`backup@*.service`, `sync.service`, …)
- Dataset-scoped lists (`mount.list`, `unmount.list`, `snapshot.list`, `rollback.list`, `create.list`, `destroy.list`, `rename.from.list`, `rename.to.list`, `share.list`, `setprop.list`) expect one entry per line in the form:
  ```text
  <user> <dataset-glob>
  ```
  Use the literal username or `*` for any `zfshelper` member. Globs follow gitignore rules (`*` within a segment, `**` across segments).
  Example:
  ```text
  bob   tank/home/bob/**
  *     tank/projects/shared/*
  ```
- `setprop.values.list` - value constraints, e.g.:
  ```text
  canmount=on
  canmount=noauto
  sharenfs=off
  mountpoint:/home/alex*
  ```
- `share.list` - datasets allowed to be shared

## Delegation sync

- `apply-delegation.py` reads the policy tree and applies corresponding `zfs allow` and `zfs unallow` rules so that OpenZFS delegation mirrors the helper’s policy (run as root).
- Use `--dry-run` to inspect the changes without executing them:
  ```bash
  sudo /usr/sbin/apply-delegation.py --dry-run
  ```
- The script manages a focused set of permissions (`mount`, `snapshot`, `rollback`, `create`, `destroy`, `rename`, selected properties, and - where supported - `share`). Operations that OpenZFS refuses to delegate are skipped but reported.
- Trigger it manually after policy edits or wire it into an automated workflow; avoid running it for datasets that do not yet exist, as wildcards resolve only to present names.

## Security notes

- The daemon runs as root but is hardened with systemd sandboxing and a minimal `CapabilityBoundingSet`.
- Every request must pass:
  1. socket group membership (coarse gate: `zfshelper`)
  2. kernel-provided creds (SO_PEERCRED)
  3. **systemd user-service** origin check
  4. authorized **unit name** check
  5. per-action **dataset whitelist** (plus optional value guards)
  6. per-user dataset ownership checks
- Root callers are rejected.
- All denials and errors are logged with structured details for auditing.

## Background and Why

I've been an avid user of ZFS on Solaris then on Linux for decades, appreciating its robustness, data integrity features, and advanced CoW capabilities like snapshots and clones. However, Linux OpenZFS's delegation model has historically been less mature compared to Solaris, the biggest issue lies in unprivileged users mounting and unmounting datasets or snapshots. For ages I've used workarounds for these problems.

Finally, when cornered, I had no choice but to publish and share the "workaround". I decided to clean up my scripts and services, make them more robust, document them, and make it so others can use them and support them. Hence this new zfs-helper project.

This workaround is really old and an evolution. Previous approaches to this problem have included setuid wrappers, or sudoers rules. However, these approaches are fraught with security risks and lack fine-grained control. The need for a secure, auditable mechanism (with a least privilege approach) to allow specific unprivileged services to perform ZFS operations without granting them full root access did not exist. A lingering yet semi-functional delegation model in OpenZFS left a gap that this helper aims to fill.

By implementing a socket-activated daemon with strict policy enforcement, zfs-helper provides a robust solution that balances security and usability. It allows system administrators to define precise policies for which services can perform specific ZFS operations on designated datasets, all while maintaining comprehensive logging for auditing purposes. This approach not only enhances security but also simplifies management and oversight of ZFS operations in multi-user environments.

## Roadmap

For now the focus is on stabilizing the core functionality, improving documentation, and gathering user feedback. Future enhancements may include:

- Policy validation before achieving a new system-wide `zfs-helper.target`, so all user scoped units can depend on it, waiting until the policy is valid and synchronized with zfs allow properties.
- A [test harness](Testing.md) for automated integration and unit tests: after all this is not a simple API and has system components with systemd requiring a full virtual machine.
  - Purpose-built suites: unit, integration, end-to-end, and regression tests covering policy parsing, glob matching, unit validation, cgroup checks, SO_PEERCRED handling, and each ZFS action.
  - ZFS pool and dataset tree, mounts, snapshots, and on-disk fixtures for real ZFS pool (container/VM based).
  - Declarative test cases: YAML/JSON test manifests that declare caller identity, unit name, policy files, dataset layout, requested action, expected allow/deny, and expected side-effects (mounts, ownership changes).
  - Golden-file and mutation testing: store canonical outputs and mutate rules to detect regressions and overly-broad globs.
  - Concurrency and race scenarios: targeted tests for rename/rename-from, concurrent snapshot/create/destroy sequences, and delegation reapply races.
  - Property fuzzing: exercise setprop constraints and value guards with fuzzed inputs to validate sanitisation and rejection paths.
- Full code coverage and tests for all positive and negative operation tests
  - Coverage goals per layer: policy parser, glob matcher, auth checks, systemd unit validator, delegation applier, and the socket protocol boundary.
  - Negative-path emphasis: exhaustive checks for invalid inputs, malicious globs, UID/GID edge-cases, privileged-caller rejection, and malformed socket payloads.
  - Instrumented runs: coverage reports (HTML, lcov), per-test timing, and slow-test annotations to focus optimization.
  - Fuzz harnesses: targeted fuzzers for parsing layers and network/IPC deserialisation to detect panics, resource exhaustion, and injection vectors.
  - Release validation: a staged release pipeline that runs full acceptance tests against a disposable ZFS pool before publishing packages.
- Enhanced logging, observability and audit pipelines — structured, schema-versioned events and tooling
  - Event schema and required fields:
    - schema version, timestamp (RFC3339), request id (UUID), caller uid/gid/pid, originating unit name, action, dataset(s), policy rule id(s), decision (ALLOW/DENY/ERROR), reason, zfs command + exit metadata, elapsed micros, and optional kernel/SELinux/context metadata.
  - Metrics and health:
    - Prometheus metrics (counters for requests, denies, errors, latencies, per-action histograms), health and readiness probes for orchestration, and alerting playbooks for common faults.
  - Audit tooling:
    - search/filter CLI for historical events, replay and rehydration utilities to re-run non-destructive sequences in emulator mode, and built-in exporters to common SIEMs.
  - Versioning and migration:
    - schema evolution rules, migration tooling for older logs, and compatibility guarantees for consumers across minor schema bumps.
- Policy testing, validation and continuous integration — a declarative test harness that exercises policy permutations against real ZFS environments (containerized/lightweight VM testbeds), with fixtures for datasets, snapshots and mounts. Features include: policy linter and static validator (detects unreachable rules, conflicting globs, overly-permissive entries), unit/acceptance test templates for policy authors, golden-file expectations, property constraint fuzzing, end-to-end dry-run mode that simulates effects without invoking destructive ZFS ops, mutation testing for policy regressions, automatic CI job generation and GitHub/GitLab pipeline snippets, test coverage reporting, and pre-commit hooks to prevent regressive policy commits. Provide an emulator mode for offline development that mimics core permission checks, systemd unit validation, and mount behavior to enable rapid local iteration.
- Consider a dataset archive manager — a policy-driven tool to export/import dataset snapshots to long-term archives (stream/receive, optional compression/encryption, manifesting), with retention rules, dry-run/restore workflows, pluggable backends (local archive pool, object storage), and integration with the helper's delegation, audit logging, and access controls.
- A management UI for policy administration?
  - These white list files and permissions can get complex over time. A web-based or TUI management interface could help visualize and edit policies, view logs, and manage delegation settings.
  - A neat approach would be to fire up the UI as root for a specific user:
    - `sudo zfs-helper-ui --user alice`
    - all user-scoped units are scanned for zfs-helper interaction
    - the policy for alice is loaded and presented: units, datasets, users, and operations
    - edits are validated and written back to `/etc/zfs-helper/policy.d/alice/`
    - delegation sync is triggered
    - logs are filtered to show only alice's actions in past
  - This would simplify administration and reduce human error in complex policy configurations.

## License

Apache Software License 2.0. See LICENSE file.
