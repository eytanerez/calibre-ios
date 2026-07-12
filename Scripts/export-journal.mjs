#!/usr/bin/env node
// Exports the web app's static Journal articles into the iOS bundle.
// Re-run when editorial content changes in the frontend:
//   node Scripts/export-journal.mjs
import { readFileSync, writeFileSync, mkdirSync, copyFileSync, existsSync, readdirSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const frontend = resolve(here, "../../frontend");
const source = join(frontend, "src/pages/public/journalArticles.ts");
const outDir = resolve(here, "../Calibre/Resources/Journal");

const ts = readFileSync(source, "utf8");
const start = ts.indexOf("JOURNAL_ARTICLES");
const arrayStart = ts.indexOf("[", start);
const arrayEnd = ts.lastIndexOf("];");
const literal = ts.slice(arrayStart, arrayEnd + 1);
// Data-only object literal from our own repo — evaluating it is safe.
const articles = new Function(`return ${literal}`)();

mkdirSync(join(outDir, "images"), { recursive: true });

for (const article of articles) {
  // Rewrite web image paths ("/journal/foo.jpg") to bundled names ("foo.jpg").
  const imageName = article.image.split("/").pop();
  const webImage = join(frontend, "public", article.image.replace(/^\//, ""));
  if (existsSync(webImage)) {
    copyFileSync(webImage, join(outDir, "images", imageName));
    article.image = imageName;
  } else {
    console.warn(`missing image: ${webImage}`);
    article.image = null;
  }
}

writeFileSync(join(outDir, "articles.json"), JSON.stringify(articles, null, 1));
console.log(`Exported ${articles.length} articles → ${outDir}`);
console.log(readdirSync(join(outDir, "images")).join(", "));
