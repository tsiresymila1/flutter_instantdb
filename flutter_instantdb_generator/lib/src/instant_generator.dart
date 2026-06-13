import 'package:analyzer/dart/constant/value.dart';
import 'package:analyzer/dart/element/element.dart';
import 'package:analyzer/dart/element/nullability_suffix.dart';
import 'package:analyzer/dart/element/type.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

/// Local stand-in for the `@InstantModel` annotation, used only as the type
/// parameter for [GeneratorForAnnotation] so the `source_gen_test` harness can
/// drive the generator. The generator never relies on this type at runtime — it
/// matches annotations structurally by class NAME (see [generate]), so it works
/// against `flutter_instantdb`'s `InstantModel` without depending on that
/// (Flutter) package.
class InstantModel {
  final String entityType;
  const InstantModel(this.entityType);
}

/// Generates a typed `InstantModelTable` + a `TypedQuery` extension for every
/// class annotated with `@InstantModel`.
class InstantGenerator extends GeneratorForAnnotation<InstantModel> {
  const InstantGenerator();

  // Match any annotation class named `InstantModel` (the runtime one and the
  // test-local stand-in share this name). The element is read structurally.
  static const _annotationName = 'InstantModel';

  @override
  String generate(LibraryReader library, BuildStep buildStep) {
    final buffer = StringBuffer();
    for (final element in library.classes) {
      final annotation = _instantModelAnnotation(element);
      if (annotation == null) continue;
      buffer.writeln(_generateForClass(element, annotation));
    }
    return buffer.toString().trim();
  }

  /// Drives a single annotated element. Used by the `source_gen_test` harness,
  /// which invokes this directly (rather than [generate]).
  @override
  String generateForAnnotatedElement(
    Element element,
    ConstantReader annotation,
    BuildStep buildStep,
  ) {
    if (element is! ClassElement) {
      throw InvalidGenerationSourceError(
        '@InstantModel can only be applied to classes.',
        element: element,
      );
    }
    return _generateForClass(element, annotation.objectValue);
  }

  DartObject? _instantModelAnnotation(ClassElement element) {
    for (final meta in element.metadata) {
      final value = meta.computeConstantValue();
      final typeName = value?.type?.element?.name;
      if (typeName == _annotationName) return value;
    }
    return null;
  }

  String _generateForClass(ClassElement element, DartObject annotation) {
    final modelName = element.name;
    final tableName = '${modelName}Table';
    final entityType = annotation.getField('entityType')!.toStringValue()!;

    final fields = _modelFields(element);

    final cols = StringBuffer();
    final ctorArgs = StringBuffer();
    for (final f in fields) {
      cols.writeln(
        "  final ${f.fieldName} = const Col<${f.dartType}>('${f.attr}');",
      );
      ctorArgs.writeln(
        "        ${f.fieldName}: m['${f.attr}'] as ${f.dartType}${f.nullable ? '?' : ''},",
      );
    }

    return '''
class $tableName extends InstantModelTable<$tableName, $modelName> {
  $tableName() : super('$entityType');

${cols.toString().trimRight()}

  @override
  $modelName fromRow(Map<String, dynamic> m) => $modelName(
${ctorArgs.toString().trimRight()}
      );
}

extension ${modelName}QueryX on TypedQuery<$tableName> {
  Future<List<$modelName>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this)).documents.map($tableName().fromRow).toList();

  ReadonlySignal<List<$modelName>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(() => src.value.documents.map($tableName().fromRow).toList());
  }
}
''';
  }

  List<_FieldInfo> _modelFields(ClassElement element) {
    final result = <_FieldInfo>[];
    for (final field in element.fields) {
      if (field.isStatic || field.isSynthetic) continue;

      final type = field.type;
      final dartType = type.getDisplayString(withNullability: false);
      final nullable = type.nullabilitySuffix == NullabilitySuffix.question;

      if (!_isSupportedScalar(type)) {
        // Relation / unsupported type: deferred to the nested sub-phase.
        if (!nullable) {
          throw InvalidGenerationSourceError(
            'Field "${field.name}" on ${element.name} has unsupported type '
            '"$dartType". Relations/non-primitive types are not yet generated; '
            'make the field nullable to skip it until nested support lands.',
            element: field,
          );
        }
        continue; // nullable unsupported field: skip emitting a column/mapping.
      }

      result.add(_FieldInfo(
        fieldName: field.name,
        attr: _attrName(field),
        dartType: dartType,
        nullable: nullable,
      ));
    }
    return result;
  }

  bool _isSupportedScalar(DartType type) =>
      type.isDartCoreString ||
      type.isDartCoreInt ||
      type.isDartCoreDouble ||
      type.isDartCoreNum ||
      type.isDartCoreBool;

  String _attrName(FieldElement field) {
    for (final meta in field.metadata) {
      final value = meta.computeConstantValue();
      if (value?.type?.element?.name == 'InstantField') {
        return value!.getField('name')!.toStringValue()!;
      }
    }
    return field.name;
  }
}

class _FieldInfo {
  final String fieldName;
  final String attr;
  final String dartType;
  final bool nullable;
  _FieldInfo({
    required this.fieldName,
    required this.attr,
    required this.dartType,
    required this.nullable,
  });
}
