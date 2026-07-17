// Generates the Starlight reference pages under
// src/content/docs/reference/ from Gleam's package-interface.json.
//
// The Gleam-formatted code blocks (type-variable naming, current-module
// qualifier elision, multi-line constructors and function params, sum-type
// blocks, deprecation notices) are ported from gleamoire's render.gleam:
//   https://github.com/GearsDatapacks/gleamoire (Apache-2.0)
// Many thanks to the gleamoire authors.

import { mkdir, readFile, rm, writeFile } from "node:fs/promises";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const websiteRoot = path.resolve(__dirname, "..");
const repoRoot = path.resolve(websiteRoot, "..");
const packageName = "gluegun";
const defaultDocsJsonPath = path.join(
	repoRoot,
	"build",
	"dev",
	"docs",
	packageName,
	"package-interface.json",
);
const defaultOutputDir = path.join(
	websiteRoot,
	"src",
	"content",
	"docs",
	"reference",
);

export async function generateReference({
	docsJsonPath = defaultDocsJsonPath,
	outputDir = defaultOutputDir,
} = {}) {
	const packageInterface = await readPackageInterface(docsJsonPath);
	const modules = Object.entries(packageInterface.modules).sort(([left], [right]) =>
		left.localeCompare(right),
	);

	await rm(outputDir, { force: true, recursive: true });
	await mkdir(outputDir, { recursive: true });

	await writeFile(
		path.join(outputDir, "index.md"),
		renderIndex(packageInterface, modules),
	);

	for (const [moduleName, moduleInterface] of modules) {
		await writeFile(
			path.join(outputDir, `${moduleSlug(moduleName)}.md`),
			renderModulePage(moduleName, moduleInterface),
		);
	}

	return { pageCount: modules.length + 1, moduleCount: modules.length };
}

async function readPackageInterface(docsJsonPath) {
	let raw;
	try {
		raw = await readFile(docsJsonPath, "utf8");
	} catch (error) {
		if (error && error.code === "ENOENT") {
			throw new Error(
				`Missing ${path.relative(repoRoot, docsJsonPath)}. Run \`gleam docs build\` from the repository root first.`,
			);
		}
		throw error;
	}

	const parsed = JSON.parse(raw);
	if (!parsed || parsed.name !== packageName || typeof parsed.modules !== "object") {
		throw new Error(
			`Invalid Gleam package interface JSON at ${path.relative(repoRoot, docsJsonPath)}`,
		);
	}

	return parsed;
}

function moduleSlug(moduleName) {
	return moduleName.replaceAll("/", "-");
}

function titleForModule(moduleName) {
	return moduleName;
}

function descriptionFromDocs(documentation, fallback) {
	const text = normalizeDoc(documentation);
	const firstLine = text.split("\n").find((line) => line.trim().length > 0);
	return firstLine ? firstLine.replaceAll('"', '\\"') : fallback;
}

function normalizeDoc(documentation) {
	if (Array.isArray(documentation)) {
		return documentation.map((line) => line.trimEnd()).join("\n").trim();
	}
	if (typeof documentation === "string") {
		return documentation.trim();
	}
	return "";
}

function code(value) {
	return `\`${String(value).replaceAll("`", "\\`")}\``;
}

const VARIABLE_ANCHOR_CODE = "a".charCodeAt(0);

// Port of gleamoire's render.gleam type-variable naming: 0 -> "a", 1 -> "b", ...
function variableSymbol(id) {
	const code = VARIABLE_ANCHOR_CODE + (Number.isInteger(id) ? id : 0);
	return String.fromCharCode(code);
}

function renderTypeParameters(count) {
	if (!Number.isInteger(count) || count <= 0) {
		return "";
	}
	const vars = [];
	for (let i = 0; i < count; i++) {
		vars.push(variableSymbol(i));
	}
	return `(${vars.join(", ")})`;
}

// Mirrors gleamoire's render_type: omits the qualifier for prelude types
// (module "gleam") and for types declared in the current module, and uses
// only the last segment of the module path otherwise.
function renderType(type, currentModule) {
	if (!type || typeof type !== "object") {
		return "Unknown";
	}

	switch (type.kind) {
		case "named": {
			let qualifier = "";
			if (type.module && type.module !== "gleam" && type.module !== currentModule) {
				const segments = type.module.split("/");
				qualifier = `${segments[segments.length - 1]}.`;
			}
			const parameters =
				Array.isArray(type.parameters) && type.parameters.length > 0
					? `(${type.parameters.map((t) => renderType(t, currentModule)).join(", ")})`
					: "";
			return `${qualifier}${type.name}${parameters}`;
		}
		case "fn": {
			const parameters = Array.isArray(type.parameters)
				? type.parameters.map((t) => renderType(t, currentModule)).join(", ")
				: "";
			return `fn(${parameters}) -> ${renderType(type.return, currentModule)}`;
		}
		case "tuple":
			return `#(${(type.elements || []).map((t) => renderType(t, currentModule)).join(", ")})`;
		case "variable":
			return variableSymbol(type.id ?? 0);
		default:
			return type.name || type.kind || "Unknown";
	}
}

function renderParameter(parameter, currentModule) {
	const label = parameter.label ? `${parameter.label}: ` : "";
	return `${label}${renderType(parameter.type, currentModule)}`;
}

// Constructors and functions render inline for 0–1 parameters and break onto
// multiple lines for 2+ parameters, matching gleamoire.
function renderConstructor(constructor, currentModule) {
	const parameters = constructor.parameters || constructor.arguments || [];
	if (parameters.length === 0) {
		return constructor.name;
	}
	if (parameters.length === 1) {
		return `${constructor.name}(${renderParameter(parameters[0], currentModule)})`;
	}
	const rendered = parameters
		.map((p) => renderParameter(p, currentModule))
		.join(",\n  ");
	return `${constructor.name}(\n  ${rendered}\n)`;
}

// Single-line constructor signature for use in headings, which cannot contain
// line breaks. Unlike renderConstructor, this never breaks parameters across
// lines, so the surrounding code span stays closed on one line.
function renderConstructorInline(constructor, currentModule) {
	const parameters = constructor.parameters || constructor.arguments || [];
	if (parameters.length === 0) {
		return constructor.name;
	}
	const rendered = parameters
		.map((p) => renderParameter(p, currentModule))
		.join(", ");
	return `${constructor.name}(${rendered})`;
}

function renderFunctionSignature(name, parameters, returnType, currentModule) {
	let rendered;
	if (!Array.isArray(parameters) || parameters.length === 0) {
		rendered = "()";
	} else if (parameters.length === 1) {
		rendered = `(${renderParameter(parameters[0], currentModule)})`;
	} else {
		const params = parameters
			.map((p) => renderParameter(p, currentModule))
			.join(",\n  ");
		rendered = `(\n  ${params}\n)`;
	}
	const ret = returnType ? renderType(returnType, currentModule) : "Nil";
	return `pub fn ${name}${rendered} -> ${ret}`;
}

function renderTypeDefinition(name, typeDef, currentModule) {
	const params = renderTypeParameters(typeDef.parameters || 0);
	const constructors = normalizeConstructors(typeDef.constructors);
	if (constructors.length === 0) {
		return `pub type ${name}${params}`;
	}
	const body = constructors
		.map((c) => `  ${renderConstructor(c, currentModule).replaceAll("\n", "\n  ")}`)
		.join("\n");
	return `pub type ${name}${params} {\n${body}\n}`;
}

function renderAliasDefinition(name, alias, currentModule) {
	const params = renderTypeParameters(alias.parameters || 0);
	const aliasType = alias.alias ?? alias.type;
	return `pub type ${name}${params} = ${renderType(aliasType, currentModule)}`;
}

function renderConstantDefinition(name, constant, currentModule) {
	return `pub const ${name}: ${renderType(constant.type, currentModule)}`;
}

function deprecationBlock(deprecation) {
	if (!deprecation || typeof deprecation !== "object") {
		return "";
	}
	const message = (deprecation.message || "").trim();
	const body = message.length > 0 ? message : "This item has been deprecated.";
	return `\n\n:::caution[Deprecated]\n${body}\n:::`;
}

function renderIndex(packageInterface, modules) {
	const moduleRows = modules
		.map(([moduleName, moduleInterface]) => {
			const description = descriptionFromDocs(
				moduleInterface.documentation,
				`Reference for ${moduleName}.`,
			);
			return `| [${code(moduleName)}](/reference/${moduleSlug(moduleName)}/) | ${description} |`;
		})
		.join("\n");

	return `---
title: Reference
description: Generated Gluegun API reference from Gleam docs metadata.
---

This reference is generated from Gleam's docs metadata for ${code(packageInterface.name)} ${code(packageInterface.version)}.

For the canonical HexDocs rendering, see [hexdocs.pm/gluegun](https://hexdocs.pm/gluegun/).

:::note[Generated content]
Pages under \`/reference/\` are generated from Gleam's docs metadata and reflect every public type, function, and constant. For conceptual overviews and recommended patterns, see the hand-written [guides](/guides/basic-requests/) and [advanced topics](/advanced/error-handling/).
:::

## Modules

| Module | Description |
|---|---|
${moduleRows}
`;
}

function renderModulePage(moduleName, moduleInterface) {
	const title = titleForModule(moduleName);
	const description = descriptionFromDocs(
		moduleInterface.documentation,
		`Reference for ${moduleName}.`,
	);
	const sections = [
		renderTypes(moduleInterface.types, moduleName),
		renderTypeAliases(moduleInterface["type-aliases"], moduleName),
		renderConstants(moduleInterface.constants, moduleName),
		renderFunctions(moduleInterface.functions, moduleName),
	].filter(Boolean);

	return `---
title: ${title}
description: ${description}
---

${normalizeDoc(moduleInterface.documentation) || description}

${sections.join("\n\n")}
`;
}

function renderConstructorsSection(typeInterface, moduleName) {
	const constructors = normalizeConstructors(typeInterface.constructors).filter(
		(c) => normalizeDoc(c.documentation).length > 0,
	);
	if (constructors.length === 0) {
		return "";
	}

	const items = constructors
		.map((c) => {
			const signature = renderConstructorInline(c, moduleName);
			const docs = normalizeDoc(c.documentation);
			return `##### ${code(signature)}\n\n${docs}`;
		})
		.join("\n\n");
	return `#### Constructors\n\n${items}`;
}

function renderTypes(types, moduleName) {
	const entries = Object.entries(types || {}).sort(([left], [right]) =>
		left.localeCompare(right),
	);
	if (entries.length === 0) {
		return "";
	}

	return [
		"## Types",
		...entries.map(([name, typeInterface]) => {
			const docs = normalizeDoc(typeInterface.documentation);
			const deprecation = deprecationBlock(typeInterface.deprecation);
			const definition = renderTypeDefinition(name, typeInterface, moduleName);
			const constructors = renderConstructorsSection(typeInterface, moduleName);
			const sections = [
				docs ? `${docs}${deprecation}` : deprecation.replace(/^\n\n/, ""),
				`\`\`\`gleam\n${definition}\n\`\`\``,
				constructors,
			].filter((section) => section && section.length > 0);
			return `### ${code(name)}\n\n${sections.join("\n\n")}`;
		}),
	].join("\n\n");
}

function normalizeConstructors(constructors) {
	if (Array.isArray(constructors)) {
		return constructors;
	}
	return Object.entries(constructors || {})
		.sort(([left], [right]) => left.localeCompare(right))
		.map(([name, constructor]) => ({ name, ...constructor }));
}

function renderTypeAliases(typeAliases, moduleName) {
	const entries = Object.entries(typeAliases || {}).sort(([left], [right]) =>
		left.localeCompare(right),
	);
	if (entries.length === 0) {
		return "";
	}

	return [
		"## Type aliases",
		...entries.map(([name, alias]) => {
			const docs = normalizeDoc(alias.documentation);
			const deprecation = deprecationBlock(alias.deprecation);
			return `### ${code(name)}

${docs}${deprecation}

\`\`\`gleam
${renderAliasDefinition(name, alias, moduleName)}
\`\`\``;
		}),
	].join("\n\n");
}

function renderConstants(constants, moduleName) {
	const entries = Object.entries(constants || {}).sort(([left], [right]) =>
		left.localeCompare(right),
	);
	if (entries.length === 0) {
		return "";
	}

	return [
		"## Constants",
		...entries.map(([name, constant]) => {
			const docs = normalizeDoc(constant.documentation);
			const deprecation = deprecationBlock(constant.deprecation);
			return `### ${code(name)}

${docs}${deprecation}

\`\`\`gleam
${renderConstantDefinition(name, constant, moduleName)}
\`\`\``;
		}),
	].join("\n\n");
}

function renderFunctions(functions, moduleName) {
	const entries = Object.entries(functions || {}).sort(([left], [right]) =>
		left.localeCompare(right),
	);
	if (entries.length === 0) {
		return "";
	}

	return [
		"## Functions",
		...entries.map(([name, functionInterface]) => {
			const docs = normalizeDoc(functionInterface.documentation);
			const deprecation = deprecationBlock(functionInterface.deprecation);
			const signature = renderFunctionSignature(
				name,
				functionInterface.parameters,
				functionInterface.return,
				moduleName,
			);
			return `### ${code(name)}

${docs}${deprecation}

\`\`\`gleam
${signature}
\`\`\``;
		}),
	].join("\n\n");
}

if (import.meta.url === pathToFileURL(process.argv[1]).href) {
	generateReference()
		.then(({ pageCount }) => {
			console.log(
				`Generated ${pageCount} reference pages in ${path.relative(repoRoot, defaultOutputDir)}`,
			);
		})
		.catch((error) => {
			console.error(error.message);
			process.exit(1);
		});
}
