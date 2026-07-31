// Syncs provider `map` fields in proxy-config.json from the Claude-3p configLibrary.
// Claude-3p configLibrary is the single source of truth for the claude-name -> backend-model
// mapping: `inferenceModels[].name` (official Claude ID) -> `labelOverride` (backend model).
// This script regenerates the `map` for each provider that has a matching configLibrary
// entry, then the proxy reads the synced config at startup.
//
// Non-fatal: if the configLibrary is missing, exit 0 and leave the config untouched - the
// proxy falls back to whatever is already on disk. Any other error exits non-zero without
// writing, so the proxy still starts with the existing config.
"use strict";

const fs = require("fs");
const path = require("path");

function log(msg) {
  console.log("[sync-models] " + msg);
}

function die(msg) {
  log("ERROR: " + msg);
  process.exit(1);
}

// 1. Resolve config path (same env var + default as the proxy).
const configPath = process.env.PROXY_CONFIG_PATH ||
  path.join(__dirname, "..", "config", "proxy-config.json");
if (!fs.existsSync(configPath)) {
  die("proxy config not found: " + configPath);
}

// 2. Resolve configLibrary path: CONFIG_LIBRARY_PATH env, else %LOCALAPPDATA%\Claude-3p\configLibrary.
let configLibraryPath = process.env.CONFIG_LIBRARY_PATH;
if (!configLibraryPath && process.env.LOCALAPPDATA) {
  configLibraryPath = path.join(process.env.LOCALAPPDATA, "Claude-3p", "configLibrary");
}
if (!configLibraryPath || !fs.existsSync(configLibraryPath)) {
  log("configLibrary not found" + (configLibraryPath ? " at " + configLibraryPath : "") +
    "; leaving proxy-config.json unchanged");
  return;
}

// 3. Read _meta.json -> {name: id} for every provider entry.
const metaPath = path.join(configLibraryPath, "_meta.json");
if (!fs.existsSync(metaPath)) {
  die("_meta.json not found in " + configLibraryPath);
}
let meta;
try {
  meta = JSON.parse(fs.readFileSync(metaPath, "utf8"));
} catch (e) {
  die("failed to parse _meta.json: " + e.message);
}
const entries = (meta && meta.entries) || [];
const nameToId = {};
entries.forEach((e) => {
  if (e && e.name && e.id) {
    nameToId[e.name] = e.id;
  }
});

// 4. Read proxy-config.json.
let config;
try {
  config = JSON.parse(fs.readFileSync(configPath, "utf8"));
} catch (e) {
  die("failed to parse " + configPath + ": " + e.message);
}
const providers = (config && config.providers) || {};
const providerNames = Object.keys(providers);

// 5. Sync each provider that has a matching configLibrary entry.
let changed = false;
const summary = [];

providerNames.forEach((name) => {
  const id = nameToId[name];
  if (!id) {
    summary.push(name + ": skipped (no configLibrary entry)");
    return;
  }
  const providerFile = path.join(configLibraryPath, id + ".json");
  if (!fs.existsSync(providerFile)) {
    summary.push(name + ": skipped (configLibrary file missing: " + id + ".json)");
    return;
  }
  let providerCfg;
  try {
    providerCfg = JSON.parse(fs.readFileSync(providerFile, "utf8"));
  } catch (e) {
    summary.push(name + ": skipped (failed to parse " + id + ".json: " + e.message + ")");
    return;
  }
  const inferenceModels = providerCfg && providerCfg.inferenceModels;
  if (!Array.isArray(inferenceModels)) {
    summary.push(name + ": skipped (no inferenceModels array in " + id + ".json)");
    return;
  }
  const newMap = {};
  inferenceModels.forEach((m) => {
    if (m && m.name) {
      newMap[m.name] = m.labelOverride || m.name;
    }
  });
  providers[name].map = newMap;
  changed = true;
  summary.push(name + ": synced " + Object.keys(newMap).length + " models");
});

if (!changed) {
  log("no providers matched configLibrary entries; leaving proxy-config.json unchanged");
  summary.forEach((s) => log("  " + s));
  return;
}

// 6. Validate by round-trip parse, then atomic write (temp + rename, same volume).
const output = JSON.stringify(config, null, 2);
try {
  JSON.parse(output);
} catch (e) {
  die("internal error: serialized config is not valid JSON: " + e.message);
}

const tmpPath = configPath + ".tmp";
try {
  fs.writeFileSync(tmpPath, output + "\n", "utf8");
  fs.renameSync(tmpPath, configPath);
} catch (e) {
  try { fs.unlinkSync(tmpPath); } catch (_e) { /* ignore */ }
  die("failed to write " + configPath + ": " + e.message);
}

log("synced " + configPath);
summary.forEach((s) => log("  " + s));
