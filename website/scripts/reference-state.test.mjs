import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { mkdir, mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";
import { checkRenderedReference, generateReference } from "./generate-reference.mjs";
import { checkReferenceState, referenceDir, writeReferenceState } from "./reference-state.mjs";

async function fixture(t) {
	const root = await mkdtemp(path.join(os.tmpdir(), "gluegun-reference-state-"));
	t.after(() => rm(root, { recursive: true, force: true }));
	for (const directory of ["src", "website/scripts", referenceDir]) {
		await mkdir(path.join(root, directory), { recursive: true });
	}
	for (const file of [
		"src/gluegun.gleam", "gleam.toml", "manifest.toml", ".tool-versions",
		"website/scripts/generate-reference.mjs", "website/scripts/reference-state.mjs",
	]) {
		await writeFile(path.join(root, file), file);
	}
	await writeFile(path.join(root, referenceDir, "index.md"), "Current reference");
	await writeReferenceState(root);
	return root;
}

test("fresh references pass without modifying pages", async (t) => {
	const root = await fixture(t);
	const before = await readFile(path.join(root, referenceDir, "index.md"), "utf8");
	await checkReferenceState(root);
	assert.equal(await readFile(path.join(root, referenceDir, "index.md"), "utf8"), before);
});

for (const file of [
	"src/gluegun.gleam", "src/new.gleam", "gleam.toml", "manifest.toml",
	".tool-versions", "website/scripts/generate-reference.mjs",
	"website/scripts/reference-state.mjs",
]) {
	test(`rejects changed source input ${file}`, async (t) => {
		const root = await fixture(t);
		await writeFile(path.join(root, file), "Changed");
		await assert.rejects(checkReferenceState(root), /source inputs changed.*just site-reference/);
	});
}

test("rejects a removed source file", async (t) => {
	const root = await fixture(t);
	await rm(path.join(root, "src/gluegun.gleam"));
	await assert.rejects(checkReferenceState(root), /source inputs changed/);
});

for (const action of ["edit", "add", "remove", "missing-directory"]) {
	test(`rejects reference page ${action}`, async (t) => {
		const root = await fixture(t);
		if (action === "edit" || action === "add") {
			await writeFile(path.join(root, referenceDir, action === "edit" ? "index.md" : "extra.md"), "Changed");
		} else {
			await rm(path.join(root, referenceDir, ...(action === "remove" ? ["index.md"] : [])), {
				recursive: true,
			});
		}
		await assert.rejects(checkReferenceState(root), /Reference pages (changed|are missing)/);
	});
}

for (const state of [null, "{", "null", "{}"]) {
	test(`rejects missing or invalid state ${state}`, async (t) => {
		const root = await fixture(t);
		const file = path.join(root, "website/reference-state.json");
		if (state === null) {
			await rm(file);
		} else {
			await writeFile(file, state);
		}
		await assert.rejects(checkReferenceState(root), /just site-reference/);
	});
}

test("source docs and API changes require regeneration and appear in the reference", async (t) => {
	const root = await fixture(t);
	const docsJsonPath = path.join(root, "package-interface.json");
	const outputDir = path.join(root, referenceDir);
	const metadata = {
		name: "gluegun", version: "0.2.0",
		modules: { gluegun: { documentation: "Initial docs", functions: {} } },
	};
	await writeFile(docsJsonPath, JSON.stringify(metadata));
	await generateReference({ docsJsonPath, outputDir });
	await writeReferenceState(root);
	await checkRenderedReference({ docsJsonPath, outputDir });
	const before = await readFile(path.join(outputDir, "gluegun.md"), "utf8");

	await writeFile(path.join(root, "src/gluegun.gleam"), "New source docs and function");
	metadata.modules.gluegun.documentation = "Updated source documentation";
	metadata.modules.gluegun.functions.new_api = {
		documentation: "New public function", parameters: [],
		return: { kind: "named", name: "String", module: "gleam", parameters: [] },
	};
	await writeFile(docsJsonPath, JSON.stringify(metadata));
	await assert.rejects(checkReferenceState(root), /source inputs changed/);
	await assert.rejects(checkRenderedReference({ docsJsonPath, outputDir }), /differ from current Gleam metadata/);
	assert.equal(await readFile(path.join(outputDir, "gluegun.md"), "utf8"), before);

	await generateReference({ docsJsonPath, outputDir });
	await writeReferenceState(root);
	await checkReferenceState(root);
	await checkRenderedReference({ docsJsonPath, outputDir });
	const page = await readFile(path.join(outputDir, "gluegun.md"), "utf8");
	assert.match(page, /Updated source documentation/);
	assert.match(page, /pub fn new_api\(\) -> String/);

	await writeFile(path.join(outputDir, "gluegun.md"), "Manually changed");
	await writeReferenceState(root);
	await assert.rejects(checkRenderedReference({ docsJsonPath, outputDir }), /differ from current Gleam metadata/);
});

test("website commands check stale references before starting Astro", async (t) => {
	const root = await fixture(t);
	const packageJson = JSON.parse(
		await readFile(new URL("../package.json", import.meta.url), "utf8"),
	);
	await writeFile(
		path.join(root, "website/scripts/reference-state.mjs"),
		await readFile(new URL("./reference-state.mjs", import.meta.url)),
	);
	await writeReferenceState(root);
	await writeFile(path.join(root, "src/gluegun.gleam"), "Changed source docs");

	for (const command of ["astro", "build", "check:astro", "dev", "start", "preview"]) {
		const script = packageJson.scripts[command];
		assert.ok(script.startsWith("node scripts/reference-state.mjs && astro"));
		const result = spawnSync("/bin/sh", ["-c", script], {
			cwd: path.join(root, "website"),
			encoding: "utf8",
		});
		assert.equal(result.status, 1, command);
		assert.match(result.stderr, /source inputs changed.*just site-reference/);
		assert.doesNotMatch(result.stderr, /astro: (command )?not found/);
	}
});
