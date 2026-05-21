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

function renderType(type) {
	if (!type || typeof type !== "object") {
		return "Unknown";
	}

	switch (type.kind) {
		case "named": {
			const base =
				type.module && type.module !== "gleam"
					? `${type.module}.${type.name}`
					: type.name;
			const parameters =
				Array.isArray(type.parameters) && type.parameters.length > 0
					? `(${type.parameters.map(renderType).join(", ")})`
					: "";
			return `${base}${parameters}`;
		}
		case "fn": {
			const parameters = Array.isArray(type.parameters)
				? type.parameters.map(renderType).join(", ")
				: "";
			return `fn(${parameters}) -> ${renderType(type.return)}`;
		}
		case "tuple":
			return `#(${(type.elements || []).map(renderType).join(", ")})`;
		case "variable":
			return type.name || "a";
		default:
			return type.name || type.kind || "Unknown";
	}
}

function renderParameters(parameters) {
	if (!Array.isArray(parameters) || parameters.length === 0) {
		return "";
	}

	return parameters
		.map((parameter) => {
			const label = parameter.label ? `${parameter.label}: ` : "";
			return `${label}${renderType(parameter.type)}`;
		})
		.join(", ");
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

# Reference

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
		renderTypes(moduleInterface.types),
		renderTypeAliases(moduleInterface["type-aliases"]),
		renderConstants(moduleInterface.constants),
		renderFunctions(moduleInterface.functions),
	].filter(Boolean);

	return `---
title: ${title}
description: ${description}
---

# ${code(moduleName)}

${normalizeDoc(moduleInterface.documentation) || description}

${sections.join("\n\n")}
`;
}

function renderTypes(types) {
	const entries = Object.entries(types || {}).sort(([left], [right]) =>
		left.localeCompare(right),
	);
	if (entries.length === 0) {
		return "";
	}

	return [
		"## Types",
		...entries.map(([name, typeInterface]) => {
			const constructors = normalizeConstructors(typeInterface.constructors)
				.map((constructor) => {
					const parameters = constructor.parameters || constructor.arguments || [];
					const parametersText = parameters
						.map((parameter) => renderType(parameter.type))
						.join(", ");
					return `- ${code(`${constructor.name}(${parametersText})`)}`;
				})
				.join("\n");
			const docs = normalizeDoc(typeInterface.documentation);
			return `### ${code(name)}

${docs}

${constructors}`;
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

function renderTypeAliases(typeAliases) {
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
			const aliasType = alias.alias ?? alias.type;
			return `### ${code(name)}

${docs}

\`\`\`gleam
pub type ${name} = ${renderType(aliasType)}
\`\`\``;
		}),
	].join("\n\n");
}

function renderConstants(constants) {
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
			return `### ${code(name)}

${docs}

\`\`\`gleam
pub const ${name}: ${renderType(constant.type)}
\`\`\``;
		}),
	].join("\n\n");
}

function renderFunctions(functions) {
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
			const parameters = renderParameters(functionInterface.parameters);
			return `### ${code(name)}

${docs}

\`\`\`gleam
pub fn ${name}(${parameters}) -> ${renderType(functionInterface.return)}
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
