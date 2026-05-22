#!/usr/bin/env node
import { execFileSync } from "node:child_process";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const repoRoot = path.resolve(import.meta.dirname, "..");
const bundledPath = path.join(repoRoot, "Sources/CodexPetApp/Resources/Dictionaries/雅思高频单词.json");
const localPath = path.join(os.homedir(), "Library/Application Support/CodexDesktopPet/Dictionaries/雅思高频单词.json");
const settingsPath = path.join(os.homedir(), "Library/Application Support/CodexDesktopPet/settings.json");

const args = new Map();
for (let i = 2; i < process.argv.length; i += 1) {
  const arg = process.argv[i];
  if (arg.startsWith("--")) {
    const next = process.argv[i + 1];
    if (next && !next.startsWith("--")) {
      args.set(arg, next);
      i += 1;
    } else {
      args.set(arg, "true");
    }
  }
}

const batchSize = Number(args.get("--batch-size") ?? 60);
const limit = args.has("--limit") ? Number(args.get("--limit")) : Infinity;
const dryRun = args.get("--dry-run") === "true";

const settings = fs.existsSync(settingsPath) ? JSON.parse(fs.readFileSync(settingsPath, "utf8")) : {};
const model = String(args.get("--model") ?? settings.deepSeekModel ?? "deepseek-chat").trim() || "deepseek-chat";
const baseURL = String(args.get("--base-url") ?? settings.deepSeekBaseURL ?? "https://api.deepseek.com").replace(/\/+$/, "");
const apiKey = process.env.DEEPSEEK_API_KEY ?? readDeepSeekKeyFromKeychain();
if (!apiKey) {
  throw new Error("Missing DeepSeek API key. Save it in the app settings or set DEEPSEEK_API_KEY.");
}

const pack = JSON.parse(fs.readFileSync(bundledPath, "utf8"));
const candidates = pack.entries
  .filter((entry) => !String(entry.phonetic ?? "").trim())
  .filter((entry) => isEnglishTerm(entry.term))
  .slice(0, limit);

console.log(`Need phonetics: ${candidates.length}. Model: ${model}. Batch size: ${batchSize}. Dry run: ${dryRun}`);

let filled = 0;
let failed = 0;
for (let start = 0; start < candidates.length; start += batchSize) {
  const batch = candidates.slice(start, start + batchSize);
  const result = await requestPhonetics(batch);
  const byTerm = new Map(result.map((item) => [normalizeKey(item.term), normalizePhonetic(item.phonetic)]));

  for (const entry of batch) {
    const phonetic = byTerm.get(normalizeKey(entry.term)) ?? "";
    if (phonetic) {
      entry.phonetic = phonetic;
      filled += 1;
    } else {
      failed += 1;
    }
  }

  if (!dryRun) {
    savePack(pack);
  }

  console.log(`Batch ${Math.floor(start / batchSize) + 1}/${Math.ceil(candidates.length / batchSize)}: filled=${filled}, failed=${failed}`);
  await delay(250);
}

if (!dryRun) {
  savePack(pack);
}

const remaining = pack.entries.filter((entry) => !String(entry.phonetic ?? "").trim()).length;
console.log(`Done. Filled ${filled}. Failed ${failed}. Remaining without phonetic: ${remaining}.`);

function savePack(value) {
  const text = `${JSON.stringify(value, null, 2)}\n`;
  fs.writeFileSync(bundledPath, text);
  fs.mkdirSync(path.dirname(localPath), { recursive: true });
  fs.writeFileSync(localPath, text);
}

async function requestPhonetics(entries) {
  const payloadEntries = entries.map((entry) => ({
    term: entry.term,
    meaning: String(entry.meaning ?? "").slice(0, 180),
  }));
  const body = {
    model,
    response_format: { type: "json_object" },
    messages: [
      {
        role: "system",
        content:
          "Return only JSON. You add accurate IPA phonetic transcriptions for IELTS vocabulary. Prefer British English IPA when common; for American-only spellings, use common American IPA. Wrap each IPA in slashes. If a term is a multi-word phrase, transcribe the whole phrase. Keep the original term string unchanged.",
      },
      {
        role: "user",
        content:
          `For each item, return {"phonetics":[{"term":"same term","phonetic":"/IPA/"}]}. Items: ${JSON.stringify(payloadEntries)}`,
      },
    ],
  };

  const response = await fetch(`${baseURL}/chat/completions`, {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(body),
  });
  const text = await response.text();
  if (!response.ok) {
    throw new Error(`DeepSeek HTTP ${response.status}: ${text.slice(0, 400)}`);
  }
  const object = JSON.parse(text);
  const content = object?.choices?.[0]?.message?.content;
  if (!content) {
    throw new Error(`DeepSeek response has no content: ${text.slice(0, 400)}`);
  }
  const parsed = JSON.parse(stripCodeFence(content));
  const phonetics = normalizePhoneticsPayload(parsed);
  if (!Array.isArray(phonetics)) {
    throw new Error(`DeepSeek JSON missing phonetics array: ${content.slice(0, 400)}`);
  }
  return phonetics;
}

function normalizePhoneticsPayload(value) {
  if (Array.isArray(value)) {
    return value.flatMap((item) => normalizePhoneticsPayload(item) ?? []);
  }
  if (value && Array.isArray(value.phonetics)) {
    return value.phonetics;
  }
  return null;
}

function readDeepSeekKeyFromKeychain() {
  try {
    return execFileSync("/usr/bin/security", [
      "find-generic-password",
      "-s",
      "CodexDesktopPet",
      "-a",
      "deepseek-api-key",
      "-w",
    ], { encoding: "utf8" }).trim();
  } catch {
    return "";
  }
}

function isEnglishTerm(value) {
  return /^[A-Za-z][A-Za-z\s'./-]*$/.test(String(value).trim());
}

function normalizeKey(value) {
  return String(value).trim().toLowerCase();
}

function normalizePhonetic(value) {
  let text = String(value ?? "").trim();
  if (!text) return "";
  text = text.replace(/^["'`]+|["'`]+$/g, "");
  text = text.replace(/^\/+|\/+$/g, "");
  if (!text) return "";
  return `/${text}/`;
}

function stripCodeFence(value) {
  return String(value)
    .trim()
    .replace(/^```(?:json)?\s*/i, "")
    .replace(/\s*```$/i, "")
    .trim();
}

function delay(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}
