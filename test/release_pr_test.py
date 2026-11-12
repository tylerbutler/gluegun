"""Release mode checks with no GitHub writes, tags, or publication."""

import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import tomllib
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "release_pr", ROOT / "scripts" / "release_pr.py",
)
release_pr = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_pr)
COMMAND = ["trellis", "release", "pr", "--base", "main", "--branch", "release/pending"]


class ReleasePreparationTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.previous = Path.cwd()
        os.chdir(self.directory.name)
        self.addCleanup(self.directory.cleanup)
        self.addCleanup(os.chdir, self.previous)
        Path("gleam.toml").write_text('name = "gluegun"\nversion = "0.2.0"\n')
        self.run = self.enterContext(patch.object(release_pr.subprocess, "run"))

    def current(self, version):
        Path("gleam.toml").write_text(f'name = "gluegun"\nversion = "{version}"\n')

    def result(self, stdout="", returncode=0):
        return subprocess.CompletedProcess([], returncode, stdout=stdout)

    def pending(self, version):
        self.run.side_effect = [
            self.result(json.dumps([{"headRefOid": "candidate", "isCrossRepository": False}])),
            self.result(f'name = "gluegun"\nversion = "{version}"\n'),
            self.result(),
        ]

    def assert_release(self, *args):
        self.assertEqual(self.run.call_args.args[0], COMMAND + list(args))
        self.assertEqual(self.run.call_args.kwargs, {"check": True})

    def test_manual_first_candidate(self):
        self.assertTrue(release_pr.prepare("workflow_dispatch", " rc ", " 1.0.0 "))
        self.assert_release("--pre", "rc", "--set", "gluegun=1.0.0")
        self.assertEqual(self.run.call_count, 1)

    def test_manual_next_candidate_and_promotion(self):
        self.current("1.0.0-rc.0")
        for pre in ("rc", "none"):
            with self.subTest(pre=pre):
                release_pr.prepare("workflow_dispatch", pre)
                self.assert_release("--pre", pre)

    def test_manual_stable_target(self):
        release_pr.prepare("workflow_dispatch", version="1.0.0")
        self.assert_release("--set", "gluegun=1.0.0")

    def test_pending_candidate_mode_survives_push(self):
        self.pending("1.0.0-rc.0")
        release_pr.prepare("push")
        self.assert_release("--pre", "rc", "--set", "gluegun=1.0.0")

    def test_pending_promotion_survives_push(self):
        self.current("1.0.0-rc.1")
        self.pending("1.0.0")
        release_pr.prepare("push")
        self.assert_release("--pre", "none")

    def test_pending_stable_target_survives_push(self):
        self.pending("0.3.0")
        release_pr.prepare("push")
        self.assert_release("--set", "gluegun=0.3.0")

    def test_new_candidate_fragments_continue_cycle(self):
        self.current("1.0.0-rc.0")
        self.run.side_effect = [
            self.result("[]"), self.result("version-commit"), self.result(returncode=1),
            self.result(),
        ]
        release_pr.prepare("push")
        self.assert_release("--pre", "rc")
        self.assertEqual(self.run.call_args_list[2].args[0], [
            "git", "diff", "--quiet", "version-commit", "HEAD", "--",
            ":(glob).changes/unreleased/*.toml",
        ])

    def test_unchanged_candidate_does_not_prepare(self):
        self.current("1.0.0-rc.0")
        self.run.side_effect = [
            self.result("[]"), self.result("version-commit"), self.result(),
        ]
        self.assertFalse(release_pr.prepare("push"))
        self.assertEqual(self.run.call_count, 3)

    def test_normal_stable_push(self):
        self.run.side_effect = [self.result("[]"), self.result()]
        release_pr.prepare("push")
        self.assert_release()

    def test_fork_release_pr_is_ignored(self):
        self.run.side_effect = [
            self.result(json.dumps([{"headRefOid": "fork", "isCrossRepository": True}])),
            self.result(),
        ]
        release_pr.prepare("push")
        self.assert_release()
        self.assertEqual(self.run.call_count, 2)

    def test_missing_baseline_fails(self):
        self.current("1.0.0-rc.0")
        self.run.side_effect = [self.result("[]"), self.result()]
        with self.assertRaisesRegex(RuntimeError, "version commit"):
            release_pr.prepare("push")

    def test_git_diff_error_fails(self):
        self.current("1.0.0-rc.0")
        self.run.side_effect = [
            self.result("[]"), self.result("version-commit"), self.result(returncode=128),
        ]
        with self.assertRaises(subprocess.CalledProcessError):
            release_pr.prepare("push")

    def test_github_and_trellis_errors_fail(self):
        for event in ("push", "workflow_dispatch"):
            with self.subTest(event=event):
                self.run.side_effect = subprocess.CalledProcessError(1, "command")
                with self.assertRaises(subprocess.CalledProcessError):
                    release_pr.prepare(event)

    def test_non_main_dispatch_fails_before_commands(self):
        with patch.dict(os.environ, {"GITHUB_REF": "refs/heads/feature"}):
            with self.assertRaisesRegex(SystemExit, "on main"):
                release_pr.main()
        self.run.assert_not_called()

    def test_main_dispatch_passes_inputs(self):
        with patch.dict(os.environ, {
            "GITHUB_REF": "refs/heads/main",
            "GITHUB_EVENT_NAME": "workflow_dispatch",
            "INPUT_PRE": "rc",
            "INPUT_VERSION": "1.0.0",
        }):
            release_pr.main()
        self.assert_release("--pre", "rc", "--set", "gluegun=1.0.0")

    def test_release_mode_with_build_metadata(self):
        self.assertEqual(release_pr.release_mode("1.0.0-rc.2+build.3"), ("1.0.0", "rc"))
        self.assertEqual(release_pr.release_mode("1.0.0+build.3"), ("1.0.0", ""))


class ReleasePolicyTests(unittest.TestCase):
    def test_hex_publication_requires_manual_tagged_run_after_checks(self):
        config = tomllib.loads((ROOT / "gleam.toml").read_text())
        self.assertEqual(config["tools"]["trellis"]["publish"]["lifecycle"], {
            "default": "hex",
        })
        workflow = (ROOT / ".github/workflows/publish.yml").read_text()
        self.assertIn("needs: [package, test]", workflow)
        self.assertIn(
            "if: github.event_name == 'workflow_dispatch' && "
            "needs.package.outputs.hex == 'true'", workflow,
        )
        self.assertIn('trellis publish --tag "$RELEASE_TAG"', workflow)
        self.assertIn("gleam docs publish", workflow)
        self.assertIn("git merge-base --is-ancestor HEAD origin/main", workflow)

    def test_candidate_cycle_retains_fragments_until_promotion(self):
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            (fixture / "gleam.toml").write_text((ROOT / "gleam.toml").read_text())

            def git(*args):
                return subprocess.run(
                    ["git", "-C", directory, "-c", "user.name=Release Test",
                     "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
                     "-c", "core.hooksPath=/dev/null", *args],
                    check=True, capture_output=True, text=True,
                ).stdout.strip()

            git("init")
            git("add", "gleam.toml")
            git("commit", "-m", "Initial fixture")
            base = git("rev-parse", "HEAD")
            fragments = fixture / ".changes" / "unreleased"
            fragments.mkdir(parents=True)
            fragment = fragments / "gluegun-candidate.toml"
            fragment.write_text(
                'package = "gluegun"\nkind = "Added"\nbody = "Add candidate support"\n',
            )
            for args, expected, retained in [
                (["--set", "gluegun=1.0.0", "--pre", "rc"], "1.0.0-rc.0", True),
                (["--pre", "rc"], "1.0.0-rc.1", True),
                (["--pre", "none"], "1.0.0", False),
            ]:
                with self.subTest(expected=expected):
                    subprocess.run(
                        ["trellis", "--no-update-check", "-C", directory,
                         "version", "apply", *args],
                        check=True, capture_output=True, text=True,
                    )
                    version = tomllib.loads((fixture / "gleam.toml").read_text())["version"]
                    self.assertEqual(version, expected)
                    self.assertEqual(fragment.exists(), retained)
                    if retained:
                        git("add", ".")
                        git("commit", "-m", f"Prepare {expected}")
                        check = subprocess.run(
                            ["trellis", "--no-update-check", "-C", directory,
                             "changelog", "check", "--base", base, "--head", "HEAD",
                             "--format", "github"],
                            check=True, capture_output=True, text=True,
                        )
                        self.assertIn("ok=true", check.stdout)


if __name__ == "__main__":
    unittest.main()
