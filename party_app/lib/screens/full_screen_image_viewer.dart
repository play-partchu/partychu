import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:party_app/widgets/applicant_photo_protection.dart';

/// 사진을 검은 배경에 꽉 채워 보여주고 핀치 확대/축소를 지원하는 전체화면
/// 뷰어. `InteractiveViewer`는 이미 이 프로젝트의 사진/동영상 크롭 도구
/// (`photo_crop_screen.dart`, `video_crop_screen.dart`)에서 쓰던 방식을 그대로
/// 재사용한 것 — 새 패키지 없이 핀치줌을 구현한다.
///
/// 여러 장을 넘겨 볼 수도 있다([FullScreenImageViewer.gallery]) — 그때는 좌우
/// 스와이프로 이동하고 위쪽에 '3 / 5'가 뜬다. 한 장짜리로 열면 예전과 똑같이
/// 넘기기도 번호도 없다.
///
/// ── 확대와 스와이프가 같은 손가락을 두고 다투는 문제 ──────────────────────
///
/// `InteractiveViewer`는 **자기 위에서 시작한 드래그를 무조건 가져간다**
/// (panEnabled/scaleEnabled를 꺼도 마찬가지다 — 제스처 아레나에서 먼저
/// 이긴다). 그래서 그대로 PageView 안에 넣으면 좌우로 아무리 밀어도 다음
/// 장으로 넘어가지 않는다.
///
/// 그래서 **손가락 개수로 주인을 가른다.**
///
///   · 한 장(기존 호출부) — 넘길 것이 없으니 InteractiveViewer가 계속 주인이다.
///     핀치 확대가 예전과 똑같이 동작한다. 아래 장치는 하나도 끼지 않는다.
///   · 여러 장 + 1× — InteractiveViewer를 재워 두고(IgnorePointer) 그 자리에
///     [_PinchOnlyScaleRecognizer]를 놓는다. 이 인식기는 **손가락이 둘 이상일
///     때만** 아레나에 남고, 한 손가락이 움직이기 시작하면 스스로 빠져 그
///     드래그를 PageView에 넘긴다. 그래서 한 손가락 = 사진 넘기기,
///     두 손가락 = 즉시 확대가 동시에 성립한다.
///   · 여러 장 + 확대 상태 — 다시 InteractiveViewer가 주인이다. 끌어서 사진을
///     옮기고 핀치로 배율을 바꾼다. 이때는 페이지가 넘어가지 않는다(옆으로
///     끄는 것은 '사진 옮기기'여야 한다). 배율을 1로 되돌리면 다시 스와이프.
///
/// 더블탭은 어느 상태에서나 확대/복원이다 — 탭은 드래그와 다투지 않아서
/// 위 규칙과 무관하게 항상 살아 있다.
///
/// 다운로드 기능은 없다 — 사진을 자세히 보는 용도로만 쓴다.
class FullScreenImageViewer extends StatefulWidget {
  /// 볼 사진들. 순서가 곧 넘기는 순서다.
  final List<String> imageUrls;

  /// 처음 보여줄 사진의 위치.
  final int initialIndex;

  /// 신청자 제출 사진처럼 **보호 대상**인가.
  ///
  /// 켜면 화면이 떠 있는 동안 캡처 보호를 잡고(Android는 스크린샷·녹화 차단,
  /// iOS는 녹화 감지 시 가리기), 아래에 보호 안내가 붙는다. 파티 사진 같은
  /// 공개 이미지는 그대로 꺼 둔다 — 사용자가 캡처해 공유하는 것이 정상이다.
  final bool protected;

  /// 한 장짜리 — 예전부터 쓰던 모양 그대로다.
  FullScreenImageViewer({
    super.key,
    required String imageUrl,
    this.protected = false,
  }) : imageUrls = [imageUrl],
       initialIndex = 0;

  /// 여러 장을 넘겨 보는 형태. 탭한 사진이 먼저 보이도록 [initialIndex]를 준다.
  const FullScreenImageViewer.gallery({
    super.key,
    required this.imageUrls,
    this.initialIndex = 0,
    this.protected = false,
  });

  @override
  State<FullScreenImageViewer> createState() => _FullScreenImageViewerState();
}

class _FullScreenImageViewerState extends State<FullScreenImageViewer> {
  late final PageController _pageController = PageController(
    initialPage: _startIndex,
  );

  late int _index = _startIndex;

  /// 페이지마다 따로 둔다 — 한 장을 확대해 둔 채 옆으로 넘겼을 때 다음 장이
  /// 남의 확대 상태를 물려받으면 안 된다.
  final Map<int, TransformationController> _zoomControllers = {};

  /// 지금 보고 있는 사진이 확대돼 있는가(페이지 넘기기를 잠글지 판단).
  bool _zoomed = false;

  /// 마지막 더블탭 위치 — 그 지점을 중심으로 확대한다.
  Offset _doubleTapAt = Offset.zero;

  /// 지금 [_PinchOnlyScaleRecognizer]가 핀치를 처리하는 중인가.
  ///
  /// 배율이 1을 넘어도 손가락이 붙어 있는 동안에는 주인을 InteractiveViewer로
  /// 넘기지 않는다 — 진행 중인 제스처의 포인터는 이미 이쪽 아레나에 있어서,
  /// 중간에 넘겨봤자 그 손가락은 따라가지 않는다.
  bool _pinching = false;

  /// 핀치 시작 시점의 변환과 초점 — 그때를 기준으로 배율을 곱한다.
  Matrix4 _pinchStartMatrix = Matrix4.identity();
  Offset _pinchStartFocal = Offset.zero;

  static const double _minScale = 1.0;
  static const double _maxScale = 4.0;

  void _onPinchStart(int index, ScaleStartDetails details) {
    _pinchStartMatrix = _zoomFor(index).value.clone();
    _pinchStartFocal = details.localFocalPoint;
    setState(() => _pinching = true);
  }

  /// 두 손가락 사이 거리 변화를 그대로 배율에 반영한다 — 초점(두 손가락의
  /// 가운데)이 가리키던 사진 위의 점이 제자리에 남도록 함께 밀어 준다.
  void _onPinchUpdate(int index, ScaleUpdateDetails details, Size viewport) {
    // 손가락이 하나로 줄었으면 확대가 아니다(인식기가 이미 걸러내지만,
    // 손가락을 하나 떼는 순간의 업데이트가 남아 들어올 수 있다).
    if (details.pointerCount < 2) return;

    final startScale = _pinchStartMatrix.getMaxScaleOnAxis();
    final scale = (startScale * details.scale).clamp(_minScale, _maxScale);

    // 시작 시점 행렬에서 초점이 가리키던 사진 좌표(행렬이 배율+이동뿐이라
    // 역변환을 스칼라 계산으로 풀 수 있다).
    final childX =
        (_pinchStartFocal.dx - _pinchStartMatrix.entry(0, 3)) / startScale;
    final childY =
        (_pinchStartFocal.dy - _pinchStartMatrix.entry(1, 3)) / startScale;

    // 확대한 사진이 화면을 계속 덮도록 가둔다 — InteractiveViewer의 기본
    // 경계(boundaryMargin 0)와 같은 규칙이라, 손을 뗀 뒤 이어서 끌어도
    // 그림이 튀지 않는다.
    final tx = (details.localFocalPoint.dx - scale * childX).clamp(
      -(scale - 1) * viewport.width,
      0.0,
    );
    final ty = (details.localFocalPoint.dy - scale * childY).clamp(
      -(scale - 1) * viewport.height,
      0.0,
    );

    _zoomFor(index).value = Matrix4.diagonal3Values(scale, scale, 1)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  /// 손을 떼면 주인을 돌려준다 — 배율이 1보다 크면 이제부터 InteractiveViewer가
  /// 핀치와 끌기를 모두 받는다.
  void _onPinchEnd() => setState(() => _pinching = false);

  int get _startIndex => widget.initialIndex.clamp(
    0,
    (widget.imageUrls.length - 1).clamp(0, 1 << 30),
  );

  bool get _hasMany => widget.imageUrls.length > 1;

  /// 그 장이 지금 확대돼 있는가. 한 번도 만지지 않은 장은 원래 크기다.
  bool _isZoomed(int index) =>
      (_zoomControllers[index]?.value.getMaxScaleOnAxis() ?? 1) > 1.01;

  TransformationController _zoomFor(int index) =>
      _zoomControllers.putIfAbsent(index, () {
        final controller = TransformationController();
        controller.addListener(() {
          // 지금 보고 있는 페이지의 확대 상태만 신경 쓴다.
          if (index != _index || !mounted) return;
          final zoomed = controller.value.getMaxScaleOnAxis() > 1.01;
          if (zoomed != _zoomed) setState(() => _zoomed = zoomed);
        });
        return controller;
      });

  /// 더블탭한 지점을 [_zoomStep]배로 키운다(이미 커져 있으면 원래대로).
  ///
  /// 핀치와 별개로 항상 살아 있다 — 탭은 드래그와 아레나에서 다투지 않는다.
  static const double _zoomStep = 2.5;

  void _toggleZoom(int index, Offset focalPoint) {
    final controller = _zoomFor(index);
    if (controller.value.getMaxScaleOnAxis() > 1.01) {
      controller.value = Matrix4.identity();
      return;
    }
    // 누른 지점이 제자리에 남도록 배율만큼 반대로 밀어 준다.
    controller.value = Matrix4.diagonal3Values(_zoomStep, _zoomStep, 1)
      ..setEntry(0, 3, -focalPoint.dx * (_zoomStep - 1))
      ..setEntry(1, 3, -focalPoint.dy * (_zoomStep - 1));
  }

  void _onPageChanged(int next) {
    // 떠나는 페이지의 확대는 풀어 둔다 — 되돌아왔을 때 원래 크기로 시작하는
    // 편이, 아까 확대해 둔 자리에서 시작하는 것보다 예측하기 쉽다.
    _zoomControllers[_index]?.value = Matrix4.identity();
    setState(() {
      _index = next;
      _zoomed = _isZoomed(next);
    });
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final controller in _zoomControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        // 몇 번째 사진인지 — 한 장뿐이면 셀 것이 없으니 띄우지 않는다.
        title: _hasMany
            ? Text(
                '${_index + 1} / ${widget.imageUrls.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              )
            : null,
        centerTitle: true,
      ),
      body: _protected(
        PageView.builder(
          controller: _pageController,
          itemCount: widget.imageUrls.length,
          onPageChanged: _onPageChanged,
          // 확대 중에는 좌우 드래그가 '사진 옮기기'다.
          physics: _zoomed
              ? const NeverScrollableScrollPhysics()
              : const PageScrollPhysics(),
          itemBuilder: (context, i) => _page(i),
        ),
      ),
    );
  }

  /// 보호 대상 사진일 때만 캡처 보호와 안내 문구를 얹는다.
  ///
  /// 안내는 덮개 **바깥**에 둔다 — 녹화가 감지돼 사진이 가려진 순간이야말로
  /// "왜 안 보이는지"를 읽어야 할 때다. 저장·공유 버튼은 원래도 없다.
  Widget _protected(Widget pages) {
    if (!widget.protected) return pages;
    return Stack(
      children: [
        Positioned.fill(child: ProtectedPhotoScope(dark: true, child: pages)),
        Positioned(
          left: 20,
          right: 20,
          bottom: 0,
          child: const SafeArea(
            top: false,
            child: Padding(
              padding: EdgeInsets.only(bottom: 12),
              child: Center(child: ApplicantPhotoHostNotice(dark: true)),
            ),
          ),
        ),
      ],
    );
  }

  Widget _page(int i) {
    // 여러 장이고 아직 축소 상태면 InteractiveViewer를 재워 둔다 — 그래야 한
    // 손가락 드래그가 PageView까지 내려가 다음 장으로 넘어간다.
    //
    // 핀치가 진행 중이면 배율이 1을 넘어도 계속 재워 둔 채로 둔다. 그 제스처의
    // 주인은 아래 [_PinchOnlyScaleRecognizer]이고, 손가락이 붙어 있는 중간에
    // 주인을 바꿀 수는 없기 때문이다(포인터는 이미 그쪽 아레나에 있다).
    final zoomAsleep = _hasMany && (!_isZoomed(i) || _pinching);

    return GestureDetector(
      // 더블탭은 드래그가 아니라 PageView의 스와이프와 다투지 않는다 —
      // IgnorePointer 바깥에 둬서 재워 둔 동안에도 확대를 켤 수 있다.
      //
      // opaque가 필요하다: 기본값(deferToChild)은 자식이 히트테스트를 받아야
      // 자기도 받는데, 재워 둔 동안에는 그 자식이 IgnorePointer라 아무도 받지
      // 못해 더블탭이 영영 오지 않는다.
      behavior: HitTestBehavior.opaque,
      onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
      onDoubleTap: () => _toggleZoom(i, _doubleTapAt),
      child: LayoutBuilder(
        builder: (context, constraints) => RawGestureDetector(
          behavior: HitTestBehavior.opaque,
          // 재워 둔 동안에만 단다 — 확대 상태에서는 InteractiveViewer가 직접
          // 핀치를 받으므로 여기서 또 받으면 두 번 적용된다.
          gestures: zoomAsleep
              ? <Type, GestureRecognizerFactory>{
                  _PinchOnlyScaleRecognizer:
                      GestureRecognizerFactoryWithHandlers<
                        _PinchOnlyScaleRecognizer
                      >(_PinchOnlyScaleRecognizer.new, (recognizer) {
                        recognizer.onStart = (details) =>
                            _onPinchStart(i, details);
                        recognizer.onUpdate = (details) =>
                            _onPinchUpdate(i, details, constraints.biggest);
                        recognizer.onEnd = (_) => _onPinchEnd();
                      }),
                }
              : const <Type, GestureRecognizerFactory>{},
          child: IgnorePointer(
            ignoring: zoomAsleep,
            child: Center(
              child: InteractiveViewer(
                transformationController: _zoomFor(i),
                minScale: _minScale,
                maxScale: _maxScale,
                child: Image.network(
                  widget.imageUrls[i],
                  // 원본 비율 그대로 — 잘라내지 않는다.
                  fit: BoxFit.contain,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const Center(
                      child: CircularProgressIndicator(color: Colors.white70),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) {
                    // 보호 대상 사진은 오류 원문에 다운로드 URL이 그대로
                    // 들어 있다 — URL 하나면 보호를 통째로 우회할 수 있어
                    // 로그에도 남기지 않는다.
                    debugPrint(
                      widget.protected
                          ? '[FullScreenImageViewer] 보호 사진 로드 실패'
                          : '[FullScreenImageViewer] 이미지 로드 실패: $error',
                    );
                    return const Center(
                      child: Icon(
                        Icons.image_not_supported_outlined,
                        color: Colors.white38,
                        size: 48,
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// **두 손가락 이상일 때만** 아레나에 남는 확대 인식기.
///
/// `ScaleGestureRecognizer`를 그대로 쓰면 한 손가락 드래그까지 가져가 버려서
/// 아래 PageView가 페이지를 넘길 수 없다. 여기서는 손가락이 하나뿐인 채로
/// 움직이기 시작하면 **스스로 아레나에서 빠져** 그 드래그를 페이지 넘기기에
/// 넘겨준다. 손가락이 둘이면 평소처럼 경쟁해서 이긴다.
///
/// 그래서 1× 상태에서도 핀치는 즉시 확대가 되고, 한 손가락 스와이프는 그대로
/// 이전/다음 사진이 된다.
class _PinchOnlyScaleRecognizer extends ScaleGestureRecognizer {
  final Set<int> _downPointers = {};

  /// 이번 제스처에서 이미 아레나를 떠났는가.
  bool _gaveUp = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downPointers.add(event.pointer);
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      _downPointers.remove(event.pointer);
    }

    // 한 손가락으로 움직이기 시작했다 = 확대가 아니라 스와이프다.
    if (!_gaveUp && event is PointerMoveEvent && _downPointers.length < 2) {
      _gaveUp = true;
      resolve(GestureDisposition.rejected);
      // **super를 부르지 않고 끝낸다.** 아레나에서 빠지는 순간
      // ScaleGestureRecognizer는 내부 상태를 ready로 되돌리는데, 그 상태로
      // handleEvent에 들어가면 단언(_state != ready)에 걸려 터진다.
      return;
    }
    if (_gaveUp) return;

    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _downPointers.clear();
    _gaveUp = false;
    super.didStopTrackingLastPointer(pointer);
  }
}
