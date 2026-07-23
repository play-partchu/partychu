// 모바일(비웹) 빌드에서는 절대 호출되지 않는다 — nice_auth_verification_screen.dart가
// kIsWeb으로 분기해서 웹 경로에서만 이 함수를 호출하기 때문. 그럼에도 실수로
// 호출되면 원인을 바로 알 수 있도록 명시적으로 예외를 던진다.
Future<String?> openNicePopupAndWaitForCallback(String authUrl) {
  throw UnsupportedError('openNicePopupAndWaitForCallback은 웹 전용입니다.');
}
