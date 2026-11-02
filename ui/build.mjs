import { build } from "esbuild";
import { copyFileSync, mkdirSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, join } from "node:path";

const root = dirname(fileURLToPath(import.meta.url));
mkdirSync(join(root, "dist"), { recursive: true });
await build({
  entryPoints: [join(root, "src", "app.js")],
  bundle: true,
  minify: true,
  target: ["chrome120"],
  format: "iife",
  platform: "browser",
  loader: { ".css": "css" },
  outfile: join(root, "dist", "app.js"),
  logLevel: "info",
  legalComments: "linked"
});
copyFileSync(join(root, "src", "index.html"), join(root, "dist", "index.html"));
copyFileSync(join(root, "src", "styles.css"), join(root, "dist", "styles.css"));
console.log("CuteTerm UI compiled to ui/dist");
