// GENERATED CODE - DO NOT MODIFY BY HAND
// Matches flutter_instantdb_generator output for Gadget and Widget2.
// ignore_for_file: type=lint
// ignore_for_file: unused_element, deprecated_member_use, deprecated_member_use_from_same_package, use_function_type_syntax_for_parameters, unnecessary_const, avoid_init_to_null, invalid_override_different_default_values_named, prefer_expression_function_bodies, annotate_overrides, invalid_annotation_target, unnecessary_question_mark

part of 'sample.dart';

class GadgetTable extends InstantModelTable<GadgetTable, Gadget> {
  GadgetTable() : super('gadgets');

  final id = const Col<String>('id');
  final label = const Col<String>('label');

  @override
  Gadget fromRow(Map<String, dynamic> m) => Gadget(
        id: m['id'] as String,
        label: m['label'] as String,
      );

  Map<String, dynamic> toMap(Gadget m) => {
        'id': m.id,
        'label': m.label,
      };
}

extension GadgetQueryX on TypedQuery<GadgetTable> {
  Future<List<Gadget>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(GadgetTable().fromRow)
          .toList();

  ReadonlySignal<List<Gadget>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(GadgetTable().fromRow).toList());
  }
}

extension GadgetTxX on TypedTx<GadgetTable> {
  TransactionChunk createModel(Gadget m) =>
      createFromMap(GadgetTable().toMap(m));
  TransactionChunk updateModel(String id, Gadget m) =>
      updateFromMap(id, GadgetTable().toMap(m));
}

class Widget2Table extends InstantModelTable<Widget2Table, Widget2> {
  Widget2Table() : super('widgets');

  final id = const Col<String>('id');
  final name = const Col<String>('name');
  final weight = const Col<int>('weight');

  TypedQuery<GadgetTable> get gadgets =>
      TypedQuery<GadgetTable>(GadgetTable(), relationAttr: 'gadgets');

  static const gadgetsRel = RelationRef<GadgetTable>('gadgets');

  @override
  Widget2 fromRow(Map<String, dynamic> m) => Widget2(
        id: m['id'] as String,
        name: m['name'] as String,
        weight: m['weight'] as int,
        gadgets: (m['gadgets'] as List<dynamic>?)
                ?.whereType<Map<String, dynamic>>()
                .map(GadgetTable().fromRow)
                .toList() ??
            const <Gadget>[],
      );

  Map<String, dynamic> toMap(Widget2 m) => {
        'id': m.id,
        'name': m.name,
        'weight': m.weight,
      };
}

extension Widget2QueryX on TypedQuery<Widget2Table> {
  Future<List<Widget2>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map(Widget2Table().fromRow)
          .toList();

  ReadonlySignal<List<Widget2>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map(Widget2Table().fromRow).toList());
  }
}

extension Widget2TxX on TypedTx<Widget2Table> {
  TransactionChunk createModel(Widget2 m) =>
      createFromMap(Widget2Table().toMap(m));
  TransactionChunk updateModel(String id, Widget2 m) =>
      updateFromMap(id, Widget2Table().toMap(m));
}
