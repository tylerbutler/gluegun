import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { generateReference } from "./generate-reference.mjs";

test("generates reference index and module pages from Gleam docs JSON", async () => {
	const tempDir = await mkdtemp(path.join(os.tmpdir(), "gluegun-reference-"));
	const docsJsonPath = path.join(tempDir, "package-interface.json");
	const outputDir = path.join(tempDir, "reference");

	await writeFile(
		docsJsonPath,
		JSON.stringify({
			name: "gluegun",
			version: "0.1.0",
			modules: {
				"gluegun/connection": {
					documentation: [
						" Connection management for Erlang Gun.",
						"",
						" Open a Gun process.",
					],
					"type-aliases": {},
					types: {
						Protocol: {
							documentation: " Negotiated protocol.\n",
							constructors: {
								Http: { arguments: [] },
								Http2: { arguments: [] },
							},
						},
					},
					constants: {},
					functions: {
						await_up: {
							documentation: " Wait until a Gun connection is up.\n",
							parameters: [
								{
									label: null,
									type: {
										kind: "named",
										name: "Connection",
										package: "gluegun",
										module: "gluegun/internal",
										parameters: [],
									},
								},
							],
							return: {
								kind: "named",
								name: "Result",
								package: "",
								module: "gleam",
								parameters: [
									{
										kind: "named",
										name: "Protocol",
										package: "gluegun",
										module: "gluegun/connection",
										parameters: [],
									},
								],
							},
						},
					},
				},
			},
		}),
	);

	try {
		const result = await generateReference({ docsJsonPath, outputDir });
		const index = await readFile(path.join(outputDir, "index.md"), "utf8");
		const modulePage = await readFile(
			path.join(outputDir, "gluegun-connection.md"),
			"utf8",
		);

		assert.deepEqual(result, { pageCount: 2, moduleCount: 1 });
		assert.match(index, /title: Reference/);
		assert.match(index, /\[`gluegun\/connection`\]\(\/reference\/gluegun-connection\/\)/);
		assert.match(modulePage, /title: gluegun\/connection/);
		assert.match(modulePage, /## Types/);
		assert.match(modulePage, /`Http\(\)`/);
		assert.match(modulePage, /## Functions/);
		assert.match(
			modulePage,
			/pub fn await_up\(gluegun\/internal\.Connection\) -> Result\(gluegun\/connection\.Protocol\)/,
		);
	} finally {
		await rm(tempDir, { force: true, recursive: true });
	}
});

test("reports missing Gleam docs JSON with recovery command", async () => {
	const tempDir = await mkdtemp(path.join(os.tmpdir(), "gluegun-reference-"));

	try {
		await assert.rejects(
			() =>
				generateReference({
					docsJsonPath: path.join(tempDir, "missing-package-interface.json"),
					outputDir: path.join(tempDir, "reference"),
				}),
			/Run `gleam docs build` from the repository root first/,
		);
	} finally {
		await rm(tempDir, { force: true, recursive: true });
	}
});
