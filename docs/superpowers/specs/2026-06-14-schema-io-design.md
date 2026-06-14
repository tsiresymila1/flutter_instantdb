# schema-io — instant.schema.ts ⇆ Dart `@InstantModel` converter

Status: implemented. `bin/schema.dart` shells out to `instant-cli` for pull/push
and now performs the **TS ⇆ Dart conversion** via the pure-Dart converter in
`lib/src/schema/instant_schema_io.dart` (offline `to-dart`/`to-ts` subcommands
plus pull/push wiring; `diff` is a best-effort normalized line diff).

## Goal

- **pull (TS → Dart)**: parse `instant.schema.ts` → emit Dart `@InstantModel`
  classes (the 6b/6d codegen input) → run `build_runner` to get typed tables.
- **push (Dart → TS)**: parse Dart `@InstantModel` classes → emit
  `instant.schema.ts` → `instant-cli push`.
- Plus offline `to-dart` / `to-ts` subcommands (no cloud) for tests + local use.

## Decisions (locked)

- **Dart target = `@InstantModel` classes** (annotated model classes, the codegen
  input). One file with all entity classes + a single `part '<name>.instant.dart'`.
- **Both directions** (pull + push), plus offline convert commands.
- **Coverage**: field types (string/number/boolean/json/date) + modifiers
  (`.optional` / `.unique` / `.indexed`) + links (cardinality → `@InstantLink`).
  Rooms/presence out of scope.
- **`@InstantField` gains `unique`/`indexed` flags** (additive) so Dart→TS
  preserves constraints. The generator ignores them (no codegen/golden impact).
- **Pure Dart, no analyzer dep**: the TS parser and the Dart parser are focused
  hand-written/regex parsers over the constrained DSL / generated-style Dart.

## Existing code facts (verified — trust these)

- **`bin/schema.dart`**: `args`-based CLI. `--schema-file` default
  `lib/schema/app_schema.dart`. `_pullSchema` runs `npx instant-cli@latest pull`
  then TODO-converts; `_pushSchema` expects a hand-written `instant.schema.ts`
  then `push`; `_diffSchema` is a stub. `args` is a root dependency (pubspec).
- **TS DSL** (`example/scripts/instant.schema.ts`):
  `i.schema({ entities: { name: i.entity({ field: i.TYPE().mod().mod(), ... }) },
  links: {...}, rooms: {} })`. Types seen: `i.string()`, `i.number()`,
  `i.boolean()`. Modifiers chain: `.unique()`, `.indexed()`, `.optional()`.
  System entities are `$`-prefixed (`$files`, `$users`).
- **Codegen input shape** (`test/fixtures/sample.dart`): a file with
  `import 'package:flutter_instantdb/flutter_instantdb.dart';`,
  `part 'sample.instant.dart';`, then `@InstantModel('ns') class X { final ...;
  const X({required ...}); }`. `@InstantField('attr')` renames; `@InstantLink()`
  marks relations (cardinality from `List<T>` vs `T`; target must be `@InstantModel`).
- **`@InstantField`** (`lib/src/typed/annotations.dart`): `class InstantField {
  final String name; const InstantField(this.name); }`. The generator reads
  `value.getField('name')` (`instant_generator.dart` `_attrName`) — adding named
  params is backward compatible.
- The generator rejects **non-nullable** unsupported (non-scalar) field types and
  **skips nullable** ones (nested-1). Supported scalars: String/int/double/num/bool.

## Design

### Intermediate model (`lib/src/schema/instant_schema_io.dart`, new)

```dart
class SchemaDef { final List<EntityDef> entities; final List<LinkDef> links; }
class EntityDef {
  final String name;        // InstantDB namespace, e.g. 'todos'
  final String className;   // Dart class, e.g. 'Todo'
  final bool system;        // $-prefixed
  final List<FieldDef> fields;
}
class FieldDef {
  final String name;        // dart field == instant attr
  final String instantType; // 'string'|'number'|'boolean'|'json'|'date'
  final String dartType;    // 'String'|'num'|'bool'|'Map<String, dynamic>'|'DateTime'
  final bool optional, unique, indexed;
  final bool codegenSupported; // false for json/date → emitted nullable+optional
}
class LinkDef {
  final String name;                       // link key, e.g. 'todoOwner'
  final String fromEntity, fromLabel; final bool fromMany;
  final String toEntity, toLabel; final bool toMany;
}
```

### Type mapping (TS ⇆ Dart)

| TS              | Dart                    | notes |
|-----------------|-------------------------|-------|
| `i.string()`    | `String`                | |
| `i.number()`    | `num`                   | int/double/num all → `i.number()` on the way back |
| `i.boolean()`   | `bool`                  | |
| `i.json()`      | `Map<String, dynamic>?` | always nullable + **optional ctor param** (generator skips it) |
| `i.date()`      | `DateTime?`             | always nullable + **optional ctor param** (generator skips it) |
| unknown `i.x()` | `Object?`               | nullable + optional; emit a `// TODO` comment |

- `.optional()` → nullable Dart type + **optional** named ctor param (`this.x`).
  Non-optional supported scalar → non-null + **required** param.
- Every entity gets `final String id` (required). If TS declares
  `id: i.string()...`, use its modifiers; else inject `id` (implicit unique pk,
  not annotated).
- json/date/unknown are ALWAYS optional params so the generated `fromRow` (which
  skips them) still compiles.

### TS → Dart (`parseInstantTs` + `emitDart`)

- `parseInstantTs(String ts) → SchemaDef`: locate `i.schema({...})`; extract the
  `entities:` object and the `links:` object via brace-matching; for each
  `name: i.entity({ ... })` parse `field: i.TYPE()` + chained `.mod()` calls.
  Parse `links: { key: { forward: {on,has,label}, reverse: {on,has,label} } }`.
  `has: 'one'|'many'` → `*Many` booleans. Ignore `rooms`.
- `emitDart(SchemaDef) → String`: a single Dart file —
  `import '...flutter_instantdb.dart';` + `part '<base>.instant.dart';` + one
  class per **non-system** entity. Fields: scalars (with `@InstantField` when
  unique/indexed or attr≠name), then `@InstantLink` relation fields synthesized
  from `links` (forward label on `fromEntity`, reverse label on `toEntity`;
  skip the side that lands on a system entity). Constructor: required params for
  non-optional supported scalars (incl. `id`), optional for the rest.
- **Class naming**: singularize + PascalCase (`todos`→`Todo`, `tiles`→`Tile`,
  `messages`→`Message`, `tags`→`Tag`; `ies`→`y`; else drop trailing `s`).
  `$users`→`User`, `$files`→`File` (used only as link targets). The namespace in
  `@InstantModel('todos')` always preserves the original entity name.
- **System entities** (`$`-prefixed) are NOT emitted as Dart classes; they only
  resolve as link targets.

### Dart → TS (`parseDartModels` + `emitInstantTs`)

- `parseDartModels(String dartSource) → SchemaDef`: focused parser over the
  generated/conventional style — for each `@InstantModel('ns')` + following
  `class X { ... }`, read `final <type> <name>;` declarations and their
  `@InstantField(...)` / `@InstantLink(...)` annotations. Map Dart type → instant
  type (String→string, int/double/num→number, bool→boolean,
  `Map<...>`→json, `DateTime`→date; `List<T>`/`T` with `@InstantLink` → link).
  Nullable (`?`) → `.optional()`. `@InstantField(unique/indexed)` → modifiers;
  `id` → `i.string().unique()` by convention.
- `emitInstantTs(SchemaDef) → String`: emit `import { i } from '@instantdb/react';`
  + `i.schema({ entities: { ... }, links: { ... }, rooms: {} })` +
  `export type AppSchema = typeof schema; export default schema;`. Each entity →
  `name: i.entity({ field: i.type()<mods> })`. Each `@InstantLink` pair → a
  `links` entry; dedupe reciprocal links by (entity-pair + labels); synthesize a
  reverse (`has:'many'`, label = source entity name) when only one side is
  declared. Re-emit `$users`/`$files` only if they appeared in the source TS
  (preserved via a side input) — otherwise omit (instant-cli manages system
  entities).

### CLI wiring (`bin/schema.dart`)

- `pull`: after `instant-cli pull` writes `instant.schema.ts`, read it →
  `parseInstantTs` → `emitDart` → write to `--schema-file` (creating dirs). Print
  next step (`dart run build_runner build`).
- `push`: read `--schema-file` → `parseDartModels` → `emitInstantTs` → write
  `instant.schema.ts` → confirm → `instant-cli push`.
- `to-dart <input.ts>`: offline TS→Dart to `--schema-file` (no cloud/npx).
- `to-ts`: offline Dart(`--schema-file`)→TS to `instant.schema.ts` (no cloud).
- `diff`: parse both sides → `emitInstantTs` for each → textual diff (best-effort).

## Tests (`test/schema_io_test.dart`, pure Dart — no DB)

- Parse `example/scripts/instant.schema.ts` → `SchemaDef`: entity count, fields,
  modifiers; `$`-entities flagged system.
- TS→Dart emit: `todos`→`class Todo` with `String id/text`, `bool completed`,
  `num createdAt`; `.optional()` → nullable+optional param; `i.json()`/`i.date()`
  → nullable optional, skipped-safe.
- Dart→TS emit: a model file → `i.entity({...})` with right types + `.unique()`
  on id + `@InstantField(unique:true)` → `.unique()`.
- Link round-trip: a forward/reverse link → `@InstantLink` on both user-side
  classes; back to a `links` entry (deduped). System-entity link → only the
  user-side `@InstantLink`.
- Round-trip stability: `parseInstantTs → emitDart → parseDartModels →
  emitInstantTs` preserves entities/fields/modifiers (modulo number→num and
  documented link reverse synthesis).
- `@InstantField(unique/indexed)` annotation: generator golden suite still green
  (no fixture uses the new params; additive).

## Risks

- **Link round-trip** is the hardest: forward/reverse pairing + reverse synthesis.
  v1 rule: forward-driven, dedupe reciprocals, synthesize sensible reverses;
  document that hand-tuned link names may change.
- **`i.number()` → `num`**: int/double distinction is lost on import (all → `num`);
  on export int/double/num all collapse to `i.number()`. Documented.
- **Dart parser is regex-based** over the conventional style — documents the
  supported subset (one class per `@InstantModel`, simple `final <type> <name>;`
  fields). Not a general Dart parser (no analyzer dep).
- **System entities** ($-prefixed) are not round-tripped as Dart; preserved only
  if re-emitted from the original TS.

## Next

Optional follow-ups: permissions (`instant.perms.ts`) generation; a real
structural `diff`; analyzer-backed Dart parsing for arbitrary user models.
