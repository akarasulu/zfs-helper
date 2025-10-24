#!/usr/bin/env python3
"""Synchronize ZFS delegated permissions with zfs-helper policy."""

from __future__ import annotations

import argparse
import importlib.util
import subprocess
import sys
from collections import defaultdict
from pathlib import Path
from typing import Dict, List, Optional, Set, Tuple


def load_helper_module() -> object:
    repo_root = Path(__file__).resolve().parent
    helper_path = repo_root / "zfs-helper.py"
    spec = importlib.util.spec_from_file_location("zfs_helper", helper_path)
    if spec is None or spec.loader is None:
        raise RuntimeError(f"Unable to load helper module at {helper_path}")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run_zfs(zfs_bin: str, args: List[str]) -> Tuple[int, str, str]:
    proc = subprocess.run([zfs_bin] + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    return proc.returncode, proc.stdout.strip(), proc.stderr.strip()


def list_datasets(zfs_bin: str) -> List[str]:
    rc, out, err = run_zfs(zfs_bin, ["list", "-H", "-o", "name", "-t", "filesystem,volume"])
    if rc != 0:
        raise RuntimeError(f"zfs list failed: {err or f'rc={rc}'}")
    datasets = [line.strip() for line in out.splitlines() if line.strip()]
    return datasets


def pattern_prefix(pattern: str, existing: Set[str]) -> Optional[str]:
    parts = pattern.split("/")
    prefix_parts: List[str] = []
    for part in parts:
        if part in {"**"} or any(ch in part for ch in "*?[]"):
            break
        prefix_parts.append(part)
    while prefix_parts:
        candidate = "/".join(prefix_parts)
        if candidate in existing:
            return candidate
        prefix_parts.pop()
    return None


def expand_pattern_targets(helper: object, pattern: str, datasets: List[str], dataset_set: Set[str]) -> Set[str]:
    matches = {ds for ds in datasets if helper.dataset_glob_match(pattern, ds)}
    prefix = pattern_prefix(pattern, dataset_set)
    if prefix:
        matches.add(prefix)
    return matches


def parse_allow_output(output: str) -> Dict[str, Set[str]]:
    grants: Dict[str, Set[str]] = defaultdict(set)
    for raw in output.splitlines():
        line = raw.strip()
        if not line or not line.startswith("user "):
            continue
        parts = line.split(None, 2)
        if len(parts) < 3:
            continue
        _, principal, perms = parts
        for perm in perms.replace(",", " ").split():
            perm = perm.strip().rstrip(",")
            if perm:
                grants[principal].add(perm)
    return grants


def get_current_permissions(zfs_bin: str, dataset: str) -> Dict[str, Set[str]]:
    rc, out, err = run_zfs(zfs_bin, ["allow", "-l", dataset])
    if rc != 0:
        return {}
    return parse_allow_output(out)


def grant_permissions(zfs_bin: str, dataset: str, user: str, perms: Set[str], dry_run: bool) -> None:
    if not perms:
        return
    regular = sorted(p for p in perms if not p.startswith("property="))
    properties = sorted(p.split("=", 1)[1] for p in perms if p.startswith("property="))
    if regular:
        cmd = [zfs_bin, "allow", "-u", user, ",".join(regular), dataset]
        print(f"[grant] {' '.join(cmd)}")
        if not dry_run:
            rc, _, err = run_zfs(zfs_bin, cmd[1:])
            if rc != 0:
                print(f"  ! failed: {err or f'rc={rc}'}", file=sys.stderr)
    for prop in properties:
        cmd = [zfs_bin, "allow", "-u", user, f"property={prop}", dataset]
        print(f"[grant] {' '.join(cmd)}")
        if not dry_run:
            rc, _, err = run_zfs(zfs_bin, cmd[1:])
            if rc != 0:
                print(f"  ! failed: {err or f'rc={rc}'}", file=sys.stderr)


def revoke_permissions(zfs_bin: str, dataset: str, user: str, perms: Set[str], dry_run: bool) -> None:
    if not perms:
        return
    regular = sorted(p for p in perms if not p.startswith("property="))
    properties = sorted(p.split("=", 1)[1] for p in perms if p.startswith("property="))
    if regular:
        cmd = [zfs_bin, "unallow", "-u", user, ",".join(regular), dataset]
        print(f"[revoke] {' '.join(cmd)}")
        if not dry_run:
            rc, _, err = run_zfs(zfs_bin, cmd[1:])
            if rc != 0:
                print(f"  ! failed: {err or f'rc={rc}'}", file=sys.stderr)
    for prop in properties:
        cmd = [zfs_bin, "unallow", "-u", user, f"property={prop}", dataset]
        print(f"[revoke] {' '.join(cmd)}")
        if not dry_run:
            rc, _, err = run_zfs(zfs_bin, cmd[1:])
            if rc != 0:
                print(f"  ! failed: {err or f'rc={rc}'}", file=sys.stderr)


def build_desired_state(helper: object, datasets: List[str]) -> Dict[str, Dict[str, Set[str]]]:
    datasets_set = set(datasets)
    desired: Dict[str, Dict[str, Set[str]]] = defaultdict(lambda: defaultdict(set))
    policy_root = Path(helper.POLICY_ROOT)
    if not policy_root.is_dir():
        raise RuntimeError(f"Policy root {policy_root} not found")

    managed_actions = {
        "mount": {"mount"},
        "unmount": {"mount"},
        "snapshot": {"snapshot"},
        "rollback": {"rollback"},
        "destroy": {"destroy"},
        "rename_from": {"rename"},
    }

    property_keys_allowed = helper.PROP_KEY_ALLOW

    for entry in sorted(policy_root.iterdir()):
        if not entry.is_dir():
            continue
        user = entry.name
        policy = helper.load_policy(user)

        # dataset-bound actions
        for action, perms in managed_actions.items():
            for dataset in datasets:
                if helper.dataset_allowed(policy, action, user, dataset):
                    desired[dataset][user].update(perms)

        # property permissions
        setprop_entries = helper.list_allows(policy, "setprop")
        if setprop_entries:
            value_rules = helper.parse_setprop_values(helper.list_allows(policy, "setprop.values"))
            if value_rules:
                keys = {rule[0] for rule in value_rules if rule[0]}
                prop_keys = (keys & property_keys_allowed) or property_keys_allowed
            else:
                prop_keys = property_keys_allowed
            for dataset in datasets:
                if helper.dataset_allowed(policy, "setprop", user, dataset):
                    for key in prop_keys:
                        desired[dataset][user].add(f"property={key}")

        # create / rename_to (parent-focused permissions)
        for action, perm in (("create", "create"), ("rename_to", "rename"), ("share", "share")):
            for actor, pattern in helper.list_allows(policy, action):
                if actor not in (user, "*"):
                    continue
                targets = expand_pattern_targets(helper, pattern, datasets, datasets_set)
                if not targets:
                    continue
                for target in targets:
                    desired[target][user].add(perm)

    return desired


def apply_desired_state(helper: object, desired: Dict[str, Dict[str, Set[str]]], zfs_bin: str, dry_run: bool) -> None:
    managed_perms = {
        "mount",
        "snapshot",
        "rollback",
        "create",
        "destroy",
        "rename",
        "share",
    } | {f"property={k}" for k in helper.PROP_KEY_ALLOW}

    for dataset, users in sorted(desired.items()):
        current = get_current_permissions(zfs_bin, dataset)
        # additions & updates
        for user, perms in users.items():
            current_perms = current.get(user, set())
            to_add = perms - current_perms
            to_remove = (current_perms & managed_perms) - perms
            if to_add:
                grant_permissions(zfs_bin, dataset, user, to_add, dry_run)
                current_perms.update(to_add)
            if to_remove:
                revoke_permissions(zfs_bin, dataset, user, to_remove, dry_run)
                current_perms -= to_remove
            current[user] = current_perms
        # removals for principals no longer desired
        for user, current_perms in list(current.items()):
            if user in users:
                continue
            to_remove = current_perms & managed_perms
            if to_remove:
                revoke_permissions(zfs_bin, dataset, user, to_remove, dry_run)


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Apply ZFS delegation to mirror zfs-helper policies.")
    parser.add_argument("--zfs-bin", default="/usr/sbin/zfs", help="Path to zfs binary (default: /usr/sbin/zfs)")
    parser.add_argument("--dry-run", action="store_true", help="Preview changes without executing zfs allow/unallow")
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    helper = load_helper_module()
    try:
        datasets = list_datasets(args.zfs_bin)
    except RuntimeError as exc:
        print(f"error: {exc}", file=sys.stderr)
        sys.exit(1)
    desired = build_desired_state(helper, datasets)
    apply_desired_state(helper, desired, args.zfs_bin, args.dry_run)


if __name__ == "__main__":
    main()
