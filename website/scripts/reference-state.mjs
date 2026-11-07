import { createHash } from "node:crypto";
import { readFile, readdir, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

export const repoRoot = path.resolve(
	path.dirname(fileURLToPath(import.meta.url)),
	"../..",
);
export const referenceDir = "website/src/content/docs/reference";
const stateFile = "website/reference-state.json";
const refreshMessage = "Run `just site-reference` and commit the reference pages and website/reference-state.json.";

async function filesUnder(root, directory) {
	const entries = await readdir(path.join(root, directory), {
		withFileTypes: true,
	});
	const files = [];
	for (const entry of entries) {
		const relative = `${directory}/${entry.name}`;
		if (entry.isDirectory()) {
			files.push(...await filesUnder(root, relative));
		} else if (entry.isFile()) {
			files.push(relative);
		} else {
			throw new Error(`Unsupported reference input: ${relative}`);
		}
	}
	return files.sort();
}

async function hashFiles(root, files) {
	const hash = createHash("sha256");
	for (const file of files.sort()) {
		const content = await readFile(path.join(root, file));
		hash.update(`${file}\0${content.length}\0`);
		hash.update(content);
	}
	return hash.digest("hex");
}

export async function referenceHash(root = repoRoot, directory = referenceDir) {
	return hashFiles(root, await filesUnder(root, directory));
}

async function sourceHash(root) {
	return hashFiles(root, [
		...await filesUnder(root, "src"),
		"gleam.toml",
		"manifest.toml",
		".tool-versions",
		"website/scripts/generate-reference.mjs",
		"website/scripts/reference-state.mjs",
	]);
}

export async function writeReferenceState(root = repoRoot) {
	const state = {
		version: 1,
		source: await sourceHash(root),
		reference: await referenceHash(root),
	};
	await writeFile(
		path.join(root, stateFile),
		`${JSON.stringify(state, null, "\t")}\n`,
	);
}

export async function checkReferenceState(root = repoRoot) {
	let state;
	try {
		state = JSON.parse(await readFile(path.join(root, stateFile), "utf8"));
	} catch (error) {
		if (error.code === "ENOENT" || error instanceof SyntaxError) {
			throw new Error(`Missing or invalid reference state. ${refreshMessage}`);
		}
		throw error;
	}
	if (state?.version !== 1 || state.source !== await sourceHash(root)) {
		throw new Error(`Reference source inputs changed. ${refreshMessage}`);
	}
	let current;
	try {
		current = await referenceHash(root);
	} catch (error) {
		if (error.code === "ENOENT") {
			throw new Error(`Reference pages are missing. ${refreshMessage}`);
		}
		throw error;
	}
	if (state.reference !== current) {
		throw new Error(`Reference pages changed. ${refreshMessage}`);
	}
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
	checkReferenceState().catch((error) => {
		console.error(error.message);
		process.exitCode = 1;
	});
}
