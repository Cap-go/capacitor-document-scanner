import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';
import { readSwizzleEnabled, setSwizzleEnabled } from './configure-visionkit-swizzle.mjs';

const swiftMarker = String.raw`let visionKitSwizzleEnabled = (true|false)`;
const podspecMarker = String.raw`vision_kit_swizzle_enabled = (true|false)`;

test('iosVisionKitSwizzle defaults off', () => {
  assert.equal(readSwizzleEnabled(undefined), false);
  assert.equal(readSwizzleEnabled('{"plugins":{"DocumentScanner":{}}}'), false);
  assert.equal(
    readSwizzleEnabled('{"plugins":{"DocumentScanner":{"iosVisionKitSwizzle":false}}}'),
    false,
  );
  assert.equal(
    readSwizzleEnabled('{"plugins":{"DocumentScanner":{"iosVisionKitSwizzle":true}}}'),
    true,
  );
});

test('manifest markers flip without touching surrounding text', () => {
  const source = 'before\nlet visionKitSwizzleEnabled = false\nafter\n';
  const enabled = setSwizzleEnabled(source, swiftMarker, true);
  assert.equal(enabled, 'before\nlet visionKitSwizzleEnabled = true\nafter\n');
  assert.equal(setSwizzleEnabled(enabled, swiftMarker, false), source);
});

test('published manifests keep the VisionKit swizzle disabled', () => {
  const packageSwift = readFileSync(new URL('../Package.swift', import.meta.url), 'utf8');
  const podspec = readFileSync(new URL('../CapgoCapacitorDocumentScanner.podspec', import.meta.url), 'utf8');

  assert.match(packageSwift, /let visionKitSwizzleEnabled = false/);
  assert.equal(packageSwift.match(/swiftSettings: visionKitSwizzleSwiftSettings/g)?.length, 2);
  assert.match(podspec, /vision_kit_swizzle_enabled = false/);
  assert.doesNotMatch(packageSwift, /let visionKitSwizzleEnabled = true/);
  assert.equal(setSwizzleEnabled(podspec, podspecMarker, false), podspec);
});
