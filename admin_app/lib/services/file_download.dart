// 파일 저장·새 창 열기 — 웹과 Android가 **같은 이름의 함수**를 쓰고, 구현만
// 플랫폼별 파일로 나뉜다.
//
//   웹      file_download_web.dart — 기존 브라우저 다운로드·window.open 그대로
//   Android file_download_io.dart  — 다운로드 폴더 저장(MainActivity 채널),
//                                    링크는 설치된 아무 브라우저로(externalApplication)
//
// dart:html은 웹 파일에만 있어 Android 컴파일에 섞이지 않는다.
export 'file_download_io.dart'
    if (dart.library.js_interop) 'file_download_web.dart';
