/// Marks a class as an InstantDB model. [entityType] is the namespace the
/// generated table queries (e.g. 'todos').
class InstantModel {
  final String entityType;
  const InstantModel(this.entityType);
}

/// Overrides the stored attribute name for a field. Without it, the field name
/// is used as the attribute name.
class InstantField {
  final String name;
  const InstantField(this.name);
}

/// Marks a relation field on an `@InstantModel`. Cardinality is inferred from the
/// field type (`List<T>` to-many, bare `T` to-one); the target table is
/// `${T}Table` (T must be an `@InstantModel`). [attr] overrides the stored
/// relation attribute (include key), defaulting to the field name.
class InstantLink {
  final String? attr;
  const InstantLink({this.attr});
}
