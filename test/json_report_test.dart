import 'dart:convert';

import 'package:flowcheck/flowcheck.dart';
import 'package:test/test.dart';

void main() {
  group('BaselineDiff.toJson', () {
    test('clean diff produces CLEAN status', () {
      final diff = BaselineDiff(
        added: [],
        removed: [],
        modified: [],
        metadataChanged: [],
      );
      final json = diff.toJson();
      expect(json['status'], 'CLEAN');
      expect(json['totalChanges'], 0);
    });

    test('includes all change types', () {
      final entry = FileEntry(
        path: '/test/file.txt',
        size: 100,
        modified: DateTime.utc(2026, 1, 1),
        hash: 'abc123',
      );
      final diff = BaselineDiff(
        added: [entry],
        removed: [entry],
        modified: [entry],
        metadataChanged: [entry],
      );
      final json = diff.toJson();
      expect(json['status'], 'CHANGED');
      expect(json['totalChanges'], 4);
      expect((json['added'] as List).length, 1);
      expect((json['removed'] as List).length, 1);
      expect((json['modified'] as List).length, 1);
      expect((json['metadataChanged'] as List).length, 1);
    });

    test('entry json contains path, size, hash', () {
      final entry = FileEntry(
        path: '/x/y.txt',
        size: 42,
        modified: DateTime.utc(2026, 7, 19),
        hash: 'deadbeef',
      );
      final diff = BaselineDiff(
        added: [entry],
        removed: [],
        modified: [],
        metadataChanged: [],
      );
      final json = diff.toJson();
      final addedEntry = (json['added'] as List).first as Map<String, dynamic>;
      expect(addedEntry['path'], '/x/y.txt');
      expect(addedEntry['size'], 42);
      expect(addedEntry['hash'], 'deadbeef');
      expect(addedEntry['modified'], isNotNull);
    });
  });

  group('BaselineDiff.toJsonReport', () {
    test('produces valid JSON string', () {
      final entry = FileEntry(
        path: '/a.txt',
        size: 10,
        modified: DateTime.utc(2026, 1, 1),
        hash: 'h1',
      );
      final diff = BaselineDiff(
        added: [entry],
        removed: [],
        modified: [],
        metadataChanged: [],
      );
      final report = diff.toJsonReport();
      // 유효한 JSON으로 파싱되어야.
      final parsed = jsonDecode(report) as Map<String, dynamic>;
      expect(parsed['status'], 'CHANGED');
      expect(parsed['totalChanges'], 1);
    });

    test('is indented for readability', () {
      final diff = BaselineDiff(
        added: [],
        removed: [],
        modified: [],
        metadataChanged: [],
      );
      final report = diff.toJsonReport();
      // 들여쓰기가 포함되어야.
      expect(report, contains('  '));
    });
  });
}
