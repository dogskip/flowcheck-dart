import 'dart:io';

import 'baseline.dart';
import 'hash.dart';
import 'security.dart';

/// 파일 시스템 스캐너.
///
/// 지정된 루트 디렉토리를 재귀적으로 순회하며 각 파일의 해시를 계산.
/// 보안: 루트 밖으로 탈출하는 symlink를 따라가지 않고, 순환을 감지한다.
class Scanner {
  final String root;
  final bool followSymlinks;
  final List<String> excludePatterns;

  Scanner({
    required this.root,
    this.followSymlinks = false,
    this.excludePatterns = const [],
  });

  /// 루트의 모든 파일을 스캔해 베이스라인을 생성.
  Future<Baseline> scan() async {
    final rootAbs = PathSecurity.validateInsideRoot(root, root);
    final baseline = Baseline.empty(rootAbs);

    await _scanDir(Directory(rootAbs), baseline);
    return baseline;
  }

  Future<void> _scanDir(Directory dir, Baseline baseline) async {
    if (!dir.existsSync()) {
      throw FileSystemException('directory not found', dir.path);
    }

    final stream = dir.list(recursive: true, followLinks: followSymlinks);
    await for (final entity in stream) {
      // 경로가 루트 내부인지 검증 (symlink가 루트 밖을 가리킬 수 있음).
      try {
        PathSecurity.validateInsideRoot(entity.path, root);
      } on PathTraversalException {
        // 루트 밖이면 건너뜀.
        continue;
      } on SymlinkLoopException {
        continue;
      }

      if (entity is! File) continue;
      if (_isExcluded(entity.path)) continue;

      try {
        final entry = await _hashFile(entity);
        baseline.upsert(entry);
      } catch (e) {
        // 권한 오류 등은 건너뜀. 로그만.
        stderr.writeln('warning: skipping ${entity.path}: $e');
      }
    }
  }

  /// 단일 파일 해싱.
  Future<FileEntry> _hashFile(File file) async {
    final stat = file.statSync();
    final hash = await FileHasher.hashFile(file.path);
    return FileEntry(
      path: file.path,
      size: stat.size,
      modified: stat.modified,
      hash: hash,
    );
  }

  /// 제외 패턴 매칭.
  bool _isExcluded(String path) {
    for (final pattern in excludePatterns) {
      if (_matchPattern(path, pattern)) {
        return true;
      }
    }
    return false;
  }

  /// 단순 glob 매칭. '*'를 임의 문자열로.
  bool _matchPattern(String path, String pattern) {
    // 정규식으로 변환. 단순화: '*' → '.*'.
    final regexPattern = pattern
        .replaceAll('\\', '\\\\')
        .replaceAll('.', '\\.')
        .replaceAll('*', '.*');
    return RegExp(regexPattern).hasMatch(path);
  }

  /// 현재 상태를 베이스라인과 비교.
  Future<BaselineDiff> diff(Baseline baseline) async {
    final current = await scan();

    final added = <FileEntry>[];
    final removed = <FileEntry>[];
    final modified = <FileEntry>[];
    final metadataChanged = <FileEntry>[];

    // 추가/수정 감지.
    for (final entry in current.entries.values) {
      final old = baseline.get(entry.path);
      if (old == null) {
        added.add(entry);
      } else if (!constantTimeEquals(old.hash, entry.hash)) {
        modified.add(entry);
      } else if (old.size != entry.size || old.modified != entry.modified) {
        metadataChanged.add(entry);
      }
    }

    // 삭제 감지.
    for (final entry in baseline.entries.values) {
      if (!current.entries.containsKey(entry.path)) {
        removed.add(entry);
      }
    }

    return BaselineDiff(
      added: added,
      removed: removed,
      modified: modified,
      metadataChanged: metadataChanged,
    );
  }
}
