import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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
