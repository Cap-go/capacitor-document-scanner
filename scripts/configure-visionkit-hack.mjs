#!/usr/bin/env node
/**
 * Capacitor hook. Runs before `cap sync` and compiles the private VisionKit
 * swizzle only when plugins.DocumentScanner.iosVisionKitHack is true.
 * The default binary does not contain that swizzle.
 */
import { readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath, pathToFileURL } from 'node:url';

const swiftMarker = String.raw`let visionKitHackEnabled = (true|false)`;
const podspecMarker = String.raw`vision_kit_hack_enabled = (true|false)`;

export function readHackEnabled(configJson) {
  if (!configJson) {
    return false;
  }

  const config = JSON.parse(configJson);
  return config?.plugins?.DocumentScanner?.iosVisionKitHack === true;
}

export function setHackEnabled(source, pattern, enabled) {
  const regex = new RegExp(pattern);
  if (!regex.test(source)) {
    throw new Error(`Missing VisionKit hack marker (${pattern})`);
  }

  return source.replace(new RegExp(pattern), (full) => full.replace(/true|false/, enabled ? 'true' : 'false'));
}

function writeIfChanged(filePath, pattern, enabled) {
  const current = readFileSync(filePath, 'utf8');
  const next = setHackEnabled(current, pattern, enabled);
  if (next !== current) {
    writeFileSync(filePath, next);
  }
}

function main() {
  const args = new Set(process.argv.slice(2));
  let enabled;

  if (args.has('--enable')) {
    enabled = true;
  } else if (args.has('--disable')) {
    enabled = false;
  } else {
    try {
      enabled = readHackEnabled(process.env.CAPACITOR_CONFIG);
    } catch (error) {
      console.error(`[DocumentScanner] Invalid CAPACITOR_CONFIG: ${error.message}`);
      process.exit(1);
    }
  }

  const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
  writeIfChanged(path.join(root, 'Package.swift'), swiftMarker, enabled);
  writeIfChanged(path.join(root, 'CapgoCapacitorDocumentScanner.podspec'), podspecMarker, enabled);
  console.log(`[DocumentScanner] iOS VisionKit hack ${enabled ? 'enabled' : 'disabled'}`);
}

const entryPath = process.argv[1];
if (entryPath && import.meta.url === pathToFileURL(path.resolve(entryPath)).href) {
  main();
}
