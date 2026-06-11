#!/usr/bin/env node
'use strict';

// Masks likely secrets and personal/company data in exported n8n workflow
// JSON files. Runs inside the n8n container, so raw values never need to
// leave it.
//
// - Key-based: masks the "value" of {name, value, ...} pairs (e.g. Set node
//   assignments) whose "name" looks like a credential or personal/company
//   field (name, email, phone, address, ...), as long as the value is a
//   literal (not an n8n expression starting with "=").
// - Pattern-based: masks substrings matching common API key/token formats
//   and email addresses, as a fallback for values not caught by the
//   key-based rule (e.g. an email stored under an unrelated field name).
// - Project owner: n8n exports the workflow owner's "Full Name <email>" in
//   shared[].project.name for personal projects. That whole field is masked
//   so the owner's name isn't leaked alongside the (already pattern-masked)
//   email.
//
// The "name" of each masked field stays in the file, so re-importing the
// workflow makes it obvious which "*******" values need to be filled in again.
//
// Usage: node redact_workflow.js <input_dir> <output_dir>
// Prints a JSON report array to stdout, one entry per processed file.

const fs = require('fs');
const path = require('path');

const MASK = '*******';

// Covers both English and Portuguese field names. Most pt/en pairs share a
// substring (e.g. "name"/"sobrenome", "address"/"endereco"), so only the
// terms below need to be listed explicitly.
const SENSITIVE_KEY_RE = /(api[_-]?key|apikey|token|secret|password|passwd|access[_-]?key|client[_-]?secret|private[_-]?key|authorization|bearer|nome|name|e-?mail|telefone|celular|whatsapp|phone|fax|cpf|cnpj|endereco|address|empresa|company|cliente|customer|razao[_-]?social|nascimento|birth(date)?|\bidade\b|\bage\b)/i;

const SENSITIVE_VALUE_RE = new RegExp(
    [
        'cal_(live|test)_[A-Za-z0-9]+',
        'sk_(live|test)_[A-Za-z0-9]+',
        'pk_(live|test)_[A-Za-z0-9]+',
        'gh[pousr]_[A-Za-z0-9]{20,}',
        'github_pat_[A-Za-z0-9_]+',
        'xox[baprs]-[A-Za-z0-9-]+',
        'AKIA[A-Z0-9]{16}',
        'AIza[A-Za-z0-9_-]{35}',
        'eyJ[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]*',
        '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,}',
    ].join('|'),
    'g'
);

function isLiteralSecretField(node) {
    return (
        node !== null &&
        typeof node === 'object' &&
        !Array.isArray(node) &&
        typeof node.name === 'string' &&
        typeof node.value === 'string' &&
        node.value !== '' &&
        !node.value.startsWith('=') &&
        SENSITIVE_KEY_RE.test(node.name)
    );
}

function isPersonalProjectName(node) {
    return (
        node.type === 'personal' &&
        typeof node.name === 'string' &&
        node.name !== '' &&
        node.name !== MASK
    );
}

function redactByKey(node, redactedNames) {
    if (Array.isArray(node)) {
        node.forEach((item) => redactByKey(item, redactedNames));
        return;
    }
    if (node !== null && typeof node === 'object') {
        if (isLiteralSecretField(node)) {
            redactedNames.add(node.name);
            node.value = MASK;
        }
        if (isPersonalProjectName(node)) {
            redactedNames.add('project.name (workflow owner)');
            node.name = MASK;
        }
        Object.values(node).forEach((value) => redactByKey(value, redactedNames));
    }
}

function redactByPattern(node, counter) {
    if (Array.isArray(node)) {
        node.forEach((item, index) => {
            if (typeof item === 'string') {
                node[index] = maskString(item, counter);
            } else {
                redactByPattern(item, counter);
            }
        });
        return;
    }
    if (node !== null && typeof node === 'object') {
        for (const key of Object.keys(node)) {
            const value = node[key];
            if (typeof value === 'string') {
                node[key] = maskString(value, counter);
            } else {
                redactByPattern(value, counter);
            }
        }
    }
}

function maskString(value, counter) {
    const matches = value.match(SENSITIVE_VALUE_RE);
    if (!matches) return value;
    counter.count += matches.length;
    return value.replace(SENSITIVE_VALUE_RE, MASK);
}

const [, , inputDir, outputDir] = process.argv;

if (!inputDir || !outputDir) {
    console.error('Usage: node redact_workflow.js <input_dir> <output_dir>');
    process.exit(1);
}

fs.mkdirSync(outputDir, { recursive: true });

const report = [];

for (const file of fs.readdirSync(inputDir)) {
    if (!file.endsWith('.json')) continue;

    const data = JSON.parse(fs.readFileSync(path.join(inputDir, file), 'utf8'));

    const redactedNames = new Set();
    redactByKey(data, redactedNames);

    const counter = { count: 0 };
    redactByPattern(data, counter);

    fs.writeFileSync(path.join(outputDir, file), JSON.stringify(data, null, 2));

    report.push({
        file,
        name: data.name,
        id: data.id,
        isArchived: !!data.isArchived,
        redactedKeys: [...redactedNames],
        patternMatches: counter.count,
    });
}

process.stdout.write(JSON.stringify(report));
