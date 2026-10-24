import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { readHackEnabled, setHackEnabled } from './configure-visionkit-hack.mjs';

const swiftMarker = String.raw`let visionKitHackEnabled = (true|false)`;
const podspecMarker = String.raw`vision_kit_hack_enabled = (true|false)`;

test('iosVisionKitHack defaults off', () => {
  assert.equal(readHackEnabled(undefined), false);
  assert.equal(readHackEnabled('{"plugins":{"DocumentScanner":{}}}'), false);
  assert.equal(
    readHackEnabled('{"plugins":{"DocumentScanner":{"iosVisionKitHack":false}}}'),
    false,
  );
  assert.equal(
    readHackEnabled('{"plugins":{"DocumentScanner":{"iosVisionKitHack":true}}}'),
    true,
  );
});

test('manifest markers flip without touching surrounding text', () => {
  const source = 'before\nlet visionKitHackEnabled = false\nafter\n';
  const enabled = setHackEnabled(source, swiftMarker, true);
  assert.equal(enabled, 'before\nlet visionKitHackEnabled = true\nafter\n');
  assert.equal(setHackEnabled(enabled, swiftMarker, false), source);
});

test('published manifests keep the VisionKit hack disabled', () => {
  const packageSwift = readFileSync(new URL('../Package.swift', import.meta.url), 'utf8');
  const podspec = readFileSync(new URL('../CapgoCapacitorDocumentScanner.podspec', import.meta.url), 'utf8');

  assert.match(packageSwift, /let visionKitHackEnabled = false/);
  assert.match(podspec, /vision_kit_hack_enabled = false/);
  assert.doesNotMatch(packageSwift, /let visionKitHackEnabled = true/);
  assert.equal(setHackEnabled(podspec, podspecMarker, false), podspec);
});
