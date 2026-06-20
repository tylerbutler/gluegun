import { spawnSync } from "node:child_process";
import path from "node:path";
import { fileURLToPath } from "node:url";

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

const currentRef = process.env.COMMIT_REF || "HEAD";
const baseBranch = process.env.BASE_BRANCH || process.env.CHANGE_TARGET;

if (!baseBranch) {
	runBuild("BASE_BRANCH/CHANGE_TARGET is not set");
}

const baseRef = `origin/${baseBranch}`;
const fetchBase = git([
	"fetch",
	"--no-tags",
	"--depth=1",
	"origin",
	`refs/heads/${baseBranch}:refs/remotes/${baseRef}`,
]);
if (fetchBase.status !== 0) {
	runBuild(`could not fetch base branch ${baseBranch}`);
}

const diff = git(["diff", "--quiet", `${baseRef}...${currentRef}`, "--", "website/"]);

if (diff.status === 0) {
	skipBuild(`no website changes compared to ${baseRef}`);
}

if (diff.status === 1) {
	runBuild(`website changes detected compared to ${baseRef}`);
}

runBuild(`could not compare ${currentRef} to ${baseRef}`);
