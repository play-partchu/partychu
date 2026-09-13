// 호스트에게 **스캐너는 하나뿐**이어야 한다.
//
// 예전에는 '이용권 QR 스캔'이 플레이스를 고른 뒤 열렸다. 파티 참가권은 어느
// 플레이스에도 속하지 않으므로 그 전제로는 통합이 성립하지 않는다. 그래서
// 스캐너를 호스트 스코프의 [CheckInScanScreen] 하나로 합쳤는데, 나중에 누가
// 두 번째 스캐너를 만들면 이 검사가 그 자리에서 막는다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  List<File> dartFiles(String dir) => [
    for (final e in Directory(dir).listSync(recursive: true))
      if (e is File && e.path.endsWith('.dart')) e,
  ];

  test('카메라 스캐너를 그리는 화면은 하나뿐이다', () {
    final scanners = [
      for (final f in dartFiles('lib'))
        if (f.readAsStringSync().contains('MobileScanner(')) f.path,
    ];
    expect(
      scanners,
      hasLength(1),
      reason:
          '스캐너가 둘 이상이면 호스트가 QR 종류를 먼저 알아야 한다 — 통합의 전제가 깨진다:\n'
          '${scanners.join('\n')}',
    );
    expect(scanners.single, endsWith('check_in_scan_screen.dart'));
  });

  test('QR 판별·권한 검증을 화면이 직접 하지 않는다', () {
    final src = File('lib/screens/check_in_scan_screen.dart').readAsStringSync();
    // 화면이 Firestore를 뒤지기 시작하면 권한 검증이 화면마다 흩어지고,
    // 게스트가 주운 QR로 남의 문서를 열어보는 길이 생긴다.
    expect(src.contains('FirebaseFirestore'), isFalse);
    expect(src.contains('cloud_firestore'), isFalse);
    expect(src.contains('CheckInService'), isTrue);
  });

  test('스캔과 사용 처리는 다른 호출이다 — scan = consume이 아니다', () {
    final src = File('lib/services/check_in_service.dart').readAsStringSync();
    expect(src.contains("httpsCallable('resolveCheckInToken')"), isTrue);
    expect(src.contains("httpsCallable('consumeCheckIn')"), isTrue);

    final screen = File(
      'lib/screens/check_in_scan_screen.dart',
    ).readAsStringSync();
    // 스캔 직후 부르는 것은 조회뿐이어야 한다. 사용 처리는 버튼(_run) 안에서만.
    final onDetect = screen.substring(
      screen.indexOf('Future<void> _onDetect'),
      screen.indexOf('Future<void> _showResult'),
    );
    expect(onDetect.contains('CheckInService.resolve'), isTrue);
    expect(
      onDetect.contains('CheckInService.consume'),
      isFalse,
      reason: '스캔하자마자 소진되면 다른 날짜 QR을 잘못 찍었을 때 되돌릴 수 없다',
    );
  });
}
