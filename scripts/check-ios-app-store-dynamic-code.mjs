import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const iosSourcesRoot = path.join(process.cwd(), 'ios', 'Sources');
const forbiddenPatterns = [
  { name: 'NSSelectorFromString', regex: /\bNSSelectorFromString\b/ },
  { name: 'performSelector', regex: /\bperformSelector\b/ },
  { name: 'NSClassFromString', regex: /\bNSClassFromString\b/ },
  { name: 'method_exchangeImplementations', regex: /\bmethod_exchangeImplementations\b/ },
  { name: 'class_addMethod', regex: /\bclass_addMethod\b/ },
  { name: 'class_getInstanceMethod', regex: /\bclass_getInstanceMethod\b/ },
  { name: 'dlopen', regex: /\bdlopen\b/ },
  { name: 'dlsym', regex: /\bdlsym\b/ },
  { name: 'KVC _targets', regex: /value\s*\(\s*forKey:\s*"_targets"\s*\)/ },
];

function listSwiftFiles(directory) {
  const entries = readdirSync(directory);
  const files = [];

  for (const entry of entries) {
    const fullPath = path.join(directory, entry);
    const stats = statSync(fullPath);
    if (stats.isDirectory()) {
      files.push(...listSwiftFiles(fullPath));
      continue;
    }

    if (fullPath.endsWith('.swift')) {
      files.push(fullPath);
    }
  }

  return files;
}

const violations = [];

for (const filePath of listSwiftFiles(iosSourcesRoot)) {
  const contents = readFileSync(filePath, 'utf8');
  const relativePath = path.relative(process.cwd(), filePath);

  for (const pattern of forbiddenPatterns) {
    if (pattern.regex.test(contents)) {
      violations.push(`${relativePath}: ${pattern.name}`);
    }
  }
}

if (violations.length > 0) {
  console.error('Forbidden iOS dynamic/private APIs detected:');
  for (const violation of violations) {
    console.error(`  - ${violation}`);
  }
  process.exit(1);
}

console.log('iOS App Store dynamic code check passed.');
