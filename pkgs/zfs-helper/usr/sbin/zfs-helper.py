#!/usr/bin/env python3
"""User-service-facing daemon that proxies a constrained set of ZFS commands."""

import os
import socket
import struct
# trunk-ignore(bandit/B404)
import subprocess
import fnmatch
import pwd
import grp
import re
import time
import json

SOCK_PATH = "/run/zfs-helper.sock"
ZFS_BIN = "/usr/sbin/zfs"
POLICY_ROOT = "/etc/zfs-helper/policy.d"
LOG_TAG = "zfs-helper"
DATASET_RE = re.compile(r"^[A-Za-z0-9:_\-.]+(?:/[A-Za-z0-9:_\-.]+)*$")
SNAP_RE = re.compile(r"^[A-Za-z0-9:_\-.]+(?:/[A-Za-z0-9:_\-.]+)*@[A-Za-z0-9:_\-.]+$")
PROP_KEY_ALLOW = {"mountpoint", "canmount", "sharenfs"}
CANMOUNT_VALS = {"on", "off", "noauto"}

def log(level, msg, **kw):
    """Emit a structured log line with optional key/value metadata."""
    kv = " ".join(f"{k}={v}" for k, v in kw.items())
    print(f"{LOG_TAG} [{level}] {msg}" + (f" {kv}" if kv else ""), flush=True)

def read_peer_ucred(conn):
    """Return (pid, uid, gid) for a connected UNIX socket peer."""
    ucred = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, struct.calcsize("3i"))
    pid, uid, gid = struct.unpack("3i", ucred)
    return pid, uid, gid

def is_user_service(pid, uid):
    """Check whether the peer PID belongs to the caller's systemd user service."""
    try:
        with open(f"/proc/{pid}/cgroup", "r") as f:
            cg = f.read()
    except FileNotFoundError:
        return (False, None)
    path = None
    for line in cg.splitlines():
        parts = line.split(":")
        if len(parts) == 3 and parts[0] == "0":
            path = parts[2]
            break
    if not path:
        return (False, None)
    wanted = f"/user.slice/user-{uid}.slice/user@{uid}.service/app.slice/"
    if wanted not in path:
        return (False, None)
    try:
        seg = path.split("/app.slice/")[1]
        unit = seg.split(".service")[0] + ".service"
        return (True, unit)
    except Exception:
        return (False, None)

def uname(uid):
    """Resolve a UID to a username, falling back to the numeric identifier."""
    try:
        return pwd.getpwuid(uid).pw_name
    except KeyError:
        return f"uid{uid}"

def load_lines(path):
    """Load newline-delimited allow-list entries, skipping comments and blanks."""
    out = []
    try:
        with open(path, "r") as f:
            for line in f:
                s = line.strip()
                if s and not s.startswith("#"):
                    out.append(s)
    except FileNotFoundError:
        pass
    return out

def load_dataset_rules(path):
    """Load dataset policy entries that scope globs to specific users."""
    entries = []
    try:
        with open(path, "r") as f:
            for raw in f:
                line = raw.strip()
                if not line or line.startswith("#"):
                    continue
                parts = line.split(None, 1)
                if len(parts) < 2:
                    log("WARN", "invalid dataset policy entry", path=path, entry=line)
                    continue
                actor = parts[0].strip()
                pattern = parts[1].strip()
                if not actor or not pattern:
                    log("WARN", "invalid dataset policy entry", path=path, entry=line)
                    continue
                entries.append((actor, pattern))
    except FileNotFoundError:
        pass
    return entries

def load_policy(user):
    """Collect the policy lists for a user identified by name."""
    base = os.path.join(POLICY_ROOT, user)
    return {
        "units":          load_lines(os.path.join(base, "units.list")),
        "mount":          load_dataset_rules(os.path.join(base, "mount.list")),
        "unmount":        load_dataset_rules(os.path.join(base, "unmount.list")),
        "snapshot":       load_dataset_rules(os.path.join(base, "snapshot.list")),
        "rollback":       load_dataset_rules(os.path.join(base, "rollback.list")),
        "create":         load_dataset_rules(os.path.join(base, "create.list")),
        "destroy":        load_dataset_rules(os.path.join(base, "destroy.list")),
        "rename_from":    load_dataset_rules(os.path.join(base, "rename.from.list")),
        "rename_to":      load_dataset_rules(os.path.join(base, "rename.to.list")),
        "setprop":        load_dataset_rules(os.path.join(base, "setprop.list")),
        "setprop.values": load_lines(os.path.join(base, "setprop.values.list")),
        "share":          load_dataset_rules(os.path.join(base, "share.list")),
    }

def list_allows(p, key):
    """Return the allow-list for a given policy key."""
    return p.get(key, []) if p else []

def dataset_allowed(p, key, user, target):
    """Check whether a dataset glob entry authorizes the user."""
    entries = p.get(key, []) if p else []
    return any(_dataset_entry_allows(entry, user, target) for entry in entries)

def _dataset_entry_allows(entry, user, target):
    actor, pattern = entry
    if actor not in (user, "*"):
        return False
    return dataset_glob_match(pattern, target)

def dataset_glob_match(pattern, target):
    """Match dataset glob patterns with gitignore-style ** semantics."""
    pat_parts = pattern.split("/")
    tgt_parts = target.split("/")
    return _match_parts(pat_parts, tgt_parts)

def _match_parts(pat_parts, tgt_parts):
    if not pat_parts:
        return not tgt_parts
    head, *rest = pat_parts
    if head == "**":
        # Match zero segments
        if _match_parts(rest, tgt_parts):
            return True
        # Match one or more segments
        return bool(tgt_parts) and _match_parts(pat_parts, tgt_parts[1:])
    if not tgt_parts:
        return False
    if not fnmatch.fnmatchcase(tgt_parts[0], head):
        return False
    return _match_parts(rest, tgt_parts[1:])

def _user_ids(uid):
    try:
        pw = pwd.getpwuid(uid)
    except KeyError:
        return None
    return pw.pw_uid, pw.pw_gid

def _dataset_mountpoint(dataset):
    ok, out, err, rc = zfs_ok(["get", "-H", "-o", "value", "mountpoint", dataset])
    if not ok:
        log("WARN", "mountpoint lookup failed", dataset=dataset, err=(err or f"rc={rc}"))
        return None
    mountpoint = (out.splitlines()[0] if out else "").strip()
    if mountpoint in {"", "legacy", "none", "-"}:
        return None
    return mountpoint

def _list_descendant_filesystems(dataset):
    ok, out, err, rc = zfs_ok(["list", "-H", "-r", "-o", "name", "-t", "filesystem", dataset])
    if not ok:
        log("WARN", "descendant listing failed", dataset=dataset, err=(err or f"rc={rc}"))
        return [dataset]
    names = [line.strip() for line in out.splitlines() if line.strip()]
    return names or [dataset]

def _safe_chown(path, uid, gid):
    try:
        if os.path.islink(path):
            os.lchown(path, uid, gid)
        else:
            os.chown(path, uid, gid)
    except FileNotFoundError:
        pass
    except PermissionError as e:
        log("WARN", "chown permission error", path=path, err=f"{e.__class__.__name__}:{e}")
    except OSError as e:
        log("WARN", "chown failed", path=path, err=f"{e.__class__.__name__}:{e}")

def _chown_recursive(path, uid, gid):
    if not os.path.exists(path):
        return
    _safe_chown(path, uid, gid)
    for root, dirs, files in os.walk(path, topdown=True, followlinks=False):
        for name in dirs:
            _safe_chown(os.path.join(root, name), uid, gid)
        for name in files:
            _safe_chown(os.path.join(root, name), uid, gid)

def _apply_dataset_tree_ownership(dataset, uid):
    ids = _user_ids(uid)
    if not ids:
        log("WARN", "unable to resolve user for ownership", dataset=dataset, uid=uid)
        return
    for ds in _list_descendant_filesystems(dataset):
        mountpoint = _dataset_mountpoint(ds)
        if not mountpoint:
            continue
        _chown_recursive(mountpoint, ids[0], ids[1])

def _apply_single_dataset_ownership(dataset, uid):
    ids = _user_ids(uid)
    if not ids:
        log("WARN", "unable to resolve user for ownership", dataset=dataset, uid=uid)
        return
    mountpoint = _dataset_mountpoint(dataset)
    if not mountpoint:
        return
    _chown_recursive(mountpoint, ids[0], ids[1])

def _apply_snapshot_ownership(dataset, snapshot, uid, recursive=False):
    ids = _user_ids(uid)
    if not ids:
        log("WARN", "unable to resolve user for snapshot ownership", dataset=dataset, uid=uid, snapshot=snapshot)
        return
    datasets = _list_descendant_filesystems(dataset) if recursive else [dataset]
    for ds in datasets:
        mountpoint = _dataset_mountpoint(ds)
        if not mountpoint:
            continue
        snap_path = os.path.join(mountpoint, ".zfs", "snapshot", snapshot)
        if not os.path.exists(snap_path):
            continue
        _chown_recursive(snap_path, ids[0], ids[1])

def user_in_zfshelper_group(uid):
    """Verify that the caller belongs to the zfshelper group."""
    try:
        user = pwd.getpwuid(uid)
    except KeyError:
        return False
    try:
        helper_group = grp.getgrnam("zfshelper")
    except KeyError:
        return False
    if user.pw_gid == helper_group.gr_gid:
        return True
    return user.pw_name in helper_group.gr_mem

def zfs_ok(args):
    """Execute a zfs(8) command and return success flag plus output."""
    try:
        # trunk-ignore(bandit/B603)
        res = subprocess.run([ZFS_BIN] + args, capture_output=True, text=True)
        return (res.returncode == 0, res.stdout.strip(), res.stderr.strip(), res.returncode)
    except Exception as e:
        return (False, "", str(e), 127)

def allow_or_error(ok, out, err, rc):
    """Normalize zfs command results into (status, info) tuples."""
    return ("OK", out or "") if ok else ("ERROR", (err or f"rc={rc}").strip())

def deny(reason): return (reason, "")

def handle_mount(p, user, ds):
    """Mount a dataset if the policy and dataset name allow it."""
    if not DATASET_RE.fullmatch(ds):
        return deny("INVALID_DATASET")
    if not dataset_allowed(p, "mount", user, ds):
        return deny("DENY_POLICY")
    return allow_or_error(*zfs_ok(["mount", ds]))

def handle_unmount(p, user, ds):
    if not DATASET_RE.fullmatch(ds):
        return deny("INVALID_DATASET")
    unmount_entries = list_allows(p, "unmount")
    if unmount_entries:
        allowed = dataset_allowed(p, "unmount", user, ds)
    else:
        allowed = dataset_allowed(p, "mount", user, ds)
    if not allowed:
        return deny("DENY_POLICY")
    return allow_or_error(*zfs_ok(["umount", ds]))

def handle_snapshot(p, user, uid, tgt, rec=False):
    """Create snapshots under permitted datasets."""
    if not SNAP_RE.fullmatch(tgt):
        return deny("INVALID_SNAPSHOT")
    ds = tgt.split("@", 1)[0]
    if not dataset_allowed(p, "snapshot", user, ds):
        return deny("DENY_POLICY")
    args = ["snapshot"]
    if rec:
        args.append("-r")
    args.append(tgt)
    ok, out, err, rc = zfs_ok(args)
    status, info = allow_or_error(ok, out, err, rc)
    if ok:
        snap_name = tgt.split("@", 1)[1]
        _apply_snapshot_ownership(ds, snap_name, uid, recursive=rec)
    return status, info

def handle_rollback(p, user, uid, snap, rec=False, force=False):
    """Rollback to a snapshot if permitted by policy."""
    if not SNAP_RE.fullmatch(snap):
        return deny("INVALID_SNAPSHOT")
    ds = snap.split("@", 1)[0]
    if not dataset_allowed(p, "rollback", user, ds):
        return deny("DENY_POLICY")
    args = ["rollback"]
    if force:
        args.append("-f")
    if rec:
        args.append("-r")
    args.append(snap)
    return allow_or_error(*zfs_ok(args))

def handle_create(p, user, uid, ds, props=None):
    """Create a dataset with optional properties, respecting policy."""
    if not DATASET_RE.fullmatch(ds):
        return deny("INVALID_DATASET")
    if not dataset_allowed(p, "create", user, ds):
        return deny("DENY_POLICY")
    args = ["create"]
    for k, v in (props or {}).items():
        args += ["-o", f"{k}={v}"]
    args.append(ds)
    ok, out, err, rc = zfs_ok(args)
    status, info = allow_or_error(ok, out, err, rc)
    if ok:
        _apply_single_dataset_ownership(ds, uid)
    return status, info

def handle_destroy(p, user, uid, tgt, rec=False, force=False):
    """Destroy datasets or snapshots when policy allows."""
    is_ds = DATASET_RE.fullmatch(tgt) is not None
    is_snap = SNAP_RE.fullmatch(tgt) is not None
    if not (is_ds or is_snap):
        return deny("INVALID_TARGET")
    base = tgt.split("@", 1)[0]
    if not dataset_allowed(p, "destroy", user, base):
        return deny("DENY_POLICY")
    args = ["destroy"]
    if force:
        args.append("-f")
    if rec:
        args.append("-r")
    args.append(tgt)
    return allow_or_error(*zfs_ok(args))

def handle_rename(p, user, uid, src, dst):
    """Rename a dataset when both source and destination are approved."""
    if not (DATASET_RE.fullmatch(src) and DATASET_RE.fullmatch(dst)):
        return deny("INVALID_DATASET")
    if not dataset_allowed(p, "rename_from", user, src):
        return deny("DENY_POLICY_SRC")
    if not dataset_allowed(p, "rename_to", user, dst):
        return deny("DENY_POLICY_DST")
    ok, out, err, rc = zfs_ok(["rename", src, dst])
    status, info = allow_or_error(ok, out, err, rc)
    if ok:
        _apply_dataset_tree_ownership(dst, uid)
    return status, info

def parse_setprop_values(lines):
    """Parse property allow-list rules from policy files."""
    rules = []
    for line in lines:
        if ":" in line and "=" not in line:
            k, glob = line.split(":", 1)
            rules.append((k.strip(), None, glob.strip()))
        elif "=" in line:
            k, v = line.split("=", 1)
            rules.append((k.strip(), v.strip(), None))
    return rules

def _setprop_key_allowed(key):
    """Whitelist of property keys user services may mutate."""
    return key in PROP_KEY_ALLOW

def _setprop_dataset_valid(ds):
    """Ensure property updates operate on syntactically valid dataset names."""
    return DATASET_RE.fullmatch(ds) is not None

def _setprop_policy_allows(p, user, ds):
    """Check whether the dataset is covered by the policy for setprop."""
    return dataset_allowed(p, "setprop", user, ds)

def _check_builtin_rules(key, value):
    """Apply baked-in validation rules for property values."""
    if key == "canmount":
        return value in CANMOUNT_VALS
    if key == "mountpoint":
        return value.startswith("/") and " " not in value
    if key == "sharenfs":
        return value in {"on", "off"}
    return False

def _value_allowed_by_rules(rules, key, value):
    """Evaluate user-specified allow rules against requested property values."""
    if not rules:
        return _check_builtin_rules(key, value)

    for (k, v, g) in rules:
        if k != key:
            continue
        if v is not None and fnmatch.fnmatch(value, v):
            return True
        if g is not None and key == "mountpoint" and fnmatch.fnmatch(value, g):
            return True
    return False

def handle_setprop(p, user, ds, key, value):
    """Set ZFS properties while enforcing policy rules and safe defaults."""
    if not _setprop_key_allowed(key):
        return deny("DENY_PROP_KEY")
    if not _setprop_dataset_valid(ds):
        return deny("INVALID_DATASET")
    if not _setprop_policy_allows(p, user, ds):
        return deny("DENY_POLICY")

    rules = parse_setprop_values(list_allows(p, "setprop.values"))
    if not _value_allowed_by_rules(rules, key, value):
        return deny("DENY_PROP_VALUE")

    return allow_or_error(*zfs_ok(["set", f"{key}={value}", ds]))

def handle_share(p, user, ds):
    """Allow user services to re-share datasets if policy permits."""
    if not DATASET_RE.fullmatch(ds):
        return deny("INVALID_DATASET")
    if not dataset_allowed(p, "share", user, ds):
        return deny("DENY_POLICY")
    return allow_or_error(*zfs_ok(["share", ds]))

def send(conn, status, info):
    """Emit a JSON response to the requester."""
    payload = json.dumps({"status": status, "info": info}, separators=(",",":")) + "\n"
    conn.sendall(payload.encode())

def parse_request(raw):
    """Decode a JSON request payload into a dictionary."""
    try:
        return json.loads(raw)
    except Exception:
        return None

def handle_action(p, req, user, uid):
    """Dispatch the request to the appropriate handler."""
    a = req["action"]
    if a == "mount":
        return handle_mount(p, user, req.get("dataset", ""))
    elif a == "unmount":
        return handle_unmount(p, user, req.get("dataset", ""))
    elif a == "snapshot":
        return handle_snapshot(p, user, uid, req.get("target", ""), bool(req.get("recursive", False)))
    elif a == "rollback":
        return handle_rollback(p, user, uid, req.get("snapshot", ""), bool(req.get("recursive", False)), bool(req.get("force", False)))
    elif a == "create":
        return handle_create(p, user, uid, req.get("dataset", ""), req.get("props") or {})
    elif a == "destroy":
        return handle_destroy(p, user, uid, req.get("target", ""), bool(req.get("recursive", False)), bool(req.get("force", False)))
    elif a == "rename":
        return handle_rename(p, user, uid, req.get("src", ""), req.get("dst", ""))
    elif a == "setprop":
        return handle_setprop(p, user, req.get("dataset", ""), req.get("key", ""), req.get("value", ""))
    elif a == "share":
        return handle_share(p, user, req.get("dataset", ""))
    return ("BAD_ACTION", "")

def validate_request(pid, uid, caller, conn):
    """Run authentication and policy checks before executing an action."""
    ok, unit = is_user_service(pid, uid)
    # Immediately reject callers who are not systemd user services.
    if not ok:
        send(conn, "DENY_NOT_USER_SERVICE", "")
        log("DENY","not a user service",peer_pid=pid,peer_uid=uid,peer_user=caller)
        return None, None
    p = load_policy(caller)
    units = list_allows(p, "units")
    if not units or not any(fnmatch.fnmatch(unit, pat) for pat in units):
        send(conn, "DENY_UNIT", unit or "")
        log("DENY","unit not allowed",unit=(unit or "unknown"),peer_uid=uid,peer_user=caller)
        return None, None
    if not user_in_zfshelper_group(uid):
        send(conn, "DENY_GROUP", "")
        log("DENY","user not in zfshelper group",peer_uid=uid,peer_user=caller,unit=unit)
        return None, None
    return p, unit

def handle(conn):
    """Receive, validate, and process a single connection."""
    pid, uid, _ = read_peer_ucred(conn)
    caller = uname(uid)
    data = b""
    while True:
        chunk = conn.recv(4096)
        if not chunk:
            break
        data += chunk
        if len(data) > 8192:
            break
    req_s = data.decode("utf-8", errors="replace").strip()
    req = parse_request(req_s)
    if not req or "action" not in req:
        send(conn, "BAD_REQUEST", "expect JSON with 'action'")
        log("DENY","bad request",peer_pid=pid,peer_uid=uid,peer_user=caller)
        return
    if uid == 0:
        send(conn, "DENY_ROOT", "")
        log("DENY","root caller not allowed",peer_pid=pid,peer_uid=uid,peer_user=caller)
        return

    p, unit = validate_request(pid, uid, caller, conn)
    if p is None:
        return

    status, info = handle_action(p, req, caller, uid)
    send(conn, status, info)
    if status == "OK":
        lvl = "ALLOW"
    elif status.startswith("DENY"):
        lvl = "DENY"
    else:
        lvl = "ERROR"
    log(lvl, req["action"], unit=unit, peer_uid=uid, peer_user=caller, status=status, info=info.replace(" ", "_")[:200])

def main():
    """Accept UNIX socket connections and service requests indefinitely."""
    listen_fds = int(os.environ.get("LISTEN_FDS", "0"))
    if listen_fds == 1 and 3 in (3,):
        sock = socket.socket(fileno=3)
    else:
        if os.path.exists(SOCK_PATH):
            os.unlink(SOCK_PATH)
        sock = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        sock.bind(SOCK_PATH)
        # trunk-ignore(bandit/B103)
        os.chmod(SOCK_PATH, 0o660) # group read/write is necessary
        try:
            os.chown(SOCK_PATH, 0, grp.getgrnam("zfshelper").gr_gid)
        except Exception as e:
            log("WARN", "failed to adjust socket ownership", err=f"{e.__class__.__name__}:{e}")
        sock.listen(16)
    while True:
        try:
            conn, _ = sock.accept()
            with conn:
                handle(conn)
        except KeyboardInterrupt:
            break
        except Exception as e:
            log("ERROR", f"server exception: {e.__class__.__name__}:{e}")
            time.sleep(0.05)

if __name__ == "__main__":
    main()
