/// 기기 하드웨어 볼륨키(+/-) 감시 — 플랫폼별 구현을 갈라 끼운다.
///
/// 볼륨키를 직접 가로챌 방법은 없어서, **시스템 볼륨 값이 바뀌는 것**을 보고
/// "사용자가 볼륨키를 눌렀다"고 판단한다. 웹에는 그 값을 읽을 방법 자체가
/// 없으므로 아무것도 하지 않는 구현이 들어간다.
///
/// (dart.library.io로 가르는 이유: flutter_volume_controller가 웹을 지원하지
/// 않고 내부에서 dart:io를 쓴다 — 그냥 import하면 웹 빌드가 컴파일부터 깨진다.)
library;

export 'device_volume_keys_stub.dart'
    if (dart.library.io) 'device_volume_keys_io.dart';
