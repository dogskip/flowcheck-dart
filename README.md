# flowcheck

Dart로 구현한 파일 무결성 모니터. 해시 기반 변조 감지, 증분 스캔, 베이스라인 diff를 제공한다.

## 특징

- **SHA-256 해싱**: 스트리밍 방식으로 대용량 파일도 메모리 효율적 처리
- **베이스라인**: 파일 메타데이터(경로, 크기, 수정 시각, 해시) 스냅샷
- **diff 보고**: 추가/삭제/수정/메타데이터 변경 감지
- **path traversal 방지**: 루트 밖으로 탈출하는 경로 차단
- **symlink 순환 감지**: 무한 루프 방지
- **제외 패턴**: glob 패턴으로 특정 파일 제외
- **상수 시간 비교**: 타이밍 공격 방지

## 사용법

### CLI

```bash
# 베이스라인 생성
dart run bin/flowcheck.dart init /path/to/monitor

# 무결성 검사 (변경 시 exit code 1)
dart run bin/flowcheck.dart check /path/to/monitor

# 베이스라인 갱신
dart run bin/flowcheck.dart update /path/to/monitor
```

### 라이브러리

```dart
import 'package:flowcheck/flowcheck.dart';

final scanner = Scanner(root: '/path/to/monitor');
final baseline = await scanner.scan();
baseline.save('baseline.json');

// 나중에 검사
final loaded = Baseline.load('baseline.json');
final diff = await scanner.diff(loaded);
print(diff.toReport());
if (!diff.isClean) {
  // 변조 감지
}
```

## 보안 고려사항

- **path traversal**: `PathSecurity.validateInsideRoot`가 모든 경로를 루트 내부로 제한. symlink가 루트 밖을 가리키면 건너뜀.
- **symlink 순환**: `resolveSymlink`가 방문한 경로를 기록해 순환 감지. 최대 깊이 40.
- **상수 시간 비교**: 해시 비교에 `constantTimeEquals` 사용. 타이밍 공격 방지.
- **원자적 쓰기**: 베이스라인 저장 시 임시 파일 + rename으로 손상 방지.
- **스트리밍 해싱**: 파일 전체를 메모리에 로드하지 않아 대용량 파일도 안전.

## 한계

- **파일 권한**: Dart가 chmod를 직접 지원하지 않아 베이스라인 파일 권한은 umask에 의존. 운영 환경에서는 별도 설정 필요.
- **ACL/확장 속성**: 메타데이터에 포함되지 않음.
- **실시간 모니터링**: 폴링 기반. 파일 시스템 이벤트(fsevents/inotify) 미사용.

## 개발

```bash
dart pub get
dart analyze
dart test
```

## 라이선스

MIT
