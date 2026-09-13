import 'package:flutter/material.dart';

import 'package:party_app/models/party_constants.dart';

/// '파티 유형 · 분위기' 항목 앞에 붙는 **이미지 아이콘** — 이모지 자리에
/// 그림이 들어가는 항목(지금은 '돌싱' 하나)을 그리는 공용 자리.
///
/// ── 왜 위젯 하나로 모았나 ─────────────────────────────────────────────
/// 이 항목은 등록·수정·복원·선택 시트·상세검색·선택된 조건 칩·카드·상세까지
/// 여덟 군데에 나온다. 각자 `Image.asset`을 부르면 크기도 대체 처리도 자리마다
/// 갈리고, "어떤 화면에서는 아이콘이 크고 어떤 화면에서는 안 뜬다"가 된다.
/// 그리는 규칙은 여기 하나뿐이고, 호출부는 [leadingFor]만 부른다.
///
/// ── 저장값에는 들어가지 않는다 ────────────────────────────────────────
/// Firestore에 남는 값은 언제나 `'돌싱'` 같은 문자열 하나다. 경로도 이모지도
/// 저장하지 않는다([PartyConstants.typeVibeIconAssets] 참고) — 그래서 그림을
/// 갈아 끼워도 이미 저장된 파티는 하나도 건드리지 않는다.
///
/// ── 이미지가 없어도 칩이 깨지지 않는다 ────────────────────────────────
/// asset이 아직 없거나 디코딩에 실패하면 [Image.asset]은 예외를 던져 그 칩
/// 전체가 빨간 오류 상자로 바뀐다. 그래서 [errorBuilder]로 **은색 별 모양의
/// 대체 아이콘**으로 떨어뜨린다 — 그림이 빠져도 "[별] 돌싱"으로는 읽힌다.
class PartyTypeVibeIcon extends StatelessWidget {
  const PartyTypeVibeIcon({super.key, required this.assetPath, this.size = 14});

  final String assetPath;

  /// 한 변 길이. 이모지와 나란히 놓이므로 **글자 크기보다 약간 크게** 준다 —
  /// 이모지는 글리프 안에 여백을 품고 있어 같은 값이면 그림이 작아 보인다.
  final double size;

  /// 그림을 못 그렸을 때의 은색 별. 색은 이 항목의 은색 별 아이콘에서 따온
  /// 중간 톤이라, 대체 아이콘이 떠도 갑자기 다른 색이 되지 않는다.
  static const Color _silver = Color(0xFFB6BCC8);

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        assetPath,
        width: size,
        height: size,
        fit: BoxFit.contain,
        // 작게 줄여 그리므로 축소 품질을 올린다 — 기본값이면 별 끝이 계단처럼
        // 깨진다.
        filterQuality: FilterQuality.medium,
        errorBuilder: (_, _, _) =>
            Icon(Icons.auto_awesome, size: size, color: _silver),
      ),
    );
  }
}

/// [value] 앞에 붙일 아이콘 위젯 — 이모지 항목이면 null.
///
/// 호출부는 이 결과가 null인지만 보고 "아이콘 자리를 그릴지"를 정하면 된다.
/// 어떤 값이 이미지 항목인지는 [PartyConstants]가 정하고, 호출부는 모른다.
Widget? partyTypeVibeIconFor(String value, {double size = 14}) {
  final path = PartyConstants.iconAssetFor(value);
  if (path == null) return null;
  return PartyTypeVibeIcon(assetPath: path, size: size);
}

/// '[아이콘] 돌싱' 한 덩어리 — 라벨을 그냥 [Text]로 그리던 자리를 그대로
/// 대체한다. 이모지 항목이면 아이콘 없이 [Text] 하나만 나오므로, 호출부는
/// 값이 어느 쪽인지 가릴 필요가 없다.
class PartyTypeVibeLabel extends StatelessWidget {
  const PartyTypeVibeLabel({
    super.key,
    required this.value,
    required this.label,
    this.style,
    this.iconSize = 14,
    this.gap = 4,
  });

  /// 저장값(`'돌싱'`, `'하우스파티'`, `'🍺 술 중심'` …). 아이콘 판정에 쓴다.
  final String value;

  /// 화면에 적을 글자([PartyConstants.labelFor] 등을 이미 거친 값).
  final String label;

  final TextStyle? style;
  final double iconSize;
  final double gap;

  @override
  Widget build(BuildContext context) {
    final icon = partyTypeVibeIconFor(value, size: iconSize);
    final text = Text(label, style: style);
    if (icon == null) return text;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [icon, SizedBox(width: gap), text],
    );
  }
}
