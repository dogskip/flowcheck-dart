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

  /// 증분 스캔.
  ///
  /// 기존 베이스라인과 비교해 메타데이터(크기, 수정 시각)가 변경된
  /// 파일만 해시를 재계산한다. 메타데이터가 동일하면 내용도 동일하다고
  /// 간주해 기존 해시를 재사용한다. 이는 대규모 디렉토리에서 해시
  /// 계산 비용을 크게 줄인다.
  ///
  /// 보안: 메타데이터만으로는 변조를 확신할 수 없으므로, 신뢰할 수 없는
  /// 환경에서는 [forceFullScan] 옵션으로 전체 재해싱을 강제해야 한다.
  Future<Baseline> incrementalScan(
    Baseline previous, {
    bool forceFullScan = false,
  }) async {
    final rootAbs = PathSecurity.validateInsideRoot(root, root);
    final baseline = Baseline.empty(rootAbs);

    await _scanDirIncremental(
      Directory(rootAbs),
      baseline,
      previous,
      forceFullScan,
    );
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

  Future<void> _scanDirIncremental(
    Directory dir,
    Baseline baseline,
    Baseline previous,
    bool forceFullScan,
  ) async {
    if (!dir.existsSync()) {
      throw FileSystemException('directory not found', dir.path);
    }

    final stream = dir.list(recursive: true, followLinks: followSymlinks);
    await for (final entity in stream) {
      try {
        PathSecurity.validateInsideRoot(entity.path, root);
      } on PathTraversalException {
        continue;
      } on SymlinkLoopException {
        continue;
      }

      if (entity is! File) continue;
      if (_isExcluded(entity.path)) continue;

      try {
        final stat = entity.statSync();
        final old = previous.get(entity.path);

        if (!forceFullScan && old != null) {
          // 메타데이터가 동일하면 해시 재사용.
          if (old.size == stat.size && old.modified == stat.modified) {
            baseline.upsert(FileEntry(
              path: entity.path,
              size: stat.size,
              modified: stat.modified,
              hash: old.hash,
            ));
            continue;
          }
        }
        // 메타데이터가 다르거나 신규 파일이면 해시 재계산.
        final entry = await _hashFile(entity);
        baseline.upsert(entry);
      } catch (e) {
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
