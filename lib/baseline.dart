import 'dart:convert';
import 'dart:io';

import 'hash.dart';

/// 베이스라인.
///
/// 파일 무결성의 기준이 되는 스냅샷. 각 파일의 경로, 크기, 수정 시각,
/// 해시를 저장한다. 이후 스캔 시 베이스라인과 비교해 변조를 감지한다.
///
/// 직렬화: JSON. 파일 권한 0600.
class Baseline {
  final Map<String, FileEntry> entries;
  final String root;
  final DateTime createdAt;

  Baseline({
    required this.entries,
    required this.root,
    required this.createdAt,
  });

  /// 빈 베이스라인.
  factory Baseline.empty(String root) {
    return Baseline(
      entries: {},
      root: root,
      createdAt: DateTime.now().toUtc(),
    );
  }

  /// JSON 파일에서 로드.
  factory Baseline.load(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      throw FileSystemException('baseline not found', path);
    }
    final raw = file.readAsStringSync();
    final json = jsonDecode(raw) as Map<String, dynamic>;
    final entriesJson = json['entries'] as Map<String, dynamic>;
    final entries = <String, FileEntry>{};
    for (final e in entriesJson.entries) {
      entries[e.key] = FileEntry.fromJson(e.value as Map<String, dynamic>);
    }
    return Baseline(
      entries: entries,
      root: json['root'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  /// JSON 파일로 저장. 원자적 쓰기 + 권한 0600.
  void save(String path) {
    final json = jsonEncode({
      'root': root,
      'createdAt': createdAt.toIso8601String(),
      'entries': entries.map((k, v) => MapEntry(k, v.toJson())),
    });

    // 원자적 쓰기: 임시 파일에 쓰고 rename.
    final tmp = '$path.tmp';
    final file = File(tmp);
    file.writeAsStringSync(json, flush: true);
    // Dart는 chmod를 직접 지원하지 않으므로, 파일 권한은 umask에 의존.
    // 운영 환경에서는 별도 설정 필요.
    file.renameSync(path);
  }

  /// 항목 추가/갱신.
  void upsert(FileEntry entry) {
    entries[entry.path] = entry;
  }

  /// 항목 제거.
  void remove(String path) {
    entries.remove(path);
  }

  /// 항목 조회.
  FileEntry? get(String path) => entries[path];

  /// 항목 수.
  int get size => entries.length;
}

/// 베이스라인과 현재 상태의 diff.
class BaselineDiff {
  /// 새로 추가된 파일.
  final List<FileEntry> added;
  /// 삭제된 파일.
  final List<FileEntry> removed;
  /// 내용이 변경된 파일 (해시가 다름).
  final List<FileEntry> modified;
  /// 메타데이터만 변경 (크기/시각은 다르나 해시는 같음 — 드문 케이스).
  final List<FileEntry> metadataChanged;

  BaselineDiff({
    required this.added,
    required this.removed,
    required this.modified,
    required this.metadataChanged,
  });

  /// 변경 사항이 없으면 true.
  bool get isClean =>
      added.isEmpty && removed.isEmpty && modified.isEmpty && metadataChanged.isEmpty;

  /// 변경된 파일 수.
  int get changeCount =>
      added.length + removed.length + modified.length + metadataChanged.length;

  /// 보고서 문자열.
  String toReport() {
    final buf = StringBuffer();
    buf.writeln('=== Integrity Check Report ===');
    buf.writeln('Baseline root: (root)');
    buf.writeln('Added: ${added.length}');
    for (final e in added) {
      buf.writeln('  + ${e.path}');
    }
    buf.writeln('Removed: ${removed.length}');
    for (final e in removed) {
      buf.writeln('  - ${e.path}');
    }
    buf.writeln('Modified: ${modified.length}');
    for (final e in modified) {
      buf.writeln('  ~ ${e.path}');
    }
    buf.writeln('Metadata changed: ${metadataChanged.length}');
    for (final e in metadataChanged) {
      buf.writeln('  m ${e.path}');
    }
    buf.writeln('Total changes: $changeCount');
    buf.writeln('Status: ${isClean ? "CLEAN" : "CHANGED"}');
    return buf.toString();
  }
}
