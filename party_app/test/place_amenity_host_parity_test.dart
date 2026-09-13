import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/pet_policy.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_quick_picks.dart';
import 'package:party_app/models/place_taxonomy.dart';
import 'package:party_app/widgets/partychu_perk.dart' show kPartychuPerkField;

/// **편의·서비스 필터 ↔ 플레이스 등록/수정 1:1 대조.**
///
/// 이 파일이 막는 사고는 하나다 — "게스트는 검색할 수 있는데 어느 호스트도
/// 등록할 수 없는 조건", 그리고 그 반대.
///
/// ── 어떻게 증명하는가 ─────────────────────────────────────────────────────
/// 특징은 저장하는 값이 아니라 **다른 필드에서 유도되는 값**이다
/// ([PlaceFeatures.of]). 그래서 "등록 화면에 있다"를 위젯으로 확인하는 대신,
/// 각 특징마다 **등록 화면이 실제로 저장하는 모양 그대로** 문서를 만들어
/// [PlaceFeatures.of]가 그 특징을 켜는지 본다. 켜지면 그 경로는 살아 있는
/// 것이고, 그 경로에 쓰이는 그룹·라벨이 카탈로그에 있는지까지 함께 확인하면
/// 호스트가 화면에서 고를 수 있다는 뜻이 된다.
///
/// [_hostInputs]의 문서 모양이 틀리면 테스트가 곧바로 깨지므로, 이 표 자체가
/// [PlaceFeatures.of]와 어긋난 채로 남을 수 없다.
void main() {
  // ── 등록 화면이 저장하는 모양 ──────────────────────────────────────────
  //
  // 값은 전부 이미 있던 저장 경로다. 새로 만든 것은 무알콜 음료 하나뿐이고,
  // 그것도 새 최상위 필드가 아니라 기존 `placeAttributes` 안의 그룹이다.

  // `placeAttributes`는 그룹키 → 고른 라벨 배열이고,
  // `facilityOptions`는 그룹키 → {selected: [...]}다. 두 필드의 모양이 서로
  // 다르므로 헬퍼도 따로 둔다(등록 화면이 실제로 쓰는 모양 그대로).
  Map<String, dynamic> attrs(String group, List<String> picked) => {
    PlaceAttributeCatalog.field: {group: picked},
  };

  Map<String, dynamic> facility(String group, List<String> picked) => {
    'facilityOptions': {
      group: {'selected': picked},
    },
  };

  /// 특징 키 → (그 값이 어디서 오는가, 그때 저장되는 문서).
  final hostInputs = <String, (String, Map<String, dynamic>)>{
    // ① themeTags — 예전에는 등록 화면의 '특징 태그' 칩이 켰지만, 그 입력은
    //    없어졌다. 문서 모양과 판정은 그대로라 이미 달린 태그가 계속 걸린다.
    //      · 핫플     — 옛 문서에만 남아 있는 값(새로 켤 자리가 없다).
    //      · 이벤트   — 이벤트 등록이 자동으로 켠다
    //                   ([PartyEventSource.eventMirrorUpdate]).
    PlaceFeatures.hot.key: (
      '옛 특징 태그(themeTags)',
      {
        'themeTags': ['핫플'],
      },
    ),
    PlaceFeatures.eventNow.key: (
      '이벤트 등록(자동)',
      {
        'themeTags': [ListingConstants.placeEventTag],
      },
    ),

    // ② 세부 속성(PlaceAttributesSection) — 업종에 맞는 그룹만 펼쳐진다.
    PlaceFeatures.unlimited.key: (
      '세부 속성 · 무제한',
      attrs(PlaceAttributeCatalog.unlimitedKey, [
        PlaceAttributeCatalog.unlimitedMeat,
      ]),
    ),
    PlaceFeatures.corkageAvailable.key: (
      '세부 속성 · 콜키지',
      attrs(PlaceAttributeCatalog.corkageKey, [
        PlaceAttributeCatalog.corkageFree,
      ]),
    ),
    PlaceFeatures.bigScreen.key: (
      '세부 속성 · 대형스크린',
      attrs(PlaceAttributeCatalog.screenKey, ['대형스크린 있음']),
    ),
    PlaceFeatures.play.key: (
      '세부 속성 · 놀거리',
      attrs(PlaceAttributeCatalog.playItemsKey, ['노래방']),
    ),
    PlaceFeatures.birthday.key: (
      '세부 속성 · 생일 혜택',
      attrs(PlaceAttributeCatalog.birthdayPerksKey, ['케이크']),
    ),
    PlaceFeatures.dj.key: ('세부 속성 · DJ', attrs('dj', ['DJ 있음'])),
    PlaceFeatures.firepit.key: (
      '세부 속성 · 불멍',
      attrs(PlaceAttributeCatalog.firepitKey, ['불멍 가능']),
    ),
    PlaceFeatures.pool.key: (
      '세부 속성 · 수영장',
      attrs(PlaceAttributeCatalog.poolKey, ['실내 수영장']),
    ),
    PlaceFeatures.parking.key: (
      '세부 속성 · 주차',
      attrs(PlaceAttributeCatalog.parkingKey, ['주차 가능']),
    ),
    PlaceFeatures.valet.key: (
      '세부 속성 · 주차',
      attrs(PlaceAttributeCatalog.parkingKey, ['발렛 가능']),
    ),
    PlaceFeatures.bbq.key: (
      '세부 속성 · BBQ',
      attrs(PlaceAttributeCatalog.bbqKey, ['BBQ 가능']),
    ),
    PlaceFeatures.private.key: (
      '세부 속성 · 이런 모임에 좋아요',
      attrs(PlaceAttributeCatalog.purposesKey, ['프라이빗']),
    ),
    PlaceFeatures.groupSeat.key: (
      '세부 속성 · 이런 모임에 좋아요',
      attrs(PlaceAttributeCatalog.purposesKey, ['단체석']),
    ),
    PlaceFeatures.live.key: (
      '세부 속성 · 이런 모임에 좋아요',
      attrs(PlaceAttributeCatalog.purposesKey, ['라이브공연']),
    ),
    PlaceFeatures.cakeBringIn.key: (
      '세부 속성 · 반입 조건',
      attrs(PlaceAttributeCatalog.bringInKey, ['케이크 반입 가능']),
    ),
    PlaceFeatures.delivery.key: (
      '세부 속성 · 반입 조건',
      attrs(PlaceAttributeCatalog.bringInKey, ['배달음식 가능']),
    ),
    PlaceFeatures.bringAlcohol.key: (
      '세부 속성 · 반입 조건',
      attrs(PlaceAttributeCatalog.bringInKey, ['주류 반입 가능']),
    ),
    PlaceFeatures.smokeFree.key: (
      '세부 속성 · 흡연 정책',
      attrs(PlaceAttributeCatalog.smokingKey, [
        PlaceAttributeCatalog.smokeFreeAll,
      ]),
    ),
    PlaceFeatures.smokingArea.key: (
      '세부 속성 · 흡연 정책',
      attrs(PlaceAttributeCatalog.smokingKey, [
        PlaceAttributeCatalog.smokingRoom,
      ]),
    ),
    PlaceFeatures.grill.key: (
      '세부 속성 · 구워주는 서비스',
      attrs(PlaceAttributeCatalog.grillKey, [PlaceAttributeCatalog.grillAll]),
    ),
    // 등록 화면 '조리 제공' 그룹 — 구워주는 서비스와 **별개**의 질문이다.
    PlaceFeatures.cookedServed.key: (
      '세부 속성 · 조리 제공',
      attrs(PlaceAttributeCatalog.cookedKey, [
        PlaceAttributeCatalog.cookedServed,
      ]),
    ),
    // 등록 화면 '노래' 그룹 — 손님이 직접 노래할 수 있나(라이브·DJ와 별개).
    PlaceFeatures.singing.key: (
      '세부 속성 · 노래',
      attrs(PlaceAttributeCatalog.singingKey, [
        PlaceAttributeCatalog.singingAvailable,
      ]),
    ),
    PlaceFeatures.songRequest.key: (
      '세부 속성 · 노래',
      attrs(PlaceAttributeCatalog.singingKey, [
        PlaceAttributeCatalog.songRequestAvailable,
      ]),
    ),
    PlaceFeatures.sportsBroadcast.key: (
      '세부 속성 · 스포츠 중계',
      attrs(PlaceAttributeCatalog.sportsKey, [
        PlaceAttributeCatalog.sportsBroadcast,
      ]),
    ),
    // 이번에 새로 이은 자리 — 등록 화면 '무알콜 음료' 그룹.
    PlaceFeatures.nonAlcoholic.key: (
      '세부 속성 · 무알콜 음료',
      attrs(PlaceAttributeCatalog.drinksKey, [
        PlaceAttributeCatalog.nonAlcoholicDrink,
      ]),
    ),
    PlaceFeatures.highball.key: (
      '세부 속성 · 하이볼 · 막걸리',
      attrs(PlaceAttributeCatalog.servedDrinksKey, [
        PlaceAttributeCatalog.highballServed,
      ]),
    ),
    PlaceFeatures.makgeolli.key: (
      '세부 속성 · 하이볼 · 막걸리',
      attrs(PlaceAttributeCatalog.servedDrinksKey, [
        PlaceAttributeCatalog.makgeolliServed,
      ]),
    ),

    // ③ 좌석·공간 / 외부 음식(PlaceFacilityOptionsSection).
    PlaceFeatures.barSeat.key: (
      '좌석·공간',
      facility(PlaceFacilityCatalog.seatingTypes.key, ['카운터석']),
    ),
    PlaceFeatures.soloFriendly.key: (
      '좌석·공간 · 이용 편의',
      facility(PlaceFacilityCatalog.seatingConveniences.key, ['1인 방문 가능']),
    ),
    PlaceFeatures.outsideFood.key: (
      '외부 음식 반입',
      facility(PlaceFacilityCatalog.outsideFood.key, [
        PlaceFacilityCatalog.outsideFoodAllowedLabel,
      ]),
    ),

    // ④ 전용 섹션들.
    PlaceFeatures.pet.key: (
      '애견동반',
      {
        'petPolicy': PetPolicy.empty()
            .copyWith(status: PetPolicyStatus.possible)
            .toMap(),
      },
    ),
    PlaceFeatures.lateNight.key: ('운영시간', {'isOpen24Hours': true}),
    PlaceFeatures.partychuPerk.key: (
      '파티츄 전용 혜택',
      {kPartychuPerkField: '웰컴 드링크 1잔'},
    ),
    // 예전에는 클럽 전용 '입장 정보'에서만 켤 수 있어, 맛집·술집 호스트는
    // 게스트가 검색하는 이 조건을 켤 방법이 없었다. 이제 방문 예약 설정이
    // 같은 뜻으로 이어진다.
    PlaceFeatures.tableReservation.key: (
      '방문 예약',
      {
        'visitReservation': {'enabled': true},
      },
    ),
  };

  /// 편의·서비스 시트가 실제로 보여주는 **특징** 키들(어느 업종에서 열어도 같다).
  ///
  /// 🎉 With파티는 특징이 아니라 파티 연결 조건이라 값이 없고, ♾ 무제한
  /// 묶음은 속성이라 특징 키가 아니다 — 둘 다 여기서 제외한다.
  List<String> sheetKeys() => PlaceQuickPicks.amenityKinds(
    PlaceTaxonomy.restaurant.label,
  ).where((p) => p.values.isNotEmpty).map((p) => p.values.first).toList();

  group('1. 옵션 변경', () {
    test('🕛 24시간은 어느 필터에서도 고를 수 없다', () {
      expect(PlaceFeatures.open24.retired, isTrue);
      expect(
        PlaceFeatures.selectable.map((f) => f.key),
        isNot(contains(PlaceFeatures.open24.key)),
      );
      expect(sheetKeys(), isNot(contains(PlaceFeatures.open24.key)));
    });

    test('24시간 영업 정보와 판정은 그대로 살아 있다', () {
      // 어휘에는 남아 있어야 예전에 저장된 필터 상태가 계속 걸린다.
      expect(PlaceFeatures.all.map((f) => f.key), contains('24시간'));
      final open24Place = {'name': '24시 포차', 'isOpen24Hours': true};
      expect(PlaceFeatures.of(open24Place), contains('24시간'));
      expect(
        EventFilter(features: {'24시간'}).matchesDiscovery(open24Place),
        isTrue,
        reason: '옛 필터 상태로도 예전과 똑같이 걸려야 한다',
      );
      // 심야영업도 같은 운영시간에서 함께 유도된다(예전 그대로).
      expect(
        PlaceFeatures.of(open24Place),
        contains(PlaceFeatures.lateNight.key),
      );
    });

    test('🥤 무알콜 음료가 그 자리에 들어왔다', () {
      expect(PlaceFeatures.nonAlcoholic.key, '무알콜');
      expect(PlaceFeatures.nonAlcoholic.label, '무알콜 음료');
      expect(PlaceFeatures.nonAlcoholic.emoji, '🥤');
      expect(sheetKeys(), contains('무알콜'));
    });
  });

  group('2. 필터 ↔ 저장값 1:1 — 누락 0', () {
    test('필터에 있는 모든 항목이 실제로 켜지는 저장 경로를 갖는다', () {
      final missing = <String>[];
      for (final key in sheetKeys()) {
        final input = hostInputs[key];
        if (input == null) {
          missing.add('$key — 이 특징을 켜는 저장 경로가 없다');
          continue;
        }
        final derived = PlaceFeatures.of({'name': '테스트', ...input.$2});
        if (!derived.contains(key)) {
          missing.add('$key — "${input.$1}"로 저장해도 특징이 안 켜진다');
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('반대로 켜지는 것 중 검색 못 하는 항목이 없다', () {
      final sheet = sheetKeys().toSet();
      // 편의·서비스 시트에 일부러 안 넣는 것들:
      //   · 무제한 — 시트 맨 아래 '♾ 무제한' 묶음이 세부종류째 맡는다.
      //   · 이벤트중 — 카테고리 영역의 '🎉 이벤트'가 맡는 다른 축이다.
      //   · 놀거리·심야영업·케이크반입·배달음식·BBQ — 목록이 길어 뺐다.
      //     저장·판정은 그대로고 상세검색·지도 필터에는 계속 있다.
      const ownChip = {'무제한', '이벤트중', '놀거리', '심야영업', '케이크반입', '배달음식', 'BBQ'};
      final unreachable = [
        for (final e in hostInputs.entries)
          if (!sheet.contains(e.key) && !ownChip.contains(e.key))
            '${e.key} — "${e.value.$1}"에서 켤 수 있는데 검색할 자리가 없다',
      ];
      expect(unreachable, isEmpty, reason: unreachable.join('\n'));
    });

    test('세부 속성 경로는 실제로 등록 화면에 펼쳐지는 그룹을 쓴다', () {
      // 어느 업종에서도 안 펼쳐지는 그룹으로 잇는 것을 막는다 —
      // 그러면 값은 유도되는데 호스트는 영원히 못 고른다.
      final categories = [null, ...PlaceTaxonomy.all.map((c) => c.label)];
      for (final g in PlaceAttributeCatalog.all) {
        final reachable = categories.any(
          (c) => PlaceAttributeCatalog.groupsFor(c).contains(g),
        );
        expect(reachable, isTrue, reason: '${g.key} 그룹을 아무 업종도 안 보여준다');
      }
    });

    // ── 업종별 대조 ─────────────────────────────────────────────────────
    //
    // 위 테스트들은 "어딘가 한 업종에서는 켤 수 있다"까지만 본다. 정작
    // 어긋남은 그 아래에 있었다 — 게스트의 편의·서비스 필터는 업종을 가리지
    // 않는데(지도 상세필터·✨ 편의·서비스 시트가 selectable 전부를 보여준다)
    // 등록 화면은 업종으로 그룹을 잘라, 카페 사장은 🍽️ 조리되어 나와요·
    // 🍶 콜키지 가능·🔥 구워줘요·🍖 BBQ·🎧 DJ를 켤 자리가 없었다.
    test('어느 업종으로 등록해도 필터의 편의·서비스를 전부 켤 수 있다', () {
      final categories = [null, ...PlaceTaxonomy.all.map((c) => c.label)];
      final missing = <String>[];

      for (final category in categories) {
        final where = category ?? '업종 미선택';
        final askable = {
          for (final g in PlaceAttributeCatalog.askableFor(category)) g.key,
        };
        for (final f in PlaceFeatures.selectable) {
          final input = hostInputs[f.key];
          if (input == null) {
            missing.add('${f.key} — 이 특징을 켜는 저장 경로가 없다');
            continue;
          }
          // 속성이 아닌 경로(좌석·반려동물·운영시간·themeTags …)는 업종을
          // 타지 않는다 — 등록 화면에 늘 있는 섹션들이다.
          final attrMap =
              input.$2[PlaceAttributeCatalog.field] as Map<String, dynamic>?;
          if (attrMap == null) continue;
          for (final groupKey in attrMap.keys) {
            if (askable.contains(groupKey)) continue;
            missing.add(
              '${f.key}(${f.label}) — $where 등록 화면에 "$groupKey" 그룹이 없다',
            );
          }
        }
      }
      expect(missing, isEmpty, reason: missing.join('\n'));
    });

    test('featureKeys는 실재하는 특징이고, 그 그룹으로 실제로 켜진다', () {
      // 카탈로그가 문자열로 적어 둔 연결이 특징 쪽과 어긋나지 않게 못 박는다
      // (특징이 이 파일을 읽는 방향이라 import로는 확인할 수 없다).
      final vocabulary = {for (final f in PlaceFeatures.all) f.key};
      final broken = <String>[];

      for (final g in PlaceAttributeCatalog.all) {
        if (g.featureKeys.isEmpty) continue;

        // ① 어휘에 있는 키인가.
        for (final k in g.featureKeys) {
          if (!vocabulary.contains(k)) broken.add('${g.key} → "$k" 라는 특징이 없다');
        }

        // ② 그 그룹의 선택지 중 하나로 실제 켜지는가.
        final derivable = <String>{};
        for (final o in g.options) {
          derivable.addAll(
            PlaceFeatures.of({
              PlaceAttributeCatalog.field: {
                g.key: [o.label],
              },
            }),
          );
        }
        for (final k in g.featureKeys) {
          if (!derivable.contains(k)) {
            broken.add('${g.key} → "$k"이 이 그룹의 어떤 선택지로도 안 켜진다');
          }
        }
      }
      expect(broken, isEmpty, reason: broken.join('\n'));
    });

    test('필터(상세검색)와 등록 화면이 같은 그룹 목록을 본다', () {
      // 상세검색 시트는 askableFor를, 등록 화면은 groupsFor+extraGroupsFor를
      // 쓴다 — 둘이 같은 집합임을 여기서 고정한다.
      for (final c in [null, ...PlaceTaxonomy.all.map((c) => c.label)]) {
        final where = c ?? '업종 미선택';
        expect(
          PlaceAttributeCatalog.askableFor(c).map((g) => g.key).toList(),
          [
            ...PlaceAttributeCatalog.groupsFor(c).map((g) => g.key),
            ...PlaceAttributeCatalog.extraGroupsFor(c).map((g) => g.key),
          ],
          reason: where,
        );
        // 위·아래 묶음이 겹치지 않는다(같은 그룹이 두 번 그려지면 안 된다).
        final keys = PlaceAttributeCatalog.askableFor(c).map((g) => g.key);
        expect(keys.toSet().length, keys.length, reason: where);
      }
    });

    test("'그 밖' 묶음에 안 가는 그룹은 다른 길이 있거나 특징을 안 켠다", () {
      // 업종 안에 머무르는 그룹이 늘어날 때, 그것이 의도인지 사고인지
      // 여기서 갈린다.
      final stayInCategory = PlaceAttributeCatalog.all.where(
        (g) =>
            g.categories.isNotEmpty &&
            !PlaceAttributeCatalog.extraGroupsFor(
              PlaceTaxonomy.cafe.label,
            ).contains(g) &&
            !g.appliesTo(PlaceTaxonomy.cafe.label),
      );
      expect(
        stayInCategory.map((g) => g.key).toSet(),
        {
          // 특징을 하나도 안 켠다 — 업종 안에서만 뜻이 있는 값.
          PlaceAttributeCatalog.musicGenresKey,
          'alcoholTypes',
          // 🪑 테이블 예약은 켜지만, 방문 예약 설정이라는 다른 길이 모든
          // 업종에 열려 있다.
          PlaceAttributeCatalog.clubEntryKey,
        },
        reason: '업종 안에만 머무르는 그룹이 바뀌었다 — 게스트가 그 조건으로 검색할 수 있는지 확인할 것',
      );
    });
  });

  group('3. 정본 통일', () {
    test('세 필터 화면이 같은 목록 하나를 훑는다', () {
      // 지도 상세필터·상세검색 시트는 PlaceFeatures.selectable을 그대로 쓰고,
      // 편의·서비스 시트는 거기서 자기 칩이 따로 있는 둘만 뺀다.
      final selectable = PlaceFeatures.selectable.map((f) => f.key).toSet();
      expect(sheetKeys().toSet().difference(selectable), isEmpty);
      expect(selectable.difference(sheetKeys().toSet()), {
        '무제한',
        '이벤트중',
        '놀거리',
        '심야영업',
        '케이크반입',
        '배달음식',
        'BBQ',
      });
    });

    test('키 · 이름 · 이모지가 한 곳에서 나온다', () {
      for (final f in PlaceFeatures.selectable) {
        expect(f.key, isNotEmpty);
        expect(f.label, isNotEmpty);
        expect(f.emoji, isNotEmpty);
        expect(PlaceFeatures.byKey(f.key), same(f));
        expect(PlaceFeatures.displayOf(f.key), '${f.emoji} ${f.label}');
      }
    });

    test('키가 겹치지 않는다', () {
      final keys = PlaceFeatures.all.map((f) => f.key).toList();
      expect(keys.toSet().length, keys.length);
    });
  });

  group('4. 기존 데이터 호환', () {
    test('예전 문서의 편의·서비스 값이 그대로 읽힌다', () {
      // 새 필드가 하나도 없는 옛 문서 — themeTags·petPolicy·영업시간만 있다.
      final legacy = {
        'name': '옛 술집',
        'themeTags': ['핫플'],
        'petPolicy': PetPolicy.empty()
            .copyWith(status: PetPolicyStatus.possible)
            .toMap(),
        'isOpen24Hours': true,
      };
      final derived = PlaceFeatures.of(legacy);
      expect(derived, containsAll(['핫플', '반려동물', '심야영업', '24시간']));
    });

    test('무알콜 음료를 안 고른 문서에는 아무것도 새로 생기지 않는다', () {
      expect(PlaceFeatures.of({'name': '옛 가게'}), isEmpty);
      expect(
        PlaceFeatures.of({
          'name': '옛 가게',
          ...attrs('alcoholTypes', ['와인']),
        }),
        isNot(contains('무알콜')),
      );
    });
  });

  group('5. 무알콜 음료 — 등록부터 검색까지 같은 값', () {
    final doc = {
      'name': '무알콜 되는 바',
      'placeCategory': 'BAR',
      ...attrs(PlaceAttributeCatalog.drinksKey, [
        PlaceAttributeCatalog.nonAlcoholicDrink,
      ]),
    };

    test('① 등록 화면이 이 그룹을 보여준다', () {
      final group = PlaceAttributeCatalog.groupOf(
        PlaceAttributeCatalog.drinksKey,
      );
      expect(group, isNotNull);
      expect(group!.hasOption(PlaceAttributeCatalog.nonAlcoholicDrink), isTrue);
      // 업종을 가리지 않는다 — 어느 대분류로 등록해도 펼쳐진다.
      for (final c in PlaceTaxonomy.all) {
        expect(
          PlaceAttributeCatalog.groupsFor(c.label),
          contains(group),
          reason: c.label,
        );
      }
    });

    test('② 저장된 문서에서 속성이 그대로 복원된다', () {
      final restored = PlaceAttributes.fromDoc(doc);
      expect(
        restored.isSelected(
          PlaceAttributeCatalog.drinksKey,
          PlaceAttributeCatalog.nonAlcoholicDrink,
        ),
        isTrue,
      );
    });

    test('③ 특징으로 유도된다', () {
      expect(PlaceFeatures.of(doc), contains(PlaceFeatures.nonAlcoholic.key));
    });

    test('④ 편의·서비스 필터로 검색된다', () {
      final f = EventFilter();
      // 🎉 With파티 칩은 특징이 아니라 값이 비어 있다 — 먼저 걸러야
      // .first가 터지지 않는다(위 sheetKeys()와 같은 관례).
      final chip = PlaceQuickPicks.amenityKinds(PlaceTaxonomy.bar.label)
          .where((p) => p.values.isNotEmpty)
          .firstWhere((p) => p.values.first == PlaceFeatures.nonAlcoholic.key);
      chip.toggle(f);
      expect(f.features, {'무알콜'});
      expect(f.matchesDiscovery(doc), isTrue);
      expect(
        f.matchesDiscovery({'name': '술만 파는 바', 'placeCategory': 'BAR'}),
        isFalse,
      );
    });

    test('⑤ 상세 화면 표기도 같은 값에서 나온다', () {
      expect(
        PlaceAttributeCatalog.emojiFor(PlaceAttributeCatalog.nonAlcoholicDrink),
        '🥤',
      );
      expect(PlaceFeatures.displayOf('무알콜'), '🥤 무알콜 음료');
    });
  });
}
