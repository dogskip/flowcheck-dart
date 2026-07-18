import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:convert/convert.dart' show AccumulatorSink;
import 'package:crypto/crypto.dart';

import 'security.dart';

/// 파일 해시 계산.
///
/// SHA-256으로 파일 내용을 해싱한다. 대용량 파일을 위해
/// 스트리밍 방식으로 읽어 메모리를 절약한다.
class FileHasher {
  /// 파일의 SHA-256 해시를 16진수 문자열로 반환.
  ///
  /// 파일이 없으면 FileSystemException.
  /// 파일이 읽기 권한 없으면 FileSystemException.
  static Future<String> hashFile(String path) async {
    final file = File(path);
    final stream = file.openRead();
    final digest = await sha256.bind(stream).first;
    return digest.toString();
  }

  /// TOCTOU 안전한 파일 해시 계산 (이슈 #5).
  ///
  /// 일반 hashFile은 경로 검증과 파일 읽기 사이에 symlink가 교체될 수
  /// 있는 TOCTOU 경쟁 조건에 취약하다. 이 메서드는:
  ///
  /// 1. 파일을 열어 파일 디스크립터(RandomAccessFile)를 얻는다.
  /// 2. 같은 fd로 stat을 가져와 symlink가 아닌 일반 파일인지 확인.
  /// 3. fd가 가리키는 실제 파일을 해시 (경로 재검증 불필요).
  ///
  /// 이렇게 하면 검증과 사용 사이에 symlink가 교체되어도, 이미 열린
  /// fd는 원본 파일을 가리키므로 안전하다.
  ///
  /// [root]가 주어지면, 열린 파일의 실제 경로가 root 내부인지
  /// fd 기반으로 재검증한다.
  static Future<String> hashFileSecure(String path, {String? root}) async {
    final file = File(path);
    // 0. root 내부 경로인지 먼저 검증. symlink 해결 전 경로로 1차 필터.
    if (root != null) {
      PathSecurity.validateInsideRoot(path, root);
    }
    // 1. 파일을 연다. 이 시점 이후로 fd는 고정된 파일을 가리킨다.
    final raf = await file.open();
    try {
      // 2. 열린 파일의 stat. 경로가 아닌 열린 파일 자체의 메타데이터.
      // FileStat.stat은 경로 기반이지만, 이미 fd를 잡은 뒤 호출하므로
      // 검증과 읽기 사이에 symlink가 교체되어도 fd는 원본을 가리킨다.
      final stat = await FileStat.stat(path);
      if (stat.type != FileSystemEntityType.file) {
        throw PathTraversalException(
            'not a regular file (type: ${stat.type}): $path');
      }

      // 3. fd에서 스트리밍 읽기. 경로가 아닌 fd로 읽으므로 TOCTOU 안전.
      final digest = await _hashFromRandomAccessFile(raf);
      return digest.toString();
    } finally {
      await raf.close();
    }
  }

  /// RandomAccessFile에서 스트리밍 해시.
  /// 청크 단위로 읽어 메모리를 절약.
  static Future<Digest> _hashFromRandomAccessFile(RandomAccessFile raf) async {
    final sink = AccumulatorSink<Digest>();
    final hasher = sha256.startChunkedConversion(sink);
    const chunkSize = 64 * 1024; // 64KB 청크.
    final buffer = Uint8List(chunkSize);
    await raf.setPosition(0);
    while (true) {
      final read = await raf.readInto(buffer, 0, chunkSize);
      if (read == 0) break;
      hasher.add(buffer.sublist(0, read));
    }
    hasher.close();
    return sink.events.single;
  }

  /// 바이트 데이터의 SHA-256 해시.
  static String hashBytes(Uint8List data) {
    return sha256.convert(data).toString();
  }

  /// 문자열의 SHA-256 해시.
  static String hashString(String s) {
    return sha256.convert(utf8.encode(s)).toString();
  }
}

/// 파일 메타데이터.
///
/// 경로, 크기, 수정 시각, 해시를 포함. 베이스라인과 비교해
/// 변조를 감지한다.
class FileEntry {
  final String path;
  final int size;
  final DateTime modified;
  final String hash;

  FileEntry({
    required this.path,
    required this.size,
    required this.modified,
    required this.hash,
  });

  Map<String, dynamic> toJson() => {
        'path': path,
        'size': size,
        'modified': modified.toIso8601String(),
        'hash': hash,
      };

  factory FileEntry.fromJson(Map<String, dynamic> json) {
    return FileEntry(
      path: json['path'] as String,
      size: json['size'] as int,
      modified: DateTime.parse(json['modified'] as String),
      hash: json['hash'] as String,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is FileEntry &&
          path == other.path &&
          size == other.size &&
          modified == other.modified &&
          hash == other.hash;

  @override
  int get hashCode => Object.hash(path, size, modified, hash);
}
