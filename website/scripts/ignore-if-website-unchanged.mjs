import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const websiteRoot = path.resolve(scriptDir, "..");
const repoRoot = path.resolve(websiteRoot, "..");

function git(args, options = {}) {
	const result = spawnSync("git", ["-C", repoRoot, ...args], {
		encoding: "utf8",
		stdio: ["ignore", "pipe", "pipe"],
		...options,
	});

	return result;
}

function runBuild(reason) {
	console.log(`Building website: ${reason}`);
	process.exit(1);
}

function skipBuild(reason) {
	console.log(`Skipping website build: ${reason}`);
	process.exit(0);
}

export const buildPaths = [
	"website/",
	"src/",
	"gleam.toml",
	"manifest.toml",
	".tool-versions",
	"justfile",
	".github/actions/setup/",
	".github/workflows/ci.yml",
];

export function previewDecision(env = process.env, runGit = git) {
	const currentRef = env.COMMIT_REF || "HEAD";
	const baseBranch = env.BASE_BRANCH || env.CHANGE_TARGET;

	if (!baseBranch) {
		return { build: true, reason: "BASE_BRANCH/CHANGE_TARGET is not set" };
	}

	const baseRef = `origin/${baseBranch}`;
	const fetchBase = runGit([
		"fetch",
		"--no-tags",
		"--depth=1",
		"origin",
		`refs/heads/${baseBranch}:refs/remotes/${baseRef}`,
	]);
	if (fetchBase.status !== 0) {
		return { build: true, reason: `could not fetch base branch ${baseBranch}` };
	}

	const diff = runGit([
		"diff", "--quiet", `${baseRef}...${currentRef}`, "--", ...buildPaths,
	]);
	if (diff.status === 0) {
		return { build: false, reason: `no website or reference input changes compared to ${baseRef}` };
	}
	if (diff.status === 1) {
		return { build: true, reason: `website or reference input changes detected compared to ${baseRef}` };
	}
	return { build: true, reason: `could not compare ${currentRef} to ${baseRef}` };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	const { build, reason } = previewDecision();
	if (build) {
		runBuild(reason);
	} else {
		skipBuild(reason);
	}
}
