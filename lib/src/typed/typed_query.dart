/// Typed query DSL for InstantDB. Compiles to the InstaQL string-maps that the
/// query engine already consumes. Pure Dart — no DB dependency.

/// A where-clause expression. Combine leaves with `&` (and) / `|` (or).
class Filter {
  final Map<String, dynamic> _map;
  const Filter._(this._map);

  /// Leaf filter for a single field condition.
  factory Filter.field(String field, dynamic condition) =>
      Filter._({field: condition});

  Map<String, dynamic> toMap() => _map;

  Filter operator &(Filter other) =>
      Filter._({'and': [toMap(), other.toMap()]});

  Filter operator |(Filter other) =>
      Filter._({'or': [toMap(), other.toMap()]});
}

/// Ordering spec: `{field: 'asc' | 'desc'}`.
class Order {
  final String field;
  final String direction;
  const Order(this.field, this.direction);

  Map<String, dynamic> toMap() => {field: direction};
}

/// A typed reference to an entity field named [name].
class Col<T> {
  final String name;
  const Col(this.name);

  /// Direct equality (`{name: value}`).
  Filter eq(T value) => Filter.field(name, value);

  Filter ne(T value) => Filter.field(name, {r'$ne': value});

  Filter isNull(bool value) => Filter.field(name, {r'$isNull': value});

  Filter inList(List<T> values) => Filter.field(name, {r'$in': values});

  Order asc() => Order(name, 'asc');
  Order desc() => Order(name, 'desc');
}

/// Comparison operators, available only on `Col` of a `Comparable` type.
extension ComparableCol<T extends Comparable<dynamic>> on Col<T> {
  Filter gt(T value) => Filter.field(name, {r'$gt': value});
  Filter gte(T value) => Filter.field(name, {r'$gte': value});
  Filter lt(T value) => Filter.field(name, {r'$lt': value});
  Filter lte(T value) => Filter.field(name, {r'$lte': value});
}

/// String match operators, available only on `Col<String>`.
extension StringCol on Col<String> {
  Filter like(String pattern) => Filter.field(name, {r'$like': pattern});
  Filter ilike(String pattern) => Filter.field(name, {r'$ilike': pattern});
}
