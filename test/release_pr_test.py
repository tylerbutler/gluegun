"""Release mode checks with no GitHub writes, tags, or publication."""

import importlib.util
from http.server import BaseHTTPRequestHandler, HTTPServer
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import threading
import tomllib
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "release_pr", ROOT / "scripts" / "release_pr.py",
)
release_pr = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release_pr)
COMMAND = [
    "trellis", "release", "pr", "--base", "main", "--branch", "release/pending",
    "--prepare-command", "node website/scripts/generate-reference.mjs",
]


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
    def test_hex_publication_is_disabled(self):
        config = tomllib.loads((ROOT / "gleam.toml").read_text())
        self.assertEqual(config["tools"]["trellis"]["publish"]["lifecycle"], {
            "default": "git_only",
            "packages": {"examples/*": "workspace"},
        })
        for workflow in (ROOT / ".github" / "workflows").glob("*.yml"):
            with self.subTest(workflow=workflow.name):
                self.assertNotRegex(workflow.read_text(), r"\b(?:trellis|gleam)\s+publish\b")
                self.assertNotIn("HEXPM_API_KEY", workflow.read_text())

    def test_release_versions_commit_fresh_references(self):
        class GitHub(BaseHTTPRequestHandler):
            def do_GET(self):
                self.send_response(200)
                self.end_headers()
                self.wfile.write(b"[]")

            def do_POST(self):
                self.rfile.read(int(self.headers["Content-Length"]))
                self.send_response(201)
                self.end_headers()
                self.wfile.write(
                    b'{"number":1,"html_url":"https://example.invalid/release/pull/1"}',
                )

            def log_message(self, *_args):
                pass

        server = self.enterContext(HTTPServer(("127.0.0.1", 0), GitHub))
        thread = threading.Thread(target=server.serve_forever)
        thread.start()
        self.addCleanup(thread.join)
        self.addCleanup(server.shutdown)
        self.enterContext(patch.dict(os.environ, {
            "TRELLIS_GITHUB_API_URL": f"http://127.0.0.1:{server.server_port}",
            "TRELLIS_GITHUB_REPO": "fixture/release",
            "GITHUB_TOKEN": "local-test-token",
            "GIT_CONFIG_COUNT": "2",
            "GIT_CONFIG_KEY_0": "commit.gpgsign",
            "GIT_CONFIG_VALUE_0": "false",
            "GIT_CONFIG_KEY_1": "core.hooksPath",
            "GIT_CONFIG_VALUE_1": "/dev/null",
        }))
        remote = self.enterContext(tempfile.TemporaryDirectory())
        subprocess.run(["git", "init", "--bare", remote], check=True, capture_output=True)
        with tempfile.TemporaryDirectory() as directory:
            fixture = Path(directory)
            for file in ("gleam.toml", "manifest.toml", ".mise.toml", ".gitignore"):
                shutil.copyfile(ROOT / file, fixture / file)
            shutil.copytree(ROOT / "src", fixture / "src")
            scripts = fixture / "website" / "scripts"
            scripts.mkdir(parents=True)
            for file in ("generate-reference.mjs", "reference-state.mjs"):
                shutil.copyfile(ROOT / "website" / "scripts" / file, scripts / file)
            example_versions = {}
            for manifest in sorted((ROOT / "examples").glob("*/gleam.toml")):
                relative = manifest.relative_to(ROOT)
                destination = fixture / relative
                destination.parent.mkdir(parents=True)
                destination.write_text(manifest.read_text())
                example_versions[relative] = tomllib.loads(manifest.read_text())["version"]

            releasable = subprocess.run(
                ["trellis", "--no-update-check", "-C", directory,
                 "list", "--releasable", "--json"],
                check=True, capture_output=True, text=True,
            )
            self.assertEqual(
                [package["name"] for package in json.loads(releasable.stdout)["packages"]],
                ["gluegun"],
            )

            def git(*args):
                return subprocess.run(
                    ["git", "-C", directory, "-c", "user.name=Release Test",
                     "-c", "user.email=test@example.invalid", "-c", "commit.gpgsign=false",
                     "-c", "core.hooksPath=/dev/null", *args],
                    check=True, capture_output=True, text=True,
                ).stdout.strip()

            def generate():
                subprocess.run(
                    ["node", "website/scripts/generate-reference.mjs"],
                    cwd=directory, check=True, capture_output=True, text=True,
                )

            def fresh():
                subprocess.run(
                    ["node", "website/scripts/reference-state.mjs"],
                    cwd=directory, check=True, capture_output=True, text=True,
                )

            git("init", "-b", "main")
            git("config", "user.name", "Release Test")
            git("config", "user.email", "test@example.invalid")
            git("remote", "add", "origin", remote)
            generate()
            git("add", ".")
            git("commit", "-m", "Initial fixture")
            fragments = fixture / ".changes" / "unreleased"
            fragments.mkdir(parents=True)
            fragment = fragments / "gluegun-candidate.toml"
            fragment.write_text(
                'package = "gluegun"\nkind = "Added"\nbody = "Add candidate support"\n',
            )
            for args, expected in [
                (["--set", "gluegun=1.0.0", "--pre", "rc"], "1.0.0-rc.0"),
                (["--pre", "rc"], "1.0.0-rc.1"),
                (["--pre", "none"], "1.0.0"),
                (["--set", "gluegun=1.0.1"], "1.0.1"),
            ]:
                with self.subTest(expected=expected):
                    fragments.mkdir(parents=True, exist_ok=True)
                    if expected == "1.0.0-rc.1":
                        fragment.write_text(
                            'package = "gluegun"\nkind = "Fixed"\nbody = "Fix candidate support"\n',
                        )
                    if expected == "1.0.1":
                        fragment.write_text(
                            'package = "gluegun"\nkind = "Fixed"\nbody = "Fix stable release"\n',
                        )
                    if fragment.exists():
                        git("add", ".changes/unreleased")
                        git("commit", "-m", "Add release fragment")
                    source = git("rev-parse", "HEAD")
                    subprocess.run(
                        [*COMMAND, "--no-update-check", "-C", directory, *args],
                        check=True, capture_output=True, text=True,
                    )
                    git("fetch", "origin", "release/pending")
                    git("merge", "--ff-only", "FETCH_HEAD")
                    self.assertEqual(git("rev-parse", "HEAD^"), source)
                    version = tomllib.loads((fixture / "gleam.toml").read_text())["version"]
                    self.assertEqual(version, expected)
                    for relative, original in example_versions.items():
                        self.assertEqual(
                            tomllib.loads((fixture / relative).read_text())["version"],
                            original,
                        )
                    self.assertFalse(fragment.exists())
                    archive = fixture / ".changes" / "gluegun" / "v1.0.0-rc.0.toml"
                    self.assertIn("Add candidate support", archive.read_text())
                    if expected == "1.0.0":
                        changelog = (fixture / "CHANGELOG.md").read_text()
                        stable = changelog.split("## 1.0.0 -", 1)[1].split("\n## ", 1)[0]
                        self.assertIn("Add candidate support", stable)
                        self.assertIn("Fix candidate support", stable)
                    fresh()
                    index = "website/src/content/docs/reference/index.md"
                    self.assertIn(f"`{expected}`", (fixture / index).read_text())
                    self.assertIn(f"`{expected}`", git("show", f"HEAD:{index}"))
                    self.assertEqual(
                        git("show", "HEAD:website/reference-state.json"),
                        (fixture / "website" / "reference-state.json").read_text().strip(),
                    )
                    self.assertEqual(git("status", "--porcelain"), "")

            previous = git("ls-remote", "origin", "refs/heads/release/pending")
            fragments.mkdir(parents=True, exist_ok=True)
            fragment.write_text(
                'package = "gluegun"\nkind = "Fixed"\nbody = "Check generation failure"\n',
            )
            git("add", ".changes/unreleased")
            git("commit", "-m", "Add failing release fragment")
            failed = subprocess.run(
                ["trellis", "--no-update-check", "-C", directory, "release", "pr",
                 "--prepare-command", 'node -e "process.exit(1)"'],
                capture_output=True, text=True,
            )
            self.assertNotEqual(failed.returncode, 0)
            self.assertIn("prepare command", failed.stderr)
            self.assertEqual(
                git("ls-remote", "origin", "refs/heads/release/pending"), previous,
            )


if __name__ == "__main__":
    unittest.main()
