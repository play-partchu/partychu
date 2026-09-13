// 편의·서비스 / 시설 / 특징에는 **선택 개수 제한이 없다**.
//
// 정책은 하나다 — 해당하는 항목이 몇 개든 호스트는 전부 켤 수 있고, 켠 것이
// 저장·복원·검색까지 하나도 빠지지 않고 따라간다.
//
// 이 파일은 그 정책이 **다시 깨지지 않게** 못 박는다. 항목이 앞으로 늘어나도
// 여기서 전부 켜 보므로, 어딘가에 최대 N개 가드나 take()/sublist()가 새로
// 생기면 곧바로 실패한다.
//
// ⚠ 범위: 시설·편의·서비스·특징 계열만이다. 파티 유형·분위기
//   ([PartyConstants.maxTypeVibes])·업종·지역·날짜처럼 **다른 축**의 제한은
//   이 파일이 다루지 않는다(그쪽은 의도된 제한이다).
//
// ⚠ '하나만 고르는' 정책 그룹(흡연 정책·구워주는 서비스·콜키지·외부 음식
//   반입)은 개수 제한이 아니라 **서로 배타적인 값**이라 여기서 제외한다 —
//   '전 구역 금연'과 '흡연 가능 매장'을 동시에 켜면 데이터가 모순된다.
//   아래 [_exclusiveGroups] 테스트가 "그 넷 말고는 없다"를 지킨다.

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/event_filter.dart';
import 'package:party_app/models/listing_constants.dart';
import 'package:party_app/models/place_attributes.dart';
import 'package:party_app/models/place_facility_options.dart';
import 'package:party_app/models/place_feature.dart';
import 'package:party_app/models/place_filter.dart';

void main() {
  group('플레이스 세부 속성 — 그룹 안 항목을 전부 켤 수 있다', () {
    // 하나만 고르는 정책 그룹. 개수 제한이 아니라 배타적 선택이다.
    final exclusive = PlaceAttributeCatalog.all.where((g) => g.singleChoice);

    test('배타 그룹은 정해진 것들뿐이다 — 늘어나면 의도한 것인지 확인할 것', () {
      // 세부 속성 쪽 셋 — 전부 "둘 중 하나"인 정책이다.
      expect(exclusive.map((g) => g.key).toSet(), {
        PlaceAttributeCatalog.smokingKey,
        PlaceAttributeCatalog.grillKey,
        PlaceAttributeCatalog.corkageKey,
      }, reason: '배타 그룹이 바뀌었다 — 개수 제한을 새로 넣은 것은 아닌지 볼 것');

      // 좌석·편의 옵션 쪽 하나 — '가능/불가능/협의'라 동시에 켤 수 없다.
      expect(
        PlaceFacilityCatalog.all
            .where((g) => g.singleChoice)
            .map((g) => g.key)
            .toSet(),
        {'outsideFood'},
        reason: '배타 그룹이 바뀌었다 — 개수 제한을 새로 넣은 것은 아닌지 볼 것',
      );
    });

    for (final group in PlaceAttributeCatalog.all) {
      if (group.singleChoice || group.options.isEmpty) continue;

      test('${group.title} — ${group.options.length}개 전부 켜고 저장·복원된다', () {
        var attrs = PlaceAttributes.empty();
        for (final o in group.options) {
          attrs = attrs.toggle(group.key, o.label);
        }

        // ① 켠 개수가 줄지 않는다(선택 단계에서 자르지 않는다).
        expect(
          attrs.selected(group.key).length,
          group.options.length,
          reason: '선택에서 잘렸다',
        );

        // ② 저장 — 배열에 전부 실린다(take()/sublist() 없음).
        final saved = attrs.toMap();
        expect(
          (saved[group.key] as List).length,
          group.options.length,
          reason: '저장에서 잘렸다',
        );

        // ③ 수정 재진입 — 전부 복원된다.
        final restored = PlaceAttributes.fromDoc({
          PlaceAttributeCatalog.field: saved,
        });
        for (final o in group.options) {
          expect(
            restored.isSelected(group.key, o.label),
            isTrue,
            reason: '복원에서 빠졌다: ${o.label}',
          );
        }

        // ④ 임시저장 왕복에서도 그대로다.
        final draft = PlaceAttributes.fromDraftMap(attrs.toDraftMap());
        expect(draft.selected(group.key).length, group.options.length);
      });
    }
  });

  group('플레이스 좌석·편의 옵션(facilityOptions) — 전부 켤 수 있다', () {
    for (final group in PlaceFacilityCatalog.all) {
      if (group.singleChoice || group.options.isEmpty) continue;

      test('${group.title} — ${group.options.length}개 전부 켜고 저장·복원된다', () {
        var options = PlaceFacilityOptions.empty();
        for (final o in group.options) {
          options = options.toggle(group.key, o.label);
        }
        expect(options.selected(group.key).length, group.options.length);

        final saved = options.toMap();
        final restored = PlaceFacilityOptions.fromMap(saved);
        for (final o in group.options) {
          expect(
            restored.selected(group.key).contains(o.label),
            isTrue,
            reason: '복원에서 빠졌다: ${o.label}',
          );
        }
      });
    }
  });

  group('장소대여 공용 편의시설 — 프리셋 전부 + 직접 입력', () {
    test('${ListingConstants.placeFacilities.length}개를 전부 골라도 하나도 안 잘린다', () {
      // 등록 화면이 저장하는 모양 그대로 — `commonFacilities` 배열 하나.
      final picked = {...ListingConstants.placeFacilities};
      final saved = picked.toList();
      expect(saved.length, ListingConstants.placeFacilities.length);

      // 수정 재진입 — 프리셋/직접입력으로 갈라 담아도 총합이 유지된다.
      final preset = <String>{};
      final custom = <String>{};
      for (final f in saved) {
        if (ListingConstants.placeFacilities.contains(f)) {
          preset.add(f);
        } else {
          custom.add(f);
        }
      }
      expect(preset.length + custom.length, saved.length);
      expect(preset, containsAll(ListingConstants.placeFacilities));
    });

    test('직접 입력을 얼마든지 더해도 제한이 없다', () {
      final all = {
        ...ListingConstants.placeFacilities,
        for (var i = 0; i < 20; i++) '직접입력$i',
      };
      expect(all.length, ListingConstants.placeFacilities.length + 20);
    });

    test('편의시설 필터는 고른 개수만큼 그대로 들고 간다', () {
      final filter = PlaceFilter()
        ..facilities.addAll(ListingConstants.placeFacilities);
      expect(filter.facilities.length, ListingConstants.placeFacilities.length);
      // 칩으로 펼쳐도 개수가 유지된다(요약에서 자르지 않는다).
      final chips = filter.selectedEntries
          .where((e) => e.key == 'facilities')
          .length;
      expect(chips, ListingConstants.placeFacilities.length);
    });
  });

  group('편의·서비스 특징 — 고를 수 있는 전부를 한 번에 건다', () {
    test('selectable 전부를 필터에 담아도 잘리지 않는다', () {
      final all = {for (final f in PlaceFeatures.selectable) f.key};
      final filter = EventFilter()..features.addAll(all);
      expect(filter.features.length, all.length);
      expect(filter.features, containsAll(all));
    });

    test('전부 켠 플레이스는 전부 건 필터에 그대로 걸린다', () {
      // 모든 특징을 켜는 문서를 만든다 — 배타 그룹은 대표값 하나씩.
      var attrs = PlaceAttributes.empty();
      for (final g in PlaceAttributeCatalog.all) {
        if (g.options.isEmpty) continue;
        if (g.singleChoice) {
          attrs = attrs.toggle(g.key, g.options.first.label);
          continue;
        }
        for (final o in g.options) {
          attrs = attrs.toggle(g.key, o.label);
        }
      }
      final doc = <String, dynamic>{
        PlaceAttributeCatalog.field: attrs.toMap(),
      };

      // 이 문서에서 유도된 특징 전부를 조건으로 걸어도 자기 자신은 걸린다
      // (AND 판정이라 하나라도 빠지면 실패한다).
      final derived = PlaceFeatures.of(doc);
      expect(derived.length, greaterThan(5), reason: '유도가 거의 안 됐다');
      expect(
        PlaceFeatures.matchesAll(doc, derived),
        isTrue,
        reason: '고른 것 전부를 조건으로 걸면 자기 자신이 빠진다 — 어딘가에서 잘렸다',
      );
    });

    test('특징 어휘에 개수 상한 상수가 없다', () {
      // 항목이 늘어도 고를 수 있는 수는 항상 전체와 같다.
      expect(
        PlaceFeatures.selectable.length,
        PlaceFeatures.all.where((f) => !f.retired).length,
      );
    });
  });
}
