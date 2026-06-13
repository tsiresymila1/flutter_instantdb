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

/// An immutable, fluent, type-safe query over a single namespace. Compiles to
/// the InstaQL `{entityType: {r'$': {...}}}` map the engine consumes.
///
/// Every fluent method returns a **new** [TypedQuery] instance with the updated
/// field; the original query is never mutated. This makes it safe to branch a
/// base query and reuse/alias it freely.
class TypedQuery<E extends InstantTable<E>> {
  final E table;

  final Filter? _where;
  final Order? _order;
  final int? _first;
  final int? _last;
  final int? _offset;
  final int? _limit;
  final String? _after;
  final String? _before;
  final bool? _afterInclusive;
  final bool? _beforeInclusive;
  final List<Col<dynamic>>? _fields;

  TypedQuery(this.table)
      : _where = null,
        _order = null,
        _first = null,
        _last = null,
        _offset = null,
        _limit = null,
        _after = null,
        _before = null,
        _afterInclusive = null,
        _beforeInclusive = null,
        _fields = null;

  TypedQuery._(
    this.table, {
    required Filter? where,
    required Order? order,
    required int? first,
    required int? last,
    required int? offset,
    required int? limit,
    required String? after,
    required String? before,
    required bool? afterInclusive,
    required bool? beforeInclusive,
    required List<Col<dynamic>>? fields,
  })  : _where = where,
        _order = order,
        _first = first,
        _last = last,
        _offset = offset,
        _limit = limit,
        _after = after,
        _before = before,
        _afterInclusive = afterInclusive,
        _beforeInclusive = beforeInclusive,
        _fields = fields;

  TypedQuery<E> _copyWith({
    Filter? where,
    Order? order,
    int? first,
    int? last,
    int? offset,
    int? limit,
    String? after,
    String? before,
    bool? afterInclusive,
    bool? beforeInclusive,
    List<Col<dynamic>>? fields,
  }) {
    return TypedQuery._(
      table,
      where: where ?? _where,
      order: order ?? _order,
      first: first ?? _first,
      last: last ?? _last,
      offset: offset ?? _offset,
      limit: limit ?? _limit,
      after: after ?? _after,
      before: before ?? _before,
      afterInclusive: afterInclusive ?? _afterInclusive,
      beforeInclusive: beforeInclusive ?? _beforeInclusive,
      fields: fields ?? _fields,
    );
  }

  TypedQuery<E> where(Filter Function(E t) build) =>
      _copyWith(where: build(table));

  TypedQuery<E> order(Order Function(E t) build) =>
      _copyWith(order: build(table));

  TypedQuery<E> select(List<Col<dynamic>> Function(E t) build) =>
      _copyWith(fields: build(table));

  TypedQuery<E> first(int n) => _copyWith(first: n);

  TypedQuery<E> last(int n) => _copyWith(last: n);

  TypedQuery<E> offset(int n) => _copyWith(offset: n);

  TypedQuery<E> limit(int n) => _copyWith(limit: n);

  TypedQuery<E> after(String cursor) => _copyWith(after: cursor);

  TypedQuery<E> before(String cursor) => _copyWith(before: cursor);

  TypedQuery<E> afterInclusive(bool value) => _copyWith(afterInclusive: value);

  TypedQuery<E> beforeInclusive(bool value) =>
      _copyWith(beforeInclusive: value);

  /// Compile to the InstaQL map.
  Map<String, dynamic> toQuery() {
    final options = <String, dynamic>{
      if (_where != null) 'where': _where.toMap(),
      if (_order != null) 'order': _order.toMap(),
      if (_first != null) 'first': _first,
      if (_last != null) 'last': _last,
      if (_after != null) 'after': _after,
      if (_before != null) 'before': _before,
      if (_afterInclusive != null) 'afterInclusive': _afterInclusive,
      if (_beforeInclusive != null) 'beforeInclusive': _beforeInclusive,
      if (_limit != null) 'limit': _limit,
      if (_offset != null) 'offset': _offset,
      if (_fields != null) 'fields': _fields.map((c) => c.name).toList(),
    };
    return {
      table.entityType: {r'$': options},
    };
  }
}
