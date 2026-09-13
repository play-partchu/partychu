import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/party_constants.dart';
import 'package:party_app/models/party_search.dart';

/// 파티 상단 검색창 한 칸이 무엇을 찾는지 고정한다.
///
/// 상세검색의 '태그' 카드를 없애고 검색창으로 합쳤으므로, **태그가 실제로
/// 검색되는지**가 이 파일의 첫 번째 약속이다. 힌트에 적힌 '파티 제목, 장소,
/// 태그, 키워드'가 전부 실제로 걸려야 한다.
void main() {
  Map<String, dynamic> party({
    String title = '금요일 와인 모임',
    String? description,
    String? placeName,
    String? location,
    String? address,
    String? district,
    List<String>? partyTypes,
    List<String>? vibes,
    List<String>? tags,
  }) => {
    'title': title,
    if (description != null) 'description': description,
    if (placeName != null) 'placeName': placeName,
    if (location != null) 'location': location,
    if (address != null) 'address': address,
    if (district != null) 'district': district,
    if (partyTypes != null) 'partyTypes': partyTypes,
    if (vibes != null) 'vibes': vibes,
    if (tags != null) 'tags': tags,
  };

  group('태그 — 검색창으로 통합됐다', () {
    final tagged = party(tags: ['감성', '소규모']);

    test('태그명을 치면 그 태그가 붙은 파티가 나온다', () {
      expect(partySearchMatches(tagged, '감성'), isTrue);
      expect(partySearchMatches(tagged, '소규모'), isTrue);
    });

    test('# 를 붙여 쳐도 같다 — 칩에 적힌 그대로 쳐도 찾힌다', () {
      expect(partySearchMatches(tagged, '#감성'), isTrue);
    });

    test('부분만 쳐도 걸리고 대소문자는 무시한다', () {
      final en = party(tags: ['Wine']);
      expect(partySearchMatches(tagged, '감'), isTrue);
      expect(partySearchMatches(en, 'wine'), isTrue);
      expect(partySearchMatches(en, 'WIN'), isTrue);
    });

    test('없는 태그는 걸리지 않는다', () {
      expect(partySearchMatches(tagged, '힙합'), isFalse);
    });

    test('태그가 없는 파티도 다른 조건으로는 그대로 걸린다', () {
      final none = party(title: '감성 모임');
      expect(partySearchMatches(none, '감성'), isTrue);
    });
  });

  group('장소 — 힌트에 적힌 대로 실제로 찾는다', () {
    test('장소명으로 찾는다', () {
      final p = party(placeName: '연남동 루프탑');
      expect(partySearchMatches(p, '루프탑'), isTrue);
    });

    test('주소 계열 어느 필드에 들어 있어도 찾는다', () {
      for (final key in [
        'location',
        'address',
        'roadAddress',
        'jibunAddress',
        'detailAddress',
        'district',
      ]) {
        final p = <String, dynamic>{'title': '모임', key: '서울 마포구 서교동'};
        expect(partySearchMatches(p, '마포'), isTrue, reason: key);
      }
    });
  });

  group('제목·키워드 — 예전 그대로', () {
    test('제목과 소개글', () {
      final p = party(title: '와인 한 잔', description: '조용한 곳에서 천천히');
      expect(partySearchMatches(p, '와인'), isTrue);
      expect(partySearchMatches(p, '조용한'), isTrue);
    });

    test('분위기와 파티 유형(저장값)', () {
      final raw = PartyConstants.partyTypes.first;
      final vibe = PartyConstants.vibes.first;
      final p = party(partyTypes: [raw], vibes: [vibe]);
      expect(partySearchMatches(p, raw), isTrue);
      expect(partySearchMatches(p, vibe), isTrue);
    });

    test('파티 유형은 화면에 적힌 표기로도 찾는다', () {
      // 저장값과 라벨이 다른 유형이 하나라도 있으면 그것으로 확인한다.
      final raw = PartyConstants.partyTypes.firstWhere(
        (t) => PartyConstants.labelFor(t) != t,
        orElse: () => PartyConstants.partyTypes.first,
      );
      final label = PartyConstants.labelFor(raw);
      final p = party(partyTypes: [raw]);
      expect(partySearchMatches(p, label), isTrue);
    });
  });

  group('빈 검색어', () {
    test('아무것도 안 치면 전부 통과한다 — 검색이 목록을 좁히지 않는다', () {
      expect(partySearchMatches(party(), ''), isTrue);
      expect(partySearchMatches(const {}, ''), isTrue);
    });

    test('필드가 통째로 없는 문서도 터지지 않는다', () {
      expect(partySearchMatches(const {}, '와인'), isFalse);
    });
  });
}
