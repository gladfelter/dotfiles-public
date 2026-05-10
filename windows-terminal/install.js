#!/usr/bin/env node
// Merge saved Windows Terminal settings into the live config.
// Overwrites matching settings, adds missing ones, leaves unrelated settings untouched.
//
// Usage: node install.js [--apply]
//
// Default mode: dry-run — shows what would change without writing.
// Pass --apply to actually write the changes.
//
// Profile matching (in order):
//   1. By GUID — if the live config already has a profile with the saved GUID
//   2. By commandline — any profile whose commandline contains "ubuntu" or "wsl"
//   3. By name — any profile whose name contains "wsl" or "ubuntu" (case-insensitive)
//   If none match, a new profile entry is created with the saved GUID.

import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";

const apply = process.argv.includes("--apply");

const getWtConfigPath = () => {
  if (process.env.WT_CONFIG) return process.env.WT_CONFIG;
  // Windows
  if (process.env.USERPROFILE) {
    return path.join(
      process.env.USERPROFILE,
      "AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json",
    );
  }
  // WSL — search each user directory for the config file
  const wslUsers = path.join("/mnt/c/Users/");
  if (fs.existsSync(wslUsers)) {
    const subPath =
      "AppData/Local/Packages/Microsoft.WindowsTerminal_8wekyb3d8bbwe/LocalState/settings.json";
    for (const user of fs.readdirSync(wslUsers)) {
      const candidate = path.join(wslUsers, user, subPath);
      if (fs.existsSync(candidate)) return candidate;
    }
  }
  return null;
};

const WT_CONFIG = getWtConfigPath();

const SAVED_CONFIG = path.join(import.meta.dirname, "settings.json");

const normalizeGuid = (g) => (g ?? "").replace(/[{}]/g, "");

// --- Read saved config ---
let saved;
try {
  saved = JSON.parse(fs.readFileSync(SAVED_CONFIG, "utf-8"));
} catch (e) {
  console.error(`Cannot read ${SAVED_CONFIG}: ${e.message}`);
  process.exit(1);
}

const { wslProfile, colorSchemes = [], globalSettings } = saved;

if (!wslProfile) {
  console.error("No wslProfile found in saved settings. Run extract.js first.");
  process.exit(1);
}

// --- Read live config (strip JSON5) ---
let raw = "";
try {
  raw = fs.readFileSync(WT_CONFIG, "utf-8");
} catch {
  console.error(
    `Cannot read ${WT_CONFIG}. This script must run on the Windows side (or WSL with /mnt/c access).`,
  );
  process.exit(1);
}

// Strip JSON5: comments outside strings, trailing commas
const stripJson5 = (src) => {
  let out = "";
  let inString = false;
  let escape = false;
  for (let i = 0; i < src.length; i++) {
    const ch = src[i];
    if (inString) {
      out += ch;
      if (escape) { escape = false; continue; }
      if (ch === "\\") escape = true;
      if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') { inString = true; out += ch; continue; }
    if (ch === "/" && src[i + 1] === "/") {
      i += 2;
      while (i < src.length && src[i] !== "\n") i++;
      out += "\n";
      continue;
    }
    out += ch;
  }
  return out.replace(/,\s*([}\]])/g, "$1");
};

const stripped = stripJson5(raw);

let wt;
try {
  wt = JSON.parse(stripped);
} catch (e) {
  console.error(`Failed to parse settings.json: ${e.message}`);
  process.exit(1);
}

// Snapshot original state for diff
const originalWt = JSON.parse(JSON.stringify(wt));

// Ensure structure
wt.profiles ??= { defaults: {}, list: [] };
wt.schemes ??= [];

const profiles = wt.profiles.list;
const targetGuid = normalizeGuid(wslProfile.guid);

// --- Find the target profile ---
let targetProfile = null;

// 1. Match by GUID
targetProfile = profiles.find((p) => normalizeGuid(p.guid) === targetGuid);

// 2. Match by commandline (ubuntu.exe, wsl.exe, etc.)
if (!targetProfile) {
  targetProfile = profiles.find((p) => {
    const cl = (p.commandline ?? "").toLowerCase();
    return cl.includes("ubuntu") || cl.includes("wsl");
  });
  if (targetProfile) {
    console.log(
      `No profile matched by GUID. Found by commandline: ${targetProfile.name} (${targetProfile.guid})`,
    );
  }
}

// 3. Match by name
if (!targetProfile) {
  targetProfile = profiles.find((p) => {
    const name = (p.name ?? "").toLowerCase();
    return name.includes("wsl") || name.includes("ubuntu");
  });
  if (targetProfile) {
    console.log(
      `No profile matched by GUID or commandline. Found by name: ${targetProfile.name} (${targetProfile.guid})`,
    );
  }
}

if (targetProfile) {
  const oldGuid = targetProfile.guid;
  const wasGuidMatch = normalizeGuid(oldGuid) === targetGuid;

  if (wasGuidMatch) {
    // Same GUID — just update fields in place
    console.log(`Updating existing profile: ${targetProfile.name}`);
    mergeProfileFields(targetProfile, wslProfile);
  } else {
    // Different GUID — this profile exists locally but isn't ours.
    // Rename it to keep name-based shortcuts working, then update with our GUID.
    const oldName = targetProfile.name;
    targetProfile.name = `${oldName} (local)`;
    console.log(
      `Renamed existing "${oldName}" → "${oldName} (local)" to free the name`,
    );
    console.log(`Installing saved profile "${wslProfile.name}" with GUID ${wslProfile.guid}`);
    mergeProfileFields(targetProfile, wslProfile);
    targetProfile.guid = wslProfile.guid;
    console.error(
      `\nNOTE: GUID changed from ${oldGuid} → ${wslProfile.guid}.`,
    );
    console.error(
      `Any existing taskbar pins or shortcuts using the old GUID will be orphaned.`,
    );
    console.error(
      `Re-pin the profile or update shortcuts to use the new GUID.`,
    );
  }
} else {
  // No match found — add a new profile
  console.log("No matching profile found. Adding new profile.");
  const newProfile = { ...wslProfile };
  newProfile.hidden = false;
  profiles.push(newProfile);
}

function mergeProfileFields(target, source) {
  for (const key of [
    "name",
    "commandline",
    "colorScheme",
    "cursorShape",
    "font",
    "icon",
    "startingDirectory",
    "tabTitle",
  ]) {
    if (source[key] !== undefined && source[key] !== null) {
      target[key] = source[key];
    }
  }
}

// --- Merge color schemes ---
for (const scheme of colorSchemes) {
  const idx = wt.schemes.findIndex((s) => s.name === scheme.name);
  if (idx >= 0) {
    wt.schemes[idx] = scheme; // overwrite
  } else {
    wt.schemes.push(scheme); // add
  }
}

// --- Merge global settings ---
if (globalSettings) {
  // Actions: merge by id, overwriting matches, adding new ones
  if (globalSettings.actions && globalSettings.actions.length > 0) {
    const savedActionIds = new Set(
      globalSettings.actions.map((a) => a.id),
    );
    // Remove actions that are in our saved set (we'll re-add)
    wt.actions = (wt.actions ?? []).filter((a) => !savedActionIds.has(a.id));
    // Add saved actions
    wt.actions = [...(wt.actions ?? []), ...globalSettings.actions];
  }

  // Keybindings: merge by id
  if (globalSettings.keybindings && globalSettings.keybindings.length > 0) {
    const savedKbIds = new Set(
      globalSettings.keybindings.map((k) => k.id),
    );
    wt.keybindings = (wt.keybindings ?? []).filter((k) => !savedKbIds.has(k.id));
    wt.keybindings = [...(wt.keybindings ?? []), ...globalSettings.keybindings];
  }

  // Scalar settings: overwrite
  if (globalSettings.copyFormatting !== undefined) {
    wt.copyFormatting = globalSettings.copyFormatting;
  }
  if (globalSettings.copyOnSelect !== undefined) {
    wt.copyOnSelect = globalSettings.copyOnSelect;
  }
}

// --- Compare and report ---
const originalJson = JSON.stringify(originalWt, null, 4);
const mergedJson = JSON.stringify(wt, null, 4);

if (originalJson === mergedJson) {
  console.log("No changes needed — saved settings already match live config.");
  process.exit(0);
}

// Report what changed in human-readable form
const changes = computeChanges(originalWt, wt);

if (changes.length === 0) {
  console.log("No changes needed — saved settings already match live config.");
  process.exit(0);
}

console.log(`\nWould apply ${changes.length} change(s):`);
for (const c of changes) {
  console.log(`  ${c.type.padEnd(8)} ${c.path}`);
  if (c.old !== undefined) {
    console.log(`    was:    ${formatValue(c.old)}`);
  }
  if (c.new !== undefined) {
    console.log(`    would:  ${formatValue(c.new)}`);
  }
}

if (apply) {
  // Prompt for confirmation
  const rl = readline.createInterface({ input: process.stdin, output: process.stdout });
  const answer = await new Promise((resolve) => {
    rl.question("Apply changes? [y/N] ", (a) => {
      rl.close();
      resolve(a);
    });
  });
  if (!answer.match(/^[Yy]$/)) {
    console.log("\nSkipped.");
    process.exit(0);
  }

  fs.writeFileSync(WT_CONFIG, mergedJson + "\n");
  console.log(`\nApplied. Config updated: ${WT_CONFIG}`);
  console.log(
    `\nRestart Windows Terminal (or Ctrl+Shift+R) to apply changes.`,
  );
} else {
  console.log(
    `\nNo changes written. Pass --apply to write to ${WT_CONFIG}`,
  );
}

// --- Deep diff: collect human-readable changes ---
function computeChanges(oldObj, newObj, path = "") {
  const changes = [];
  const allKeys = new Set([...Object.keys(oldObj), ...Object.keys(newObj)]);

  for (const key of allKeys) {
    const p = path ? `${path}.${key}` : key;
    const oldVal = oldObj[key];
    const newVal = newObj[key];

    if (oldVal === undefined) {
      changes.push({ type: "added", path: p, new: newVal });
    } else if (newVal === undefined) {
      changes.push({ type: "removed", path: p, old: oldVal });
    } else if (typeof oldVal !== typeof newVal) {
      changes.push({ type: "changed", path: p, old: oldVal, new: newVal });
    } else if (Array.isArray(oldVal) && Array.isArray(newVal)) {
      if (JSON.stringify(oldVal) !== JSON.stringify(newVal)) {
        changes.push({ type: "changed", path: p, old: oldVal, new: newVal });
      }
    } else if (typeof oldVal === "object" && oldVal !== null) {
      changes.push(...computeChanges(oldVal, newVal, p));
    } else if (oldVal !== newVal) {
      changes.push({ type: "changed", path: p, old: oldVal, new: newVal });
    }
  }
  return changes;
}

function formatValue(v) {
  if (typeof v === "string") return JSON.stringify(v);
  if (typeof v === "object") return JSON.stringify(v);
  return String(v);
}
