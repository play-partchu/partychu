import 'package:flutter/material.dart';

/// 사진을 검은 배경에 꽉 채워 보여주고 핀치 확대/축소를 지원하는 단순
/// 전체화면 뷰어. `InteractiveViewer`는 이미 이 프로젝트의 사진/동영상 크롭
/// 도구(`photo_crop_screen.dart`, `video_crop_screen.dart`)에서 쓰던 방식을
/// 그대로 재사용한 것 — 새 패키지 없이 핀치줌을 구현한다.
///
/// 갤러리 슬라이드(여러 장 넘기기)나 다운로드 기능은 없다 — 사진 한 장을
/// 자세히 보는 용도로만 쓴다.
class FullScreenImageViewer extends StatelessWidget {
  final String imageUrl;

  const FullScreenImageViewer({super.key, required this.imageUrl});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Center(
        child: InteractiveViewer(
          minScale: 1.0,
          maxScale: 4.0,
          child: Image.network(
            imageUrl,
            fit: BoxFit.contain,
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return const Center(
                child: CircularProgressIndicator(color: Colors.white70),
              );
            },
            errorBuilder: (context, error, stackTrace) {
              debugPrint('[FullScreenImageViewer] 이미지 로드 실패: $error');
              return const Center(
                child: Icon(Icons.image_not_supported_outlined, color: Colors.white38, size: 48),
              );
            },
          ),
        ),
      ),
    );
  }
}
