import 'package:flutter/material.dart';

import 'package:party_app/models/subway_line_style.dart';

/// 노선 하나를 나타내는 작은 원형 배지 — ②, ⑧처럼 노선색 원 안에 번호.
///
/// 유니코드 원문자(①②…)를 쓰지 않는 이유: 9호선까지밖에 없고 색도 못 넣는다.
/// 여기서는 실제 노선색 원을 그리고 그 안에 짧은 라벨을 넣는다
/// ([SubwayLineStyle]).
class SubwayLineBadge extends StatelessWidget {
  final String lineName;

  /// 원 지름. 주소 아래 보조 정보 줄에 들어가므로 기본값이 작다.
  final double size;

  const SubwayLineBadge({super.key, required this.lineName, this.size = 14});

  @override
  Widget build(BuildContext context) {
    final label = SubwayLineStyle.shortLabelOf(lineName);
    return Semantics(
      label: lineName,
      child: Container(
        width: label.characters.length > 1 ? null : size,
        height: size,
        constraints: BoxConstraints(minWidth: size),
        padding: label.characters.length > 1
            ? const EdgeInsets.symmetric(horizontal: 4)
            : EdgeInsets.zero,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: SubwayLineStyle.colorOf(lineName),
          borderRadius: BorderRadius.circular(size),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: size * 0.62,
            fontWeight: FontWeight.w800,
            color: Colors.white,
            height: 1.1,
          ),
        ),
      ),
    );
  }
}
