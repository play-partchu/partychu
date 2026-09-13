import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/video_crop.dart';

/// 사진이 기본 카드에 노출될 위치(초점)와 확대 배율을 고르는 편집 화면.
///
/// [VideoCropScreen](party_app/lib/screens/video_crop_screen.dart)과 완전히
/// 동일한 제스처·좌표계를 쓴다(매트릭스 변환·역변환도 정확히 같은
/// [matrixForCrop]/[cropFromMatrix]를 공유) — 다른 점은 재생 컨트롤이 없고,
/// "원본 크기"를 동영상 컨트롤러 대신 [ImageStream]으로 알아낸다는 것뿐이다.
/// 완료 시 `{cropX, cropY, cropScale}`을 반환한다(취소 시 null).
class PhotoCropScreen extends StatefulWidget {
  final String? imageUrl;

  /// 아직 업로드되지 않은, 방금 고른 사진. 앱은 파일 경로, 웹은 blob 오브젝트
  /// URL을 들고 있으므로 [LocalMedia]를 통해서만 연다.
  final XFile? imageFile;
  // 미리보기 프레임 크기(논리 픽셀) — 기본카드와 같은 비율로 화면에 크게
  // 보여주는 크기를 그대로 받는다([PartyMediaEditor._cardFrameSize] 참고).
  final double frameWidth;
  final double frameHeight;
  final double initialCropX;
  final double initialCropY;
  final double initialCropScale;

  /// AppBar 타이틀 — 기본카드 크롭 외 다른 문맥(예: 상세페이지 사진 블록)
  /// 에서 재사용할 때 문구를 맞추기 위함.
  final String title;

  const PhotoCropScreen({
    super.key,
    this.imageUrl,
    this.imageFile,
    required this.frameWidth,
    required this.frameHeight,
    this.initialCropX = 0.5,
    this.initialCropY = 0.5,
    this.initialCropScale = 1.0,
    this.title = '카드 노출 위치 조정',
  }) : assert(
         imageUrl != null || imageFile != null,
         'imageUrl 또는 imageFile 중 하나는 있어야 합니다',
       );

  @override
  State<PhotoCropScreen> createState() => _PhotoCropScreenState();
}

class _PhotoCropScreenState extends State<PhotoCropScreen> {
  final TransformationController _transformCtrl = TransformationController();

  late final ImageProvider _provider = widget.imageFile != null
      ? LocalMedia.imageProvider(widget.imageFile!)
      : NetworkImage(widget.imageUrl!);
  ImageStream? _stream;
  late final ImageStreamListener _listener = ImageStreamListener(
    _onImageResolved,
    onError: (error, stackTrace) {
      if (mounted) setState(() => _loadFailed = true);
    },
  );

  bool _initialized = false;
  bool _loadFailed = false;

  // 원본을 프레임에 꽉 채우는(cover) 크기 — 이미지 원본 픽셀 크기를 알아야
  // 계산할 수 있어 ImageStream이 resolve된 뒤에 채워진다.
  CoverGeometry? _cover;

  @override
  void initState() {
    super.initState();
    _stream = _provider.resolve(const ImageConfiguration());
    _stream!.addListener(_listener);
  }

  void _onImageResolved(ImageInfo info, bool synchronousCall) {
    if (!mounted) return;
    final cover = CoverGeometry.of(
      naturalWidth: info.image.width.toDouble(),
      naturalHeight: info.image.height.toDouble(),
      frameWidth: widget.frameWidth,
      frameHeight: widget.frameHeight,
    );
    _cover = cover;
    _transformCtrl.value = matrixForCrop(
      cover: cover,
      frameWidth: widget.frameWidth,
      frameHeight: widget.frameHeight,
      cropX: widget.initialCropX,
      cropY: widget.initialCropY,
      cropScale: widget.initialCropScale,
    );
    setState(() => _initialized = true);
  }

  @override
  void dispose() {
    _stream?.removeListener(_listener);
    _transformCtrl.dispose();
    super.dispose();
  }

  void _complete() {
    final cover = _cover;
    if (cover == null) return;
    final result = cropFromMatrix(
      matrix: _transformCtrl.value,
      cover: cover,
      frameWidth: widget.frameWidth,
      frameHeight: widget.frameHeight,
    );
    Navigator.pop(context, {
      'cropX': result.cropX,
      'cropY': result.cropY,
      'cropScale': result.cropScale,
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.title,
          style: const TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: _initialized ? _complete : null,
            child: Text(
              '완료',
              style: TextStyle(
                color: _initialized ? const Color(0xFFFF6FA0) : Colors.white24,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
        ],
      ),
      body: _loadFailed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.error_outline,
                      color: Colors.white54,
                      size: 40,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      '사진을 불러오지 못했어요.',
                      style: TextStyle(color: Colors.white70, fontSize: 14),
                    ),
                    const SizedBox(height: 16),
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text(
                        '돌아가기',
                        style: TextStyle(color: Color(0xFFFF6FA0)),
                      ),
                    ),
                  ],
                ),
              ),
            )
          : SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Column(
                      children: [
                        Text(
                          '기본카드 미리보기 영역을 조정해주세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.9),
                            fontSize: 14,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '아래 사각형이 기본카드에 실제로 보이는 비율이에요',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: 0.55),
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 20),
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: widget.frameWidth,
                        height: widget.frameHeight,
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              !_initialized
                                  ? const Center(
                                      child: CircularProgressIndicator(
                                        color: Color(0xFFFF6FA0),
                                      ),
                                    )
                                  : InteractiveViewer(
                                      transformationController: _transformCtrl,
                                      // 자식(원본을 cover 배율로 미리 키운
                                      // coverW×coverH SizedBox)이 실제로 그
                                      // 크기 그대로 렌더링되려면 반드시
                                      // false여야 한다 — true(기본값)면
                                      // 자식이 뷰포트 크기로 도로 clamp되어
                                      // matrixForCrop/cropFromMatrix의 계산이
                                      // 실제 렌더링과 어긋난다.
                                      constrained: false,
                                      minScale: 1.0,
                                      maxScale: 5.0,
                                      boundaryMargin: EdgeInsets.zero,
                                      panEnabled: true,
                                      scaleEnabled: true,
                                      child: SizedBox(
                                        width: _cover!.width,
                                        height: _cover!.height,
                                        child: Image(
                                          image: _provider,
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                          alpha: 0.4,
                                        ),
                                        width: 1.5,
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: const [
                        Icon(
                          Icons.pinch_outlined,
                          color: Colors.white38,
                          size: 18,
                        ),
                        SizedBox(width: 6),
                        Text(
                          '핀치: 확대/축소',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                        SizedBox(width: 24),
                        Icon(Icons.open_with, color: Colors.white38, size: 18),
                        SizedBox(width: 6),
                        Text(
                          '드래그: 위치 이동',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
    );
  }
}
