import type { InstantRules } from '@instantdb/react';

// Demo app — fully permissive so every example (todos, tiles, messages,
// file upload) works without auth. Rules are CEL-style string expressions,
// NOT booleans, and are per-namespace/action (not per-attribute).
//
// `$default` covers any namespace/action without an explicit rule; the
// explicit `$files` entry makes storage upload/list/delete work (without it
// uploads fail with `not-has-permission`).
//
// DO NOT ship these rules to production — replace with real auth checks.
const rules = {
  $files: {
    allow: {
      view: 'true',
      create: 'true',
      delete: 'true',
    },
  },
  $default: {
    allow: {
      view: 'true',
      create: 'true',
      update: 'true',
      delete: 'true',
      $default: 'true',
    },
  },
} satisfies InstantRules;

export default rules;
