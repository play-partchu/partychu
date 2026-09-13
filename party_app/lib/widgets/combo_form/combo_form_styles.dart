import 'package:flutter/material.dart';

/// 통합 "플레이스+파티 등록" 화면의 공용 스타일.
///
/// 예전에는 "플레이스+파티"/"숙박+파티" 두 화면이 각자 `_inputDeco`,
/// `_label`, `_sectionCard`를 똑같이 갖고 있었다 — 유형별 본문이 같은 모양을
/// 유지하도록 여기 하나로 모은다.

/// 섹션 제목·다이얼로그 제목에 쓰는 서울한강체 + 얇은 외곽선 스타일.
const TextStyle comboHeadingStyle = TextStyle(
  fontFamily: 'SeoulHangang',
  fontSize: 17,
  fontWeight: FontWeight.w500,
  shadows: [
    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
  ],
);

/// AppBar·다이얼로그 제목용(크기를 지정하지 않는 변형).
const TextStyle comboTitleStyle = TextStyle(
  fontFamily: 'SeoulHangang',
  fontWeight: FontWeight.w500,
  shadows: [
    Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
    Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
    Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
  ],
);

InputDecoration comboInputDeco(String hint) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: const Color(0xFFF7F7FA),
  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: BorderSide.none,
  ),
);

/// 입력칸 위 소제목.
Widget comboFieldLabel(String text) => Padding(
  padding: const EdgeInsets.only(bottom: 8, top: 16),
  child: Text(
    text,
    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
  ),
);

/// 흰 카드 한 장짜리 섹션.
Widget comboSectionCard({
  required String title,
  String? subtitle,
  required Widget child,
}) => Container(
  margin: const EdgeInsets.only(bottom: 16),
  padding: const EdgeInsets.fromLTRB(16, 16, 16, 20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(16),
  ),
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: comboHeadingStyle),
      if (subtitle != null) ...[
        const SizedBox(height: 4),
        Text(
          subtitle,
          style: const TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ],
      child,
    ],
  ),
);
