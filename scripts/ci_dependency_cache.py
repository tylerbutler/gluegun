"""Select dependency-cache paths and export them for the CI cache action.

Run from the repository root with CACHE_EXAMPLES and GITHUB_OUTPUT set.
This script does not build packages or restore/save caches.
"""

import hashlib
import os
from pathlib import Path
import subprocess
import tomllib


def main():
    # Compiled dependencies must match the tools actually active on this runner.
    versions = [
        subprocess.check_output(["gleam", "--version"]),
        subprocess.check_output([
            "erl", "-noshell", "-eval",
            'io:format("~s", [erlang:system_info(system_version)]), halt().',
        ]),
        subprocess.check_output(["rebar3", "--version"]),
    ]
    identity = hashlib.sha256(b"\0".join(versions)).hexdigest()
    manifests = [Path("manifest.toml")]
    if os.environ["CACHE_EXAMPLES"] == "true":
        manifests.extend(sorted(Path("examples").glob("*/manifest.toml")))
    paths = ["~/.cache/gleam"]
    for manifest in manifests:
        build = manifest.parent / "build"
        # Keep downloaded packages and the compiler fingerprint with Hex output.
        paths.extend([str(build / "packages"), str(build / "dev/erlang/fingerprint")])
        for package in tomllib.loads(manifest.read_text())["packages"]:
            # Exclude workspace packages so current source and tests compile fresh.
            if package["source"] == "hex":
                paths.append(str(build / "dev/erlang" / package["name"]))
    # GitHub Actions passes these outputs to the following cache step.
    with open(os.environ["GITHUB_OUTPUT"], "a") as output:
        output.write(f"identity={identity}\npaths<<CACHE_PATHS\n")
        output.write("\n".join(paths) + "\nCACHE_PATHS\n")


if __name__ == "__main__":
    main()
