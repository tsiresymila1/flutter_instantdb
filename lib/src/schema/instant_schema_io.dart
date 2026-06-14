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
  final forward = _extractObjectValue(value, 'forward');
  final reverse = _extractObjectValue(value, 'reverse');
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
  // Collect link fields per (user-side) entity.
  final linkFields = <String, List<_LinkFieldEmit>>{};
  for (final link in schema.links) {
    final fromSys = _isSystem(link.fromEntity, entitiesByName);
    final toSys = _isSystem(link.toEntity, entitiesByName);

    // Forward field lives on fromEntity, points at toEntity.
    if (!fromSys) {
      linkFields.putIfAbsent(link.fromEntity, () => []).add(
            _LinkFieldEmit(
              label: link.fromLabel,
              targetClass: classNameFor(link.toEntity),
              many: link.toMany,
            ),
          );
    }
    // Reverse field lives on toEntity, points at fromEntity.
    if (!toSys) {
      linkFields.putIfAbsent(link.toEntity, () => []).add(
            _LinkFieldEmit(
              label: link.toLabel,
              targetClass: classNameFor(link.fromEntity),
              many: link.fromMany,
            ),
          );
    }
  }

  final buf = StringBuffer();
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
