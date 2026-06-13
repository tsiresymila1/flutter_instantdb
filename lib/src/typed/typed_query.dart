// Typed query DSL for InstantDB. Compiles to the InstaQL string-maps that the
// query engine already consumes. Pure Dart — no DB dependency.

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

/// Base class for a typed entity handle. Uses the self-referential generic so
/// `query()` returns a `TypedQuery<Self>` with correctly-typed columns.
abstract class InstantTable<Self extends InstantTable<Self>> {
  final String entityType;
  InstantTable(this.entityType);

  TypedQuery<Self> query() => TypedQuery<Self>(this as Self);
}

/// A fluent, type-safe query over a single namespace. Compiles to the InstaQL
/// `{entityType: {r'$': {...}}}` map the engine consumes.
class TypedQuery<E extends InstantTable<E>> {
  final E table;

  Filter? _where;
  Order? _order;
  int? _first;
  int? _last;
  int? _offset;
  int? _limit;
  String? _after;
  String? _before;
  bool? _afterInclusive;
  bool? _beforeInclusive;
  List<Col<dynamic>>? _fields;

  TypedQuery(this.table);

  TypedQuery<E> where(Filter Function(E t) build) {
    _where = build(table);
    return this;
  }

  TypedQuery<E> order(Order Function(E t) build) {
    _order = build(table);
    return this;
  }

  TypedQuery<E> select(List<Col<dynamic>> Function(E t) build) {
    _fields = build(table);
    return this;
  }

  TypedQuery<E> first(int n) {
    _first = n;
    return this;
  }

  TypedQuery<E> last(int n) {
    _last = n;
    return this;
  }

  TypedQuery<E> offset(int n) {
    _offset = n;
    return this;
  }

  TypedQuery<E> limit(int n) {
    _limit = n;
    return this;
  }

  TypedQuery<E> after(String cursor) {
    _after = cursor;
    return this;
  }

  TypedQuery<E> before(String cursor) {
    _before = cursor;
    return this;
  }

  TypedQuery<E> afterInclusive(bool value) {
    _afterInclusive = value;
    return this;
  }

  TypedQuery<E> beforeInclusive(bool value) {
    _beforeInclusive = value;
    return this;
  }

  /// Compile to the InstaQL map.
  Map<String, dynamic> toQuery() {
    final options = <String, dynamic>{
      if (_where != null) 'where': _where!.toMap(),
      if (_order != null) 'order': _order!.toMap(),
      if (_first != null) 'first': _first,
      if (_last != null) 'last': _last,
      if (_after != null) 'after': _after,
      if (_before != null) 'before': _before,
      if (_afterInclusive != null) 'afterInclusive': _afterInclusive,
      if (_beforeInclusive != null) 'beforeInclusive': _beforeInclusive,
      if (_limit != null) 'limit': _limit,
      if (_offset != null) 'offset': _offset,
      if (_fields != null) 'fields': _fields!.map((c) => c.name).toList(),
    };
    return {
      table.entityType: {r'$': options},
    };
  }
}
