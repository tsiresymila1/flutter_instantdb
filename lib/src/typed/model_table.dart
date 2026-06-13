import 'typed_query.dart';

/// A typed table (like a 6a [InstantTable]) that also maps query-result
/// documents to typed [Row] objects via [fromRow]. Generated subclasses provide
/// the columns and the mapper. Extends [InstantTable] additively — hand-written
/// 6a tables keep working unchanged.
abstract class InstantModelTable<Self extends InstantModelTable<Self, Row>, Row>
    extends InstantTable<Self> {
  InstantModelTable(super.entityType);

  /// Map a single query-result document to a typed [Row].
  Row fromRow(Map<String, dynamic> map);
}
