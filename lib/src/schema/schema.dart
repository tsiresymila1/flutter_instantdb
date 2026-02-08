/// Simple schema system for InstantDB Flutter.
/// This is a basic implementation - in production you'd want more sophisticated validation.
library;

/// Base class for schema validation
abstract class SchemaValidator {
  bool validate(dynamic value);
  String get description;
}

/// String schema validator
class StringSchema extends SchemaValidator {
  final int? minLength;
  final int? maxLength;
  final RegExp? pattern;

  StringSchema({this.minLength, this.maxLength, this.pattern});

  @override
  bool validate(dynamic value) {
    if (value is! String) return false;

    if (minLength != null && value.length < minLength!) return false;
    if (maxLength != null && value.length > maxLength!) return false;
    if (pattern != null && !pattern!.hasMatch(value)) return false;

    return true;
  }

  @override
  String get description =>
      'String${minLength != null ? ' (min: $minLength)' : ''}${maxLength != null ? ' (max: $maxLength)' : ''}';
}

/// Number schema validator
class NumberSchema extends SchemaValidator {
  final num? min;
  final num? max;

  NumberSchema({this.min, this.max});

  @override
  bool validate(dynamic value) {
    if (value is! num) return false;

    if (min != null && value < min!) return false;
    if (max != null && value > max!) return false;

    return true;
  }

  @override
  String get description =>
      'Number${min != null ? ' (min: $min)' : ''}${max != null ? ' (max: $max)' : ''}';
}

/// Boolean schema validator
class BooleanSchema extends SchemaValidator {
  @override
  bool validate(dynamic value) => value is bool;

  @override
  String get description => 'Boolean';
}

/// Array schema validator
class ArraySchema extends SchemaValidator {
  final SchemaValidator itemSchema;
  final int? minLength;
  final int? maxLength;

  ArraySchema(this.itemSchema, {this.minLength, this.maxLength});

  @override
  bool validate(dynamic value) {
    if (value is! List) return false;

    if (minLength != null && value.length < minLength!) return false;
    if (maxLength != null && value.length > maxLength!) return false;

    return value.every(itemSchema.validate);
  }

  @override
  String get description => 'Array<${itemSchema.description}>';
}

/// Object schema validator
class ObjectSchema extends SchemaValidator {
  final Map<String, SchemaValidator> properties;
  final List<String> required;

  ObjectSchema(this.properties, {this.required = const []});

  @override
  bool validate(dynamic value) {
    if (value is! Map<String, dynamic>) return false;

    // Check required fields
    for (final field in required) {
      if (!value.containsKey(field)) return false;
    }

    // Validate each property
    for (final entry in value.entries) {
      final schema = properties[entry.key];
      if (schema != null && !schema.validate(entry.value)) {
        return false;
      }
    }

    return true;
  }

  @override
  String get description => 'Object';
}

/// Optional schema wrapper
class OptionalSchema extends SchemaValidator {
  final SchemaValidator schema;

  OptionalSchema(this.schema);

  @override
  bool validate(dynamic value) {
    if (value == null) return true;
    return schema.validate(value);
  }

  @override
  String get description => '${schema.description}?';
}

/// Schema builder with fluent API
class Schema {
  static StringSchema string({
    int? minLength,
    int? maxLength,
    RegExp? pattern,
  }) => StringSchema(
    minLength: minLength,
    maxLength: maxLength,
    pattern: pattern,
  );

  static NumberSchema number({num? min, num? max}) =>
      NumberSchema(min: min, max: max);

  static BooleanSchema boolean() => BooleanSchema();

  static ArraySchema array(
    SchemaValidator itemSchema, {
    int? minLength,
    int? maxLength,
  }) => ArraySchema(itemSchema, minLength: minLength, maxLength: maxLength);

  static ObjectSchema object(
    Map<String, SchemaValidator> properties, {
    List<String> required = const [],
  }) => ObjectSchema(properties, required: required);

  static OptionalSchema optional(SchemaValidator schema) =>
      OptionalSchema(schema);

  // Common patterns
  static StringSchema email() => StringSchema(
    pattern: RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$'),
  );

  static StringSchema id() => StringSchema(minLength: 1);
}

/// Link definition for entity relationships
class Link {
  final EntityRef from;
  final EntityRef to;
  final LinkType type;

  Link({required this.from, required this.to, this.type = LinkType.oneToMany});
}

/// Reference to an entity field
class EntityRef {
  final String entity;
  final String field;

  EntityRef(this.entity, this.field);
}

/// Type of relationship link
enum LinkType { oneToOne, oneToMany, manyToMany }

/// Entity definition with schema and metadata
class InstantEntity {
  final SchemaValidator validator;
  final bool localOnly;

  const InstantEntity({required this.validator, this.localOnly = false});
}

/// Complete schema definition for an InstantDB app
class InstantSchema {
  final Map<String, InstantEntity> entities;
  final Map<String, Link> links;

  InstantSchema({required this.entities, this.links = const {}});

  /// Check if an entity type is local-only
  bool isLocalOnly(String entityType) {
    return entities[entityType]?.localOnly ?? false;
  }

  /// Validate an entity against its schema
  bool validateEntity(String entityType, Map<String, dynamic> data) {
    final entity = entities[entityType];
    if (entity == null) return false;

    return entity.validator.validate(data);
  }

  /// Get schema for an entity type
  SchemaValidator? getEntitySchema(String entityType) =>
      entities[entityType]?.validator;
}

/// Builder for InstantSchema
class InstantSchemaBuilder {
  final Map<String, InstantEntity> _entities = {};
  final Map<String, Link> _links = {};

  /// Add an entity schema
  InstantSchemaBuilder addEntity(
    String name,
    SchemaValidator schema, {
    bool localOnly = false,
  }) {
    // Ensure required fields for InstantDB entities
    SchemaValidator validator;
    if (schema is ObjectSchema) {
      final properties = Map<String, SchemaValidator>.from(schema.properties);
      properties['id'] ??= Schema.id();
      properties['createdAt'] ??= Schema.number();
      properties['updatedAt'] ??= Schema.number();

      final required = List<String>.from(schema.required);
      if (!required.contains('id')) required.add('id');

      validator = ObjectSchema(properties, required: required);
    } else {
      validator = schema;
    }

    _entities[name] = InstantEntity(validator: validator, localOnly: localOnly);

    return this;
  }

  /// Add a local-only entity schema (convenience method)
  InstantSchemaBuilder addLocalEntity(String name, SchemaValidator schema) {
    return addEntity(name, schema, localOnly: true);
  }

  /// Add a relationship link
  InstantSchemaBuilder addLink(String name, Link link) {
    _links[name] = link;
    return this;
  }

  /// Build the schema
  InstantSchema build() {
    return InstantSchema(
      entities: Map.unmodifiable(_entities),
      links: Map.unmodifiable(_links),
    );
  }
}
