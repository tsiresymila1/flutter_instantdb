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
