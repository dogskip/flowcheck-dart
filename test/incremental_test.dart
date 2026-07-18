import 'dart:io';

import 'package:flowcheck/flowcheck.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('flowcheck_inc');
    tempDir = Directory(tempDir.resolveSymbolicLinksSync());
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('Scanner.incrementalScan', () {
    test('reuses hash when metadata unchanged', () async {
      final file = File('${tempDir.path}/a.txt');
      await file.writeAsString('content-a');

      final scanner = Scanner(root: tempDir.path);
      final baseline1 = await scanner.scan();

      // 파일 변경 없이 증분 스캔.
      final baseline2 = await scanner.incrementalScan(baseline1);

      // 해시가 동일해야 (재사용).
      expect(baseline2.get(file.path)!.hash, baseline1.get(file.path)!.hash);
      expect(baseline2.size, 1);
    });

    test('recomputes hash when file modified', () async {
      final file = File('${tempDir.path}/a.txt');
      await file.writeAsString('original');

      final scanner = Scanner(root: tempDir.path);
      final baseline1 = await scanner.scan();

      // 파일 내용 변경. 수정 시각이 바뀌도록 약간 대기.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await file.writeAsString('modified');

      final baseline2 = await scanner.incrementalScan(baseline1);

      // 해시가 달라야.
      expect(baseline2.get(file.path)!.hash,
          isNot(equals(baseline1.get(file.path)!.hash)));
    });

    test('detects newly added files', () async {
      final scanner = Scanner(root: tempDir.path);
      final baseline1 = await scanner.scan();

      final newFile = File('${tempDir.path}/new.txt');
      await newFile.writeAsString('new content');

      final baseline2 = await scanner.incrementalScan(baseline1);
      expect(baseline2.get(newFile.path), isNotNull);
      expect(baseline2.size, 1);
    });

    test('forceFullScan recomputes all hashes', () async {
      final file = File('${tempDir.path}/a.txt');
      await file.writeAsString('content-a');

      final scanner = Scanner(root: tempDir.path);
      final baseline1 = await scanner.scan();

      // forceFullScan=true면 메타데이터 동일해도 재해싱.
      final baseline2 = await scanner.incrementalScan(
        baseline1,
        forceFullScan: true,
      );

      // 해시는 동일해야 (같은 내용이므로) 하지만 재계산됨.
      expect(baseline2.get(file.path)!.hash, baseline1.get(file.path)!.hash);
    });

    test('incremental matches full scan result', () async {
      // 여러 파일 생성.
      for (var i = 0; i < 5; i++) {
        await File('${tempDir.path}/file$i.txt').writeAsString('content-$i');
      }

      final scanner = Scanner(root: tempDir.path);
      final baseline1 = await scanner.scan();

      // 일부 파일 수정.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      await File('${tempDir.path}/file2.txt').writeAsString('changed-2');
      await File('${tempDir.path}/file6.txt').writeAsString('new-6');

      final incremental = await scanner.incrementalScan(baseline1);
      final full = await scanner.scan();

      // 두 결과의 해시가 모두 일치해야.
      expect(incremental.size, full.size);
      for (final entry in full.entries.values) {
        expect(incremental.get(entry.path)!.hash, entry.hash);
      }
    });

    test('handles empty directory', () async {
      final scanner = Scanner(root: tempDir.path);
      final baseline1 = await scanner.scan();
      final baseline2 = await scanner.incrementalScan(baseline1);
      expect(baseline2.size, 0);
    });

    test('respects exclude patterns', () async {
      await File('${tempDir.path}/keep.txt').writeAsString('keep');
      await File('${tempDir.path}/skip.log').writeAsString('skip');

      final scanner = Scanner(
        root: tempDir.path,
        excludePatterns: ['*.log'],
      );
      final baseline1 = await scanner.scan();
      final baseline2 = await scanner.incrementalScan(baseline1);

      expect(baseline2.size, 1);
      expect(baseline2.get('${tempDir.path}/keep.txt'), isNotNull);
      expect(baseline2.get('${tempDir.path}/skip.log'), isNull);
    });
  });
}
