import 'package:flutter/material.dart';
import 'package:party_app/utils/party_utils.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 파티 제목 입력 — 글자 수 제한은 없다. 다만 기본 카드에는 앞
// kPartyCardTitleVisibleLength자까지만 노출되므로, 그 이후로 입력한 부분은
// 입력창 안에서부터 다른 색으로 미리 보여주고 안내 문구를 띄운다. 등록/수정
// 화면이 이 위젯 하나를 그대로 가져다 쓴다.
// ─────────────────────────────────────────────────────────────────────────────

/// [buildTextSpan]을 오버라이드해 kPartyCardTitleVisibleLength자를 넘는
/// 부분만 다른 색으로 렌더링하는 컨트롤러 — API는 TextEditingController와
/// 동일해 기존 코드(.text 읽기/쓰기, dispose 등)를 그대로 쓸 수 있다.
class PartyTitleController extends TextEditingController {
  PartyTitleController({super.text});

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    if (text.length <= kPartyCardTitleVisibleLength) {
      return TextSpan(style: style, text: text);
    }
    return TextSpan(
      style: style,
      children: [
        TextSpan(text: text.substring(0, kPartyCardTitleVisibleLength)),
        TextSpan(
          text: text.substring(kPartyCardTitleVisibleLength),
          style: const TextStyle(color: Color(0xFFFF6FA0)),
        ),
      ],
    );
  }
}

class PartyTitleField extends StatefulWidget {
  final PartyTitleController controller;
  final InputDecoration decoration;
  final String? Function(String?)? validator;
  final Key? fieldKey;

  const PartyTitleField({
    super.key,
    required this.controller,
    required this.decoration,
    this.validator,
    this.fieldKey,
  });

  @override
  State<PartyTitleField> createState() => _PartyTitleFieldState();
}

class _PartyTitleFieldState extends State<PartyTitleField> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    super.dispose();
  }

  void _onTextChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final overLimit = widget.controller.text.length > kPartyCardTitleVisibleLength;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFormField(
          key: widget.fieldKey,
          controller: widget.controller,
          decoration: widget.decoration,
          validator: widget.validator,
        ),
        if (overLimit)
          const Padding(
            padding: EdgeInsets.only(top: 6, left: 4),
            child: Text(
              '${kPartyCardTitleVisibleLength + 1}자 이후는 상세화면에서 노출됩니다',
              style: TextStyle(
                fontSize: 12,
                color: Color(0xFFFF6FA0),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
      ],
    );
  }
}
