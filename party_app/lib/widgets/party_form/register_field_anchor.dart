import 'dart:async';

import 'package:flutter/material.dart';

import 'package:party_app/utils/register_validation.dart';

/// 필수 항목이 가리키는 **입력 영역 그 자체**를 감싼다.
///
/// ── 왜 0높이 마커가 아니라 감싸는가 ───────────────────────────────────────
/// 예전에는 섹션 앞에 `SizedBox(key: ..., height: 0)`를 두고 그 자리로
/// 스크롤했다. 이동은 되지만 **도착한 뒤가 문제**였다 — 화면이 바뀐 것은
/// 알겠는데 어느 카드를 고쳐야 하는지는 여전히 눈으로 찾아야 했다. 높이가 0인
/// 마커는 강조할 수도 없다.
///
/// 그래서 마커 대신 영역을 감싸고, 도착하면 그 영역에 잠깐 테두리를 둘러
/// 준다. **이동 대상과 강조 대상이 같은 키 하나**([RegisterFieldCheck.anchorKey])
/// 로 정해지므로 둘이 갈라질 수 없다.
///
/// ── 끄는 타이머를 여기서 드는 이유 ────────────────────────────────────────
/// 강조를 끄는 일은 **이 위젯의 [State]**가 한다([RegisterHighlightMixin]).
/// 공용 유틸(전역)에 타이머를 두면 화면이 사라진 뒤에도 남아서, 테스트에서는
/// "타이머가 아직 있다"로 걸리고 실제 앱에서는 이미 없는 화면을 향해 알림을
/// 쏜다. 위젯이 들고 있으면 화면과 함께 정확히 사라진다.
///
/// ── 쓰는 법 ───────────────────────────────────────────────────────────────
/// ```dart
/// RegisterFieldAnchor(key: _productsKey, child: PlaceProductSection(...)),
/// ```
/// 그리고 검증 목록에서 같은 키를 가리킨다:
/// ```dart
/// RegisterFieldCheck(
///   missing: ...,
///   message: ...,
///   anchorKey: _productsKey,
///   scrollController: _scrollCtrl,   // ListView는 화면 밖을 안 만든다
/// )
/// ```
///
/// 이미 자기 테두리를 그리는 요약 행([SectionSummaryRow])은 이 위젯으로
/// 감싸지 않고 [RegisterHighlightMixin]을 직접 쓴다 — 겉을 한 겹 더 두르면
/// 여백이 늘어 도착 지점이 밀리기 때문이다.
class RegisterFieldAnchor extends StatefulWidget {
  const RegisterFieldAnchor({
    required GlobalKey super.key,
    required this.child,
    this.padding = const EdgeInsets.all(4),
    this.borderRadius = 18,
  });

  final Widget child;

  /// 강조 테두리가 내용에 닿지 않도록 두는 여백. 강조가 꺼져 있을 때도 같은
  /// 크기를 차지한다 — 강조가 켜지고 꺼질 때마다 레이아웃이 흔들리면 도착한
  /// 자리가 도로 밀려난다.
  final EdgeInsets padding;

  final double borderRadius;

  @override
  State<RegisterFieldAnchor> createState() => _RegisterFieldAnchorState();
}

class _RegisterFieldAnchorState extends State<RegisterFieldAnchor>
    with RegisterHighlightMixin {
  @override
  Object? get highlightAnchorKey => widget.key;

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: highlighted
            ? RegisterFieldAnchorStyle.fill
            : const Color(0x00FFFFFF),
        borderRadius: BorderRadius.circular(widget.borderRadius),
        border: Border.all(
          color: highlighted
              ? RegisterFieldAnchorStyle.border
              : Colors.transparent,
          width: 2,
        ),
      ),
      child: widget.child,
    );
  }
}

/// 도착 강조의 색 — 앵커든 요약 행이든 **같은 분홍**이어야 "여기로 왔다"가
/// 화면마다 다르게 보이지 않는다.
abstract final class RegisterFieldAnchorStyle {
  static const Color border = Color(0xFFFF6FA0);
  static const Color fill = Color(0xFFFFF1F5);
}

/// "지금 이 앵커가 강조 대상인가"를 듣는 공통 부품.
///
/// [RegisterValidation.goTo]는 도착한 앵커 키 하나를 전역으로 알릴 뿐이고,
/// 실제로 테두리를 그렸다 지우는 일은 그 키를 가진 위젯이 한다. 그 "듣고
/// 껐다 켜는" 부분만 여기 모아 두면, 감싸는 앵커([RegisterFieldAnchor])와
/// 자기 테두리를 이미 그리는 요약 행([SectionSummaryRow])이 **같은 규칙·같은
/// 시간**으로 강조된다.
///
/// 타이머를 State가 드는 이유는 [RegisterFieldAnchor] 문서 참고 — 화면이
/// 사라지면 타이머도 함께 사라져야 한다.
mixin RegisterHighlightMixin<T extends StatefulWidget> on State<T> {
  /// 이 위젯이 대표하는 앵커 키. build마다 달라질 수 있어 getter로 받는다
  /// (예: 요약 행은 `widget.rowKey`).
  Object? get highlightAnchorKey;

  bool _on = false;
  int? _seenSerial;
  Timer? _timer;

  /// 지금 강조가 켜져 있는지 — 그리는 방법은 위젯마다 다르다.
  bool get highlighted => _on;

  @override
  void initState() {
    super.initState();
    RegisterValidation.highlightRequest.addListener(_onHighlightRequest);
    // 이 위젯이 **뒤늦게 만들어진** 경우(화면 밖이라 스크롤해 온 순간에야
    // 만들어지는 ListView 항목) — 나를 부른 요청이 이미 서 있다.
    _onHighlightRequest();
  }

  @override
  void dispose() {
    RegisterValidation.highlightRequest.removeListener(_onHighlightRequest);
    _timer?.cancel();
    super.dispose();
  }

  void _onHighlightRequest() {
    final anchor = highlightAnchorKey;
    if (anchor == null) return;
    final request = RegisterValidation.highlightRequest.value;
    if (request == null || !identical(request.anchorKey, anchor)) return;
    if (_seenSerial == request.serial) return;
    _seenSerial = request.serial;
    _timer?.cancel();
    _timer = Timer(RegisterValidation.highlightDuration, () {
      if (mounted) setState(() => _on = false);
    });
    if (mounted) setState(() => _on = true);
  }
}
