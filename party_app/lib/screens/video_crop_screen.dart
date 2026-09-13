import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:video_player/video_player.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/video_crop.dart';

/// 동영상이 기본 카드에 노출될 위치(초점)와 확대 배율을 고르는 편집 화면.
///
/// [InteractiveViewer]로 실제 사진 크롭 도구와 동일한 제스처(한 손가락 드래그
/// = 이동, 두 손가락 핀치 = 확대/축소, 확대 후 자유 이동)를 제공한다. 프레임은
/// 기본카드와 "가로:세로 비율"이 같은 미리보기 영역이다(화면에서는 손가락으로
/// 조작하기 편하도록 실제 카드보다 크게 보여준다 — [PartyMediaEditor._cardFrameSize]
/// 참고). 완료 시 `{cropX, cropY, cropScale}`을 반환한다(취소 시 null).
///
/// ── 좌표계 ──────────────────────────────────────────────────────────────
/// 매트릭스 변환·역변환은 [matrixForCrop]/[cropFromMatrix](party_app/lib/utils/video_crop.dart)
/// 딱 한 곳만 쓴다 — 이 화면과 실제 카드([CroppedMedia])가 각자 크롭 공식을
/// 따로 구현하다가 서로 어긋나는 사고를 막기 위함(과거 실제로 있었던 버그:
/// 편집 화면에서 맞춘 위치와 실제 카드에 보이는 위치가 서로 달랐음 — 원인은
/// `InteractiveViewer`의 `constrained` 기본값이 `true`라 자식이 뷰포트 크기로
/// 강제로 clamp되어, "원본을 cover 배율로 미리 키운 자식" 크기가 무시되고
/// 있었던 것. 아래 `constrained: false` 참고).
///
/// InteractiveViewer의 자식은 항상 "원본을 프레임에 꽉 채우는(cover) 배율"로
/// 미리 확대한 크기(coverW × coverH)로 만든다 — 그래야 스케일 1.0(추가 확대
/// 없음) 상태에서도 최소 한 축에는 프레임보다 남는 여유(slack)가 생겨서
/// 드래그로 이동할 수 있다. 단, 이 오버사이즈 자식이 실제로 그 크기 그대로
/// 렌더링되려면 `InteractiveViewer(constrained: false)`가 **반드시** 필요하다
/// — 기본값(`true`)이면 자식이 뷰포트 크기로 도로 clamp돼 이 모든 계산이
/// 무의미해진다.
class VideoCropScreen extends StatefulWidget {
  final String? videoUrl;

  /// 아직 업로드되지 않은, 방금 고른 동영상. 앱은 파일 경로, 웹은 blob
  /// 오브젝트 URL을 들고 있으므로 [LocalMedia]를 통해서만 연다.
  final XFile? videoFile;
  // 미리보기 프레임 크기(논리 픽셀) — 기본카드와 같은 비율로 화면에 크게
  // 보여주는 크기를 그대로 받는다.
  final double frameWidth;
  final double frameHeight;
  final double initialCropX;
  final double initialCropY;
  final double initialCropScale;

  const VideoCropScreen({
    super.key,
    this.videoUrl,
    this.videoFile,
    required this.frameWidth,
    required this.frameHeight,
    this.initialCropX = 0.5,
    this.initialCropY = 0.5,
    this.initialCropScale = 1.0,
  }) : assert(
         videoUrl != null || videoFile != null,
         'videoUrl 또는 videoFile 중 하나는 있어야 합니다',
       );

  @override
  State<VideoCropScreen> createState() => _VideoCropScreenState();
}

class _VideoCropScreenState extends State<VideoCropScreen> {
  VideoPlayerController? _ctrl;
  bool _initialized = false;
  bool _loadFailed = false;
  bool _isPlaying = false;

  final TransformationController _transformCtrl = TransformationController();

  // 원본을 프레임에 꽉 채우는(cover) 크기 — 동영상 해상도를 알아야 계산할 수
  // 있어 initialize() 완료 후에 채워진다.
  CoverGeometry? _cover;

  @override
  void initState() {
    super.initState();
    final ctrl = widget.videoFile != null
        ? LocalMedia.videoController(widget.videoFile!)
        : VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl!));
    _ctrl = ctrl;
    ctrl
        .initialize()
        .then((_) {
          if (!mounted) return;
          ctrl.setLooping(true);
          final size = ctrl.value.size;
          final naturalW = size.width > 0 ? size.width : widget.frameWidth;
          final naturalH = size.height > 0 ? size.height : widget.frameHeight;
          final cover = CoverGeometry.of(
            naturalWidth: naturalW,
            naturalHeight: naturalH,
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
        })
        .catchError((e) {
          if (mounted) setState(() => _loadFailed = true);
        });
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    _transformCtrl.dispose();
    super.dispose();
  }

  void _togglePlayback() {
    final c = _ctrl;
    if (c == null || !_initialized) return;
    setState(() {
      if (c.value.isPlaying) {
        c.pause();
        _isPlaying = false;
      } else {
        c.play();
        _isPlaying = true;
      }
    });
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
        title: const Text(
          '카드 노출 위치 조정',
          style: TextStyle(
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
                      '영상을 불러오지 못했어요.',
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
                                      // 실제 렌더링과 어긋난다(이 화면 상단
                                      // 문서 주석 참고).
                                      constrained: false,
                                      minScale: 1.0,
                                      maxScale: 5.0,
                                      boundaryMargin: EdgeInsets.zero,
                                      panEnabled: true,
                                      scaleEnabled: true,
                                      child: GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _togglePlayback,
                                        child: SizedBox(
                                          width: _cover!.width,
                                          height: _cover!.height,
                                          child: VideoPlayer(_ctrl!),
                                        ),
                                      ),
                                    ),
                              if (_initialized && !_isPlaying)
                                const IgnorePointer(
                                  child: Center(
                                    child: Icon(
                                      Icons.play_arrow_rounded,
                                      size: 44,
                                      color: Colors.white70,
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
