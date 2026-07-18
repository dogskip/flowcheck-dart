import 'dart:io';

import 'package:flowcheck/flowcheck.dart';

/// flowcheck CLI.
///
/// 사용법:
///   flowcheck init <root> [--baseline <path>]
///   flowcheck check <root> [--baseline <path>]
///   flowcheck update <root> [--baseline <path>]
Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    _usage();
    exit(1);
  }

  final command = args[0];
  final positional = args.where((a) => !a.startsWith('--')).skip(1).toList();
  final baselinePath = _argValue(args, '--baseline') ?? '.flowcheck.json';

  switch (command) {
    case 'init':
      await _cmdInit(positional, baselinePath);
      break;
    case 'check':
      await _cmdCheck(positional, baselinePath);
      break;
    case 'update':
      await _cmdUpdate(positional, baselinePath);
      break;
    default:
      stderr.writeln('unknown command: $command');
      _usage();
      exit(1);
  }
}

Future<void> _cmdInit(List<String> positional, String baselinePath) async {
  if (positional.isEmpty) {
    stderr.writeln('init requires <root>');
    exit(1);
  }
  final root = positional.first;
  final scanner = Scanner(root: root);
  try {
    final baseline = await scanner.scan();
    baseline.save(baselinePath);
    print('baseline created: $baselinePath (${baseline.size} files)');
  } catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  }
}

Future<void> _cmdCheck(List<String> positional, String baselinePath) async {
  if (positional.isEmpty) {
    stderr.writeln('check requires <root>');
    exit(1);
  }
  final root = positional.first;
  try {
    final baseline = Baseline.load(baselinePath);
    final scanner = Scanner(root: root);
    final diff = await scanner.diff(baseline);
    print(diff.toReport());
    exit(diff.isClean ? 0 : 1);
  } catch (e) {
    stderr.writeln('error: $e');
    exit(2);
  }
}

Future<void> _cmdUpdate(List<String> positional, String baselinePath) async {
  if (positional.isEmpty) {
    stderr.writeln('update requires <root>');
    exit(1);
  }
  final root = positional.first;
  final scanner = Scanner(root: root);
  try {
    final baseline = await scanner.scan();
    baseline.save(baselinePath);
    print('baseline updated: $baselinePath (${baseline.size} files)');
  } catch (e) {
    stderr.writeln('error: $e');
    exit(1);
  }
}

String? _argValue(List<String> args, String name) {
  for (var i = 0; i < args.length - 1; i++) {
    if (args[i] == name) {
      return args[i + 1];
    }
  }
  return null;
}

void _usage() {
  stderr.writeln('usage: flowcheck [init|check|update] <root> [--baseline <path>]');
}
