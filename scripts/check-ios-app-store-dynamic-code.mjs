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

const visionKitHackCondition = 'CAPGO_DOCUMENT_SCANNER_VISIONKIT_HACK';

const defaultBinaryBannedPatterns = [
  { name: 'method_exchangeImplementations', regex: /\bmethod_exchangeImplementations\s*\(/ },
  { name: 'NSClassFromString', regex: /\bNSClassFromString\s*\(/ },
  { name: 'class_getInstanceVariable', regex: /\bclass_getInstanceVariable\s*\(/ },
  { name: 'object_getIvar', regex: /\bobject_getIvar\s*\(/ },
  { name: 'ivar_getOffset', regex: /\bivar_getOffset\s*\(/ },
  { name: 'VNDocumentCameraViewController_InProcess', regex: /VNDocumentCameraViewController_InProcess/ },
  { name: 'documentCameraController:canAddImages:', regex: /documentCameraController:canAddImages:/ },
  { name: 'ICDocCamThumbnailContainerView', regex: /ICDocCamThumbnailContainerView/ },
  { name: 'private gesture target key', regex: /"_targets"|"_target"|"_action"/ },
];

export function splitVisionKitHack(contents) {
  const needle = `#if ${visionKitHackCondition}`;
  let defaultSource = '';
  let hackSource = '';
  let index = 0;
  let error = null;

  while (index < contents.length) {
    const ifAt = contents.indexOf(needle, index);
    if (ifAt === -1) {
      defaultSource += contents.slice(index);
      break;
    }

    defaultSource += contents.slice(index, ifAt);
    const elseAt = contents.indexOf('\n#else', ifAt);
    const endAt = contents.indexOf('\n#endif', ifAt);
    if (elseAt === -1 || endAt === -1 || elseAt > endAt) {
      error = `Malformed #if ${visionKitHackCondition}`;
      defaultSource += contents.slice(ifAt);
      break;
    }

    hackSource += contents.slice(ifAt + needle.length, elseAt);
    const elseBodyStart = elseAt + '\n#else'.length;
    const elseNewline = contents.indexOf('\n', elseBodyStart);
    const elseContentStart = elseNewline === -1 ? contents.length : elseNewline + 1;
    defaultSource += contents.slice(elseContentStart, endAt);
    const endLineEnd = contents.indexOf('\n', endAt + '\n#endif'.length);
    index = endLineEnd === -1 ? contents.length : endLineEnd + 1;
  }

  return { defaultSource, hackSource, error };
}

export function analyzeDefaultBinary(contents) {
  const split = splitVisionKitHack(contents);
  const violations = analyzeSwiftSource(split.defaultSource);

  if (split.error) {
    violations.push({ kind: split.error, line: null });
  }

  for (const pattern of defaultBinaryBannedPatterns) {
    if (pattern.regex.test(split.defaultSource)) {
      violations.push({
        kind: `default binary contains ${pattern.name}`,
        line: null,
      });
    }
  }

  return violations;
}

export function analyzeHackBranch(contents) {
  const split = splitVisionKitHack(contents);
  return analyzeSwiftSource(split.hackSource);
}

function formatViolation(relativePath, violation) {
  const location = violation.line ? `${relativePath}:${violation.line}` : relativePath;
  const detail = violation.detail ? ` (${violation.detail})` : '';
  return `${location}: ${violation.kind}${detail}`;
}

function main() {
  const violations = [];
  let hackSource = '';

  for (const filePath of listSwiftFiles(iosSourcesRoot)) {
    const contents = readFileSync(filePath, 'utf8');
    const relativePath = path.relative(process.cwd(), filePath);
    hackSource += splitVisionKitHack(contents).hackSource;

    for (const violation of analyzeDefaultBinary(contents)) {
      violations.push(formatViolation(relativePath, violation));
    }

    for (const violation of analyzeHackBranch(contents)) {
      violations.push(formatViolation(`${relativePath} (opt-in hack)`, violation));
    }
  }

  if (!/\bmethod_exchangeImplementations\s*\(/.test(hackSource)) {
    violations.push('ios/Sources: opt-in VisionKit hack is missing method_exchangeImplementations');
  }

  if (violations.length > 0) {
    console.error('iOS App Store dynamic code check failed:');
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
