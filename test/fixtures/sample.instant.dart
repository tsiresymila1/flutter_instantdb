// GENERATED CODE - matches flutter_instantdb_generator output for Widget2.
part of 'sample.dart';

class Widget2Table extends InstantModelTable<Widget2Table, Widget2> {
  Widget2Table() : super('widgets');

  final id = const Col<String>('id');
  final name = const Col<String>('name');
  final weight = const Col<int>('weight');

  @override
  Widget2 fromRow(Map<String, dynamic> m) => Widget2(
        id: m['id'] as String,
        name: m['name'] as String,
        weight: m['weight'] as int,
      );
}

extension Widget2QueryX on TypedQuery<Widget2Table> {
  Future<List<Widget2>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this)).documents.map(Widget2Table().fromRow).toList();

  ReadonlySignal<List<Widget2>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(() => src.value.documents.map(Widget2Table().fromRow).toList());
  }
}
