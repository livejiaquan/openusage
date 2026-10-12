#!/usr/bin/env python3
"""Prepare an isolated stable-upstream merge, then publish a review-only PR."""
import argparse
import json
import os
import re
import subprocess
import tempfile
from pathlib import Path

UPSTREAM = "robinebers/openusage"
TAG = re.compile(r"v\d+\.\d+\.\d+\Z")
BRANCH = re.compile(r"[A-Za-z0-9][A-Za-z0-9._/-]*\Z")


def run(*args, cwd=None):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def gh_json(*args):
    return json.loads(run("gh", *args))


def upstream_url():
    return f"https://github.com/{UPSTREAM}.git"


def valid_branch(value):
    if not BRANCH.fullmatch(value) or ".." in value or "//" in value or value.endswith("/"):
        raise ValueError("Invalid target branch")
    return value


def dispatch_ci(repository, branch, head):
    runs = gh_json("run", "list", "--repo", repository, "--branch", branch,
                   "--workflow", "remote-usage-build.yml", "--limit", "20", "--json", "headSha")
    if not any(item["headSha"] == head for item in runs):
        run("gh", "workflow", "run", "remote-usage-build.yml", "--repo", repository, "--ref", branch)


def existing_pr(repository, target, branch):
    candidates = gh_json("pr", "list", "--repo", repository, "--base", target,
                         "--head", branch, "--state", "all", "--limit", "100", "--json",
                         "url,headRefOid,isCrossRepository,state")
    # --head filters branch names, not owner:branch. An external fork may use the same name.
    owned = [item for item in candidates if item.get("isCrossRepository") is False]
    return next((item for item in owned if item.get("state") == "OPEN"), owned[0] if owned else None)


def prepare(product, repository, target):
    valid_branch(target)
    release = gh_json("api", f"repos/{UPSTREAM}/releases/latest")
    tag = release["tag_name"]
    if not TAG.fullmatch(tag) or release.get("draft") or release.get("prerelease"):
        raise ValueError("Only stable vX.Y.Z releases may be synchronized")
    branch = f"feat/ssh-upstream-{tag}"
    existing = existing_pr(repository, target, branch)
    if existing:
        if existing["state"] == "OPEN":
            dispatch_ci(repository, branch, existing["headRefOid"])
        return {"needs_sync": "false", "tag": tag, "branch": branch, "pr": existing["url"], "state": existing["state"]}
    target_head = run("git", "rev-parse", "--verify", f"refs/heads/{target}", cwd=product)
    if run("git", "rev-parse", "HEAD", cwd=product) != target_head:
        raise ValueError("Checkout is not at the product branch head")
    if run("git", "status", "--porcelain", cwd=product):
        raise ValueError("Refusing to merge into a dirty checkout")
    # Pin an exact official release ref; never merge the upstream development branch.
    run("git", "fetch", "--no-tags", upstream_url(), f"refs/tags/{tag}", cwd=product)
    commit = run("git", "rev-parse", "FETCH_HEAD^{commit}", cwd=product)
    already = subprocess.run(["git", "merge-base", "--is-ancestor", commit, "HEAD"], cwd=product)
    if already.returncode == 0:
        return {"needs_sync": "false", "tag": tag, "branch": branch}
    if already.returncode != 1:
        raise RuntimeError("Could not determine upstream ancestry")
    run("git", "switch", "-c", branch, cwd=product)
    run("git", "config", "user.name", "github-actions[bot]", cwd=product)
    run("git", "config", "user.email", "41898282+github-actions[bot]@users.noreply.github.com", cwd=product)
    # Any conflict fails before a push. No ours/theirs strategy or force push is permitted.
    run("git", "merge", "--no-ff", commit, "-m", f"Merge official {tag} into SSH fork", cwd=product)
    run("git", "diff", "--check", "HEAD^1", "HEAD", cwd=product)
    return {"needs_sync": "true", "tag": tag, "branch": branch,
            "head": run("git", "rev-parse", "HEAD", cwd=product)}


def publish(product, repository, target, tag, branch):
    valid_branch(target)
    if not TAG.fullmatch(tag) or branch != f"feat/ssh-upstream-{tag}":
        raise ValueError("Unexpected publication branch or release tag")
    if run("git", "branch", "--show-current", cwd=product) != branch:
        raise ValueError("Checkout does not match the prepared sync branch")
    existing = existing_pr(repository, target, branch)
    if existing:
        if existing["state"] == "OPEN":
            dispatch_ci(repository, branch, existing["headRefOid"])
        return existing["url"]
    # checkout uses persist-credentials:false; authenticate only for this push/publication step.
    run("gh", "auth", "setup-git", cwd=product)
    remote = run("git", "ls-remote", "--heads", "origin", f"refs/heads/{branch}", cwd=product)
    if remote:
        # A previous attempt may have pushed but failed to create its PR. Reuse only an equivalent
        # merge containing both the current product base and exact upstream parent; never overwrite.
        run("git", "fetch", "origin", f"refs/heads/{branch}", cwd=product)
        head = run("git", "rev-parse", "FETCH_HEAD", cwd=product)
        run("git", "diff", "--exit-code", head, "HEAD", cwd=product)
        run("git", "merge-base", "--is-ancestor", target, head, cwd=product)
        upstream_parent = run("git", "rev-parse", "HEAD^2", cwd=product)
        run("git", "merge-base", "--is-ancestor", upstream_parent, head, cwd=product)
    else:
        run("git", "push", "origin", f"HEAD:refs/heads/{branch}", cwd=product)
        head = run("git", "rev-parse", "HEAD", cwd=product)
    body = f"""## TL;DR
Integrate official {tag} into the SSH product branch. Keep fork changes and require review before merging.

## What was happening
The product branch did not contain official stable release {tag}.

## What this changes
- Merge the exact official release tag; do not rebase or force overwrite published work.
- Preserve SSH feature commits. Source SHA: `{head}`.
- Automatically dispatch the SSH test/build workflow for this SHA; no release or installation is performed.

## Heads-up
Review SSH, account-history ownership and any GUI changes before merging. A clean Git merge does not prove behavioral compatibility. This automation never approves or merges a PR.

## Tests
CI is dispatched after PR creation. Its result must be checked before merging.
"""
    with tempfile.TemporaryDirectory(prefix="upstream-pr-") as temporary:
        path = Path(temporary) / "body.md"
        path.write_text(body)
        url = run("gh", "pr", "create", "--repo", repository, "--base", target, "--head", branch,
                  "--title", f"Sync official {tag} into SSH fork", "--body-file", str(path), cwd=product)
    # GITHUB_TOKEN pushes/PRs do not trigger CI; explicitly dispatch to the actual sync ref.
    dispatch_ci(repository, branch, head)
    return url


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=["prepare", "publish"])
    parser.add_argument("--product", required=True)
    parser.add_argument("--repository", required=True)
    parser.add_argument("--target", required=True)
    parser.add_argument("--tag")
    parser.add_argument("--branch")
    args = parser.parse_args()
    product = str(Path(args.product).resolve())
    if args.mode == "prepare":
        result = prepare(product, args.repository, args.target)
        print(json.dumps(result))
        if os.environ.get("GITHUB_OUTPUT"):
            with open(os.environ["GITHUB_OUTPUT"], "a") as output:
                for key in ["needs_sync", "tag", "branch", "head"]:
                    if key in result:
                        output.write(f"{key}={result[key]}\n")
    else:
        if not args.tag or not args.branch:
            parser.error("publish requires --tag and --branch")
        print(publish(product, args.repository, args.target, args.tag, args.branch))


if __name__ == "__main__":
    main()
