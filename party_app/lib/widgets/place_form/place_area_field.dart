import 'package:flutter/material.dart';

import 'package:party_app/models/place_area.dart';
import 'package:party_app/widgets/place_form/place_area_picker_sheet.dart';

/// 공간 평수 입력칸 — 플레이스 등록/수정, 장소대여 등록/수정, 콤보 등록이
/// **같은 위젯 하나**를 쓴다.
///
/// ── 왜 위젯까지 공유하는가 ────────────────────────────────────────────────
/// 검증만 모델([PlaceArea])로 모으고 입력칸은 화면마다 두면, 어느 화면에는
/// 단위 '평'이 붙고 어느 화면에는 안 붙거나, 휠이 한 곳만 빠지는 식으로
/// 곧 갈라진다. 실제로 이 프로젝트에서 등록/수정 화면이 갈라졌던 전례가 있다
/// (place_edit_screen.dart 주석 참고).
///
/// ── 손으로 치지 않고 휠에서 고른다 ────────────────────────────────────────
/// 칸을 누르면 [showPlaceAreaPickerSheet]가 열리고, 고른 정수 평수가
/// [controller]에 **쉼표 없는 숫자 문자열**로 들어간다. 임시저장·수정 복원·
/// 저장이 모두 예전처럼 이 컨트롤러 문자열 하나만 보므로, 화면 쪽 코드는
/// 그대로다.
///
/// ── 생김새는 화면이 정한다 ────────────────────────────────────────────────
/// 세 화면의 입력칸 장식이 서로 다르다(흰 배경 + 테두리 / 회색 채움 / 콤보
/// 전용). 그래서 [decoration]을 받아 그대로 쓰고, 이 위젯은 **선택 방식·표기·
/// 검증**만 책임진다.
class PlaceAreaField extends StatelessWidget {
  const PlaceAreaField({
    super.key,
    required this.controller,
    required this.decoration,
    this.focusNode,
    this.onChanged,
    this.showLabel = true,
    this.labelBuilder,
    this.fieldKey,
  });

  final TextEditingController controller;

  /// 화면의 기본 입력칸 장식 — 힌트·테두리·채움색을 그대로 쓴다.
  final InputDecoration decoration;

  final FocusNode? focusNode;

  /// 값이 바뀔 때 — 등록 화면이 임시저장 dirty 처리나 오류 문구 갱신에 쓴다.
  /// 넘어가는 문자열은 [controller]에 방금 들어간 값과 같다.
  final ValueChanged<String>? onChanged;

  /// 제목·안내 문구를 이 위젯이 직접 그릴지. 화면이 자기 `_label()`로 이미
  /// 그렸다면 false로 두고 입력칸만 받는다.
  final bool showLabel;

  /// 제목을 화면의 라벨 스타일로 그리고 싶을 때 — 주면 [showLabel]과 함께 쓴다.
  final Widget Function(String text)? labelBuilder;

  /// 입력칸 자체의 키 — [Form] 안에 있지 않은 화면이 저장 버튼에서
  /// `fieldKey.currentState?.validate()`로 빨간 문구를 **강제로 띄울** 때 쓴다.
  ///
  /// 자동 검증은 "한 번이라도 건드린 뒤"에만 뜬다
  /// ([AutovalidateMode.onUserInteraction]). 아예 손대지 않고 저장을 누른
  /// 경우에도 어디가 비었는지 보여야 해서 이 통로가 필요하다.
  final GlobalKey<FormFieldState<String>>? fieldKey;

  @override
  Widget build(BuildContext context) {
    final input = FormField<String>(
      key: fieldKey,
      initialValue: controller.text,
      autovalidateMode: AutovalidateMode.onUserInteraction,
      // **컨트롤러가 정본이다.** 수정 화면 진입(`_prefillFromSource`)이나
      // 임시저장 복원(`applyDraftPayload`)은 이 위젯을 거치지 않고 컨트롤러에
      // 값을 직접 넣는다. FormField가 들고 있는 값으로 검증하면 그런 경로에서
      // 값이 멀쩡한데도 "공간 평수를 입력해주세요"가 뜬다.
      validator: (_) => PlaceArea.validate(controller.text),
      builder: (state) => ValueListenableBuilder<TextEditingValue>(
        // 화면이 컨트롤러를 직접 바꿔도 표시가 따라오도록 — 이 위젯의
        // setState에 기대지 않는다.
        valueListenable: controller,
        builder: (_, editing, _) {
          final text = editing.text.trim();
          final value = double.tryParse(text);
          final hasValue = value != null && value.isFinite && value > 0;

          return InkWell(
          focusNode: focusNode,
            borderRadius: BorderRadius.circular(12),
            onTap: () async {
              final picked = await showPlaceAreaPickerSheet(
                context,
                // 옛 문서의 소수점 값('12.5')은 가장 가까운 칸에서 휠이 열린다.
                current: hasValue ? value.round() : null,
              );
              if (picked == null) return;
              final next = PlaceArea.format(picked.toDouble());
              controller.text = next;
              state.didChange(next);
              onChanged?.call(next);
            },
            child: InputDecorator(
              decoration: decoration.copyWith(
                hintText: decoration.hintText ?? PlaceArea.placeholder,
                errorText: state.errorText,
                // 값이 있으면 표기에 '평'이 이미 들어 있어 접미사를 붙이지
                // 않는다 — '20평평'이 되지 않게.
                suffixText: null,
                suffixIcon: const Icon(
                  Icons.unfold_more,
                  size: 18,
                  color: Colors.black38,
                ),
              ),
              // 빈 칸일 때는 InputDecorator가 hintText를 대신 그린다.
              isEmpty: !hasValue,
              child: hasValue
                  ? Text(
                      // '1,250평 · 약 4,132.3㎡'
                      PlaceArea.summary(value),
                      style: const TextStyle(
                        fontSize: 14,
                        color: Colors.black87,
                      ),
                    )
                  : const SizedBox(height: 20),
            ),
          );
        },
      ),
    );

    if (!showLabel) return input;

    final build = labelBuilder;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (build != null)
          build(PlaceArea.label)
        else
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              PlaceArea.label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: Colors.black87,
              ),
            ),
          ),
        const Padding(
          padding: EdgeInsets.only(bottom: 8),
          child: Text(
            PlaceArea.hint,
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ),
        input,
      ],
    );
  }
}
