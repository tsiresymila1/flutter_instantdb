import 'package:flutter_instantdb/flutter_instantdb.dart';

part 'sample.instant.dart';

@InstantModel('widgets')
class Widget2 {
  final String id;
  final String name;
  final int weight;
  const Widget2({required this.id, required this.name, required this.weight});
}
