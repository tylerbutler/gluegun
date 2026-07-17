/**
 * Generates public/og.png (1200×630) for social sharing cards.
 *
 * Derive before declaring, applied to the image pipeline itself:
 * - Colors are parsed from src/styles/custom.css (the dark-theme --sl-color-*
 *   tokens the site ships) and converted to hex with culori.
 * - Fonts are instanced at DESIGN.md weights (Chivo 700 display / 600 wordmark,
 *   JetBrains Mono 500 command line) from the same @fontsource-variable woff2
 *   files the site serves, via HarfBuzz.
 * - The mark is the committed dark-scheme glue-gun logo.
 *
 * Run: pnpm og
 */

import { readFileSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { formatHex, parse } from "culori";
import satori from "satori";
import sharp from "sharp";
import subsetFont from "subset-font";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");

// ---- colors: parsed from the shipped dark-theme tokens ----

// custom.css opens with the dark-mode `:root {}` block; scope the lookup to it
// so we read the instrument-panel palette rather than the light overrides.
const customCss = readFileSync(join(root, "src/styles/custom.css"), "utf8");
const darkRoot = customCss.slice(
  customCss.indexOf(":root {"),
  customCss.indexOf("}"),
);

function token(name: string): string {
  const match = darkRoot.match(new RegExp(`--${name}:\\s*([^;]+);`));
  if (!match?.[1]) throw new Error(`token --${name} not found in custom.css`);
  const color = parse(match[1].trim());
  if (!color) throw new Error(`token --${name} is not a parsable color`);
  return formatHex(color);
}

const bg = token("sl-color-black"); // gunmetal ink
const panel = token("sl-color-gray-6"); // midnight purple
const accent = token("sl-color-accent"); // charged magenta
const ink = token("sl-color-white"); // frost white
const inkSoft = token("sl-color-gray-1"); // pale signal
const muted = token("sl-color-gray-2"); // light pink
const line = token("sl-color-gray-5"); // deep violet

// ---- copy: mirrors the splash hero ----

const wordmark = "gluegun";
const headlinePlain = "HTTP without footguns.";
const headlineAccent = "Typed Gleam on the BEAM.";
const command = "gleam add gluegun";
const domain = "gluegun.tylerbutler.com";

// ---- fonts: instanced from the site's own variable fonts ----

async function instance(
  fontsourcePath: string,
  text: string,
  axes: Record<string, number>,
): Promise<Buffer> {
  const woff2 = readFileSync(join(root, "node_modules", fontsourcePath));
  return subsetFont(woff2, text, {
    targetFormat: "truetype",
    variationAxes: axes,
  });
}

const chivo = "@fontsource-variable/chivo/files/chivo-latin-wght-normal.woff2";
const jetbrains =
  "@fontsource-variable/jetbrains-mono/files/jetbrains-mono-latin-wght-normal.woff2";

const displayText = headlinePlain + headlineAccent;
const monoText = `$ ${command}${domain}`;

const [chivoDisplay, chivoWordmark, jetbrainsMono] = await Promise.all([
  instance(chivo, displayText, { wght: 700 }),
  instance(chivo, wordmark, { wght: 600 }),
  instance(jetbrains, monoText, { wght: 500 }),
]);

// ---- mark: the committed dark-scheme glue-gun logo ----

const markPng = readFileSync(join(root, "src/assets/gluegun-dark.png"));
const markUri = `data:image/png;base64,${markPng.toString("base64")}`;

// ---- layout ----

type Node = {
  type: string;
  props: Record<string, unknown> & { children?: Node[] | string };
};

function h(
  type: string,
  style: Record<string, unknown>,
  children?: Node[] | string,
): Node {
  // exactOptionalPropertyTypes: only set `children` when we actually have some.
  return { type, props: children === undefined ? { style } : { style, children } };
}

const width = 1200;
const height = 630;
const pad = 72;

const card = h(
  "div",
  {
    width,
    height,
    display: "flex",
    flexDirection: "column",
    backgroundColor: bg,
    // Tonal-first depth: a soft magenta wash bleeds from the top-left corner,
    // the same instrument-panel glow the splash lab uses.
    backgroundImage: `radial-gradient(circle at 12% -10%, ${panel}, ${bg} 55%)`,
  },
  [
    // charged-magenta band: the single accent voice, machined flat
    h("div", { height: 10, backgroundColor: accent }),
    h(
      "div",
      {
        flexGrow: 1,
        display: "flex",
        flexDirection: "column",
        padding: `54px ${pad}px 48px`,
      },
      [
        h("div", { display: "flex", alignItems: "center", gap: 20 }, [
          {
            type: "img",
            props: { src: markUri, width: 74, height: 59, style: {} },
          },
          h(
            "div",
            {
              fontFamily: "Chivo Wordmark",
              fontSize: 38,
              color: ink,
              letterSpacing: "-0.01em",
            },
            wordmark,
          ),
        ]),
        h(
          "div",
          {
            display: "flex",
            flexDirection: "column",
            marginTop: 42,
            maxWidth: 1010,
            fontFamily: "Chivo Display",
            fontSize: 82,
            lineHeight: 1.1,
            letterSpacing: "-0.02em",
          },
          [
            h("div", { color: ink }, headlinePlain),
            h("div", { color: accent }, headlineAccent),
          ],
        ),
        h("div", { flexGrow: 1 }),
        h("div", { height: 2, backgroundColor: line }),
        h(
          "div",
          {
            display: "flex",
            justifyContent: "space-between",
            alignItems: "center",
            marginTop: 30,
            fontFamily: "JetBrains Mono",
            fontSize: 23,
          },
          [
            h("div", { display: "flex", color: inkSoft }, [
              h("div", { color: accent, marginRight: 16 }, "$"),
              h("div", {}, command),
            ]),
            h("div", { color: muted }, domain),
          ],
        ),
      ],
    ),
  ],
);

// ---- render: satori (text → paths) then sharp (svg → png) ----

const svg = await satori(card, {
  width,
  height,
  fonts: [
    { name: "Chivo Display", data: chivoDisplay, weight: 700 },
    { name: "Chivo Wordmark", data: chivoWordmark, weight: 600 },
    { name: "JetBrains Mono", data: jetbrainsMono, weight: 500 },
  ],
});

const png = await sharp(Buffer.from(svg), { density: 144 })
  .resize(width, height)
  .png({ compressionLevel: 9 })
  .toBuffer();

const out = join(root, "public/og.png");
writeFileSync(out, png);
console.log(
  `wrote ${out} (${width}×${height}, ${(png.length / 1024).toFixed(1)} KiB)`,
);
