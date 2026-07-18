/// flowcheck — 파일 무결성 모니터.
///
/// 해시 기반 변조 감지, 증분 스캔, 베이스라인 diff를 제공한다.
/// 루트 디렉토리 밖으로의 탈출(path traversal)과 symlink 순환을
/// 방지한다.
library flowcheck;

export 'hash.dart';
export 'security.dart';
export 'baseline.dart';
export 'scanner.dart';
