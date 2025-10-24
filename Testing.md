# Testing

This document describes the architecture and operation of the automated test harness for `zfs-helper`, which uses `pytest` to run integration tests against a Debian 12 VM provisioned via Vagrant and libvirt. Each test executes ZFS operations through the helper in an isolated ephemeral zpool, verifying correct behavior, policy enforcement, ownership, and logging.

After all what makes this system valuable is not just the little snippets of code here and there but the tests and real life use that ensure its correctness and security. The following sections outline the architecture and lifecycle of the test harness.

## Harness Architecture

```mermaid
graph TB
  subgraph HOST [Host Machine]
    GH[GitHub Repo zfs-helper]
    PY[pytest test runner]
    VA[Vagrant CLI libvirt]
    AN[Ansible optional]
    AR[Artifacts logs reports]
  end

  subgraph VM [Debian 12 VM systemd]
    SYS[systemd user and system]
    ZFS[ZFS stack]
    ZHS[zfs-helper.socket]
    ZHC[zfs-helperctl CLI]
    ZH[zfs-helper service]
    DISKS[Extra virtio disks]
    DATA[Ephemeral zpools per test]
    LOGS[Journal and service logs]
  end

  PY --> VA
  AN --> VA
  GH --> PY

  VA --> VM
  PY --> VA
  PY --> VM

  SYS --> ZHS
  ZHS --> ZH
  ZHC --> ZHS
  ZH --> ZFS
  ZFS --> DATA
  ZH --> LOGS

  PY --> AR
  VM --> AR
  DISKS --> ZFS
  ZFS --> DATA

```

## Per-Test Lifecycle

```mermaid
sequenceDiagram
  autonumber
  participant Dev as Developer
  participant Py as pytest
  participant Va as Vagrant
  participant V as Debian 12 VM
  participant Sd as systemd
  participant Zc as zfs-helperctl
  participant Zh as zfs-helper
  participant Zf as ZFS

  Dev->>Py: run tests
  Py->>Va: ensure VM up
  Va->>V: boot and provision if first run
  Va->>Va: save baseline snapshot

  loop each test
    Py->>Va: restore baseline snapshot
    Py->>V: prepare test pool
    Py->>Zc: run command mount or snapshot or rollback
    Zc->>Sd: trigger socket
    Sd->>Zh: start service
    Zh->>Zf: perform ZFS operation
    Zf-->>Zh: result
    Zh-->>Zc: json status
    alt failure
      Py->>Va: save failed snapshot
    end
    Py->>V: collect logs and status
    V-->>Py: artifacts
  end

```

## Test Coverage

- Unit tests cover policy parsing, glob matching, request validation, and action handlers.
- Integration tests exercise end-to-end request flows for all supported actions (`mount`, `unmount`, `snapshot`, `rollback`, `create`, `destroy`, `rename`, `setprop`, `share`).
- Negative tests verify denial cases: unauthorized units, disallowed datasets, invalid arguments, root callers, malformed payloads.
- Ownership tests confirm that created datasets and snapshots have correct UID/GID ownership.
- Logging tests ensure that all decisions are logged with appropriate structured data.
- Delegation sync tests validate that `apply-delegation.py` correctly reflects policy in ZFS delegation settings.
