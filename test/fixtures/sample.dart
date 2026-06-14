import 'package:flutter_instantdb/flutter_instantdb.dart';

part 'sample.instant.dart';

@InstantModel('gadgets')
class Gadget {
  final String id;
  final String label;
  const Gadget({required this.id, required this.label});
}

@InstantModel('widgets')
class Widget2 {
  final String id;
  final String name;
  final int weight;
  @InstantLink()
  final List<Gadget> gadgets;
  const Widget2({
    required this.id,
    required this.name,
    required this.weight,
    required this.gadgets,
  });
}
