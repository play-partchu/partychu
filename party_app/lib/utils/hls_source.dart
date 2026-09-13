// 이 주소가 HLS 매니페스트인가 — 플랫폼과 무관한 순수 판정 하나.
//
// 웹 구현([web_video_hls_web.dart]) 안에 두면 `dart:js_interop`에 묶여 테스트
// 러너(VM)에서 부를 수 없다. 재생 경로가 갈리는 기준이라 값으로 붙잡아 둘
// 가치가 있어서 따로 뺐다.
library;

/// `…/manifest/video.m3u8` 처럼 HLS 재생목록을 가리키는 주소인가.
///
/// 쿼리스트링은 떼고 **경로만** 본다(`?token=…`이 붙어도 판정이 흔들리면 안
/// 된다). 대소문자도 무시한다.
///
/// false가 되어야 하는 것들:
///   · mp4 등 브라우저가 그대로 읽는 형식 — 예전 경로 그대로 두면 된다.
///   · `blob:…` — 웹에서 방금 고른 로컬 파일의 미리보기다. 확장자가 없고,
///     브라우저가 직접 디코딩한다(길이 30초 검증이 이것으로 돈다).
///   · 빈 문자열.
bool isHlsSource(String src) {
  if (src.isEmpty) return false;
  final path = Uri.tryParse(src)?.path ?? src;
  return path.toLowerCase().endsWith('.m3u8');
}
