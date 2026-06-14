#!/usr/bin/env dart

/// InstantDB Schema Management CLI
///
/// This CLI tool helps manage InstantDB schemas for Flutter/Dart projects.
/// It wraps the official InstantDB CLI and provides TypeScript ↔ Dart conversion.
///
/// Usage:
///   dart run instantdb_flutter:schema <command> [options]
///
/// Commands:
///   pull      Pull schema from InstantDB cloud and convert to Dart
///   push      Convert Dart schema to TypeScript and push to cloud
///   status    Show current schema status
///   validate  Validate Dart schema file
///   diff      Compare local Dart schema with cloud schema
///   help      Show this help message
///
/// Examples:
///   dart run instantdb_flutter:schema pull
///   dart run instantdb_flutter:schema push
///   dart run instantdb_flutter:schema validate lib/schema/app_schema.dart

import 'dart:io';
import 'package:args/args.dart';
import 'package:flutter_instantdb/src/schema/instant_schema_io.dart';

void main(List<String> arguments) async {
  final parser = ArgParser()
    ..addFlag(
      'help',
      abbr: 'h',
      negatable: false,
      help: 'Show this help message',
    )
    ..addOption('app-id', abbr: 'a', help: 'InstantDB app ID')
    ..addOption(
      'schema-file',
      abbr: 's',
      defaultsTo: 'lib/schema/app_schema.dart',
      help: 'Path to Dart schema file',
    )
    ..addFlag(
      'verbose',
      abbr: 'v',
      negatable: false,
      help: 'Enable verbose logging',
    );

  try {
    final results = parser.parse(arguments);

    if (results['help'] as bool || results.rest.isEmpty) {
      _showHelp(parser);
      exit(0);
    }

    final command = results.rest.first;
    final verbose = results['verbose'] as bool;
    final appId = results['app-id'] as String?;
    final schemaFile = results['schema-file'] as String;

    switch (command) {
      case 'pull':
        await _pullSchema(
          appId: appId,
          schemaFile: schemaFile,
          verbose: verbose,
        );
        break;
      case 'push':
        await _pushSchema(
          appId: appId,
          schemaFile: schemaFile,
          verbose: verbose,
        );
        break;
      case 'status':
        await _showStatus(schemaFile: schemaFile, verbose: verbose);
        break;
      case 'validate':
        await _validateSchema(schemaFile: schemaFile, verbose: verbose);
        break;
      case 'diff':
        await _diffSchema(
          appId: appId,
          schemaFile: schemaFile,
          verbose: verbose,
        );
        break;
      case 'to-dart':
        await _toDart(
          input: results.rest.length > 1 ? results.rest[1] : null,
          schemaFile: schemaFile,
          verbose: verbose,
        );
        break;
      case 'to-ts':
        await _toTs(schemaFile: schemaFile, verbose: verbose);
        break;
      case 'help':
        _showHelp(parser);
        break;
      default:
        _error('Unknown command: $command');
        _showHelp(parser);
        exit(1);
    }
  } catch (e) {
    _error('Error: $e');
    exit(1);
  }
}

void _showHelp(ArgParser parser) {
  print('''
InstantDB Schema Management CLI
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Manage InstantDB schemas for Flutter/Dart projects.

USAGE:
  dart run instantdb_flutter:schema <command> [options]

COMMANDS:
  pull            Pull schema from cloud (instant-cli) and convert TS -> Dart
  push            Convert Dart -> instant.schema.ts and push to cloud
  to-dart <ts>    Offline: convert an instant.schema.ts to Dart @InstantModel
  to-ts           Offline: convert the Dart schema file to instant.schema.ts
  status          Show current schema status
  validate        Validate Dart schema file syntax
  diff            Compare local Dart schema with cloud schema
  help            Show this help message

OPTIONS:
${parser.usage}

EXAMPLES:
  # Pull schema from cloud (requires npx instant-cli installed)
  dart run instantdb_flutter:schema pull

  # Push local Dart schema to cloud
  dart run instantdb_flutter:schema push

  # Validate your Dart schema file
  dart run instantdb_flutter:schema validate

  # Show current schema status
  dart run instantdb_flutter:schema status

  # Compare local vs cloud
  dart run instantdb_flutter:schema diff

  # Offline conversion (no cloud / npx)
  dart run instantdb_flutter:schema to-dart instant.schema.ts -s lib/schema/app_schema.dart
  dart run instantdb_flutter:schema to-ts -s lib/schema/app_schema.dart

  # Use custom schema file location
  dart run instantdb_flutter:schema pull -s lib/my_schema.dart

PREREQUISITES:
  - Node.js and npx must be installed
  - InstantDB CLI: npx instant-cli@latest login
  - Set INSTANT_APP_ID environment variable or use --app-id flag

MORE INFO:
  https://github.com/pillowsoft/instantdb_flutter
  https://www.instantdb.com/docs/cli
''');
}

Future<void> _pullSchema({
  String? appId,
  required String schemaFile,
  required bool verbose,
}) async {
  _info('Pulling schema from InstantDB cloud...');

  // Check if instant-cli is available
  final cliCheck = await Process.run('npx', [
    'instant-cli@latest',
    '--version',
  ]);
  if (cliCheck.exitCode != 0) {
    _error('InstantDB CLI not found. Install Node.js and npx first.');
    exit(1);
  }

  // Run npx instant-cli pull
  _info('Running: npx instant-cli@latest pull');
  final pullProcess = await Process.start('npx', [
    'instant-cli@latest',
    'pull',
  ], mode: ProcessStartMode.inheritStdio);

  final exitCode = await pullProcess.exitCode;
  if (exitCode != 0) {
    _error('Failed to pull schema from cloud (exit code: $exitCode)');
    exit(exitCode);
  }

  // Check if instant.schema.ts was created
  final tsSchemaFile = File('instant.schema.ts');
  if (!await tsSchemaFile.exists()) {
    _error('instant.schema.ts not found after pull');
    exit(1);
  }

  _success('Schema pulled successfully: instant.schema.ts');

  // Convert TS -> Dart.
  final ts = await tsSchemaFile.readAsString();
  await _writeDartFromTs(ts, schemaFile);
  _success('Converted to Dart: $schemaFile');

  print('');
  _info('Next steps:');
  print('  1. Review $schemaFile');
  print('  2. Run: dart run build_runner build');
}

/// Convert TS source to a Dart `@InstantModel` file at [schemaFile],
/// deriving the `part` base name from the output filename.
Future<void> _writeDartFromTs(String ts, String schemaFile) async {
  final schema = parseInstantTs(ts);
  final partBase = _baseName(schemaFile);
  final dart = emitDart(schema, partBase: partBase);
  final out = File(schemaFile);
  await out.parent.create(recursive: true);
  await out.writeAsString(dart);
}

/// Filename without directory or `.dart` extension.
String _baseName(String path) {
  final name = path.split(Platform.pathSeparator).last.split('/').last;
  return name.endsWith('.dart')
      ? name.substring(0, name.length - '.dart'.length)
      : name;
}

Future<void> _pushSchema({
  String? appId,
  required String schemaFile,
  required bool verbose,
}) async {
  _info('Pushing schema to InstantDB cloud...');

  // Check if Dart schema file exists
  final dartSchema = File(schemaFile);
  if (!await dartSchema.exists()) {
    _error('Dart schema file not found: $schemaFile');
    exit(1);
  }

  // Convert Dart -> TS.
  final tsSchemaFile = File('instant.schema.ts');
  await _writeTsFromDart(await dartSchema.readAsString(), tsSchemaFile);
  _success('Generated instant.schema.ts from $schemaFile');
  print('');

  final confirmation = _confirm('Continue with push?');
  if (!confirmation) {
    _info('Push cancelled');
    exit(0);
  }

  // Run npx instant-cli push schema
  _info('Running: npx instant-cli@latest push schema');
  final pushProcess = await Process.start('npx', [
    'instant-cli@latest',
    'push',
    'schema',
  ], mode: ProcessStartMode.inheritStdio);

  final exitCode = await pushProcess.exitCode;
  if (exitCode != 0) {
    _error('Failed to push schema to cloud (exit code: $exitCode)');
    exit(exitCode);
  }

  _success('Schema pushed successfully!');
}

/// Convert a Dart `@InstantModel` source to `instant.schema.ts` at [out].
Future<void> _writeTsFromDart(String dartSource, File out) async {
  final schema = parseDartModels(dartSource);
  final ts = emitInstantTs(schema);
  await out.writeAsString(ts);
}

/// Offline TS -> Dart (no cloud / npx).
Future<void> _toDart({
  String? input,
  required String schemaFile,
  required bool verbose,
}) async {
  final inputPath = input ?? 'instant.schema.ts';
  final tsFile = File(inputPath);
  if (!await tsFile.exists()) {
    _error('TypeScript schema not found: $inputPath');
    exit(1);
  }
  _info('Converting $inputPath -> $schemaFile');
  await _writeDartFromTs(await tsFile.readAsString(), schemaFile);
  _success('Wrote Dart schema: $schemaFile');
  _info('Next: dart run build_runner build');
}

/// Offline Dart -> TS (no cloud / npx).
Future<void> _toTs({
  required String schemaFile,
  required bool verbose,
}) async {
  final dartSchema = File(schemaFile);
  if (!await dartSchema.exists()) {
    _error('Dart schema file not found: $schemaFile');
    exit(1);
  }
  _info('Converting $schemaFile -> instant.schema.ts');
  await _writeTsFromDart(
    await dartSchema.readAsString(),
    File('instant.schema.ts'),
  );
  _success('Wrote TypeScript schema: instant.schema.ts');
}

Future<void> _showStatus({
  required String schemaFile,
  required bool verbose,
}) async {
  _info('Schema Status');
  print('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Check Dart schema
  final dartSchema = File(schemaFile);
  if (await dartSchema.exists()) {
    final stat = await dartSchema.stat();
    _success('Dart Schema: $schemaFile');
    print('  Size: ${stat.size} bytes');
    print('  Modified: ${stat.modified}');
  } else {
    _warn('Dart Schema: Not found ($schemaFile)');
  }

  print('');

  // Check TypeScript schema
  final tsSchema = File('instant.schema.ts');
  if (await tsSchema.exists()) {
    final stat = await tsSchema.stat();
    _success('TypeScript Schema: instant.schema.ts');
    print('  Size: ${stat.size} bytes');
    print('  Modified: ${stat.modified}');
  } else {
    _warn('TypeScript Schema: Not found (instant.schema.ts)');
  }

  print('');

  // Check if instant-cli is available
  final cliCheck = await Process.run('npx', [
    'instant-cli@latest',
    '--version',
  ]);
  if (cliCheck.exitCode == 0) {
    _success('InstantDB CLI: Available');
  } else {
    _warn('InstantDB CLI: Not found (install Node.js and npx)');
  }
}

Future<void> _validateSchema({
  required String schemaFile,
  required bool verbose,
}) async {
  _info('Validating Dart schema: $schemaFile');

  final dartSchema = File(schemaFile);
  if (!await dartSchema.exists()) {
    _error('Schema file not found: $schemaFile');
    exit(1);
  }

  // Basic validation - check if file is valid Dart
  final content = await dartSchema.readAsString();

  // Check for common schema patterns
  final hasSchema =
      content.contains('InstantSchema') ||
      content.contains('i.schema') ||
      content.contains('schema');

  if (!hasSchema) {
    _warn('Warning: File does not appear to contain a schema definition');
  }

  _success('Schema file exists and is readable');
  _info('File size: ${content.length} characters');

  // TODO: Add more sophisticated validation
  _warn('⚠️  Advanced validation not yet implemented');
  _warn('    Consider running: dart analyze $schemaFile');
}

Future<void> _diffSchema({
  String? appId,
  required String schemaFile,
  required bool verbose,
}) async {
  _info('Comparing local Dart schema with instant.schema.ts...');

  final dartSchema = File(schemaFile);
  if (!await dartSchema.exists()) {
    _error('Dart schema file not found: $schemaFile');
    exit(1);
  }
  final tsFile = File('instant.schema.ts');
  if (!await tsFile.exists()) {
    _error('instant.schema.ts not found');
    _warn('Run "schema pull" to fetch the cloud schema first.');
    exit(1);
  }

  // Normalize both sides to TS and do a best-effort line diff.
  final localTs = emitInstantTs(parseDartModels(await dartSchema.readAsString()));
  final cloudTs = emitInstantTs(parseInstantTs(await tsFile.readAsString()));

  if (localTs == cloudTs) {
    _success('Schemas are equivalent (normalized).');
    return;
  }

  _warn('Schemas differ (normalized line diff):');
  final localLines = localTs.split('\n');
  final cloudLines = cloudTs.split('\n');
  final max = localLines.length > cloudLines.length
      ? localLines.length
      : cloudLines.length;
  for (var i = 0; i < max; i++) {
    final l = i < localLines.length ? localLines[i] : '';
    final c = i < cloudLines.length ? cloudLines[i] : '';
    if (l != c) {
      if (l.isNotEmpty) print('  - local: $l');
      if (c.isNotEmpty) print('  + cloud: $c');
    }
  }
  _info('Note: diff is best-effort on normalized output (number->num, '
      'link reverse synthesis).');
}

// ============================================================================
// Utility Functions
// ============================================================================

void _info(String message) {
  print('\x1B[34mℹ\x1B[0m $message');
}

void _success(String message) {
  print('\x1B[32m✓\x1B[0m $message');
}

void _warn(String message) {
  print('\x1B[33m⚠\x1B[0m $message');
}

void _error(String message) {
  print('\x1B[31m✗\x1B[0m $message');
}

bool _confirm(String message) {
  stdout.write('\x1B[33m?\x1B[0m $message (y/N): ');
  final response = stdin.readLineSync()?.toLowerCase().trim() ?? 'n';
  return response == 'y' || response == 'yes';
}
