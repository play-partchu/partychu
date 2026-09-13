import 'package:flutter/material.dart';

import 'package:party_app/models/custom_play_item.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_taxonomy.dart';

const _kAccent = Color(0xFFFF6FA0);
const _kChipBg = Color(0xFFFFF0F5);
const _kBorder = Color(0xFFE8EBF2);

/// 상세페이지 맨 위의 **핵심 특징 칩** 한 줄.
///
/// 긴 글을 읽기 전에 "왜 가볼 만한 곳인지"가 먼저 보여야 한다 —
/// `🍶 콜키지 가능 · 무료 · 🚭 전 구역 금연 · 🖥 150인치 · 🎂 생일혜택`.
///
/// 값은 [PlaceFeatures.of] 하나에서 나오므로, 새 필드가 없는 옛 플레이스도
/// themeTags·petPolicy·영업시간에서 유도된 특징이 그대로 뜬다.
class PlaceHighlightChips extends StatelessWidget {
  const PlaceHighlightChips({super.key, required this.data, this.max = 6});

  final Map<String, dynamic> data;
  final int max;

  @override
  Widget build(BuildContext context) {
    final chips = _labels(data, max: max);
    if (chips.isEmpty) return const SizedBox.shrink();
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final text in chips)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
            decoration: BoxDecoration(
              color: _kChipBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 11.5,
                fontWeight: FontWeight.w700,
                color: _kAccent,
              ),
            ),
          ),
      ],
    );
  }

  /// 칩 문구 — 특징 이름만 나열하지 않고, 값이 있으면 **그 값을** 보여준다
  /// ('무제한'이 아니라 '♾ 하이볼 무제한', '♾ 노래방 시간 무제한').
  ///
  /// 문구를 만드는 곳은 [PlaceFeatures.highlightLabelsOf] 하나다 — 목록 카드도
  /// 같은 함수를 부르므로, 같은 가게가 화면마다 다른 이름으로 보이지 않는다.
  static List<String> _labels(Map<String, dynamic> data, {required int max}) =>
      // 상세는 카드보다 자세히 적는다 — 콜키지는 '🍶 콜키지 가능 · 유료 ·
      // 1병 10,000원'처럼 호스트가 적어 둔 요금 원문까지 그대로 보여준다.
      PlaceFeatures.highlightLabelsOf(data, max: max, detailed: true);
}

/// 상세페이지의 **카테고리별 정보 블록**.
///
/// 음식점에 클럽용 항목이 나오거나 그 반대가 되지 않도록, 어떤 대분류에서
/// 무엇을 먼저 보여줄지는 [PlaceDetailBlocks]가 정하고 여기서는 그 순서대로
/// 값이 있는 그룹만 그린다. 값이 하나도 없는 그룹은 통째로 빠지므로, 아무것도
/// 입력하지 않은 옛 플레이스의 상세페이지는 예전과 똑같이 보인다.
class PlaceAttributesView extends StatelessWidget {
  const PlaceAttributesView({super.key, required this.data});

  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final attrs = PlaceAttributes.fromDoc(data);
    final category = PlaceTaxonomy.categoryOf(data);
    final customPlay = CustomPlayItems.of(data);
    final groups = PlaceDetailBlocks.orderedFor(category)
        .where(
          (g) =>
              attrs.selected(g.key).isNotEmpty ||
              // 자유기재 놀거리만 남은 문서도 블록을 그린다 — 저장 규칙상
              // 이런 문서는 나오지 않지만, 콘솔에서 손댄 문서 하나 때문에
              // 호스트가 적은 값이 통째로 사라지지는 않게 한다.
              (g.key == CustomPlayItems.groupKey && customPlay.isNotEmpty),
        )
        .toList();
    if (groups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final group in groups) ...[
          const SizedBox(height: 14),
          _block(group, attrs, customPlay),
        ],
      ],
    );
  }

  Widget _block(
    PlaceAttributeGroup group,
    PlaceAttributes attrs,
    List<String> customPlay,
  ) {
    // 놀거리에서 '기타'는 **그 자체로는 아무것도 알려주지 않는다** — 호스트가
    // 적어 둔 이름이 있으면 그 칩을 대신 세운다('기타 · 포켓볼'이 아니라
    // '포켓볼 · 테이블축구'). 이름이 없으면 예전처럼 '기타'가 그대로 남는다.
    final custom = group.key == CustomPlayItems.groupKey
        ? customPlay
        : const <String>[];
    final picked = group.options
        .where((o) => attrs.isSelected(group.key, o.label))
        .where(
          (o) => !(custom.isNotEmpty && o.label == CustomPlayItems.etcOption),
        )
        .toList();
    // 카탈로그에서 빠진(옛) 값도 버리지 않는다.
    final unknown = attrs
        .selected(group.key)
        .where((label) => !group.hasOption(label))
        .toList();

    final details = <MapEntry<String, String>>[];
    for (final field in group.details) {
      final raw = attrs.detail(group.key, field.key);
      if (raw == null || raw == false) continue;
      details.add(MapEntry(field.label, raw == true ? '가능' : raw.toString()));
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            group.display,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: [
              for (final o in picked) _tag(_tagLabel(group, o.label, o.emoji)),
              for (final label in unknown) _tag(_tagLabel(group, label, null)),
              // 호스트가 직접 적은 놀거리 — 프리셋과 같은 모양의 칩으로 잇는다.
              for (final label in custom) _tag(label),
            ],
          ),
          if (details.isNotEmpty) ...[
            const SizedBox(height: 10),
            for (final d in details)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      width: 92,
                      child: Text(
                        d.key,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.black45,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Text(
                        d.value,
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  /// 블록 안 칩 문구 — 저장값을 그대로 적지 않고 읽히는 문장으로 바꾼다.
  /// 블록 제목이 '♾ 무제한'이어도 칩이 '노래방 시간'이면 무엇을 말하는지 한 번
  /// 더 생각해야 하고, '요청 시 구워줌'은 손님에게 하는 말투가 아니다.
  /// 문장을 만드는 곳은 [PlaceAttributeCatalog.phraseOf] 하나다.
  String _tagLabel(PlaceAttributeGroup group, String value, String? emoji) {
    final text = PlaceAttributeCatalog.phraseOf(group.key, value);
    return emoji == null ? text : '$emoji $text';
  }

  Widget _tag(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    decoration: BoxDecoration(
      color: _kChipBg,
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(
      label,
      style: const TextStyle(
        fontSize: 11.5,
        fontWeight: FontWeight.w700,
        color: _kAccent,
      ),
    ),
  );
}
