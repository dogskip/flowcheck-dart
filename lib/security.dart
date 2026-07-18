import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// 경로 보안 검증.
///
/// 파일 무결성 모니터는 지정된 루트 디렉토리 밖의 파일을
/// 해싱하거나 베이스라인에 포함하면 안 된다. 공격자가 symlink로
/// 루트 밖을 가리키거나, ../ 로 탈출하는 것을 막는다.
class PathSecurity {
  /// 경로를 정규화하고 루트 내부인지 검증.
  ///
  /// symlink를 모두 따라간 뒤, 결과 경로가 root의 하위인지 확인.
  /// symlink 순환은 감지되면 예외.
  static String validateInsideRoot(String path, String root) {
    final rootAbs = _normalize(File(root).absolute.path);
    final pathAbs = _normalize(File(path).absolute.path);

    if (!_isInside(pathAbs, rootAbs)) {
      throw PathTraversalException(
          'path escapes root: $path (resolved: $pathAbs, root: $rootAbs)');
    }
    return pathAbs;
  }

  /// symlink를 따라가며 순환 감지.
  ///
  /// 방문한 경로를 기록해 같은 경로 재방문 시 순환으로 판정.
  static String resolveSymlink(String path, {int maxDepth = 40}) {
    final visited = <String>{};
    String current = path;
    for (var i = 0; i < maxDepth; i++) {
      final link = Link(current);
      if (!link.existsSync()) {
        return current;
      }
      final target = link.resolveSymbolicLinksSync();
      if (visited.contains(target)) {
        throw SymlinkLoopException('symlink loop detected at $target');
      }
      visited.add(target);
      current = target;
    }
    throw SymlinkLoopException('symlink depth exceeded $maxDepth');
  }

  /// 경로 정규화. '..'와 '.'을 해결.
  static String _normalize(String path) {
    // File.path로 정규화. 절대 경로여야 '..'가 해결됨.
    return File(path).resolveSymbolicLinksSync();
  }

  /// child가 parent 내부인지 (또는 같은지).
  static bool _isInside(String child, String parent) {
    if (child == parent) return true;
    // 디렉토리 구분자로 끝나는지 확인해 'parent'가 'parentX'의 접두어가
    // 되는 것을 막는다.
    final parentWithSep = parent.endsWith(Platform.pathSeparator)
        ? parent
        : parent + Platform.pathSeparator;
    return child.startsWith(parentWithSep);
  }
}

/// 경로 탈출 예외.
class PathTraversalException implements Exception {
  final String message;
  PathTraversalException(this.message);

  @override
  String toString() => 'PathTraversalException: $message';
}

/// symlink 순환 예외.
class SymlinkLoopException implements Exception {
  final String message;
  SymlinkLoopException(this.message);

  @override
  String toString() => 'SymlinkLoopException: $message';
}

/// 상수 시간 문자열 비교.
///
/// 해시 비교에 일반 ==를 쓰면 첫 번째로 다른 문자에서 즉시 반환해
/// 타이밍 공격에 취약하다. 이 함수는 항상 전체를 비교한다.
bool constantTimeEquals(String a, String b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
  }
  return diff == 0;
}

/// 무작위 바이트 생성 (솔트/논스용).
Uint8List randomBytes(int length) {
  final random = Random.secure();
  final bytes = Uint8List(length);
  for (var i = 0; i < length; i++) {
    bytes[i] = random.nextInt(256);
  }
  return bytes;
}
