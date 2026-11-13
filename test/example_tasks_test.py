"""Exercise Just recipes through the installed Trellis, without network builds."""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]


class ExampleTaskTests(unittest.TestCase):
    def setUp(self):
        self.root = Path(self.enterContext(tempfile.TemporaryDirectory(
            prefix="example tasks 'quoted' $value ",
        ))).resolve()
        shutil.copyfile(ROOT / "justfile", self.root / "justfile")
        shutil.copyfile(ROOT / "gleam.toml", self.root / "gleam.toml")
        for manifest in sorted((ROOT / "examples").glob("*/gleam.toml")):
            package = self.root / "examples" / manifest.parent.name
            package.mkdir(parents=True)
            shutil.copyfile(manifest, package / "gleam.toml")
            (package / "src").mkdir()
            if (manifest.parent / "test").is_dir():
                (package / "test").mkdir()
        # Discovery must include new examples and ignore non-package directories.
        extra = self.root / "examples" / "zz_extra"
        extra.mkdir()
        (extra / "gleam.toml").write_text(
            'name = "zz_extra"\nversion = "0.1.0"\ntarget = "erlang"\n'
            '[dependencies]\ngluegun = { path = "../.." }\n',
        )
        (extra / "manifest.toml").write_text(
            '[requirements]\ngleescript = { version = ">= 1.5.2" }\n',
        )
        (extra / "test").mkdir()
        (self.root / "examples" / "not_a_package").mkdir()
        binaries = self.root / "bin"
        binaries.mkdir()
        gleam = binaries / "gleam"
        gleam.write_text(
            '#!/usr/bin/env python3\n'
            'import json, os, pathlib, sys, time\n'
            'root = pathlib.Path(os.environ["TASK_ROOT"])\n'
            'package = pathlib.Path.cwd().relative_to(root).as_posix()\n'
            'lock = root / "active"\n'
            'lock.mkdir()\n'
            'try:\n'
            '    with (root / "commands.jsonl").open("a") as log:\n'
            '        log.write(json.dumps([package, sys.argv[1:], '
            'os.environ["TASK_ENV"]]) + "\\n")\n'
            '    time.sleep(0.01)\n'
            '    if os.environ.get("TASK_FAIL") == package + ":" + sys.argv[1]:\n'
            '        sys.exit(7)\n'
            'finally:\n'
            '    lock.rmdir()\n',
        )
        gleam.chmod(0o755)
        self.env = {
            **os.environ,
            "PATH": f"{binaries}{os.pathsep}{os.environ['PATH']}",
            "TASK_ROOT": str(self.root),
            "TASK_ENV": "inherited value with spaces",
            "TRELLIS_NO_UPDATE_CHECK": "1",
        }
        self.examples = [
            "examples/basic_request", "examples/chunked_upload",
            "examples/http2_preferred", "examples/json_post",
            "examples/streaming_download", "examples/webprobe",
            "examples/websocket_chat", "examples/websocket_echo", "examples/zz_extra",
        ]

    def run_recipe(self, recipe, fail=""):
        log = self.root / "commands.jsonl"
        log.unlink(missing_ok=True)
        result = subprocess.run(
            ["just", recipe], cwd=self.root, env={**self.env, "TASK_FAIL": fail},
            capture_output=True, text=True,
        )
        records = [json.loads(line) for line in log.read_text().splitlines()] if log.exists() else []
        for _, _, environment in records:
            self.assertEqual(environment, self.env["TASK_ENV"])
        return result, [(package, args) for package, args, _ in records]

    def test_selection_conditions_and_serial_order(self):
        for recipe, args in (
            ("examples-deps", ["deps", "download"]),
            ("examples-format", ["format"]),
            ("examples-format-check", ["format", "--check"]),
            ("examples-test", ["test"]),
            ("examples-build", ["build"]),
        ):
            with self.subTest(recipe=recipe):
                result, commands = self.run_recipe(recipe)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                expected = []
                for package in self.examples:
                    has_tests = (self.root / package / "test").is_dir()
                    if recipe == "examples-test" and not has_tests:
                        continue
                    paths = ["src", "test"] if has_tests else ["src"]
                    expected.append((
                        package, args + paths if "format" in recipe else args,
                    ))
                    if recipe == "examples-build" and package in (
                        "examples/webprobe", "examples/zz_extra",
                    ):
                        expected.append((package, [
                            "run", "-m", "gleescript", "--", "--out=dist",
                        ]))
                self.assertEqual(commands, expected)

    def test_failures_stop_later_packages_and_packaging(self):
        for recipe, verb, package in (
            ("examples-deps", "deps", "examples/basic_request"),
            ("examples-format", "format", "examples/basic_request"),
            ("examples-format-check", "format", "examples/basic_request"),
            ("examples-test", "test", "examples/webprobe"),
            ("examples-build", "build", "examples/webprobe"),
            ("examples-build", "run", "examples/webprobe"),
        ):
            with self.subTest(recipe=recipe, verb=verb):
                result, commands = self.run_recipe(recipe, f"{package}:{verb}")
                self.assertNotEqual(result.returncode, 0)
                self.assertTrue(commands, result.stdout + result.stderr)
                self.assertEqual((commands[-1][0], commands[-1][1][0]), (package, verb))
                self.assertNotIn("examples/zz_extra", [name for name, _ in commands])

    def test_workspace_members_control_package_selection(self):
        manifest = self.root / "gleam.toml"
        manifest.write_text(manifest.read_text().replace(
            'members = [".", "examples/*"]',
            'members = [".", "examples/basic_request"]',
        ))
        result, commands = self.run_recipe("examples-deps")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(commands, [("examples/basic_request", ["deps", "download"])])


if __name__ == "__main__":
    unittest.main()
