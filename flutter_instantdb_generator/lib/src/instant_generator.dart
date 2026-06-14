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

  static String _escape(String s) =>
      s.replaceAll('\\', '\\\\').replaceAll("'", "\\'");

  String _generateForClass(ClassElement element, DartObject annotation) {
    final modelName = element.name;
    final tableName = '${modelName}Table';
    final entityType = annotation.getField('entityType')!.toStringValue()!;

    final fields = _modelFields(element);
    final links = _modelLinks(element);

    ConstructorElement? ctor;
    for (final c in element.constructors) {
      if (!c.isFactory) {
        ctor = c;
        break;
      }
    }
    if (ctor == null) {
      throw InvalidGenerationSourceError(
        '${element.name} has no generative constructor.',
        element: element,
      );
    }
    final namedParams =
        ctor.parameters.where((p) => p.isNamed).map((p) => p.name).toSet();
    // Validate both scalars and relation fields have matching ctor params.
    final allFieldNames = {
      for (final f in fields) f.fieldName,
      for (final l in links) l.fieldName,
    };
    for (final name in allFieldNames) {
      if (!namedParams.contains(name)) {
        // Find source element for error reporting.
        final srcField = element.fields.firstWhere((f) => f.name == name);
        throw InvalidGenerationSourceError(
          'Field "$name" on ${element.name} has no matching named '
          'constructor parameter. The generated fromRow needs `${element.name}('
          '{required ... $name})`.',
          element: srcField,
        );
      }
    }

    final cols = StringBuffer();
    final ctorArgs = StringBuffer();

    // Scalar columns.
    for (final f in fields) {
      cols.writeln(
        "  final ${f.fieldName} = const Col<${f.dartType}>('${_escape(f.attr)}');",
      );
      ctorArgs.writeln(
        "        ${f.fieldName}: m['${_escape(f.attr)}'] as ${f.dartType}${f.nullable ? '?' : ''},",
      );
    }

    // Relation accessors and ctor args.
    final linkAccessors = StringBuffer();
    for (final l in links) {
      // Accessor
      linkAccessors.writeln(
        '  TypedQuery<${l.relatedTableName}> get ${l.fieldName} =>\n'
        "      TypedQuery<${l.relatedTableName}>(${l.relatedTableName}(), relationAttr: '${_escape(l.attr)}');",
      );

      // fromRow arg
      if (l.toMany) {
        if (!l.nullable) {
          // Non-nullable List<T>: guard + fallback to empty list.
          ctorArgs.writeln(
            "        ${l.fieldName}: (m['${_escape(l.attr)}'] as List<dynamic>?)\n"
            '                ?.whereType<Map<String, dynamic>>()\n'
            '                .map(${l.relatedTableName}().fromRow)\n'
            '                .toList() ??\n'
            '            const <${l.relatedTypeName}>[],',
          );
        } else {
          // Nullable List<T>?: guard, no fallback.
          ctorArgs.writeln(
            "        ${l.fieldName}: (m['${_escape(l.attr)}'] as List<dynamic>?)\n"
            '                ?.whereType<Map<String, dynamic>>()\n'
            '                .map(${l.relatedTableName}().fromRow)\n'
            '                .toList(),',
          );
        }
      } else {
        // To-one (treat as nullable T? regardless of declared nullability).
        ctorArgs.writeln(
          '        ${l.fieldName}: (() {\n'
          "          final l = (m['${_escape(l.attr)}'] as List<dynamic>?)?.whereType<Map<String, dynamic>>();\n"
          '          return (l == null || l.isEmpty) ? null : ${l.relatedTableName}().fromRow(l.first);\n'
          '        })(),',
        );
      }
    }

    // RelationRef static consts, one per relation, placed after the accessors.
    final relationRefs = StringBuffer();
    for (final l in links) {
      relationRefs.writeln(
        "  static const ${l.fieldName}Rel = RelationRef<${l.relatedTableName}>('${_escape(l.attr)}');",
      );
    }

    // toMap entries over scalar fields only (relations excluded).
    final toMapEntries = StringBuffer();
    for (final f in fields) {
      toMapEntries.writeln("        '${_escape(f.attr)}': m.${f.fieldName},");
    }

    // Build the class body: scalar cols + link accessors + relation refs
    // (separated by blank lines when present), then fromRow + toMap.
    final classBody = StringBuffer();
    final colsStr = cols.toString().trimRight();
    final linkStr = linkAccessors.toString().trimRight();
    final refsStr = relationRefs.toString().trimRight();

    final sections = <String>[
      if (colsStr.isNotEmpty) colsStr,
      if (linkStr.isNotEmpty) linkStr,
      if (refsStr.isNotEmpty) refsStr,
    ];
    classBody.write(sections.join('\n\n'));

    return '''
class $tableName extends InstantModelTable<$tableName, $modelName> {
  $tableName() : super('${_escape(entityType)}');

${classBody.toString().trimRight()}

  @override
  $modelName fromRow(Map<String, dynamic> m) => $modelName(
${ctorArgs.toString().trimRight()}
      );

  Map<String, dynamic> toMap($modelName m) => {
${toMapEntries.toString().trimRight()}
      };
}

extension ${modelName}QueryX on TypedQuery<$tableName> {
  Future<List<$modelName>> getAll(InstantDB db) async =>
      (await db.queryOnceTyped(this))
          .documents
          .map($tableName().fromRow)
          .toList();

  ReadonlySignal<List<$modelName>> watchAll(InstantDB db) {
    final src = db.queryTyped(this);
    return computed(
        () => src.value.documents.map($tableName().fromRow).toList());
  }
}

extension ${modelName}TxX on TypedTx<$tableName> {
  TransactionChunk createModel($modelName m) =>
      createFromMap($tableName().toMap(m));
  TransactionChunk updateModel(String id, $modelName m) =>
      updateFromMap(id, $tableName().toMap(m));
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

      // Skip fields marked with @InstantLink — handled separately.
      if (_hasInstantLink(field)) continue;

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

  List<_LinkInfo> _modelLinks(ClassElement element) {
    final result = <_LinkInfo>[];
    for (final field in element.fields) {
      if (field.isStatic || field.isSynthetic) continue;
      if (!_hasInstantLink(field)) continue;

      final linkAnnotation = _instantLinkAnnotation(field);
      final type = field.type;

      bool toMany;
      DartType related;

      if (type is InterfaceType && type.isDartCoreList) {
        toMany = true;
        related = type.typeArguments.first;
      } else {
        toMany = false;
        // Strip nullability for the related type.
        related = type;
      }

      // The related type name (the model class name, e.g. "Todo").
      final relatedTypeName =
          (related.element as ClassElement?)?.name ?? related.getDisplayString(withNullability: false);
      final relatedTableName = '${relatedTypeName}Table';

      // Validate the related element carries @InstantModel.
      final relatedClass = related.element;
      if (relatedClass is! ClassElement ||
          _instantModelAnnotationForClass(relatedClass) == null) {
        throw InvalidGenerationSourceError(
          'Relation field "${field.name}" on ${element.name} targets '
          '"$relatedTypeName", which is not an @InstantModel.',
          element: field,
        );
      }

      // attr defaults to field name; can be overridden with @InstantLink(attr: 'x').
      final attrOverride =
          linkAnnotation?.getField('attr')?.toStringValue();
      final attr = attrOverride ?? field.name;

      final nullable = type.nullabilitySuffix == NullabilitySuffix.question;

      result.add(_LinkInfo(
        fieldName: field.name,
        attr: attr,
        relatedTypeName: relatedTypeName,
        relatedTableName: relatedTableName,
        toMany: toMany,
        nullable: nullable,
      ));
    }
    return result;
  }

  bool _hasInstantLink(FieldElement field) {
    for (final meta in field.metadata) {
      final value = meta.computeConstantValue();
      if (value?.type?.element?.name == 'InstantLink') return true;
    }
    return false;
  }

  DartObject? _instantLinkAnnotation(FieldElement field) {
    for (final meta in field.metadata) {
      final value = meta.computeConstantValue();
      if (value?.type?.element?.name == 'InstantLink') return value;
    }
    return null;
  }

  DartObject? _instantModelAnnotationForClass(ClassElement element) {
    for (final meta in element.metadata) {
      final value = meta.computeConstantValue();
      if (value?.type?.element?.name == _annotationName) return value;
    }
    return null;
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

class _LinkInfo {
  final String fieldName;
  final String attr;
  final String relatedTypeName;
  final String relatedTableName;
  final bool toMany;
  final bool nullable;
  _LinkInfo({
    required this.fieldName,
    required this.attr,
    required this.relatedTypeName,
    required this.relatedTableName,
    required this.toMany,
    required this.nullable,
  });
}
