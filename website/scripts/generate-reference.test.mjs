import assert from "node:assert/strict";
import { mkdtemp, readFile, rm, writeFile } from "node:fs/promises";
import os from "node:os";
import path from "node:path";
import test from "node:test";

import { generateReference } from "./generate-reference.mjs";

// Type helpers for fixtures
const namedType = (name, module = "gleam", parameters = []) => ({
	kind: "named",
	name,
	package: module === "gleam" ? "" : "gluegun",
	module,
	parameters,
});
const stringType = () => namedType("String");
const intType = () => namedType("Int");
const variableType = (id) => ({ kind: "variable", id });

async function runWithFixture(fixture) {
	const tempDir = await mkdtemp(path.join(os.tmpdir(), "gluegun-reference-"));
	const docsJsonPath = path.join(tempDir, "package-interface.json");
	const outputDir = path.join(tempDir, "reference");

	await writeFile(docsJsonPath, JSON.stringify(fixture));
	const result = await generateReference({ docsJsonPath, outputDir });

	const read = async (relativePath) =>
		readFile(path.join(outputDir, relativePath), "utf8");

	return { result, read, cleanup: () => rm(tempDir, { force: true, recursive: true }) };
}

test("generates reference index and module pages from Gleam docs JSON", async () => {
	const { result, read, cleanup } = await runWithFixture({
		name: "gluegun",
		version: "0.1.0",
		modules: {
			"gluegun/connection": {
				documentation: [
					" Connection management for Erlang Gun.",
					"",
					" Open a Gun process.",
				],
				"type-aliases": {
					Header: {
						documentation: " HTTP header tuple.\n",
						parameters: 0,
						alias: {
							kind: "tuple",
							elements: [stringType(), stringType()],
						},
					},
				},
				types: {
					Protocol: {
						documentation: " Negotiated protocol.\n",
						parameters: 0,
						constructors: [
							{ name: "Http1", parameters: [] },
							{ name: "Http2", parameters: [] },
						],
					},
				},
				constants: {},
				functions: {
					await_up: {
						documentation: " Wait until a Gun connection is up.\n",
						parameters: [
							{
								label: null,
								type: namedType("Connection", "gluegun/internal"),
							},
						],
						return: namedType("Result", "gleam", [
							namedType("Protocol", "gluegun/connection"),
						]),
					},
				},
			},
		},
	});

	try {
		const index = await read("index.md");
		const modulePage = await read("gluegun-connection.md");

		assert.deepEqual(result, { pageCount: 2, moduleCount: 1 });
		assert.match(index, /title: Reference/);
		assert.match(index, /\[`gluegun\/connection`\]\(\/reference\/gluegun-connection\/\)/);
		assert.match(modulePage, /title: gluegun\/connection/);
		assert.match(modulePage, /## Types/);
		// Sum types render as pub type ... { ... } blocks.
		assert.match(modulePage, /pub type Protocol \{\n {2}Http1\n {2}Http2\n\}/);
		assert.match(modulePage, /## Type aliases/);
		assert.match(modulePage, /pub type Header = #\(String, String\)/);
		assert.match(modulePage, /## Functions/);
		// internal.Connection (last path segment), and Protocol unqualified because
		// it lives in the current module.
		assert.match(
			modulePage,
			/pub fn await_up\(internal\.Connection\) -> Result\(Protocol\)/,
		);
	} finally {
		await cleanup();
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

test("renders type variables as a, b, c (gleamoire convention)", async () => {
	const { read, cleanup } = await runWithFixture({
		name: "gluegun",
		version: "0.1.0",
		modules: {
			"gluegun/result": {
				documentation: [],
				"type-aliases": {},
				types: {
					Pair: {
						documentation: "",
						parameters: 2,
						constructors: [
							{
								name: "Pair",
								parameters: [
									{ label: "first", type: variableType(0) },
									{ label: "second", type: variableType(1) },
								],
							},
						],
					},
				},
				constants: {},
				functions: {},
			},
		},
	});

	try {
		const page = await read("gluegun-result.md");
		// Multi-parameter constructors break onto multiple lines.
		assert.match(
			page,
			/pub type Pair\(a, b\) \{\n {2}Pair\(\n {4}first: a,\n {4}second: b\n {2}\)\n\}/,
		);
	} finally {
		await cleanup();
	}
});

test("renders multi-parameter functions across multiple lines with labels", async () => {
	const { read, cleanup } = await runWithFixture({
		name: "gluegun",
		version: "0.1.0",
		modules: {
			"gluegun/client": {
				documentation: [],
				"type-aliases": {},
				types: {},
				constants: {},
				functions: {
					send: {
						documentation: "",
						parameters: [
							{ label: "host", type: stringType() },
							{ label: "port", type: intType() },
							{ label: "path", type: stringType() },
						],
						return: namedType("Nil"),
					},
				},
			},
		},
	});

	try {
		const page = await read("gluegun-client.md");
		assert.match(
			page,
			/pub fn send\(\n {2}host: String,\n {2}port: Int,\n {2}path: String\n\) -> Nil/,
		);
	} finally {
		await cleanup();
	}
});

test("renders parameterised type aliases and constants", async () => {
	const { read, cleanup } = await runWithFixture({
		name: "gluegun",
		version: "0.1.0",
		modules: {
			"gluegun/types": {
				documentation: [],
				"type-aliases": {
					ResultPair: {
						documentation: "",
						parameters: 2,
						alias: {
							kind: "tuple",
							elements: [variableType(0), variableType(1)],
						},
					},
				},
				types: {},
				constants: {
					default_timeout: {
						documentation: " Default timeout in ms.\n",
						type: intType(),
					},
				},
				functions: {},
			},
		},
	});

	try {
		const page = await read("gluegun-types.md");
		assert.match(page, /pub type ResultPair\(a, b\) = #\(a, b\)/);
		assert.match(page, /## Constants/);
		assert.match(page, /pub const default_timeout: Int/);
	} finally {
		await cleanup();
	}
});

test("renders deprecation notices as Starlight caution admonitions", async () => {
	const { read, cleanup } = await runWithFixture({
		name: "gluegun",
		version: "0.1.0",
		modules: {
			"gluegun/legacy": {
				documentation: [],
				"type-aliases": {},
				types: {},
				constants: {},
				functions: {
					old_send: {
						documentation: " Old send API.\n",
						deprecation: { message: "Use send/3 instead." },
						parameters: [],
						return: namedType("Nil"),
					},
				},
			},
		},
	});

	try {
		const page = await read("gluegun-legacy.md");
		assert.match(page, /:::caution\[Deprecated\]\nUse send\/3 instead\.\n:::/);
	} finally {
		await cleanup();
	}
});

test("renders single-parameter constructors and functions inline", async () => {
	const { read, cleanup } = await runWithFixture({
		name: "gluegun",
		version: "0.1.0",
		modules: {
			"gluegun/single": {
				documentation: [],
				"type-aliases": {},
				types: {
					Wrap: {
						documentation: "",
						parameters: 1,
						constructors: [
							{ name: "Wrap", parameters: [{ label: null, type: variableType(0) }] },
						],
					},
				},
				constants: {},
				functions: {
					identity: {
						documentation: "",
						parameters: [{ label: null, type: variableType(0) }],
						return: variableType(0),
					},
				},
			},
		},
	});

	try {
		const page = await read("gluegun-single.md");
		assert.match(page, /pub type Wrap\(a\) \{\n {2}Wrap\(a\)\n\}/);
		assert.match(page, /pub fn identity\(a\) -> a/);
	} finally {
		await cleanup();
	}
});
