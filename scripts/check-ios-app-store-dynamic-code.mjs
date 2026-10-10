import { readFileSync, readdirSync, statSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const iosSourcesRoot = path.join(process.cwd(), 'ios', 'Sources');

const runtimeDynamicPatterns = [
  { name: 'NSSelectorFromString', regex: /\bNSSelectorFromString\s*\(/ },
  { name: 'performSelector', regex: /\bperformSelector\s*\(/ },
  { name: 'dlopen', regex: /\bdlopen\s*\(/ },
  { name: 'dlsym', regex: /\bdlsym\s*\(/ },
];

function containsSwiftStringInterpolation(quotedLiteral) {
  return /\\\([^)]*\)/.test(quotedLiteral);
}

function isStaticLookupArgument(expression) {
  const trimmed = expression.trim();
  if (!trimmed) {
    return false;
  }

  if (/^"(?:[^"\\]|\\.)*"$/.test(trimmed)) {
    return !containsSwiftStringInterpolation(trimmed);
  }

  if (!trimmed.startsWith('VisionKitPrivateConstants.')) {
    return false;
  }

  return /^VisionKitPrivateConstants\.[A-Za-z0-9_]+$/.test(trimmed);
}

function findViolationsInCall(contents, callName, argumentExtractor) {
  const violations = [];
  const callRegex = new RegExp(`\\b${callName}\\s*\\(`, 'g');
  let match = callRegex.exec(contents);

  while (match) {
    const openParenIndex = match.index + match[0].length - 1;
    const closeParenIndex = findMatchingParen(contents, openParenIndex);
    if (closeParenIndex === -1) {
      match = callRegex.exec(contents);
      continue;
    }

    const argumentExpression = argumentExtractor(contents, openParenIndex, closeParenIndex);
    if (!isStaticLookupArgument(argumentExpression)) {
      const line = contents.slice(0, match.index).split('\n').length;
      violations.push({ callName, line, argumentExpression: argumentExpression.trim() });
    }

    match = callRegex.exec(contents);
  }

  return violations;
}

function findMatchingParen(contents, openParenIndex) {
  let depth = 0;
  for (let index = openParenIndex; index < contents.length; index += 1) {
    const char = contents[index];
    if (char === '(') {
      depth += 1;
    } else if (char === ')') {
      depth -= 1;
      if (depth === 0) {
        return index;
      }
    }
  }

  return -1;
}

function extractFirstArgument(contents, openParenIndex, closeParenIndex) {
  const inner = contents.slice(openParenIndex + 1, closeParenIndex);
  const commaIndex = findTopLevelComma(inner);
  return commaIndex === -1 ? inner : inner.slice(0, commaIndex);
}

function extractSecondArgument(contents, openParenIndex, closeParenIndex) {
  const inner = contents.slice(openParenIndex + 1, closeParenIndex);
  const commaIndex = findTopLevelComma(inner);
  if (commaIndex === -1) {
    return '';
  }
  return inner.slice(commaIndex + 1);
}

function findTopLevelComma(value) {
  let depth = 0;
  for (let index = 0; index < value.length; index += 1) {
    const char = value[index];
    if (char === '(') {
      depth += 1;
    } else if (char === ')') {
      depth -= 1;
    } else if (char === ',' && depth === 0) {
      return index;
    }
  }
  return -1;
}

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

export function analyzeSwiftSource(contents) {
  const violations = [];

  for (const pattern of runtimeDynamicPatterns) {
    if (pattern.regex.test(contents)) {
      violations.push({ kind: pattern.name, line: null });
    }
  }

  for (const violation of findViolationsInCall(contents, 'NSClassFromString', extractFirstArgument)) {
    violations.push({
      kind: 'NSClassFromString runtime argument',
      line: violation.line,
      detail: violation.argumentExpression,
    });
  }

  const valueForKeyRegex = /\.value\s*\(\s*forKey:/g;
  let valueMatch = valueForKeyRegex.exec(contents);
  while (valueMatch) {
    const openParenIndex = contents.indexOf('(', valueMatch.index);
    const closeParenIndex = findMatchingParen(contents, openParenIndex);
    if (closeParenIndex !== -1) {
      const inner = contents.slice(openParenIndex + 1, closeParenIndex);
      const forKeyMatch = inner.match(/forKey:\s*([^,\)]+)/);
      const argumentExpression = forKeyMatch ? forKeyMatch[1] : inner;
      if (!isStaticLookupArgument(argumentExpression)) {
        const line = contents.slice(0, valueMatch.index).split('\n').length;
        violations.push({
          kind: 'value(forKey:) runtime argument',
          line,
          detail: argumentExpression.trim(),
        });
      }
    }
    valueMatch = valueForKeyRegex.exec(contents);
  }

  for (const violation of findViolationsInCall(
    contents,
    'class_getInstanceVariable',
    extractSecondArgument
  )) {
    violations.push({
      kind: 'class_getInstanceVariable runtime argument',
      line: violation.line,
      detail: violation.argumentExpression,
    });
  }

  return violations;
}

function main() {
  const violations = [];

  for (const filePath of listSwiftFiles(iosSourcesRoot)) {
    const contents = readFileSync(filePath, 'utf8');
    const relativePath = path.relative(process.cwd(), filePath);
    const fileViolations = analyzeSwiftSource(contents);

    for (const violation of fileViolations) {
      const location = violation.line ? `${relativePath}:${violation.line}` : relativePath;
      const detail = violation.detail ? ` (${violation.detail})` : '';
      violations.push(`${location}: ${violation.kind}${detail}`);
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
}

const entryPath = process.argv[1];
if (entryPath && import.meta.url === pathToFileURL(path.resolve(entryPath)).href) {
  main();
}
