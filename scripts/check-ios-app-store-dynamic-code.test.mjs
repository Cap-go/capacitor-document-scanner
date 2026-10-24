import assert from 'node:assert/strict';
import test from 'node:test';
import {
  analyzeDefaultBinary,
  analyzeHackBranch,
  analyzeSwiftSource,
} from './check-ios-app-store-dynamic-code.mjs';

test('keeps the private VisionKit swizzle out of the default binary', () => {
  const source = `
#if CAPGO_DOCUMENT_SCANNER_VISIONKIT_HACK
    NSClassFromString(VisionKitPrivateConstants.inProcessViewControllerClassName)
    method_exchangeImplementations(originalMethod, swizzledMethod)
    gestureRecognizer.value(forKey: VisionKitPrivateConstants.gestureRecognizerTargetsKey)
    class_getInstanceVariable(targetClass, VisionKitPrivateConstants.gestureTargetIvarName)
#else
    let publicScan = VNDocumentCameraViewController()
#endif
  `;

  assert.equal(analyzeDefaultBinary(source).length, 0);
  assert.equal(analyzeHackBranch(source).length, 0);
});

test('rejects private lookup symbols when they ship in the default binary', () => {
  const source = `
    NSClassFromString(VisionKitPrivateConstants.inProcessViewControllerClassName)
    method_exchangeImplementations(originalMethod, swizzledMethod)
  `;

  const violations = analyzeDefaultBinary(source);
  assert.ok(violations.some((item) => item.kind === 'default binary contains NSClassFromString'));
  assert.ok(violations.some((item) => item.kind === 'default binary contains method_exchangeImplementations'));
});

test('rejects bare identifier lookup arguments', () => {
  const source = `
    NSClassFromString(dynamicClassName)
    gestureRecognizer.value(forKey: targetsKey)
  `;

  const violations = analyzeSwiftSource(source);
  assert.ok(violations.some((item) => item.kind === 'NSClassFromString runtime argument'));
  assert.ok(violations.some((item) => item.kind === 'value(forKey:) runtime argument'));
});

test('flags runtime-built lookup arguments inside the opt-in hack', () => {
  const source = `
#if CAPGO_DOCUMENT_SCANNER_VISIONKIT_HACK
    NSClassFromString(prefix + suffix)
    NSClassFromString("Prefix\\(suffix)")
    gestureRecognizer.value(forKey: makeKey())
    class_getInstanceVariable(targetClass, makeIvarName())
    NSSelectorFromString("foo")
#else
    let publicScan = VNDocumentCameraViewController()
#endif
  `;

  const violations = analyzeHackBranch(source);
  assert.ok(violations.some((item) => item.kind === 'NSSelectorFromString'));
  assert.ok(
    violations.filter((item) => item.kind === 'NSClassFromString runtime argument').length >= 2,
  );
  assert.ok(violations.some((item) => item.kind === 'value(forKey:) runtime argument'));
  assert.ok(violations.some((item) => item.kind === 'class_getInstanceVariable runtime argument'));
  assert.equal(analyzeDefaultBinary(source).length, 0);
});
