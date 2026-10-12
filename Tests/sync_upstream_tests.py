import importlib.util
import json
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

spec = importlib.util.spec_from_file_location("sync_upstream", Path(__file__).resolve().parents[1] / "script/sync_upstream.py")
sync = importlib.util.module_from_spec(spec)
spec.loader.exec_module(sync)


class UpstreamSyncTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.upstream = Path(self.temp.name) / "upstream"
        self.product = Path(self.temp.name) / "product"
        self.upstream.mkdir()
        self.git(self.upstream, "init", "-b", "main")
        self.git(self.upstream, "config", "user.name", "Test")
        self.git(self.upstream, "config", "user.email", "test@example.invalid")
        (self.upstream / "base.txt").write_text("base\n")
        self.commit(self.upstream, "base")
        sync.run("git", "clone", str(self.upstream), str(self.product))
        self.git(self.product, "config", "user.name", "Test")
        self.git(self.product, "config", "user.email", "test@example.invalid")
        self.git(self.product, "switch", "-c", "ssh-product")
        (self.product / "ssh.txt").write_text("keep ssh\n")
        self.commit(self.product, "SSH feature")
        self.target_head = self.git(self.product, "rev-parse", "HEAD")
        (self.upstream / "official.txt").write_text("official update\n")
        self.commit(self.upstream, "official update")
        self.git(self.upstream, "tag", "v0.7.14")

    def git(self, directory, *args):
        return sync.run("git", *args, cwd=str(directory))

    def commit(self, directory, message):
        self.git(directory, "add", ".")
        self.git(directory, "commit", "-m", message)

    def prepare(self, release=None, existing=None):
        values = [release or {"tag_name": "v0.7.14", "prerelease": False}, existing or []]
        if existing: values.append([{"headSha": existing[0]["headRefOid"]}])
        with patch.object(sync, "gh_json", side_effect=values), patch.object(sync, "upstream_url", return_value=str(self.upstream)):
            return sync.prepare(str(self.product), "owner/fork", "ssh-product")

    def testNewReleaseKeepsSSHAndTargetBranchUnchanged(self):
        result = self.prepare()
        self.assertEqual(result["needs_sync"], "true")
        self.assertEqual((self.product / "ssh.txt").read_text(), "keep ssh\n")
        self.assertEqual((self.product / "official.txt").read_text(), "official update\n")
        self.assertEqual(self.git(self.product, "rev-parse", "ssh-product"), self.target_head)
        self.git(self.product, "merge-base", "--is-ancestor", "FETCH_HEAD", "HEAD")

    def testAlreadyIntegratedReleaseIsANoOp(self):
        result = self.prepare()
        self.git(self.product, "switch", "ssh-product")
        self.git(self.product, "merge", "--ff-only", result["branch"])
        self.assertEqual(self.prepare()["needs_sync"], "false")

    def testExistingPRIsReusedWithoutMutatingGit(self):
        result = self.prepare(existing=[{"url": "https://github.com/owner/fork/pull/1", "headRefOid": "same"}])
        self.assertEqual(result["needs_sync"], "false")
        self.assertEqual(self.git(self.product, "rev-parse", "HEAD"), self.target_head)

    def testConflictStopsBeforeChangingProductBranch(self):
        (self.product / "base.txt").write_text("SSH-specific change\n")
        self.commit(self.product, "fork edits")
        target = self.git(self.product, "rev-parse", "HEAD")
        (self.upstream / "base.txt").write_text("conflicting official change\n")
        self.commit(self.upstream, "official conflict")
        self.git(self.upstream, "tag", "-f", "v0.7.14")
        with self.assertRaises(subprocess.CalledProcessError):
            self.prepare()
        self.assertEqual(self.git(self.product, "rev-parse", "ssh-product"), target)
        self.assertTrue(self.git(self.product, "diff", "--name-only", "--diff-filter=U"))

    def testPrereleaseOrMalformedTagIsRejectedBeforeGitChanges(self):
        for tag in ["v0.7.15-beta.1", "v0.7.14\nneeds_sync=true", "--upload-pack=evil", "main"]:
            with self.subTest(tag=tag), self.assertRaises(ValueError):
                self.prepare(release={"tag_name": tag})
        self.assertEqual(self.git(self.product, "rev-parse", "HEAD"), self.target_head)

    def testWrongCheckoutCannotProduceASyncWithoutTheProductFeatures(self):
        self.git(self.product, "switch", "main")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual(self.git(self.product, "rev-parse", "ssh-product"), self.target_head)

    def testDirtyCheckoutIsRejected(self):
        (self.product / "uncommitted.txt").write_text("unfinished work")
        with self.assertRaises(ValueError):
            self.prepare()
        self.assertEqual(self.git(self.product, "rev-parse", "HEAD"), self.target_head)

    def testExistingPRPublishDoesNotPushOrDispatch(self):
        branch = "feat/ssh-upstream-v0.7.14"
        self.git(self.product, "switch", "-c", branch)
        with patch.object(sync, "gh_json", side_effect=[[{"url": "https://github.com/owner/fork/pull/1", "headRefOid": "same"}], [{"headSha": "same"}]]), patch.object(sync, "run", wraps=sync.run) as commands:
            self.assertIn("/pull/1", sync.publish(str(self.product), "owner/fork", "ssh-product", "v0.7.14", branch))
            self.assertEqual(commands.call_count, 1) # local branch verification only


    def testRetryOfExistingPRDispatchesMissingCIWithoutGitMutation(self):
        values = [{"tag_name": "v0.7.14"}, [{"url": "https://github.com/owner/fork/pull/1", "headRefOid": "same"}], []]
        with patch.object(sync, "gh_json", side_effect=values), patch.object(sync, "run") as commands:
            result = sync.prepare(str(self.product), "owner/fork", "ssh-product")
            self.assertEqual(result["needs_sync"], "false")
            commands.assert_called_once_with("gh", "workflow", "run", "remote-usage-build.yml", "--repo", "owner/fork", "--ref", "feat/ssh-upstream-v0.7.14")

    def testRetryReusesAnEquivalentOrphanBranchWithoutForcePushing(self):
        result = self.prepare()
        self.git(self.product, "push", "origin", "HEAD:refs/heads/" + result["branch"])
        remote_sha = self.git(self.product, "rev-parse", "HEAD")
        self.git(self.product, "commit", "--amend", "--no-edit", "--date=2025-01-01T00:00:00Z")
        self.assertNotEqual(self.git(self.product, "rev-parse", "HEAD"), remote_sha)
        real_run = sync.run
        def command(*args, **kwargs):
            if args[:3] == ("gh", "auth", "setup-git"): return ""
            if args[:3] == ("gh", "pr", "create"): return "https://github.com/owner/fork/pull/2"
            return real_run(*args, **kwargs)
        with patch.object(sync, "gh_json", side_effect=[[], [{"headSha": remote_sha}]]), patch.object(sync, "run", side_effect=command):
            url = sync.publish(str(self.product), "owner/fork", "ssh-product", result["tag"], result["branch"])
        self.assertIn("/pull/2", url)
        self.assertIn(remote_sha, self.git(self.product, "ls-remote", "--heads", "origin", "refs/heads/" + result["branch"]))


if __name__ == "__main__":
    unittest.main()
