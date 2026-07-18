import 'dart:io';

import 'package:flowcheck/flowcheck.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flowcheck_ignore_test');
    // macOS /tmp → /private/tmp symlink 정규화.
    tempDir = Directory(tempDir.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('IgnorePatterns.fromList', () {
    test('빈 패턴은 아무것도 제외하지 않는다', () {
      final ip = IgnorePatterns.fromList([]);
      expect(ip.isEmpty, isTrue);
      expect(ip.shouldExclude('/tmp/a.log'), isFalse);
    });

    test('주석과 빈 줄은 무시된다', () {
      final ip = IgnorePatterns.fromList([
        '# 이것은 주석',
        '',
        '   ',
        '*.log',
        '# 또 다른 주석',
      ]);
      expect(ip.length, 1);
    });

    test('확장자 패턴이 매칭된다', () {
      final ip = IgnorePatterns.fromList(['*.log']);
      expect(ip.shouldExclude('/root/app/debug.log'), isTrue);
      expect(ip.shouldExclude('/root/app/error.log'), isTrue);
      expect(ip.shouldExclude('/root/app/notes.txt'), isFalse);
    });

    test('디렉토리 패턴이 경로 어디서든 매칭된다', () {
      final ip = IgnorePatterns.fromList(['node_modules/']);
      expect(ip.shouldExclude('/root/node_modules/pkg/index.js'), isTrue);
      expect(ip.shouldExclude('/root/app/node_modules/lodash/index.js'), isTrue);
      expect(ip.shouldExclude('/root/app/main.dart'), isFalse);
    });

    test('.git 디렉토리가 제외된다', () {
      final ip = IgnorePatterns.fromList(['.git/']);
      expect(ip.shouldExclude('/root/.git/config'), isTrue);
      expect(ip.shouldExclude('/root/.git/refs/heads/main'), isTrue);
    });

    test('중첩 디렉토리 glob 패턴', () {
      final ip = IgnorePatterns.fromList(['build/*.tmp']);
      expect(ip.shouldExclude('/root/build/output.tmp'), isTrue);
      expect(ip.shouldExclude('/root/build/final.bin'), isFalse);
    });

    test('백업 파일 패턴', () {
      final ip = IgnorePatterns.fromList(['*~']);
      expect(ip.shouldExclude('/root/notes.txt~'), isTrue);
      expect(ip.shouldExclude('/root/notes.txt'), isFalse);
    });

    test('여러 패턴 조합', () {
      final ip = IgnorePatterns.fromList([
        '*.log',
        'node_modules/',
        '.git/',
        '*.tmp',
      ]);
      expect(ip.shouldExclude('/root/app.log'), isTrue);
      expect(ip.shouldExclude('/root/node_modules/x.js'), isTrue);
      expect(ip.shouldExclude('/root/.git/HEAD'), isTrue);
      expect(ip.shouldExclude('/root/cache.tmp'), isTrue);
      expect(ip.shouldExclude('/root/src/main.dart'), isFalse);
    });
  });

  group('IgnorePatterns.shouldExclude with rootPath', () {
    test('루트 기준 상대 경로로 매칭', () {
      final ip = IgnorePatterns.fromList(['sub/*.txt']);
      expect(
        ip.shouldExclude('/root/sub/a.txt', rootPath: '/root'),
        isTrue,
      );
      expect(
        ip.shouldExclude('/root/sub/b.txt', rootPath: '/root'),
        isTrue,
      );
      expect(
        ip.shouldExclude('/root/other/c.txt', rootPath: '/root'),
        isFalse,
      );
    });

    test('루트 밖 경로는 매칭되지 않는다', () {
      final ip = IgnorePatterns.fromList(['*.log']);
      expect(
        ip.shouldExclude('/other/a.log', rootPath: '/root'),
        isTrue, // 패턴 자체는 매칭됨 (경로 무관)
      );
    });
  });

  group('IgnorePatterns.loadFromFile', () {
    test('파일에서 패턴을 로드한다', () async {
      final file = File('${tempDir.path}/.flowcheckignore');
      await file.writeAsString('''
# 로그 파일
*.log

# 의존성
node_modules/

# 빌드 산출물
build/
''');
      final ip = IgnorePatterns.loadFromFile(file.path);
      expect(ip.length, 3);
      expect(ip.shouldExclude('/root/app.log'), isTrue);
      expect(ip.shouldExclude('/root/node_modules/x'), isTrue);
      expect(ip.shouldExclude('/root/build/out'), isTrue);
      expect(ip.shouldExclude('/root/src/main.dart'), isFalse);
    });

    test('파일이 없으면 빈 패턴을 반환한다', () {
      final ip = IgnorePatterns.loadFromFile('/nonexistent/.flowcheckignore');
      expect(ip.isEmpty, isTrue);
    });

    test('인라인 주석은 패턴의 일부로 간주된다', () async {
      // gitignore와 달리 # 은 줄 시작에만 주석으로 처리.
      final file = File('${tempDir.path}/.flowcheckignore');
      await file.writeAsString('*.log\n# 주석\nbuild/\n');
      final ip = IgnorePatterns.loadFromFile(file.path);
      expect(ip.length, 2);
    });
  });

  group('Scanner with IgnorePatterns', () {
    test('IgnorePatterns로 파일을 제외한다', () async {
      await File('${tempDir.path}/keep.txt').writeAsString('keep');
      await File('${tempDir.path}/skip.log').writeAsString('skip');
      await Directory('${tempDir.path}/node_modules').create();
      await File('${tempDir.path}/node_modules/lib.js').writeAsString('lib');

      final ip = IgnorePatterns.fromList(['*.log', 'node_modules/']);
      final scanner = Scanner(
        root: tempDir.path,
        ignorePatterns: ip,
      );
      final baseline = await scanner.scan();

      expect(baseline.size, 1);
      expect(baseline.get('${tempDir.path}/keep.txt'), isNotNull);
      expect(baseline.get('${tempDir.path}/skip.log'), isNull);
      expect(baseline.get('${tempDir.path}/node_modules/lib.js'), isNull);
    });

    test('.flowcheckignore 파일을 로드해 적용한다', () async {
      await File('${tempDir.path}/.flowcheckignore').writeAsString(
        '*.tmp\n.flowcheckignore\n',
      );
      await File('${tempDir.path}/data.bin').writeAsString('data');
      await File('${tempDir.path}/cache.tmp').writeAsString('cache');

      final ip = IgnorePatterns.loadFromFile('${tempDir.path}/.flowcheckignore');
      final scanner = Scanner(
        root: tempDir.path,
        ignorePatterns: ip,
      );
      final baseline = await scanner.scan();

      expect(baseline.size, 1);
      expect(baseline.get('${tempDir.path}/data.bin'), isNotNull);
      expect(baseline.get('${tempDir.path}/cache.tmp'), isNull);
      expect(baseline.get('${tempDir.path}/.flowcheckignore'), isNull);
    });
  });

  group('Scanner symlink 순환 감지', () {
    test('symlink 순환을 건너뛴다', () async {
      // 자기 자신을 가리키는 디렉토리 symlink 생성.
      await Directory('${tempDir.path}/real').create();
      await File('${tempDir.path}/real/file.txt').writeAsString('content');

      // 순환: loop -> real -> loop (real 안에서 loop를 가리킴)
      await Link('${tempDir.path}/loop').create('${tempDir.path}/real');
      // real 안에 loop를 다시 가리키는 symlink (순환 구성)
      await Link('${tempDir.path}/real/loop').create('${tempDir.path}/loop');

      final scanner = Scanner(
        root: tempDir.path,
        followSymlinks: true,
      );
      // 순환 감지 시 예외 대신 건너뛰어야 한다.
      final baseline = await scanner.scan();
      // real/file.txt는 해싱되어야 함.
      expect(
        baseline.get('${tempDir.path}/real/file.txt'),
        isNotNull,
      );
    });

    test('루트 밖으로 나가는 symlink를 거부한다', () async {
      // 루트 밖 디렉토리 생성.
      final outsideDir =
          await Directory.systemTemp.createTemp('flowcheck_outside');
      try {
        await File('${outsideDir.path}/secret.txt').writeAsString('secret');

        // 루트 안에서 밖을 가리키는 symlink.
        await Link('${tempDir.path}/escape').create(outsideDir.path);

        final scanner = Scanner(
          root: tempDir.path,
          followSymlinks: true,
        );
        final baseline = await scanner.scan();

        // 루트 밖 파일은 베이스라인에 없어야 함.
        expect(
          baseline.get('${outsideDir.path}/secret.txt'),
          isNull,
        );
      } finally {
        await outsideDir.delete(recursive: true);
      }
    });
  });
}
