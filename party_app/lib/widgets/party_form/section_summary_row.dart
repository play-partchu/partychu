import 'package:flutter/material.dart';

import 'package:party_app/widgets/party_form/register_field_anchor.dart';

/// 등록/수정/재등록 화면 공통 — "제목 + 한 줄 요약 + >" 형태의 탭 가능한 행.
/// [summary]가 null/빈 값이면 "선택해주세요"를 흐린 색으로 보여준다.
/// [hasError]가 true면 빨간 테두리 + [errorText] 안내 문구를 카드 아래에 표시한다.
/// [blinkOnError]가 true면(기본 false) [hasError]인 동안 그 테두리·문구가
/// 경고등처럼 깜빡인다 — 특히 눈에 띄어야 하는 항목(예: 대표 미디어 미선택)에만
/// 켜고, 나머지 항목은 기존처럼 고정된 빨간 테두리/문구만 보여준다.
///
/// [rowKey]를 준 행은 **필수항목 안내가 데려다 놓는 도착 지점**이기도 하다 —
/// 그 키로 이동해 오면 잠깐 분홍 테두리가 켜진다([RegisterHighlightMixin]).
/// 이 행은 이미 자기 카드 테두리를 그리므로 [RegisterFieldAnchor]로 한 겹 더
/// 감싸지 않는다 — 겉을 두르면 여백이 늘어 도착 지점이 그만큼 밀린다.
class SectionSummaryRow extends StatefulWidget {
  final String title;
  final String? summary;
  final bool hasError;
  final String? errorText;
  final VoidCallback onTap;
  final Key? rowKey;
  final bool blinkOnError;

  /// true면 제목 옆에 빨간 `*`를 붙이고, 아직 값이 없으면 안내 문구도
  /// "선택해주세요" 대신 "필수 항목이에요"로 바꾼다 — 선택 항목과 한눈에
  /// 구분되도록.
  final bool isRequired;

  const SectionSummaryRow({
    super.key,
    this.rowKey,
    required this.title,
    this.summary,
    this.hasError = false,
    this.errorText,
    required this.onTap,
    this.blinkOnError = false,
    this.isRequired = false,
  });

  @override
  State<SectionSummaryRow> createState() => _SectionSummaryRowState();
}

class _SectionSummaryRowState extends State<SectionSummaryRow>
    with SingleTickerProviderStateMixin, RegisterHighlightMixin {
  AnimationController? _blinkCtrl;

  /// 이 행이 대표하는 앵커 — 검증 목록의 `anchorKey`가 가리키는 바로 그 키다.
  @override
  Object? get highlightAnchorKey => widget.rowKey;

  @override
  void initState() {
    super.initState();
    if (widget.blinkOnError) {
      final ctrl = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 600),
      );
      _blinkCtrl = ctrl;
      if (widget.hasError) ctrl.repeat(reverse: true);
    }
  }

  @override
  void didUpdateWidget(covariant SectionSummaryRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final ctrl = _blinkCtrl;
    if (ctrl == null) return;
    if (widget.hasError && !ctrl.isAnimating) {
      ctrl.repeat(reverse: true);
    } else if (!widget.hasError && ctrl.isAnimating) {
      ctrl.stop();
      ctrl.value = 0;
    }
  }

  @override
  void dispose() {
    _blinkCtrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _blinkCtrl;
    if (ctrl == null) return _buildContent(1.0);
    return AnimatedBuilder(
      animation: ctrl,
      builder: (context, _) => _buildContent(ctrl.value),
    );
  }

  // blinkAlpha: 깜빡이지 않을 때는 항상 1.0(완전 불투명, 기존과 동일한
  // 고정 빨간 테두리/문구). 깜빡일 때는 0.3~1.0을 오간다(완전히 안 보이는
  // 순간은 없게 최소 알파를 남겨 위치를 계속 알 수 있게 한다).
  Widget _buildContent(double blinkT) {
    final hasValue =
        widget.summary != null && widget.summary!.trim().isNotEmpty;
    final blinkAlpha = widget.blinkOnError ? (0.3 + 0.7 * blinkT) : 1.0;
    final errorColor = Colors.red.shade400.withValues(alpha: blinkAlpha);
    final errorTextColor = Colors.red.shade600.withValues(alpha: blinkAlpha);
    // 방금 이 행으로 이동해 왔으면 잠깐 분홍으로 감싼다 — 빨간 오류 테두리와
    // 색이 갈리므로 "여기가 문제다"와 "여기로 왔다"가 섞이지 않는다.
    final borderColor = highlighted
        ? RegisterFieldAnchorStyle.border
        : (widget.hasError ? errorColor : Colors.transparent);

    return Padding(
      key: widget.rowKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOut,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: highlighted
                    ? RegisterFieldAnchorStyle.fill
                    : Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: borderColor,
                  width: highlighted ? 2 : 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            text: widget.title,
                            children: [
                              if (widget.isRequired)
                                TextSpan(
                                  text: ' *',
                                  style: TextStyle(
                                    color: Colors.red.shade400,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                            ],
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.black54,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasValue
                              ? widget.summary!
                              : (widget.isRequired ? '필수 항목이에요' : '선택해주세요'),
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: hasValue
                                ? FontWeight.w600
                                : FontWeight.normal,
                            color: hasValue
                                ? Colors.black87
                                // 아직 안 채운 필수 항목은 회색보다 진하게 —
                                // 선택 항목("선택해주세요")과 구분된다.
                                : (widget.isRequired
                                      ? Colors.red.shade400
                                      : Colors.black38),
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  // 접힌 요약 행에서도 "여기에 빠진 값이 있다"가 한눈에 보이도록
                  // 느낌표를 함께 띄운다(아래 errorText와 짝).
                  if (widget.hasError) ...[
                    Icon(
                      Icons.error_outline_rounded,
                      size: 18,
                      color: errorColor,
                    ),
                    const SizedBox(width: 2),
                  ],
                  Icon(
                    Icons.chevron_right,
                    color: widget.hasError ? errorColor : Colors.black38,
                  ),
                ],
              ),
            ),
          ),
          if (widget.hasError && widget.errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(
                widget.errorText!,
                style: TextStyle(fontSize: 12, color: errorTextColor),
              ),
            ),
        ],
      ),
    );
  }
}
