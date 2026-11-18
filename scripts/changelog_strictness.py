"""Use warning mode only when the release bot's tree matches release generation.

Rebuild from the merge base with pinned Trellis, then refresh version-only
reference metadata. Compare the full Git tree, including file modes and archives.
Generation failures fail the job; other PRs keep Trellis error mode.
"""

from contextlib import contextmanager
from datetime import date
import json
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import tomllib


ROOT = Path(__file__).resolve().parents[1]


def git(*args, cwd=None):
    return subprocess.run(
        ["git", *args], cwd=cwd or ROOT, check=True, capture_output=True, text=True,
    ).stdout.strip()


@contextmanager
def release_worktree(base):
    with tempfile.TemporaryDirectory(prefix="changelog-release-") as directory:
        path = Path(directory) / "tree"
        git("worktree", "add", "--quiet", "--detach", str(path), base)
        try:
            yield path
        finally:
            git("worktree", "remove", "--force", str(path))


def generated_tree(base, head):
    old = tomllib.loads(git("show", f"{base}:gleam.toml"))["version"]
    new = tomllib.loads(git("show", f"{head}:gleam.toml"))["version"]
    if old == new:
        raise ValueError("The package version did not change.")
    match = re.fullmatch(r"(\d+\.\d+\.\d+)(?:-([A-Za-z0-9.-]+)\.(\d+))?", new)
    if not match:
        raise ValueError("Unsupported release version.")
    version, label, _ = match.groups()
    release_md = f".changes/gluegun/v{new}.md"
    heading = git("show", f"{head}:{release_md}").splitlines()[0]
    prefix = f"## {new} - "
    if not heading.startswith(prefix):
        raise ValueError("The release heading does not match the package version.")
    release_date = date.fromisoformat(heading.removeprefix(prefix)).isoformat()

    with release_worktree(base) as tree:
        command = ["trellis", "version", "apply", "--set", f"gluegun={version}"]
        if label or "-" in old:
            command.extend(["--pre", label or "none"])
        subprocess.run(command, cwd=tree, check=True, stdout=sys.stderr)
        actual = tomllib.loads((tree / "gleam.toml").read_text())["version"]
        if actual != new:
            raise ValueError("Trellis generated a different package version.")

        # A check can run on a later day than release preparation.
        for path in (tree / release_md, tree / "CHANGELOG.md"):
            text = path.read_text()
            text = re.sub(
                rf"(?m)^## {re.escape(new)} - \d{{4}}-\d{{2}}-\d{{2}}$",
                f"{prefix}{release_date}", text,
            )
            path.write_text(text)

        index = tree / "website/src/content/docs/reference/index.md"
        index.write_text(index.read_text().replace(old, new))
        subprocess.run(
            ["node", "--input-type=module", "-e",
             "import { writeReferenceState } from './website/scripts/reference-state.mjs';"
             "await writeReferenceState();"],
            cwd=tree, check=True, stdout=sys.stderr,
        )
        git("add", "--all", cwd=tree)
        return git("write-tree", cwd=tree)


def strictness(event, repository):
    pr = event["pull_request"]
    if not (
        repository == "tylerbutler/gluegun"
        and pr["user"]["login"] == "tylerbutler-release-bot[bot]"
        and pr["user"]["type"] == "Bot"
        and pr["head"]["repo"]["full_name"] == repository
        and pr["base"]["repo"]["full_name"] == repository
        and pr["head"]["ref"] == "release/pending"
        and pr["base"]["ref"] == "main"
    ):
        return "error"
    base = git("merge-base", pr["base"]["sha"], pr["head"]["sha"])
    try:
        expected = generated_tree(base, pr["head"]["sha"])
    except ValueError as error:
        print(f"Release validation rejected warning mode: {error}", file=sys.stderr)
        return "error"
    if expected != git("rev-parse", f"{pr['head']['sha']}^{{tree}}"):
        print("Release tree differs from generated artifacts; using strict checks.", file=sys.stderr)
        return "error"
    return "warn"


if __name__ == "__main__":
    event = json.loads(Path(os.environ["GITHUB_EVENT_PATH"]).read_text())
    print(strictness(event, os.environ["GITHUB_REPOSITORY"]))
