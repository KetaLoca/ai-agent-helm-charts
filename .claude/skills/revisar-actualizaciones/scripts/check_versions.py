#!/usr/bin/env python3
"""Compare the upstream versions we pin in the charts against the latest releases.

Deterministic plumbing for the `revisar-actualizaciones` skill: it reads what each
chart currently pins (from Chart.yaml), resolves the latest *stable* upstream version
from the real source of truth (GitHub Releases / the OCI registry), and reports the
delta. It does NOT read changelogs or judge breaking changes -- that is the model's
job (see SKILL.md). Pure Python stdlib, no third-party deps.

Usage:
    check_versions.py [--json] [--digests] [--manifest PATH] [--repo-root PATH]

Exit code: 0 if everything is pinned and up to date, 1 if any component is outdated,
unpinned, or has a pinned digest that drifted from its appVersion (handy for CI). 2 on
a hard error.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request

UA = "revisar-actualizaciones/1.0 (+claude-code skill)"
TIMEOUT = 30

# Tags that are clearly not a stable release line.
_PRERELEASE = re.compile(r"-(?:alpha|beta|rc|pre|dev|next|snapshot)", re.I)
# A plain numeric, dotted version with an optional leading 'v' (used to keep OCI tag
# lists clean of signatures like sha256-..., '.sig', 'artifacthub.io', arch suffixes).
_PURE_VERSION = re.compile(r"^v?\d+(?:\.\d+)*$")


# --------------------------------------------------------------------------- utils
def warn(msg: str) -> None:
    print(f"warning: {msg}", file=sys.stderr)


def find_repo_root(explicit: str | None) -> str:
    if explicit:
        return os.path.abspath(explicit)
    try:
        out = subprocess.run(
            ["git", "rev-parse", "--show-toplevel"],
            capture_output=True, text=True, timeout=10,
        )
        if out.returncode == 0 and out.stdout.strip():
            return out.stdout.strip()
    except Exception:
        pass
    # Walk up looking for a charts/ dir.
    cur = os.getcwd()
    while True:
        if os.path.isdir(os.path.join(cur, "charts")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.getcwd()
        cur = parent


def normalize(v: str | None) -> str:
    return (v or "").strip().lstrip("vV")


def version_key(tag: str) -> tuple:
    """Sortable key for calver/semver tags: tuple of the leading numeric run."""
    nums = re.findall(r"\d+", normalize(tag).split("-")[0])
    return tuple(int(n) for n in nums) if nums else (0,)


def is_stable(tag: str) -> bool:
    return not _PRERELEASE.search(tag or "")


# ----------------------------------------------------------------- local: Chart.yaml
def read_top_scalar(text: str, field: str) -> str | None:
    """Read a top-level (column-0) YAML scalar, ignoring comments/quotes."""
    pat = re.compile(rf"^{re.escape(field)}:\s*(.+?)\s*$")
    for line in text.splitlines():
        m = pat.match(line)
        if m:
            val = m.group(1)
            val = re.sub(r"\s+#.*$", "", val).strip()  # strip trailing comment
            return val.strip("\"'")
    return None


def read_nested_scalar(text: str, parent: str, child: str) -> str | None:
    """Read a `child:` scalar under a top-level `parent:` mapping (2 levels, indent-based).

    Used to read e.g. `image.digest` from values.yaml.
    """
    in_parent = False
    pat_parent = re.compile(rf"^{re.escape(parent)}:\s*$")
    pat_child = re.compile(rf"^\s+{re.escape(child)}:\s*(.+?)\s*$")
    for line in text.splitlines():
        if pat_parent.match(line):
            in_parent = True
            continue
        if in_parent:
            if re.match(r"^\S", line):  # back to column 0 -> left the parent block
                break
            m = pat_child.match(line)
            if m:
                val = re.sub(r"\s+#.*$", "", m.group(1)).strip().strip("\"'")
                return val or None
    return None


def read_dependency_version(text: str, dep_name: str) -> str | None:
    """Read dependencies[].version for the entry whose name == dep_name."""
    lines = text.splitlines()
    in_deps = False
    target = False
    for line in lines:
        if re.match(r"^dependencies:\s*$", line):
            in_deps = True
            continue
        if not in_deps:
            continue
        # A new column-0 key (not a list item) ends the dependencies block.
        if re.match(r"^\S", line) and not re.match(r"^\s*-", line) and ":" in line:
            break
        if re.search(r"(?:^|\s|-)\s*name:\s*", line):
            name = re.sub(r".*name:\s*", "", line).strip().strip("\"'")
            target = name == dep_name
        if target:
            m = re.search(r"(?:^|\s|-)\s*version:\s*(.+?)\s*$", line)
            if m:
                return m.group(1).strip().strip("\"'")
    return None


def read_current(repo_root: str, comp: dict) -> str | None:
    cur = comp["current"]
    path = os.path.join(repo_root, cur["file"])
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        warn(f"{comp['id']}: cannot read {path}: {exc}")
        return None
    if "dependency" in cur:
        return read_dependency_version(text, cur["dependency"])
    return read_top_scalar(text, cur["field"])


def read_digest_pin(repo_root: str, comp: dict) -> str | None:
    """Read the digest the chart pins (e.g. values.yaml image.digest), if declared."""
    dp = comp.get("digest_pin")
    if not dp:
        return None
    path = os.path.join(repo_root, dp["file"])
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError as exc:
        warn(f"{comp['id']}: cannot read {path}: {exc}")
        return None
    key = dp["key"]
    if "." in key:
        parent, child = key.split(".", 1)
        return read_nested_scalar(text, parent, child)
    return read_top_scalar(text, key)


def read_chart_version(repo_root: str, comp: dict) -> str | None:
    path = os.path.join(repo_root, "charts", comp["chart"], "Chart.yaml")
    try:
        with open(path, encoding="utf-8") as fh:
            return read_top_scalar(fh.read(), "version")
    except OSError:
        return None


# ------------------------------------------------------------------- http helpers
def http_json(url: str, headers: dict | None = None):
    req = urllib.request.Request(url, headers={"User-Agent": UA, **(headers or {})})
    with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
        return json.load(resp), resp.headers


def http_head_digest(url: str, headers: dict) -> str | None:
    req = urllib.request.Request(
        url, headers={"User-Agent": UA, **headers}, method="GET"
    )
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.headers.get("Docker-Content-Digest")
    except urllib.error.HTTPError as exc:
        return exc.headers.get("Docker-Content-Digest")


# ----------------------------------------------------------------- latest: GitHub
def github_releases(repo: str) -> list[dict]:
    """All releases (most-recent first). Uses authenticated `gh` if available."""
    path = f"repos/{repo}/releases?per_page=100"
    try:
        out = subprocess.run(
            ["gh", "api", "-H", "Accept: application/vnd.github+json", path],
            capture_output=True, text=True, timeout=TIMEOUT,
        )
        if out.returncode == 0:
            return json.loads(out.stdout)
        tail = (out.stderr.strip().splitlines() or [""])[-1]
        warn(f"gh api failed for {repo}: {tail}")
    except FileNotFoundError:
        pass  # gh not installed -> fall through to anonymous API
    except Exception as exc:
        warn(f"gh api error for {repo}: {exc}")
    try:
        data, _ = http_json(
            f"https://api.github.com/{path}",
            {"Accept": "application/vnd.github+json"},
        )
        return data
    except Exception as exc:
        warn(f"GitHub API error for {repo}: {exc}")
        return []


def latest_from_github(repo: str, current: str):
    rels = [r for r in github_releases(repo)
            if not r.get("draft") and not r.get("prerelease")
            and is_stable(r.get("tag_name", ""))]
    if not rels:
        return None, []
    rels.sort(key=lambda r: version_key(r.get("tag_name", "")), reverse=True)
    latest = rels[0]["tag_name"]
    cn = version_key(current) if current else None
    newer = [
        {
            "tag": r.get("tag_name"),
            "name": r.get("name") or r.get("tag_name"),
            "date": (r.get("published_at") or "")[:10],
            "url": r.get("html_url"),
        }
        for r in rels
        if cn is None or version_key(r.get("tag_name", "")) > cn
    ]
    return latest, newer


# ------------------------------------------------------------------- latest: GHCR
def ghcr_token(repo: str) -> str | None:
    try:
        data, _ = http_json(f"https://ghcr.io/token?scope=repository:{repo}:pull")
        return data.get("token")
    except Exception as exc:
        warn(f"GHCR token error for {repo}: {exc}")
        return None


def ghcr_tags(repo: str) -> list[str]:
    """All tags for an OCI repo, following Link-header pagination (GHCR truncates!)."""
    token = ghcr_token(repo)
    if not token:
        return []
    headers = {"Authorization": f"Bearer {token}", "Accept": "application/json"}
    url = f"https://ghcr.io/v2/{repo}/tags/list?n=100"
    tags: list[str] = []
    seen = 0
    while url and seen < 100:  # safety bound on pages
        seen += 1
        try:
            data, hdrs = http_json(url, headers)
        except Exception as exc:
            warn(f"GHCR tags error for {repo}: {exc}")
            break
        tags.extend(data.get("tags") or [])
        link = hdrs.get("Link", "")
        m = re.search(r'<([^>]+)>\s*;\s*rel="next"', link)
        url = ("https://ghcr.io" + m.group(1)) if m else None
    return tags


def latest_from_ghcr_tags(repo: str, current: str):
    tags = [t for t in ghcr_tags(repo) if _PURE_VERSION.match(t) and is_stable(t)]
    if not tags:
        return None, []
    tags.sort(key=version_key, reverse=True)
    latest = tags[0]
    cn = version_key(current) if current else None
    newer = [{"tag": t} for t in tags if cn is None or version_key(t) > cn]
    return latest, newer


# ---------------------------------------------------------------------- digests
def resolve_digest(image: dict, tag: str) -> str | None:
    repo = image["repo"]
    reg = image["registry"]
    if reg == "dockerhub":
        try:
            data, _ = http_json(
                f"https://hub.docker.com/v2/repositories/{repo}/tags/{tag}"
            )
            return data.get("digest")
        except Exception as exc:
            warn(f"dockerhub digest error for {repo}:{tag}: {exc}")
            return None
    if reg == "ghcr":
        token = ghcr_token(repo)
        if not token:
            return None
        accept = ", ".join([
            "application/vnd.oci.image.index.v1+json",
            "application/vnd.docker.distribution.manifest.list.v2+json",
            "application/vnd.oci.image.manifest.v1+json",
            "application/vnd.docker.distribution.manifest.v2+json",
        ])
        return http_head_digest(
            f"https://ghcr.io/v2/{repo}/manifests/{tag}",
            {"Authorization": f"Bearer {token}", "Accept": accept},
        )
    return None


# ------------------------------------------------------------------------- core
def resolve_latest(comp: dict, current: str):
    method = comp["latest"]["method"]
    repo = comp["latest"]["repo"]
    if method == "github-release":
        return latest_from_github(repo, current)
    if method == "ghcr-tags":
        return latest_from_ghcr_tags(repo, current)
    warn(f"{comp['id']}: unknown latest.method '{method}'")
    return None, []


def evaluate(comp: dict, repo_root: str, want_digests: bool) -> dict:
    current = read_current(repo_root, comp)
    chart_version = read_chart_version(repo_root, comp)
    pinned = bool(current) and current.lower() not in {"latest", "main", "stable", ""}
    latest, newer = resolve_latest(comp, current if pinned else "")

    if latest is None:
        status = "unknown"
    elif not pinned:
        status = "unpinned"
    elif normalize(current) == normalize(latest):
        status = "up-to-date"
    else:
        status = "outdated"

    row = {
        "id": comp["id"],
        "title": comp["title"],
        "chart": comp["chart"],
        "chart_version": chart_version,
        "kind": comp["kind"],
        "current": current,
        "latest": latest,
        "status": status,
        "pinned": pinned,
        "outdated": status in {"outdated", "unpinned"},
        "digest_drift": False,
        "version_scheme": comp.get("version_scheme"),
        "changelog": comp.get("changelog"),
        "notes": comp.get("notes"),
        "newer_releases": newer[:15],
        "newer_count": len(newer),
    }
    if "image" in comp:
        img = comp["image"]
        tag = latest
        if tag and img.get("strip_v"):
            tag = normalize(tag)
        row["image"] = {"registry": img["registry"], "repo": img["repo"], "latest_tag": tag}
        if want_digests and tag and status in {"outdated", "unpinned"}:
            row["image"]["digest"] = resolve_digest(img, tag)
        # Verify a pinned digest (e.g. values.yaml image.digest) matches the digest of
        # the CURRENT appVersion. Catches a digest left stale after an appVersion bump.
        if want_digests and comp.get("digest_pin"):
            pinned_digest = read_digest_pin(repo_root, comp)
            cur_tag = current
            if cur_tag and img.get("strip_v"):
                cur_tag = normalize(cur_tag)
            expected = resolve_digest(img, cur_tag) if (pinned and cur_tag) else None
            ok = bool(pinned_digest) and bool(expected) and pinned_digest == expected
            row["image"]["pinned_digest"] = pinned_digest
            row["image"]["expected_digest"] = expected
            row["image"]["digest_ok"] = ok
            if expected is not None and not ok:
                row["digest_drift"] = True
    return row


# ----------------------------------------------------------------------- output
def print_table(rows: list[dict]) -> None:
    icon = {"up-to-date": "OK ", "outdated": "OUT", "unpinned": "PIN", "unknown": "??? "}
    w_title = max((len(r["title"]) for r in rows), default=10)
    w_cur = max((len(str(r["current"])) for r in rows), default=7)
    w_lat = max((len(str(r["latest"])) for r in rows), default=7)
    hdr = f"  {'COMPONENT':<{w_title}}  {'CURRENT':<{w_cur}}  {'LATEST':<{w_lat}}  STATUS"
    print(hdr)
    print("  " + "-" * (len(hdr) - 2))
    for r in rows:
        print(
            f"  {r['title']:<{w_title}}  {str(r['current']):<{w_cur}}  "
            f"{str(r['latest']):<{w_lat}}  {icon.get(r['status'], r['status'])}"
            + (f"  (+{r['newer_count']} releases)" if r["newer_count"] else "")
        )
    print()
    print("  Legend: OK up-to-date · OUT outdated · PIN unpinned (floating tag) · ??? could not resolve")
    flagged = [r for r in rows if r["outdated"] or r.get("digest_drift")]
    if flagged:
        print("\n  Next: read the changelog for each flagged component before bumping:")
        for r in flagged:
            img = r.get("image", {})
            if r["outdated"]:
                print(f"    - {r['title']}: {r['current']} -> {r['latest']}  {r['changelog']}")
                digest = img.get("digest")
                if digest:
                    print(f"        new digest (pin with the bump): {digest}")
            if r.get("digest_drift"):
                print(f"    - {r['title']}: pinned digest does NOT match {r['current']} (drift)")
                print(f"        values.yaml: {img.get('pinned_digest')}")
                print(f"        expected:    {img.get('expected_digest')}")
    else:
        print("\n  All tracked components are pinned and current.")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", action="store_true", help="emit structured JSON")
    ap.add_argument("--digests", action="store_true", help="resolve image digests for flagged components")
    ap.add_argument("--manifest", help="path to sources.json (default: alongside this script)")
    ap.add_argument("--repo-root", help="repo root (default: git toplevel)")
    args = ap.parse_args()

    manifest = args.manifest or os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "sources.json")
    try:
        with open(manifest, encoding="utf-8") as fh:
            components = json.load(fh)["components"]
    except (OSError, KeyError, json.JSONDecodeError) as exc:
        print(f"error: cannot load manifest {manifest}: {exc}", file=sys.stderr)
        return 2

    repo_root = find_repo_root(args.repo_root)
    rows = [evaluate(c, repo_root, args.digests) for c in components]

    if args.json:
        summary = {
            "outdated": sum(r["status"] == "outdated" for r in rows),
            "unpinned": sum(r["status"] == "unpinned" for r in rows),
            "up_to_date": sum(r["status"] == "up-to-date" for r in rows),
            "unknown": sum(r["status"] == "unknown" for r in rows),
            "digest_drift": sum(bool(r.get("digest_drift")) for r in rows),
        }
        print(json.dumps({"repo_root": repo_root, "summary": summary, "components": rows}, indent=2))
    else:
        print_table(rows)

    return 1 if any(r["outdated"] or r.get("digest_drift") for r in rows) else 0


if __name__ == "__main__":
    sys.exit(main())
