import 'dart:io';
import 'package:flutter/material.dart';

/// 파티 메인 썸네일 크롭 에디터.
/// 반환값: 정규화된 16개 double (완료) 또는 null (취소).
class CropEditorScreen extends StatefulWidget {
  final File imageFile;
  final List<double>? initialMatrix;

  const CropEditorScreen({
    super.key,
    required this.imageFile,
    this.initialMatrix,
  });

  @override
  State<CropEditorScreen> createState() => _CropEditorScreenState();
}

class _CropEditorScreenState extends State<CropEditorScreen> {
  // 현재 변환 상태
  double _scale = 1.0;
  Offset _offset = Offset.zero; // 에디터 픽셀 공간에서 이미지 중심의 이동량

  // 제스처 시작 시 스냅샷
  double _startScale = 1.0;
  Offset _startOffset = Offset.zero;
  Offset _startFocalPoint = Offset.zero;

  double _editorW = 0;
  double _editorH = 0;

  static const double _previewW = 120.0;
  static const double _previewH = 90.0;

  // ── 초기화 (LayoutBuilder 첫 콜백에서 한 번만 실행) ─────────────────
  void _initEditorSize(double w) {
    if (_editorW > 0) return; // 이미 초기화됨
    final h = w * 3 / 4;
    _editorW = w;
    _editorH = h;

    if (widget.initialMatrix != null && widget.initialMatrix!.length == 16) {
      final m = widget.initialMatrix!;
      _scale = m[0].clamp(1.0, 5.0);
      // tx_norm = (1-scale)/2 + offset.dx/editorW  →  offset.dx = tx_norm*W - (1-scale)*W/2
      _offset = Offset(
        m[12] * w - (1.0 - _scale) * w / 2.0,
        m[13] * h - (1.0 - _scale) * h / 2.0,
      );
      _clampOffset();
    }
  }

  // ── 제스처 ────────────────────────────────────────────────────────────
  void _onScaleStart(ScaleStartDetails d) {
    _startScale = _scale;
    _startOffset = _offset;
    _startFocalPoint = d.localFocalPoint;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    if (_editorW <= 0) return;
    setState(() {
      final newScale = (_startScale * d.scale).clamp(1.0, 5.0);
      final c = Offset(_editorW / 2, _editorH / 2);

      // 제스처 시작 시 포컬 포인트 아래 있던 이미지 픽셀을 현재 포컬 포인트로 유지
      // (= 핀치 줌 시 포컬 포인트 고정 + 드래그 이동 통합)
      final imagePixelUnderFocal =
          (_startFocalPoint - c - _startOffset) * (1.0 / _startScale);
      _offset = (d.localFocalPoint - c) - imagePixelUnderFocal * newScale;
      _scale = newScale;
      _clampOffset();
    });
  }

  // 이미지가 크롭 영역 밖으로 나가지 않도록 오프셋 제한
  void _clampOffset() {
    if (_editorW <= 0) return;
    final maxDx = (_scale - 1.0) * _editorW / 2.0;
    final maxDy = (_scale - 1.0) * _editorH / 2.0;
    _offset = Offset(
      _offset.dx.clamp(-maxDx, maxDx),
      _offset.dy.clamp(-maxDy, maxDy),
    );
  }

  // ── 저장용 정규화 행렬 생성 ───────────────────────────────────────────
  // PartyThumbnailWidget에서: doubles[12] *= displayW, doubles[13] *= displayH
  List<double> _exportMatrix() {
    final txNorm = _editorW > 0
        ? (1.0 - _scale) / 2.0 + _offset.dx / _editorW
        : 0.0;
    final tyNorm = _editorH > 0
        ? (1.0 - _scale) / 2.0 + _offset.dy / _editorH
        : 0.0;
    // Column-major Matrix4: scale+translate (no rotation)
    return [
      _scale, 0, 0, 0, // col 0
      0, _scale, 0, 0, // col 1
      0, 0, 1.0, 0, // col 2
      txNorm, tyNorm, 0, 1.0, // col 3
    ];
  }

  // ── 에디터 이미지 (transform 적용) ────────────────────────────────────
  Widget _cropImage(double w, double h) => ClipRect(
        child: Transform.translate(
          offset: _offset,
          child: Transform.scale(
            scale: _scale,
            alignment: Alignment.center,
            child: Image.file(
              widget.imageFile,
              fit: BoxFit.cover,
              width: w,
              height: h,
            ),
          ),
        ),
      );

  // ── 미리보기 이미지 ───────────────────────────────────────────────────
  Widget _previewImage() {
    if (_editorW <= 0) {
      return Image.file(widget.imageFile,
          fit: BoxFit.cover, width: _previewW, height: _previewH);
    }
    final ratio = _previewW / _editorW;
    return ClipRect(
      child: Transform.translate(
        offset: _offset * ratio,
        child: Transform.scale(
          scale: _scale,
          alignment: Alignment.center,
          child: Image.file(
            widget.imageFile,
            fit: BoxFit.cover,
            width: _previewW,
            height: _previewH,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: TextButton(
          onPressed: () => Navigator.pop(context, null),
          child: const Text('취소',
              style: TextStyle(color: Colors.white60, fontSize: 14)),
        ),
        title: const Text('썸네일 조정',
            style: TextStyle(
                color: Colors.white,
                fontFamily: 'SeoulHangang',
                fontSize: 16,
                fontWeight: FontWeight.w500,
                shadows: [
                  Shadow(color: Colors.white, offset: Offset(0.3, 0)),
                  Shadow(color: Colors.white, offset: Offset(-0.3, 0)),
                  Shadow(color: Colors.white, offset: Offset(0, 0.3)),
                  Shadow(color: Colors.white, offset: Offset(0, -0.3)),
                ])),
        centerTitle: true,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, _exportMatrix()),
            child: const Text('완료',
                style: TextStyle(
                    color: Color(0xFFFF6FA0),
                    fontWeight: FontWeight.bold,
                    fontSize: 15)),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(),

            // ── 크롭 에디터 영역 (4:3) ────────────────────────────
            LayoutBuilder(builder: (ctx, constraints) {
              final w = constraints.maxWidth;
              _initEditorSize(w);
              final h = w * 3 / 4;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onScaleStart: _onScaleStart,
                onScaleUpdate: _onScaleUpdate,
                child: Container(
                  width: w,
                  height: h,
                  color: Colors.black,
                  child: Stack(
                    children: [
                      _cropImage(w, h),
                      // 프레임 가이드 (이벤트 통과)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.4),
                                width: 1.5,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }),

            const Spacer(),

            // ── 조작 힌트 ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: const [
                  Icon(Icons.pinch_outlined, color: Colors.white38, size: 18),
                  SizedBox(width: 6),
                  Text('핀치: 확대/축소',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12)),
                  SizedBox(width: 24),
                  Icon(Icons.open_with, color: Colors.white38, size: 18),
                  SizedBox(width: 6),
                  Text('드래그: 이동',
                      style:
                          TextStyle(color: Colors.white38, fontSize: 12)),
                ],
              ),
            ),

            // ── 미리보기 ──────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF1C1C1E),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '파티 목록에서 보이는 모습',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                          fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: _previewW,
                            height: _previewH,
                            child: _previewImage(),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _skeleton(double.infinity, 13),
                              const SizedBox(height: 5),
                              _skeleton(100, 10),
                              const SizedBox(height: 5),
                              _skeleton(130, 10),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 4,
                                children: [
                                  _skeletonChip('카테고리'),
                                  _skeletonChip('모집중'),
                                  _skeletonChip('무료'),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _skeleton(double w, double h) => Container(
        width: w,
        height: h,
        decoration: BoxDecoration(
          color: Colors.white12,
          borderRadius: BorderRadius.circular(4),
        ),
      );

  Widget _skeletonChip(String label) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.white10,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 9, color: Colors.white30)),
      );
}
