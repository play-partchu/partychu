/// 웹용 빈 구현 — 브라우저에는 앱이 하드웨어 볼륨키나 시스템 볼륨을 알아낼
/// 방법이 없다. 부르는 쪽에서 플랫폼을 따로 분기하지 않아도 되도록 같은
/// 이름의 함수만 남겨둔다.
void watchDeviceVolume(void Function(double volume) onChanged) {}
