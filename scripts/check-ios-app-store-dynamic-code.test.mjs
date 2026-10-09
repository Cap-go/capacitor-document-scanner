import assert from 'node:assert/strict';
import test from 'node:test';
import { analyzeSwiftSource } from './check-ios-app-store-dynamic-code.mjs';

test('allows static VisionKit private constants', () => {
  const source = `
    NSClassFromString(VisionKitPrivateConstants.inProcessViewControllerClassName)
    gestureRecognizer.value(forKey: VisionKitPrivateConstants.gestureRecognizerTargetsKey)
    class_getInstanceVariable(targetClass, VisionKitPrivateConstants.gestureTargetIvarName)
  `;

  assert.equal(analyzeSwiftSource(source).length, 0);
});

test('flags runtime-built lookup arguments', () => {
  const source = `
    NSClassFromString(prefix + suffix)
    NSClassFromString("Prefix\\(suffix)")
    gestureRecognizer.value(forKey: makeKey())
    class_getInstanceVariable(targetClass, makeIvarName())
    NSSelectorFromString("foo")
  `;

  const violations = analyzeSwiftSource(source);
  assert.ok(violations.some((item) => item.kind === 'NSSelectorFromString'));
  assert.ok(
    violations.filter((item) => item.kind === 'NSClassFromString runtime argument').length >= 2
  );
  assert.ok(violations.some((item) => item.kind === 'value(forKey:) runtime argument'));
  assert.ok(violations.some((item) => item.kind === 'class_getInstanceVariable runtime argument'));
});
