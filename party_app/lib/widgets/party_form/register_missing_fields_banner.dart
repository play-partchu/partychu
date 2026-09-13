import 'package:flutter/material.dart';

import 'package:party_app/utils/register_validation.dart';

/// 등록 버튼을 눌렀을 때 비어 있는 필수 항목을 **화면 위쪽에 목록으로** 보여주는
/// 배너.
///
/// 스낵바만으로는 몇 초 뒤 사라져서 "무엇이 빠졌는지" 다시 확인할 수 없고,
/// 각 입력칸의 빨간 테두리는 화면 밖에 있으면 보이지 않는다. 그래서 폼 맨 위에
/// 남아 있는 목록을 하나 더 둔다 — 항목을 채우면 즉시 사라진다.
///
/// 각 줄은 **눌러서 해당 입력 영역으로 바로 이동**할 수 있다(접힌 섹션이면
/// 펼친 뒤 스크롤). 문구만 띄우고 끝내면 "어디를 고쳐야 하는지" 알 수 없어서다.
class RegisterMissingFieldsBanner extends StatelessWidget {
  /// 비어 있는 항목들. 비어 있으면 아무것도 그리지 않는다.
  final List<RegisterFieldCheck> fields;

  const RegisterMissingFieldsBanner({super.key, required this.fields});

  @override
  Widget build(BuildContext context) {
    if (fields.isEmpty) return const SizedBox.shrink();

    final red = Colors.red.shade600;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F1),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.red.shade300, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.error_outline_rounded, size: 18, color: red),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  fields.length > 1
                      ? '아직 입력하지 않은 필수 항목이 ${fields.length}개 있어요'
                      : '아직 입력하지 않은 필수 항목이 있어요',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w700,
                    color: red,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Padding(
            padding: const EdgeInsets.only(left: 24, bottom: 6),
            child: Text(
              '항목을 누르면 해당 입력칸으로 이동해요.',
              style: TextStyle(
                fontSize: 11.5,
                color: red.withValues(alpha: 0.8),
              ),
            ),
          ),
          for (final field in fields)
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => RegisterValidation.goTo(field),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('• ', style: TextStyle(fontSize: 13, color: red)),
                    Expanded(
                      child: Text(
                        field.message,
                        style: TextStyle(
                          fontSize: 13,
                          height: 1.45,
                          color: red,
                          fontWeight: FontWeight.w500,
                          decoration: TextDecoration.underline,
                          decorationColor: red.withValues(alpha: 0.4),
                        ),
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.arrow_forward_ios_rounded, size: 11, color: red),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
