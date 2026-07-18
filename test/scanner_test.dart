import 'dart:io';

import 'package:flowcheck/flowcheck.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flowcheck_test');
    // macOS에서 /tmp가 /private/tmp로 symlink되어 있어 정규화 필요.
    tempDir = Directory(tempDir.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('FileHasher', () {
    test('hashFile returns SHA-256 hex', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('hello');
      final hash = await FileHasher.hashFile(file.path);
      expect(hash.length, 64);
      expect(hash, matches(RegExp(r'^[0-9a-f]+$')));
    });

    test('hashFile is deterministic', () async {
      final file = File('${tempDir.path}/test.txt');
      await file.writeAsString('hello');
      final h1 = await FileHasher.hashFile(file.path);
      final h2 = await FileHasher.hashFile(file.path);
      expect(h1, h2);
    });

    test('hashString matches known vector', () {
      // SHA-256("hello") = 2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824
      expect(FileHasher.hashString('hello'),
          '2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824');
    });

    test('different content produces different hash', () async {
      final f1 = File('${tempDir.path}/a.txt');
      final f2 = File('${tempDir.path}/b.txt');
      await f1.writeAsString('content1');
      await f2.writeAsString('content2');
      final h1 = await FileHasher.hashFile(f1.path);
      final h2 = await FileHasher.hashFile(f2.path);
      expect(h1, isNot(h2));
    });
  });

  group('Scanner', () {
    test('scan creates baseline with all files', () async {
      await File('${tempDir.path}/a.txt').writeAsString('a');
      await Directory('${tempDir.path}/sub').create();
      await File('${tempDir.path}/sub/b.txt').writeAsString('b');

      final scanner = Scanner(root: tempDir.path);
      final baseline = await scanner.scan();

      expect(baseline.size, 2);
      expect(baseline.get('${tempDir.path}/a.txt'), isNotNull);
      expect(baseline.get('${tempDir.path}/sub/b.txt'), isNotNull);
    });

    test('scan empty directory', () async {
      final scanner = Scanner(root: tempDir.path);
      final baseline = await scanner.scan();
      expect(baseline.size, 0);
    });

    test('diff detects added files', () async {
      await File('${tempDir.path}/a.txt').writeAsString('a');
      final scanner = Scanner(root: tempDir.path);
      final baseline = await scanner.scan();

      await File('${tempDir.path}/b.txt').writeAsString('b');
      final diff = await scanner.diff(baseline);

      expect(diff.added.length, 1);
      expect(diff.added.first.path, contains('b.txt'));
      expect(diff.isClean, isFalse);
    });

    test('diff detects removed files', () async {
      await File('${tempDir.path}/a.txt').writeAsString('a');
      await File('${tempDir.path}/b.txt').writeAsString('b');
      final scanner = Scanner(root: tempDir.path);
      final baseline = await scanner.scan();

      await File('${tempDir.path}/b.txt').delete();
      final diff = await scanner.diff(baseline);

      expect(diff.removed.length, 1);
      expect(diff.removed.first.path, contains('b.txt'));
    });

    test('diff detects modified files', () async {
      await File('${tempDir.path}/a.txt').writeAsString('original');
      final scanner = Scanner(root: tempDir.path);
      final baseline = await scanner.scan();

      await File('${tempDir.path}/a.txt').writeAsString('modified');
      final diff = await scanner.diff(baseline);

      expect(diff.modified.length, 1);
      expect(diff.modified.first.path, contains('a.txt'));
    });

    test('diff is clean when no changes', () async {
      await File('${tempDir.path}/a.txt').writeAsString('a');
      final scanner = Scanner(root: tempDir.path);
      final baseline = await scanner.scan();
      final diff = await scanner.diff(baseline);
      expect(diff.isClean, isTrue);
    });

    test('exclude patterns skip files', () async {
      await File('${tempDir.path}/a.txt').writeAsString('a');
      await File('${tempDir.path}/b.log').writeAsString('b');
      final scanner = Scanner(
        root: tempDir.path,
        excludePatterns: ['*.log'],
      );
      final baseline = await scanner.scan();
      expect(baseline.size, 1);
      expect(baseline.get('${tempDir.path}/a.txt'), isNotNull);
      expect(baseline.get('${tempDir.path}/b.log'), isNull);
    });
  });

  group('Baseline', () {
    test('save and load roundtrip', () async {
      await File('${tempDir.path}/a.txt').writeAsString('a');
      final scanner = Scanner(root: tempDir.path);
      final baseline = await scanner.scan();

      final baselinePath = '${tempDir.path}/baseline.json';
      baseline.save(baselinePath);

      final loaded = Baseline.load(baselinePath);
      expect(loaded.size, baseline.size);
      expect(loaded.root, baseline.root);
      expect(loaded.get('${tempDir.path}/a.txt')!.hash,
          baseline.get('${tempDir.path}/a.txt')!.hash);
    });

    test('load throws on missing file', () {
      expect(() => Baseline.load('/nonexistent/baseline.json'),
          throwsA(isA<FileSystemException>()));
    });
  });

  group('PathSecurity', () {
    test('validateInsideRoot accepts inside path', () async {
      final root = tempDir.path;
      final inside = '$root/sub/file.txt';
      await Directory('$root/sub').create();
      await File(inside).writeAsString('x');
      expect(() => PathSecurity.validateInsideRoot(inside, root), returnsNormally);
    });

    test('constantTimeEquals', () {
      expect(constantTimeEquals('abc', 'abc'), isTrue);
      expect(constantTimeEquals('abc', 'abd'), isFalse);
      expect(constantTimeEquals('abc', 'ab'), isFalse);
    });

    test('randomBytes produces unique values', () {
      final a = randomBytes(16);
      final b = randomBytes(16);
      expect(a.length, 16);
      expect(b.length, 16);
      // 극히 드물게 같을 수 있지만 16바이트면 사실상 불가능.
      expect(a, isNot(equals(b)));
    });
  });

  group('BaselineDiff', () {
    test('toReport contains status', () {
      final diff = BaselineDiff(
        added: [],
        removed: [],
        modified: [],
        metadataChanged: [],
      );
      final report = diff.toReport();
      expect(report, contains('CLEAN'));
      expect(diff.isClean, isTrue);
    });

    test('changeCount counts all changes', () {
      final entry = FileEntry(
        path: '/x',
        size: 10,
        modified: DateTime.now(),
        hash: 'abc',
      );
      final diff = BaselineDiff(
        added: [entry],
        removed: [entry],
        modified: [entry],
        metadataChanged: [entry],
      );
      expect(diff.changeCount, 4);
    });
  });
}
