/// Pure-Dart converter between `instant.schema.ts` and Dart `@InstantModel`
/// classes.
///
/// No analyzer, no new dependencies — both parsers are focused, hand-written
/// scanners over the constrained InstantDB `i.schema({...})` DSL and the
/// conventional `@InstantModel` Dart style (one class per model, simple
/// `final <type> <name>;` fields).
///
/// See `docs/superpowers/specs/2026-06-14-schema-io-design.md` for the rules.
library;

// ============================================================================
// Intermediate model
// ============================================================================

/// A parsed schema: a set of entities and the links between them.
class SchemaDef {
  final List<EntityDef> entities;
  final List<LinkDef> links;
  const SchemaDef({required this.entities, required this.links});
}

/// One entity (InstantDB namespace / Dart class).
class EntityDef {
  /// InstantDB namespace, e.g. `todos` (or `$users` for system entities).
  final String name;

  /// Dart class name, e.g. `Todo`.
  final String className;

  /// True for `$`-prefixed system entities (not emitted as Dart classes).
  final bool system;

  final List<FieldDef> fields;

  const EntityDef({
    required this.name,
    required this.className,
    required this.system,
    required this.fields,
  });
}

/// A scalar field on an entity. Dart field name == InstantDB attribute name.
class FieldDef {
  final String name;

  /// `'string' | 'number' | 'boolean' | 'json' | 'date' | 'unknown'`.
  final String instantType;

  /// Dart type without trailing `?`, e.g. `String`, `num`, `bool`,
  /// `Map<String, dynamic>`, `DateTime`, `Object`.
  final String dartType;

  final bool optional;
  final bool unique;
  final bool indexed;

  /// False for json/date/unknown — emitted nullable + optional so the
  /// generated `fromRow` (which skips them) still compiles.
  final bool codegenSupported;

  const FieldDef({
    required this.name,
    required this.instantType,
    required this.dartType,
    required this.optional,
    required this.unique,
    required this.indexed,
    required this.codegenSupported,
  });

  /// Whether the emitted Dart type is nullable.
  bool get nullable => optional || !codegenSupported;

  /// Whether the constructor param is required.
  bool get required => !nullable;
}

/// A link (relation) between two entities.
class LinkDef {
  final String name;
  final String fromEntity;
  final String fromLabel;
  final bool fromMany;
  final String toEntity;
  final String toLabel;
  final bool toMany;

  const LinkDef({
    required this.name,
    required this.fromEntity,
    required this.fromLabel,
    required this.fromMany,
    required this.toEntity,
    required this.toLabel,
    required this.toMany,
  });
}

// ============================================================================
// Type mapping
// ============================================================================

const _tsToDart = {
  'string': 'String',
  'number': 'num',
  'boolean': 'bool',
  'json': 'Map<String, dynamic>',
  'date': 'DateTime',
};

bool _isCodegenSupported(String instantType) =>
    instantType == 'string' ||
    instantType == 'number' ||
    instantType == 'boolean';

String _dartTypeFor(String instantType) =>
    _tsToDart[instantType] ?? 'Object';

// ============================================================================
// Naming helpers
// ============================================================================

/// Class name from an InstantDB namespace: singularize + PascalCase.
/// `todos`->`Todo`, `tiles`->`Tile`, `messages`->`Message`, `tags`->`Tag`,
/// `categories`->`Category`; `$users`->`User`, `$files`->`File`.
String classNameFor(String entityName) {
  var name = entityName;
  if (name.startsWith(r'$')) name = name.substring(1);
  final singular = _singularize(name);
  return _pascalCase(singular);
}

String _singularize(String word) {
  if (word.isEmpty) return word;
  if (word.endsWith('ies') && word.length > 3) {
    return '${word.substring(0, word.length - 3)}y';
  }
  if (word.endsWith('ses') || word.endsWith('xes') || word.endsWith('zes') ||
      word.endsWith('ches') || word.endsWith('shes')) {
    return word.substring(0, word.length - 2);
  }
  if (word.endsWith('s') && word.length > 1) {
    return word.substring(0, word.length - 1);
  }
  return word;
}

String _pascalCase(String word) {
  final parts = word.split(RegExp(r'[_\s-]+')).where((p) => p.isNotEmpty);
  return parts
      .map((p) => p[0].toUpperCase() + p.substring(1))
      .join();
}

// ============================================================================
// TS -> SchemaDef  (parseInstantTs)
// ============================================================================

/// Parse an `instant.schema.ts` source into a [SchemaDef].
SchemaDef parseInstantTs(String ts) {
  final schemaBody = _extractCallBody(ts, 'i.schema');
  if (schemaBody == null) {
    return const SchemaDef(entities: [], links: []);
  }

  final entitiesObj = _extractObjectValue(schemaBody, 'entities');
  final linksObj = _extractObjectValue(schemaBody, 'links');

  final entities = <EntityDef>[];
  if (entitiesObj != null) {
    for (final entry in _topLevelEntries(entitiesObj)) {
      final entityName = _unquote(entry.key);
      final body = _extractCallBody(entry.value, 'i.entity');
      if (body == null) continue;
      entities.add(_parseEntity(entityName, body));
    }
  }

  final links = <LinkDef>[];
  if (linksObj != null) {
    for (final entry in _topLevelEntries(linksObj)) {
      final link = _parseLink(_unquote(entry.key), entry.value);
      if (link != null) links.add(link);
    }
  }

  return SchemaDef(entities: entities, links: links);
}

EntityDef _parseEntity(String name, String body) {
  final fields = <FieldDef>[];
  for (final entry in _topLevelEntries(body)) {
    final fieldName = _unquote(entry.key);
    final field = _parseField(fieldName, entry.value);
    if (field != null) fields.add(field);
  }
  return EntityDef(
    name: name,
    className: classNameFor(name),
    system: name.startsWith(r'$'),
    fields: fields,
  );
}

FieldDef? _parseField(String name, String value) {
  // value like: i.string().unique().indexed().optional()
  final typeMatch = RegExp(r'i\.(\w+)\s*\(').firstMatch(value);
  if (typeMatch == null) return null;
  final instantType = typeMatch.group(1)!;
  final mods = value;
  return FieldDef(
    name: name,
    instantType: instantType,
    dartType: _dartTypeFor(instantType),
    optional: mods.contains('.optional('),
    unique: mods.contains('.unique('),
    indexed: mods.contains('.indexed('),
    codegenSupported: _isCodegenSupported(instantType),
  );
}

LinkDef? _parseLink(String name, String value) {
  final body = _stripOuterBraces(value);
  final forward = _extractObjectValue(body, 'forward');
  final reverse = _extractObjectValue(body, 'reverse');
  if (forward == null || reverse == null) return null;

  String? on(String obj) =>
      _stringProp(obj, 'on') ?? _stringProp(obj, 'entity');
  String? label(String obj) => _stringProp(obj, 'label');
  bool many(String obj) {
    final has = _stringProp(obj, 'has');
    return has == 'many';
  }

  final fromEntity = on(forward);
  final toEntity = on(reverse);
  if (fromEntity == null || toEntity == null) return null;

  return LinkDef(
    name: name,
    fromEntity: fromEntity,
    fromLabel: label(forward) ?? toEntity,
    fromMany: many(forward),
    toEntity: toEntity,
    toLabel: label(reverse) ?? fromEntity,
    toMany: many(reverse),
  );
}

// ============================================================================
// SchemaDef -> Dart  (emitDart)
// ============================================================================

/// Emit a single Dart file of `@InstantModel` classes from a [SchemaDef].
String emitDart(SchemaDef schema, {String partBase = 'app_schema'}) {
  final entitiesByName = {for (final e in schema.entities) e.name: e};

  // Guard against silent class-name collisions (e.g. `status` + `stats` both
  // singularize to `Stat`). Two classes with the same name would be a confusing
  // Dart compile error downstream — fail loudly here instead.
  final seenClass = <String, String>{};
  for (final e in schema.entities) {
    if (e.system) continue;
    final prior = seenClass[e.className];
    if (prior != null) {
      throw ArgumentError(
        'Entities "$prior" and "${e.name}" both map to class '
        '"${e.className}". Rename one entity.',
      );
    }
    seenClass[e.className] = e.name;
  }
  // Collect link fields per (user-side) entity.
  final linkFields = <String, List<_LinkFieldEmit>>{};
  for (final link in schema.links) {
    final fromSys = _isSystem(link.fromEntity, entitiesByName);
    final toSys = _isSystem(link.toEntity, entitiesByName);

    // Forward field lives on fromEntity, points at toEntity. Its cardinality
    // is the forward `has` (fromMany): has:'one' -> T?, has:'many' -> List<T>.
    if (!fromSys) {
      linkFields.putIfAbsent(link.fromEntity, () => []).add(
            _LinkFieldEmit(
              label: link.fromLabel,
              targetClass: classNameFor(link.toEntity),
              many: link.fromMany,
            ),
          );
    }
    // Reverse field lives on toEntity, points at fromEntity. Cardinality is the
    // reverse `has` (toMany).
    if (!toSys) {
      linkFields.putIfAbsent(link.toEntity, () => []).add(
            _LinkFieldEmit(
              label: link.toLabel,
              targetClass: classNameFor(link.fromEntity),
              many: link.toMany,
            ),
          );
    }
  }

  final buf = StringBuffer();
  buf.writeln('// Generated from instant.schema.ts by '
      '`dart run flutter_instantdb:schema`.');
  buf.writeln('// Note: i.number() maps to `num` (the int/double distinction is '
      'not in the');
  buf.writeln('// InstantDB schema) — narrow a field to `int`/`double` by hand '
      'if you need it.');
  buf.writeln(
      "import 'package:flutter_instantdb/flutter_instantdb.dart';");
  buf.writeln();
  buf.writeln("part '$partBase.instant.dart';");

  for (final entity in schema.entities) {
    if (entity.system) continue;
    buf.writeln();
    buf.write(_emitClass(entity, linkFields[entity.name] ?? const []));
  }

  return buf.toString();
}

bool _isSystem(String entityName, Map<String, EntityDef> byName) {
  if (entityName.startsWith(r'$')) return true;
  final e = byName[entityName];
  return e?.system ?? false;
}

String _emitClass(EntityDef entity, List<_LinkFieldEmit> links) {
  final fields = _fieldsWithId(entity);
  final buf = StringBuffer();
  buf.writeln("@InstantModel('${entity.name}')");
  buf.writeln('class ${entity.className} {');

  // Scalar fields.
  for (final f in fields) {
    final ann = _fieldAnnotation(f);
    if (ann != null) buf.writeln('  $ann');
    final nullable = f.nullable ? '?' : '';
    buf.writeln('  final ${f.dartType}$nullable ${f.name};');
  }

  // Link fields.
  for (final l in links) {
    buf.writeln('  @InstantLink()');
    if (l.many) {
      buf.writeln('  final List<${l.targetClass}> ${l.label};');
    } else {
      buf.writeln('  final ${l.targetClass}? ${l.label};');
    }
  }

  // Constructor.
  buf.writeln('  const ${entity.className}({');
  for (final f in fields) {
    if (f.required) {
      buf.writeln('    required this.${f.name},');
    } else {
      buf.writeln('    this.${f.name},');
    }
  }
  for (final l in links) {
    if (l.many) {
      buf.writeln('    this.${l.label} = const [],');
    } else {
      buf.writeln('    this.${l.label},');
    }
  }
  buf.writeln('  });');
  buf.writeln('}');
  return buf.toString();
}

/// Ensure an `id` field exists (required, String). If the entity declares one,
/// keep its modifiers; otherwise inject an implicit pk.
List<FieldDef> _fieldsWithId(EntityDef entity) {
  final hasId = entity.fields.any((f) => f.name == 'id');
  if (hasId) {
    // Move id to front, keep order otherwise.
    final id = entity.fields.firstWhere((f) => f.name == 'id');
    final rest = entity.fields.where((f) => f.name != 'id');
    return [id, ...rest];
  }
  return [
    const FieldDef(
      name: 'id',
      instantType: 'string',
      dartType: 'String',
      optional: false,
      unique: true,
      indexed: false,
      codegenSupported: true,
    ),
    ...entity.fields,
  ];
}

/// `@InstantField(...)` annotation string, or null when not needed.
/// id is never annotated (implicit pk).
String? _fieldAnnotation(FieldDef f) {
  if (f.name == 'id') return null;
  if (!f.unique && !f.indexed) return null;
  final parts = <String>["'${f.name}'"];
  if (f.unique) parts.add('unique: true');
  if (f.indexed) parts.add('indexed: true');
  return '@InstantField(${parts.join(', ')})';
}

class _LinkFieldEmit {
  final String label;
  final String targetClass;
  final bool many;
  _LinkFieldEmit({
    required this.label,
    required this.targetClass,
    required this.many,
  });
}

// ============================================================================
// Dart -> SchemaDef  (parseDartModels)
// ============================================================================

const _dartToInstant = {
  'String': 'string',
  'int': 'number',
  'double': 'number',
  'num': 'number',
  'bool': 'boolean',
  'DateTime': 'date',
};

/// Parse a Dart source file of `@InstantModel` classes into a [SchemaDef].
///
/// Supported subset: one `@InstantModel('ns')` per class, simple
/// `final <type> <name>;` fields, optional `@InstantField(...)` /
/// `@InstantLink(...)` annotations on the field above.
SchemaDef parseDartModels(String dartSource) {
  final entities = <EntityDef>[];
  // Map className -> namespace, for resolving link targets.
  final classToName = <String, String>{};

  final modelRe = RegExp(r"@InstantModel\(\s*'([^']*)'\s*\)");
  // Pre-pass: collect class->namespace.
  for (final m in modelRe.allMatches(dartSource)) {
    final ns = m.group(1)!;
    final after = dartSource.substring(m.end);
    final classMatch =
        RegExp(r'class\s+(\w+)').firstMatch(after);
    if (classMatch != null) {
      classToName[classMatch.group(1)!] = ns;
    }
  }

  // Track link fields keyed by owning entity for later pairing.
  final rawLinks = <_RawLink>[];

  for (final m in modelRe.allMatches(dartSource)) {
    final ns = m.group(1)!;
    final after = dartSource.substring(m.end);
    final classMatch = RegExp(r'class\s+(\w+)').firstMatch(after);
    if (classMatch == null) continue;
    final className = classMatch.group(1)!;

    // Find class body braces.
    final braceStart = after.indexOf('{', classMatch.end);
    if (braceStart < 0) continue;
    final braceEnd = _matchBrace(after, braceStart);
    if (braceEnd < 0) continue;
    final body = after.substring(braceStart + 1, braceEnd);

    final fields = <FieldDef>[];
    _parseDartFields(
      body,
      ownerEntity: ns,
      ownerClass: className,
      classToName: classToName,
      fields: fields,
      rawLinks: rawLinks,
    );

    entities.add(EntityDef(
      name: ns,
      className: className,
      system: ns.startsWith(r'$'),
      fields: fields,
    ));
  }

  final links = _pairDartLinks(rawLinks, classToName);
  return SchemaDef(entities: entities, links: links);
}

class _RawLink {
  final String ownerEntity;
  final String label;
  final String targetEntity; // resolved namespace
  final bool many;
  _RawLink({
    required this.ownerEntity,
    required this.label,
    required this.targetEntity,
    required this.many,
  });
}

void _parseDartFields(
  String body, {
  required String ownerEntity,
  required String ownerClass,
  required Map<String, String> classToName,
  required List<FieldDef> fields,
  required List<_RawLink> rawLinks,
}) {
  // Field declaration with optional preceding annotations on the same/prior
  // line(s): match `final <type> <name>;` and look back for annotations.
  final fieldRe = RegExp(
    r'final\s+([\w<>,\s]+?)([?])?\s+(\w+)\s*;',
  );

  for (final fm in fieldRe.allMatches(body)) {
    final rawType = fm.group(1)!.trim();
    final nullable = fm.group(2) == '?';
    final fieldName = fm.group(3)!;

    // Look back for annotations immediately preceding this field.
    final preceding = body.substring(0, fm.start);
    final fieldAnn = _lastFieldAnnotation(preceding);
    final isLink = _hasLinkAnnotation(preceding);

    if (isLink) {
      final (targetClass, many) = _linkTarget(rawType);
      final targetNs = classToName[targetClass] ?? targetClass;
      rawLinks.add(_RawLink(
        ownerEntity: ownerEntity,
        label: fieldName,
        targetEntity: targetNs,
        many: many,
      ));
      continue;
    }

    final instantType = _instantTypeForDart(rawType);
    final attr = fieldAnn?.name ?? fieldName;
    final isId = fieldName == 'id';
    fields.add(FieldDef(
      name: attr,
      instantType: instantType,
      dartType: _dartTypeFor(instantType),
      optional: nullable,
      unique: (fieldAnn?.unique ?? false) || isId,
      indexed: fieldAnn?.indexed ?? false,
      codegenSupported: _isCodegenSupported(instantType),
    ));
  }
}

/// Resolve link target: `List<Todo>` -> (`Todo`, many); `User?`/`User` ->
/// (`User`, one).
(String, bool) _linkTarget(String rawType) {
  final listMatch = RegExp(r'List<\s*(\w+)\s*>').firstMatch(rawType);
  if (listMatch != null) return (listMatch.group(1)!, true);
  final bare = rawType.replaceAll('?', '').trim();
  return (bare, false);
}

String _instantTypeForDart(String rawType) {
  final t = rawType.replaceAll('?', '').trim();
  if (t.startsWith('Map<')) return 'json';
  return _dartToInstant[t] ?? 'json';
}

class _FieldAnn {
  final String name;
  final bool unique;
  final bool indexed;
  _FieldAnn(this.name, this.unique, this.indexed);
}

/// Parse the closest preceding `@InstantField(...)` to a field, if any.
_FieldAnn? _lastFieldAnnotation(String preceding) {
  // Only consider an annotation that is the last token before the field
  // (allowing whitespace / @InstantLink between is handled by link path).
  final matches =
      RegExp(r'@InstantField\(([^)]*)\)').allMatches(preceding).toList();
  if (matches.isEmpty) return null;
  final last = matches.last;
  // Ensure nothing but whitespace/other-annotations between it and field end.
  final tail = preceding.substring(last.end).trim();
  if (tail.isNotEmpty && !tail.startsWith('@')) return null;
  final args = last.group(1)!;
  // Accept both single- and double-quoted attribute names.
  final nameMatch = RegExp('''['"]([^'"]*)['"]''').firstMatch(args);
  final name = nameMatch?.group(1) ?? '';
  final unique = RegExp(r'unique\s*:\s*true').hasMatch(args);
  final indexed = RegExp(r'indexed\s*:\s*true').hasMatch(args);
  return _FieldAnn(name, unique, indexed);
}

bool _hasLinkAnnotation(String preceding) {
  final matches =
      RegExp(r'@InstantLink\([^)]*\)').allMatches(preceding).toList();
  if (matches.isEmpty) return false;
  final last = matches.last;
  final tail = preceding.substring(last.end).trim();
  return tail.isEmpty || tail.startsWith('@');
}

/// Pair reciprocal `@InstantLink` fields into [LinkDef]s; dedupe; synthesize a
/// reverse (`has:'many'`) when only one side is declared.
List<LinkDef> _pairDartLinks(
  List<_RawLink> raw,
  Map<String, String> classToName,
) {
  final links = <LinkDef>[];
  final used = <int>{};

  for (var i = 0; i < raw.length; i++) {
    if (used.contains(i)) continue;
    final a = raw[i];
    // Find a reciprocal: b.owner == a.target && b.target == a.owner.
    int? matchIdx;
    for (var j = i + 1; j < raw.length; j++) {
      if (used.contains(j)) continue;
      final b = raw[j];
      if (b.ownerEntity == a.targetEntity &&
          b.targetEntity == a.ownerEntity) {
        matchIdx = j;
        break;
      }
    }

    if (matchIdx != null) {
      final b = raw[matchIdx];
      used.add(matchIdx);
      links.add(LinkDef(
        name: '${a.ownerEntity}${_cap(a.label)}',
        fromEntity: a.ownerEntity,
        fromLabel: a.label,
        fromMany: a.many,
        toEntity: a.targetEntity,
        toLabel: b.label,
        toMany: b.many,
      ));
    } else {
      // Synthesize the reverse: a has-(one/many) target; reverse is many,
      // labeled by the owner entity name.
      links.add(LinkDef(
        name: '${a.ownerEntity}${_cap(a.label)}',
        fromEntity: a.ownerEntity,
        fromLabel: a.label,
        fromMany: a.many,
        toEntity: a.targetEntity,
        toLabel: a.ownerEntity,
        toMany: true,
      ));
    }
  }
  return links;
}

String _cap(String s) =>
    s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

// ============================================================================
// SchemaDef -> TS  (emitInstantTs)
// ============================================================================

/// Emit `instant.schema.ts` source from a [SchemaDef].
///
/// [includeSystem] re-emits `$`-prefixed system entities (off by default, since
/// instant-cli manages them).
String emitInstantTs(SchemaDef schema, {bool includeSystem = false}) {
  final buf = StringBuffer();
  buf.writeln("import { i } from '@instantdb/react';");
  buf.writeln();
  buf.writeln('const schema = i.schema({');
  buf.writeln('  entities: {');

  for (final e in schema.entities) {
    if (e.system && !includeSystem) continue;
    final name = _tsKey(e.name);
    buf.writeln('    $name: i.entity({');
    for (final f in _fieldsWithId(e)) {
      buf.writeln('      ${_tsKey(f.name)}: ${_tsFieldExpr(f)},');
    }
    buf.writeln('    }),');
  }

  buf.writeln('  },');

  // Links.
  buf.writeln('  links: {');
  for (final l in schema.links) {
    final fromSys = l.fromEntity.startsWith(r'$');
    final toSys = l.toEntity.startsWith(r'$');
    // Skip links entirely between two system entities.
    if (fromSys && toSys) continue;
    buf.writeln('    ${l.name}: {');
    buf.writeln(
        "      forward: { on: '${l.fromEntity}', has: '${l.fromMany ? 'many' : 'one'}', label: '${l.fromLabel}' },");
    buf.writeln(
        "      reverse: { on: '${l.toEntity}', has: '${l.toMany ? 'many' : 'one'}', label: '${l.toLabel}' },");
    buf.writeln('    },');
  }
  buf.writeln('  },');

  buf.writeln('  rooms: {},');
  buf.writeln('});');
  buf.writeln();
  buf.writeln('export type AppSchema = typeof schema;');
  buf.writeln('export default schema;');
  return buf.toString();
}

/// TS object key: quote `$`-prefixed names, leave plain identifiers bare.
String _tsKey(String name) {
  if (RegExp(r'^[A-Za-z_]\w*$').hasMatch(name)) return name;
  return '"$name"';
}

String _tsFieldExpr(FieldDef f) {
  final base = 'i.${f.instantType}()';
  final mods = StringBuffer();
  if (f.unique) mods.write('.unique()');
  if (f.indexed) mods.write('.indexed()');
  if (f.optional) mods.write('.optional()');
  return '$base$mods';
}

// ============================================================================
// Low-level TS scanning helpers
// ============================================================================

/// Returns the body inside the `(...)` of the first call to [callee], with the
/// outer object braces preserved if the single arg is an object. Returns the
/// content between the outermost matched `{` and `}` of the call's object arg.
String? _extractCallBody(String src, String callee) {
  final idx = src.indexOf(callee);
  if (idx < 0) return null;
  // Find the opening paren after callee.
  var i = idx + callee.length;
  while (i < src.length && src[i] != '(') {
    if (!_isSpace(src[i])) break;
    i++;
  }
  if (i >= src.length || src[i] != '(') return null;
  // Find the first '{' after '(' (the object argument).
  var j = i + 1;
  while (j < src.length && src[j] != '{') {
    if (src[j] == ')') return ''; // empty call
    j++;
  }
  if (j >= src.length) return null;
  final close = _matchBrace(src, j);
  if (close < 0) return null;
  return src.substring(j + 1, close);
}

/// Extract the object literal value (without surrounding braces) for [key]
/// inside an object body. e.g. `entities: { ... }`.
String? _extractObjectValue(String objBody, String key) {
  final value = _propValue(objBody, key);
  if (value == null) return null;
  final trimmed = value.trim();
  if (trimmed.startsWith('{')) {
    final close = _matchBrace(trimmed, 0);
    if (close < 0) return null;
    return trimmed.substring(1, close);
  }
  return null;
}

/// Find the raw value text for `key:` at the top level of [objBody].
String? _propValue(String objBody, String key) {
  for (final entry in _topLevelEntries(objBody)) {
    if (_unquote(entry.key) == key) return entry.value;
  }
  return null;
}

/// Read a string property value, e.g. `has: 'many'` -> `many`.
String? _stringProp(String objBody, String key) {
  final v = _propValue(objBody, key);
  if (v == null) return null;
  return _unquote(v.trim());
}

class _Entry {
  final String key;
  final String value;
  _Entry(this.key, this.value);
}

/// Split an object body into top-level `key: value` entries, respecting nested
/// braces/brackets/parens and strings.
List<_Entry> _topLevelEntries(String body) {
  final entries = <_Entry>[];
  var depth = 0;
  var i = 0;
  final n = body.length;

  while (i < n) {
    // Skip whitespace and commas.
    while (i < n && (_isSpace(body[i]) || body[i] == ',')) {
      i++;
    }
    if (i >= n) break;
    // Skip line comments.
    if (i + 1 < n && body[i] == '/' && body[i + 1] == '/') {
      while (i < n && body[i] != '\n') {
        i++;
      }
      continue;
    }
    // Skip block comments.
    if (i + 1 < n && body[i] == '/' && body[i + 1] == '*') {
      i += 2;
      while (i + 1 < n && !(body[i] == '*' && body[i + 1] == '/')) {
        i++;
      }
      i += 2;
      continue;
    }

    // Read key (up to the first top-level ':').
    final keyStart = i;
    var keyEnd = -1;
    depth = 0;
    while (i < n) {
      final c = body[i];
      if (c == '"' || c == "'" || c == '`') {
        i = _skipString(body, i);
        continue;
      }
      if (c == '{' || c == '[' || c == '(') depth++;
      if (c == '}' || c == ']' || c == ')') depth--;
      if (depth == 0 && c == ':') {
        keyEnd = i;
        break;
      }
      i++;
    }
    if (keyEnd < 0) break;
    final key = body.substring(keyStart, keyEnd).trim();
    i = keyEnd + 1;

    // Read value (up to the top-level comma or end).
    while (i < n && _isSpace(body[i])) {
      i++;
    }
    final valStart = i;
    depth = 0;
    while (i < n) {
      final c = body[i];
      if (c == '"' || c == "'" || c == '`') {
        i = _skipString(body, i);
        continue;
      }
      if (c == '{' || c == '[' || c == '(') depth++;
      if (c == '}' || c == ']' || c == ')') depth--;
      if (depth == 0 && c == ',') break;
      i++;
    }
    final value = body.substring(valStart, i).trim();
    if (key.isNotEmpty) entries.add(_Entry(key, value));
  }
  return entries;
}

/// Given index of `{`, return index of the matching `}`, or -1.
int _matchBrace(String src, int open) {
  var depth = 0;
  var i = open;
  final n = src.length;
  while (i < n) {
    final c = src[i];
    if (c == '"' || c == "'" || c == '`') {
      i = _skipString(src, i);
      continue;
    }
    if (c == '{') depth++;
    if (c == '}') {
      depth--;
      if (depth == 0) return i;
    }
    i++;
  }
  return -1;
}

/// Given index of a quote char, return index just past the closing quote.
int _skipString(String src, int start) {
  final quote = src[start];
  var i = start + 1;
  final n = src.length;
  while (i < n) {
    if (src[i] == '\\') {
      i += 2;
      continue;
    }
    if (src[i] == quote) return i + 1;
    i++;
  }
  return n;
}

bool _isSpace(String c) => c == ' ' || c == '\t' || c == '\n' || c == '\r';

/// Strip a single matched pair of outer `{ }` (with surrounding whitespace).
String _stripOuterBraces(String s) {
  final t = s.trim();
  if (t.startsWith('{')) {
    final close = _matchBrace(t, 0);
    if (close == t.length - 1) return t.substring(1, close);
  }
  return t;
}

String _unquote(String s) {
  final t = s.trim();
  if (t.length >= 2) {
    final f = t[0];
    final l = t[t.length - 1];
    if ((f == '"' || f == "'" || f == '`') && f == l) {
      return t.substring(1, t.length - 1);
    }
  }
  return t;
}
