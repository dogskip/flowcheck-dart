import 'dart:io';

/// 제외 패턴 매칭.
///
/// `.flowcheckignore` 파일에 정의된 glob 패턴을 기반으로 스캔에서
/// 제외할 경로를 결정한다. gitignore와 유사한 문법을 지원한다.
///
/// 지원 패턴:
/// - `*.log`       — 확장자 매칭
/// - `node_modules/` — 디렉토리 이름 매칭 (경로 어디든)
/// - `.git/`       — 숨김 디렉토리
/// - `build/*.tmp` — 중첩 경로 glob
/// - `*~`          — 백업 파일
///
/// 주석(`#`)과 빈 줄은 무시된다.
class IgnorePatterns {
  /// 컴파일된 패턴 목록.
  final List<_CompiledPattern> _patterns;

  IgnorePatterns._(this._patterns);

  /// 빈 패턴 (아무것도 제외하지 않음).
  factory IgnorePatterns.empty() => IgnorePatterns._(const []);

  /// 패턴 문자열 목록으로부터 생성.
  ///
  /// 각 패턴은 glob 형태. 빈 줄과 `#`으로 시작하는 주석은 무시.
  factory IgnorePatterns.fromList(List<String> rawPatterns) {
    final compiled = <_CompiledPattern>[];
    for (final raw in rawPatterns) {
      final trimmed = raw.trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
      compiled.add(_compile(trimmed));
    }
    return IgnorePatterns._(compiled);
  }

  /// `.flowcheckignore` 파일에서 로드.
  ///
  /// 파일이 없으면 빈 패턴을 반환한다. 한 줄에 하나의 패턴이며
  /// `#`로 시작하는 줄은 주석으로 간주한다.
  factory IgnorePatterns.loadFromFile(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return IgnorePatterns.empty();
    }
    final lines = file.readAsLinesSync();
    return IgnorePatterns.fromList(lines);
  }

  /// 주어진 경로가 제외 대상인지 판별.
  ///
  /// [rootPath]는 루트 디렉토리의 절대 경로. [path]는 검사할 파일의
  /// 절대 경로. 루트 상대 경로로 변환한 뒤 각 패턴과 매칭한다.
  bool shouldExclude(String path, {String? rootPath}) {
    if (_patterns.isEmpty) return false;

    final normalizedPath = _normalizeSeparators(path);
    final relative = rootPath != null
        ? _toRelative(normalizedPath, _normalizeSeparators(rootPath))
        : normalizedPath;

    for (final pattern in _patterns) {
      if (pattern.matches(relative, normalizedPath)) {
        return true;
      }
    }
    return false;
  }

  /// 등록된 패턴 수 (주석/빈 줄 제외).
  int get length => _patterns.length;

  /// 패턴이 하나도 없으면 true.
  bool get isEmpty => _patterns.isEmpty;

  /// 단일 glob 패턴을 컴파일해 정규식 기반 매칭 객체 생성.
  static _CompiledPattern _compile(String pattern) {
    final normalized = _normalizeSeparators(pattern);
    final dirOnly = normalized.endsWith('/');
    final body = dirOnly ? normalized.substring(0, normalized.length - 1) : normalized;

    // 패턴이 경로 구분자를 포함하면 전체 경로 매칭, 아니면 경로의
    // 임의 위치에서 매칭 (gitignore 동작 흉내).
    final anchored = body.contains('/');

    final regex = RegExp(_globToRegex(body));
    return _CompiledPattern(
      regex: regex,
      dirOnly: dirOnly,
      anchored: anchored,
    );
  }

  /// glob 패턴을 정규식 문자열로 변환.
  ///
  /// - `*` → 경로 구분자가 아닌 임의 문자
  /// - `**` → 임의 문자 (구분자 포함)
  /// - 그 외 메타문자는 이스케이프
  static String _globToRegex(String glob) {
    final buf = StringBuffer('^');
    var i = 0;
    while (i < glob.length) {
      final c = glob[i];
      if (c == '*') {
        // `**`는 경로 구분자 포함, `*`는 미포함.
        if (i + 1 < glob.length && glob[i + 1] == '*') {
          buf.write('.*');
          i += 2;
          continue;
        }
        buf.write('[^/]*');
      } else if (RegExp(r'[.+^${}()|[\]\\]').hasMatch(c)) {
        buf.write('\\');
        buf.write(c);
      } else if (c == '?') {
        buf.write('[^/]');
      } else {
        buf.write(c);
      }
      i++;
    }
    buf.write(r'$');
    return buf.toString();
  }

  /// 경로 구분자를 슬래시로 통일 (크로스 플랫폼 지원).
  static String _normalizeSeparators(String path) {
    if (Platform.pathSeparator == '/') return path;
    return path.replaceAll(Platform.pathSeparator, '/');
  }

  /// 절대 경로를 루트 기준 상대 경로로 변환.
  ///
  /// 루트 밖이거나 변환 불가능하면 원래 경로를 반환.
  static String _toRelative(String path, String root) {
    if (path == root) return '';
    final rootWithSep = root.endsWith('/') ? root : '$root/';
    if (path.startsWith(rootWithSep)) {
      return path.substring(rootWithSep.length);
    }
    return path;
  }
}

/// 컴파일된 단일 패턴.
class _CompiledPattern {
  final RegExp regex;
  final bool dirOnly;
  final bool anchored;

  _CompiledPattern({
    required this.regex,
    required this.dirOnly,
    required this.anchored,
  });

  /// [relative]는 루트 기준 상대 경로, [absolute]는 절대 경로.
  /// 둘 다 슬래시 구분자로 정규화되어 있다고 가정.
  bool matches(String relative, String absolute) {
    // anchored 패턴은 경로의 한 세그먼트 경계에서 시작해 전체 매칭.
    // 예: `build/*.tmp`는 `/root/build/output.tmp`의 `build/output.tmp`
    // 부분에 매칭되어야 한다. 경로의 모든 접미사를 시도한다.
    if (anchored) {
      if (regex.hasMatch(relative)) return true;
      // 상대 경로의 각 접미사에 매칭 시도.
      final relSegs = relative.split('/');
      for (var i = 0; i < relSegs.length; i++) {
        if (relSegs[i].isEmpty) continue;
        final suffix = relSegs.sublist(i).join('/');
        if (regex.hasMatch(suffix)) return true;
      }
      // 절대 경로의 각 접미사에도 매칭 시도.
      final absSegs = absolute.split('/');
      for (var i = 0; i < absSegs.length; i++) {
        if (absSegs[i].isEmpty) continue;
        final suffix = absSegs.sublist(i).join('/');
        if (regex.hasMatch(suffix)) return true;
      }
      return false;
    }
    // 비-anchored 패턴은 경로의 각 세그먼트에 매칭.
    final segments = relative.split('/');
    for (final seg in segments) {
      if (seg.isEmpty) continue;
      if (regex.hasMatch(seg)) return true;
    }
    // 전체 경로에도 매칭 시도 (예: `build/*.tmp`).
    if (regex.hasMatch(relative)) return true;
    return false;
  }
}
