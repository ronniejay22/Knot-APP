#!/usr/bin/env node
//
// generate-mui-icons.mjs
//
// Generates the app's icon assets from MUI (`@mui/icons-material`).
//
// Source of truth: the raw values of `enum KnotIcon` in
// `Knot/Components/UI/KnotIcon.swift` — each is an MUI component name
// (`HomeOutlined`, `Bookmark`, …). For each one this script writes
//
//   Knot/Resources/Assets.xcassets/MUI/<Name>.imageset/{<Name>.svg, Contents.json}
//
// as a template vector asset (same format as `RecommendationBadge.imageset`),
// and deletes any imageset in `MUI/` that no case references any more.
//
// Usage (from iOS/):   node scripts/generate-mui-icons.mjs
// Requires: node + npm on PATH (npm is only used to download the pinned
// package tarball; nothing is installed into the repo).
//
// Licensing: `@mui/icons-material` is MIT; the glyphs are Google's Material
// Icons, Apache-2.0.
//
// How extraction works: every MUI icon module is a tiny CommonJS file of the
// form `createSvgIcon(jsx("path", { d: "…" }), "Name")`. We evaluate it with a
// stubbed `require` that turns `jsx(type, props)` into a plain element tree
// and `createSvgIcon` into the identity, then serialise that tree to a 24×24
// SVG. No React is needed.

import { execFileSync } from "node:child_process";
import { createHash } from "node:crypto";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { fileURLToPath } from "node:url";

const MUI_PACKAGE = "@mui/icons-material";
const MUI_VERSION = "9.4.0"; // pinned — bump deliberately and re-run
// The registry's `dist.integrity` for that exact version. The script executes
// the package's modules, so the tarball is verified before anything is
// unpacked. When bumping MUI_VERSION, update this from
// `npm view @mui/icons-material@<version> dist.integrity`.
const MUI_INTEGRITY =
  "sha512-5PVgBYtLOXTk6u0YUAjoV9GoTUQDbeZ8g+pus2h0GphLT/rpmftRnB5D/Kw6QCAovB7EyBX7UxKdZqPBBAHUKw==";

const scriptDir = path.dirname(fileURLToPath(import.meta.url));
const iosDir = path.resolve(scriptDir, "..");
const enumFile = path.join(iosDir, "Knot/Components/UI/KnotIcon.swift");
const outDir = path.join(iosDir, "Knot/Resources/Assets.xcassets/MUI");

// 1. Icon names from the Swift enum.
const swift = fs.readFileSync(enumFile, "utf8");
const names = [...swift.matchAll(/^\s*case\s+\w+\s*=\s*"([A-Za-z0-9]+)"/gm)].map((m) => m[1]);
if (names.length === 0) {
  console.error(`✗ No cases found in ${enumFile}`);
  process.exit(1);
}
const unique = [...new Set(names)];
if (unique.length !== names.length) {
  console.error("✗ Duplicate raw values in KnotIcon — each MUI name must appear once.");
  process.exit(1);
}

// 2. Download + unpack the pinned package into a temp dir.
const tmp = fs.mkdtempSync(path.join(os.tmpdir(), "mui-icons-"));
try {
  const tarball = execFileSync("npm", ["pack", `${MUI_PACKAGE}@${MUI_VERSION}`, "--silent"], {
    cwd: tmp,
    encoding: "utf8",
  }).trim().split("\n").pop();
  const integrity = "sha512-" + createHash("sha512").update(fs.readFileSync(path.join(tmp, tarball))).digest("base64");
  if (integrity !== MUI_INTEGRITY) {
    throw new Error(`${MUI_PACKAGE}@${MUI_VERSION} tarball integrity mismatch: got ${integrity}`);
  }
  execFileSync("tar", ["-xzf", tarball], { cwd: tmp });
  const pkgDir = path.join(tmp, "package");

  // 3. Evaluate each module with stubs and serialise to SVG.
  const jsx = (type, props) => ({ type, props: props ?? {} });
  const stubs = {
    "./utils/createSvgIcon": (element) => element,
    "react/jsx-runtime": { jsx, jsxs: jsx },
    react: {},
    "@babel/runtime/helpers/interopRequireDefault": {
      default: (m) => (m && m.__esModule ? m : { default: m }),
    },
    "@babel/runtime/helpers/interopRequireWildcard": { default: (m) => m },
  };
  const stubRequire = (id) => {
    if (id in stubs) return stubs[id];
    throw new Error(`unexpected require("${id}")`);
  };

  const ATTRS = {
    d: "d", cx: "cx", cy: "cy", r: "r", rx: "rx", ry: "ry", x: "x", y: "y",
    width: "width", height: "height", points: "points", transform: "transform",
    fillRule: "fill-rule", clipRule: "clip-rule",
  };
  const escape = (s) => String(s).replace(/&/g, "&amp;").replace(/"/g, "&quot;").replace(/</g, "&lt;");
  const serialise = (node) => {
    if (Array.isArray(node)) return node.map(serialise).join("");
    if (!node || typeof node !== "object") return "";
    const { type, props } = node;
    if (!["path", "circle", "ellipse", "rect", "polygon", "g"].includes(type)) {
      throw new Error(`unsupported SVG element <${type}>`);
    }
    // TwoTone icons carry `opacity` layers; the Outlined/Filled sets this app
    // uses never do. Refuse rather than silently flatten a translucent layer.
    if ("opacity" in props || "fillOpacity" in props) {
      throw new Error(`<${type}> has opacity — two-tone icons are not supported`);
    }
    const attrs = Object.entries(props)
      .filter(([k]) => k in ATTRS)
      .map(([k, v]) => ` ${ATTRS[k]}="${escape(v)}"`)
      .join("");
    const children = props.children ? serialise(props.children) : "";
    return children ? `<${type}${attrs}>${children}</${type}>` : `<${type}${attrs}/>`;
  };

  fs.mkdirSync(outDir, { recursive: true });
  fs.writeFileSync(
    path.join(outDir, "Contents.json"),
    JSON.stringify({ info: { author: "xcode", version: 1 }, properties: { "provides-namespace": true } }, null, 2) + "\n",
  );

  for (const name of unique) {
    const modulePath = path.join(pkgDir, `${name}.js`);
    if (!fs.existsSync(modulePath)) {
      throw new Error(`${MUI_PACKAGE}@${MUI_VERSION} has no icon named "${name}"`);
    }
    const source = fs.readFileSync(modulePath, "utf8");
    const module = { exports: {} };
    new Function("require", "module", "exports", source)(stubRequire, module, module.exports);
    const element = module.exports.default;
    const svg =
      `<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24" viewBox="0 0 24 24">` +
      serialise(element) +
      `</svg>\n`;

    const setDir = path.join(outDir, `${name}.imageset`);
    fs.mkdirSync(setDir, { recursive: true });
    fs.writeFileSync(path.join(setDir, `${name}.svg`), svg);
    fs.writeFileSync(
      path.join(setDir, "Contents.json"),
      JSON.stringify(
        {
          images: [{ filename: `${name}.svg`, idiom: "universal" }],
          info: { author: "xcode", version: 1 },
          properties: { "preserves-vector-representation": true, "template-rendering-intent": "template" },
        },
        null,
        2,
      ) + "\n",
    );
  }

  // 4. Prune imagesets no case references.
  const wanted = new Set(unique.map((n) => `${n}.imageset`));
  let pruned = 0;
  for (const entry of fs.readdirSync(outDir)) {
    if (entry.endsWith(".imageset") && !wanted.has(entry)) {
      fs.rmSync(path.join(outDir, entry), { recursive: true, force: true });
      pruned += 1;
    }
  }

  console.log(`✓ ${unique.length} MUI icons written to ${path.relative(iosDir, outDir)} (${pruned} pruned) from ${MUI_PACKAGE}@${MUI_VERSION}`);
} finally {
  fs.rmSync(tmp, { recursive: true, force: true });
}
