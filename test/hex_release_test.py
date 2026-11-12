"""Non-publishing release tag and archive checks."""

import importlib.util
import io
import os
from pathlib import Path
import tarfile
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SPEC = importlib.util.spec_from_file_location(
    "check_hex_release", ROOT / "scripts/check_hex_release.py",
)
release = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(release)


class HexReleaseTests(unittest.TestCase):
    def test_stable_and_candidate_tags_select_hex_but_pre_1_does_not(self):
        for version, expected in [
            ("0.2.0", False), ("0.9.0-rc.1", False),
            ("1.0.0-rc.0", True), ("1.0.0", True), ("2.0.0", True),
        ]:
            with self.subTest(version=version):
                self.assertEqual(
                    release.hex_release(f"refs/tags/v{version}", version), expected,
                )

    def test_branch_mismatched_tag_and_invalid_version_fail(self):
        for ref, version in [
            ("refs/heads/main", "1.0.0"), ("refs/tags/v1.0.1", "1.0.0"),
            ("refs/tags/v1.0", "1.0"), ("refs/tags/v01.0.0", "01.0.0"),
        ]:
            with self.subTest(ref=ref, version=version):
                with self.assertRaises(ValueError):
                    release.hex_release(ref, version)

    def test_package_requires_source_and_rejects_development_files(self):
        def tar(files, mode):
            output = io.BytesIO()
            with tarfile.open(fileobj=output, mode=mode) as archive:
                for name, content in files.items():
                    entry = tarfile.TarInfo(name)
                    entry.size = len(content)
                    archive.addfile(entry, io.BytesIO(content))
            return output.getvalue()

        with tempfile.TemporaryDirectory() as directory:
            previous = Path.cwd()
            self.addCleanup(os.chdir, previous)
            os.chdir(directory)
            Path("src").mkdir()
            Path("src/gluegun.gleam").write_text("")
            files = {name: b"" for name in [
                "LICENSE", "README.md", "gleam.toml", "src/gluegun.gleam",
                "src/gluegun_ffi.erl", "src/gluegun.erl", "src/gluegun.app.src",
                "include/gluegun@message_Response.hrl",
            ]}
            cases = [
                (files, True),
                ({k: v for k, v in files.items() if k != "src/gluegun_ffi.erl"}, False),
                ({k: v for k, v in files.items() if k != "src/gluegun.gleam"}, False),
            ]
            for name in ["test/helper.erl", "build/output.beam", ".env", "src/../secret.erl"]:
                cases.append(({**files, name: b""}, False))
            for contents, valid in cases:
                with self.subTest(files=list(contents), valid=valid):
                    archive = Path("package.tar")
                    archive.write_bytes(tar({
                        "contents.tar.gz": tar(contents, "w:gz"),
                    }, "w"))
                    if valid:
                        release.inspect_package(archive, Path("src"))
                    else:
                        with self.assertRaises(ValueError):
                            release.inspect_package(archive, Path("src"))


if __name__ == "__main__":
    unittest.main()
