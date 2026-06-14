import '../core/types.dart';
import '../core/transaction_builder.dart';
import 'typed_query.dart';

enum _WriteKind { create, update, merge }

/// Typed transaction entry point for a table [E]. Delegates to the untyped
/// builder; `set<T>(Col<T>, T)` gives compile-time field/value checking.
class TypedTx<E extends InstantTable<E>> {
  final E _table;
  TypedTx(this._table);
  String get _type => _table.entityType;

  TypedWrite create({String? id}) =>
      TypedWrite._(_type, id: id, kind: _WriteKind.create);
  TypedWrite update(String id) =>
      TypedWrite._(_type, id: id, kind: _WriteKind.update);
  TypedWrite merge(String id) =>
      TypedWrite._(_type, id: id, kind: _WriteKind.merge);

  /// Upsert-by-unique-attribute target (delegates to EntityInstanceBuilder.lookup).
  TypedWrite lookup<T>(Col<T> col, T value, {bool merge = false}) =>
      TypedWrite._(_type,
          lookupRef:
              LookupRef(entityType: _type, attribute: col.name, value: value),
          kind: merge ? _WriteKind.merge : _WriteKind.update);

  TransactionChunk delete(String id) =>
      EntityInstanceBuilder(_type, id).delete();

  /// Build a create op from a whole attribute map (e.g. a generated toMap).
  /// `data['id']` (if present) is used as the entity id; [id] overrides it.
  TransactionChunk createFromMap(Map<String, dynamic> data, {String? id}) =>
      EntityBuilder(_type).create({...data, if (id != null) 'id': id});

  /// Build an update op from a whole attribute map. A generated `toMap` includes
  /// the `id` attribute; an `id` in [data] duplicates the entity id but is
  /// harmless (reconstruction skips the `id` attribute).
  TransactionChunk updateFromMap(String id, Map<String, dynamic> data,
          {TxOpts? opts}) =>
      EntityInstanceBuilder(_type, id)
          .update(Map<String, dynamic>.from(data), opts: opts);

  /// Typed relation link. [targetIds] is one id or a List of ids.
  TransactionChunk linkRel<R extends InstantTable<R>>(
          String id, RelationRef<R> rel, Object targetIds) =>
      EntityInstanceBuilder(_type, id).link({rel.attr: targetIds});

  /// Typed relation unlink. [targetIds] is one id or a List of ids.
  TransactionChunk unlinkRel<R extends InstantTable<R>>(
          String id, RelationRef<R> rel, Object targetIds) =>
      EntityInstanceBuilder(_type, id).unlink({rel.attr: targetIds});

  // [relation] is an untyped attribute name — typed relation writes (via the
  // generated relation accessor) are deferred to 6d.
  TransactionChunk link(String id, String relation, Object targetId) =>
      EntityInstanceBuilder(_type, id).link({relation: targetId});
  TransactionChunk unlink(String id, String relation, Object targetId) =>
      EntityInstanceBuilder(_type, id).unlink({relation: targetId});
}

/// A pending typed write. Cascade `..set(col, value)` to fill fields, pass to
/// `db.transact` directly (implements [ToTransaction]).
class TypedWrite implements ToTransaction {
  final String _type;
  final String? _id;
  final LookupRef? _lookupRef;
  final _WriteKind _kind;
  final Map<String, dynamic> _fields = {};
  TxOpts? _opts;

  TypedWrite._(this._type,
      {String? id, LookupRef? lookupRef, required _WriteKind kind})
      : _id = id,
        _lookupRef = lookupRef,
        _kind = kind;

  /// Set a typed field. The value type is bound to the column's `T`.
  TypedWrite set<T>(Col<T> col, T value) {
    _fields[col.name] = value;
    return this;
  }

  /// Strict/upsert control for update/merge (ignored for create).
  TypedWrite opts(TxOpts o) {
    _opts = o;
    return this;
  }

  @override
  TransactionChunk toTransactionChunk() {
    switch (_kind) {
      case _WriteKind.create:
        return EntityBuilder(_type)
            .create({if (_id != null) 'id': _id, ..._fields});
      case _WriteKind.update:
        // Copy so a later set() can't mutate an already-built operation's data.
        return _instance().update(Map<String, dynamic>.from(_fields), opts: _opts);
      case _WriteKind.merge:
        return _instance().merge(Map<String, dynamic>.from(_fields), opts: _opts);
    }
  }

  EntityInstanceBuilder _instance() => _lookupRef != null
      ? EntityInstanceBuilder.lookup(
          _type, _lookupRef.attribute, _lookupRef.value)
      : EntityInstanceBuilder(_type, _id!);
}
