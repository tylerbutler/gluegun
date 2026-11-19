"""Exercise the release exception with real Git trees and pinned Trellis."""

import copy
import importlib.util
from pathlib import Path
import re
import subprocess
import tempfile
import unittest
from unittest.mock import patch


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "changelog_strictness", ROOT / "scripts/changelog_strictness.py",
)
policy = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(policy)
REPOSITORY = "tylerbutler/gluegun"


def write(root, relative, text):
    path = root / relative
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


def commit(root):
    policy.git("add", "--all", cwd=root)
    policy.git(
        "-c", "user.name=Test", "-c", "user.email=test@example.invalid",
        "-c", "commit.gpgsign=false", "commit", "--quiet", "-m", "fixture", cwd=root,
    )
    return policy.git("rev-parse", "HEAD", cwd=root)


class ChangelogStrictnessTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.fixture = tempfile.TemporaryDirectory()
        cls.addClassCleanup(cls.fixture.cleanup)
        root = Path(cls.fixture.name)
        policy.git("init", "--quiet", cwd=root)
        write(root, "gleam.toml", (
            'name = "gluegun"\nversion = "1.0.0-rc.1"\ntarget = "erlang"\n'
            '[tools.trellis]\nmembers = ["."]\n'
            '[tools.trellis.changelog]\n'
            'header_format = "# Changelog"\n'
            'version_format = "## {{ version }} - {{ date }}"\n'
        ))
        write(root, "manifest.toml", "")
        write(root, ".mise.toml", "")
        write(root, "src/fixture.txt", "unchanged source\n")
        write(root, ".changes/unreleased/fix.toml", (
            'package = "gluegun"\nkind = "Fixed"\nbody = "Fix a bug."\n'
        ))
        write(root, "CHANGELOG.md", "# Changelog\n")
        write(root, "website/src/content/docs/reference/index.md", "gluegun 1.0.0-rc.1\n")
        write(root, "website/scripts/generate-reference.mjs", "// fixture\n")
        helper = "website/scripts/reference-state.mjs"
        write(root, helper, (ROOT / helper).read_text())
        cls.base = commit(root)
        subprocess.run(
            ["trellis", "version", "apply", "--set", "gluegun=1.0.0", "--pre", "rc"],
            cwd=root, check=True, capture_output=True,
        )
        write(root, "website/src/content/docs/reference/index.md", "gluegun 1.0.0-rc.2\n")
        subprocess.run(
            ["node", "--input-type=module", "-e",
             f"import {{ writeReferenceState }} from './{helper}';"
             "await writeReferenceState();"],
            cwd=root, check=True, capture_output=True,
        )
        cls.head = commit(root)

    def setUp(self):
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.root = Path(directory.name) / "repo"
        subprocess.run(
            ["git", "clone", "--quiet", "--shared", self.fixture.name, str(self.root)],
            check=True,
        )
        root_patch = patch.object(policy, "ROOT", self.root)
        root_patch.start()
        self.addCleanup(root_patch.stop)
        self.event = {"pull_request": {
            "user": {"login": "tylerbutler-release-bot[bot]", "type": "Bot"},
            "head": {
                "repo": {"full_name": REPOSITORY},
                "ref": "release/pending", "sha": self.head,
            },
            "base": {
                "repo": {"full_name": REPOSITORY},
                "ref": "main", "sha": self.base,
            },
        }}

    def test_only_verified_bot_release_can_generate_warning_mode(self):
        changes = (
            ("user", "login", "contributor"),
            ("user", "type", "User"),
            ("head", "ref", "feature"),
            ("base", "ref", "other"),
            ("head", "repo", {"full_name": "fork/gluegun"}),
            ("base", "repo", {"full_name": "fork/gluegun"}),
        )
        for section, key, value in changes:
            event = copy.deepcopy(self.event)
            event["pull_request"][section][key] = value
            with self.subTest(section=section, key=key), patch.object(
                policy, "generated_tree",
            ) as generate:
                self.assertEqual(policy.strictness(event, REPOSITORY), "error")
                generate.assert_not_called()
        self.assertEqual(policy.strictness(self.event, "fork/gluegun"), "error")

    def test_matching_generated_release_uses_warning_mode(self):
        self.assertEqual(policy.strictness(self.event, REPOSITORY), "warn")
        for mode, ok in (("error", False), ("warn", True)):
            result = subprocess.run(
                ["trellis", "changelog", "check", "--base", self.base,
                 "--head", self.head, "--strictness", mode, "--format", "json"],
                cwd=self.root, capture_output=True, text=True,
            )
            with self.subTest(strictness=mode):
                self.assertEqual(result.returncode == 0, ok, result.stderr)

    def test_release_branch_without_a_version_change_is_not_exempt(self):
        self.event["pull_request"]["head"]["sha"] = self.base
        self.assertEqual(policy.strictness(self.event, REPOSITORY), "error")

    def test_release_can_be_checked_on_a_later_day(self):
        for relative in (".changes/gluegun/v1.0.0-rc.2.md", "CHANGELOG.md"):
            path = self.root / relative
            path.write_text(re.sub(r"\d{4}-\d{2}-\d{2}", "2000-01-02", path.read_text()))
        self.event["pull_request"]["head"]["sha"] = commit(self.root)
        self.assertEqual(policy.strictness(self.event, REPOSITORY), "warn")

    def test_warning_mode_still_rejects_malformed_unreleased_fragments(self):
        write(self.root, ".changes/unreleased/broken.toml", "invalid TOML [\n")
        head = commit(self.root)
        result = subprocess.run(
            ["trellis", "changelog", "check", "--base", self.base,
             "--head", head, "--strictness", "warn", "--format", "json"],
            cwd=self.root, capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)

    def test_unexpected_changes_cannot_use_warning_mode(self):
        changes = (
            ("src/fixture.txt", "unexpected source edit\n"),
            ("gleam.toml", (self.root / "gleam.toml").read_text() + '\nextra = true\n'),
            (".changes/gluegun/v1.0.0-rc.2.toml", "[[fragments]]\nbody = 'wrong'\n"),
            (".changes/unreleased/fix.toml", "invalid TOML [\n"),
            ("CHANGELOG.md", "# Changelog\nRelease notes removed.\n"),
            ("website/reference-state.json", "{}\n"),
            ("website/src/content/docs/reference/index.md", "wrong version\n"),
        )
        for relative, content in changes:
            path = self.root / relative
            original = path.read_text() if path.exists() else None
            write(self.root, relative, content)
            self.event["pull_request"]["head"]["sha"] = commit(self.root)
            with self.subTest(path=relative):
                self.assertEqual(policy.strictness(self.event, REPOSITORY), "error")
            if original is None:
                path.unlink()
            else:
                path.write_text(original)

    def test_missing_archive_is_not_exempt(self):
        (self.root / ".changes/gluegun/v1.0.0-rc.2.toml").unlink()
        self.event["pull_request"]["head"]["sha"] = commit(self.root)
        self.assertEqual(policy.strictness(self.event, REPOSITORY), "error")

    def test_generation_failure_is_not_silently_exempt(self):
        with patch.object(
            policy, "generated_tree",
            side_effect=subprocess.CalledProcessError(1, ["trellis"]),
        ), self.assertRaises(subprocess.CalledProcessError):
            policy.strictness(self.event, REPOSITORY)


if __name__ == "__main__":
    unittest.main()
