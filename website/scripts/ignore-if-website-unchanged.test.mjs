import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { buildPaths, previewDecision } from "./ignore-if-website-unchanged.mjs";

test("preview comparison includes source and build inputs", () => {
	const calls = [];
	const decision = previewDecision({ BASE_BRANCH: "main", COMMIT_REF: "abc" }, (args) => {
		calls.push(args);
		return { status: args[0] === "fetch" ? 0 : 1 };
	});
	assert.equal(decision.build, true);
	assert.deepEqual(calls[1], ["diff", "--quiet", "origin/main...abc", "--", ...buildPaths]);
	for (const required of ["website/", "src/", "gleam.toml", "manifest.toml", ".tool-versions"]) {
		assert.ok(buildPaths.includes(required), required);
	}
});

test("skips a preview only when comparison succeeds with no relevant changes", () => {
	assert.equal(previewDecision({ CHANGE_TARGET: "main" }, () => ({ status: 0 })).build, false);
});

test("builds when the base branch is unknown", () => {
	assert.equal(previewDecision({}, () => assert.fail("must not run git")).build, true);
});

test("builds when fetch fails", () => {
	assert.equal(previewDecision({ BASE_BRANCH: "main" }, () => ({ status: 128 })).build, true);
});

test("builds when comparison fails", () => {
	assert.equal(previewDecision({ BASE_BRANCH: "main" }, (args) => ({
		status: args[0] === "fetch" ? 0 : 128,
	})).build, true);
});

test("source-only changes trigger a preview and unrelated tests do not", async (t) => {
	const root = await mkdtemp(path.join(os.tmpdir(), "gluegun-preview-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	const git = (args) => spawnSync("git", ["-C", root, ...args], { encoding: "utf8" });
	for (const args of [
		["init", "--quiet"],
		["-c", "user.name=Test", "-c", "user.email=test@example.invalid",
			"commit", "--quiet", "--allow-empty", "-m", "Initial"],
		["update-ref", "refs/remotes/origin/main", "HEAD"],
	]) {
		assert.equal(git(args).status, 0);
	}
	const runGit = (args) => args[0] === "fetch" ? { status: 0 } : git(args);
	for (const file of ["src/gluegun.gleam", "gleam.toml", "manifest.toml", ".tool-versions", "test/example.gleam"]) {
		await mkdir(path.dirname(path.join(root, file)), { recursive: true });
		await writeFile(path.join(root, file), "Changed");
		assert.equal(git(["add", file]).status, 0);
		assert.equal(git([
			"-c", "user.name=Test", "-c", "user.email=test@example.invalid",
			"commit", "--quiet", "-m", "Change",
		]).status, 0);
		assert.equal(
			previewDecision({ BASE_BRANCH: "main" }, runGit).build,
			file !== "test/example.gleam",
			file,
		);
		assert.equal(git(["update-ref", "refs/remotes/origin/main", "HEAD"]).status, 0);
	}
});
