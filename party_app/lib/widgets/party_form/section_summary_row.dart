import 'package:flutter/material.dart';

/// 등록/수정/재등록 화면 공통 — "제목 + 한 줄 요약 + >" 형태의 탭 가능한 행.
/// [summary]가 null/빈 값이면 "선택해주세요"를 흐린 색으로 보여준다.
/// [hasError]가 true면 빨간 테두리 + [errorText] 안내 문구를 카드 아래에 표시한다.
/// [blinkOnError]가 true면(기본 false) [hasError]인 동안 그 테두리·문구가
/// 경고등처럼 깜빡인다 — 특히 눈에 띄어야 하는 항목(예: 대표 미디어 미선택)에만
/// 켜고, 나머지 항목은 기존처럼 고정된 빨간 테두리/문구만 보여준다.
class SectionSummaryRow extends StatefulWidget {
  final String title;
  final String? summary;
  final bool hasError;
  final String? errorText;
  final VoidCallback onTap;
  final Key? rowKey;
  final bool blinkOnError;

  const SectionSummaryRow({
    super.key,
    this.rowKey,
    required this.title,
    this.summary,
    this.hasError = false,
    this.errorText,
    required this.onTap,
    this.blinkOnError = false,
  });

  @override
  State<SectionSummaryRow> createState() => _SectionSummaryRowState();
}

class _SectionSummaryRowState extends State<SectionSummaryRow>
    with SingleTickerProviderStateMixin {
  AnimationController? _blinkCtrl;

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

    return Padding(
      key: widget.rowKey,
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: widget.hasError ? errorColor : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.title,
                          style: const TextStyle(fontSize: 13, color: Colors.black54),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          hasValue ? widget.summary! : '선택해주세요',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: hasValue ? FontWeight.w600 : FontWeight.normal,
                            color: hasValue ? Colors.black87 : Colors.black38,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.chevron_right,
                      color: widget.hasError ? errorColor : Colors.black38),
                ],
              ),
            ),
          ),
          if (widget.hasError && widget.errorText != null)
            Padding(
              padding: const EdgeInsets.only(top: 6, left: 4),
              child: Text(widget.errorText!,
                  style: TextStyle(fontSize: 12, color: errorTextColor)),
            ),
        ],
      ),
    );
  }
}
