import 'dart:io';

import 'package:flowcheck/hash.dart';
import 'package:flowcheck/security.dart';
import 'package:test/test.dart';

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('secure_hash_test_');
  });

  tearDown(() async {
    if (tempDir.existsSync()) {
      await tempDir.delete(recursive: true);
    }
  });

  test('hashFileSecure matches hashFile for regular file', () async {
    final file = File('${tempDir.path}/regular.txt');
    await file.writeAsString('hello world');

    final normal = await FileHasher.hashFile(file.path);
    final secure = await FileHasher.hashFileSecure(file.path);

    expect(secure, equals(normal));
    expect(secure.length, equals(64)); // SHA-256 hex 길이.
  });

  test('hashFileSecure rejects directory', () async {
    // 디렉토리는 open 자체가 실패하거나 stat에서 일반 파일이 아니면 거부.
    expect(
      () => FileHasher.hashFileSecure(tempDir.path),
      throwsA(isA<FileSystemException>()),
    );
  });

  test('hashFileSecure handles empty file', () async {
    final file = File('${tempDir.path}/empty.txt');
    await file.writeAsString('');

    final secure = await FileHasher.hashFileSecure(file.path);
    // 빈 파일의 SHA-256은 알려진 상수.
    expect(secure, equals(
        'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'));
  });

  test('hashFileSecure handles large file', () async {
    // 1MB 파일. 청크 읽기 경로 검증.
    final file = File('${tempDir.path}/large.bin');
    final data = List<int>.generate(1024 * 1024, (i) => i % 256);
    await file.writeAsBytes(data);

    final secure = await FileHasher.hashFileSecure(file.path);
    final normal = await FileHasher.hashFile(file.path);
    expect(secure, equals(normal));
  });

  test('hashFileSecure validates root containment', () async {
    final file = File('${tempDir.path}/inside.txt');
    await file.writeAsString('content');

    // root가 tempDir이면 파일은 내부.
    final secure = await FileHasher.hashFileSecure(file.path, root: tempDir.path);
    expect(secure.length, equals(64));

    // root가 다른 디렉토리면 거부.
    final otherDir = await Directory.systemTemp.createTemp('other_');
    try {
      expect(
        () => FileHasher.hashFileSecure(file.path, root: otherDir.path),
        throwsA(isA<PathTraversalException>()),
      );
    } finally {
      await otherDir.delete(recursive: true);
    }
  });

  test('hashFileSecure produces consistent results', () async {
    final file = File('${tempDir.path}/consistent.txt');
    await file.writeAsString('same content');

    final h1 = await FileHasher.hashFileSecure(file.path);
    final h2 = await FileHasher.hashFileSecure(file.path);
    expect(h1, equals(h2));
  });

  test('hashFileSecure different files produce different hashes', () async {
    final file1 = File('${tempDir.path}/a.txt');
    final file2 = File('${tempDir.path}/b.txt');
    await file1.writeAsString('content a');
    await file2.writeAsString('content b');

    final h1 = await FileHasher.hashFileSecure(file1.path);
    final h2 = await FileHasher.hashFileSecure(file2.path);
    expect(h1, isNot(equals(h2)));
  });

  test('hashFileSecure rejects non-existent file', () async {
    expect(
      () => FileHasher.hashFileSecure('${tempDir.path}/nonexistent.txt'),
      throwsA(isA<FileSystemException>()),
    );
  });
}
