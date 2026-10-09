import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';

const iosSourcesRoot = path.join(process.cwd(), 'ios', 'Sources');

const runtimeDynamicPatterns = [
  { name: 'NSSelectorFromString', regex: /\bNSSelectorFromString\s*\(/ },
  { name: 'performSelector', regex: /\bperformSelector\s*\(/ },
  { name: 'dlopen', regex: /\bdlopen\s*\(/ },
  { name: 'dlsym', regex: /\bdlsym\s*\(/ },
  { name: 'NSClassFromString string literal', regex: /\bNSClassFromString\s*\(\s*"/ },
  {
    name: 'value(forKey:) string literal',
    regex: /\.value\s*\(\s*forKey:\s*"/,
  },
  {
    name: 'class_getInstanceVariable string literal',
    regex: /\bclass_getInstanceVariable\s*\([^,]+,\s*"/,
  },
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

  for (const pattern of runtimeDynamicPatterns) {
    if (pattern.regex.test(contents)) {
      violations.push(`${relativePath}: ${pattern.name}`);
    }
  }
}

if (violations.length > 0) {
  console.error('Runtime-built iOS dynamic dispatch detected (use static constants):');
  for (const violation of violations) {
    console.error(`  - ${violation}`);
  }
  process.exit(1);
}

console.log('iOS App Store dynamic code check passed.');
