// PlacePartyLink가 Firestore로 **실제로 보내는 값**을 그대로 검증한다.
//
// ── 왜 payload를 보나 ─────────────────────────────────────────────────────
// 이 프로젝트의 Dart 테스트에는 Firestore 페이크(fake_cloud_firestore)도,
// 에뮬레이터에 붙는 통합 테스트도 없다(pubspec의 dev_dependencies는
// flutter_test / flutter_lints뿐이고, functions/ 쪽 에뮬레이터 스위트는 Cloud
// Functions용이라 이 클라이언트 서비스를 지나가지 않는다). 그래서 쓰기 자체를
// 돌려볼 수는 없다.
//
// 대신 쓰기 payload를 만드는 부분을 순수 함수로 떼어 두었다 — linkParties /
// unlinkParty / relinkParty는 모두 아래 함수들이 만든 맵을 batch.update에
// 그대로 넘길 뿐이다. FieldValue는 값 동등성이 있어(FieldValue.delete() ==
// FieldValue.delete()) "어느 필드가 지워지는지"까지 단언할 수 있다.
//
// ── 이 파일이 지키는 불변식 ───────────────────────────────────────────────
// **한 파티 문서에 linkedEventId와 linkedPlaceId가 동시에 유효하게 남지
// 않는다.** 종류를 가로질러 연결을 바꾸면(플레이스 → 장소대여) 이전 필드는
// 같은 batch에서 delete된다. 이 규칙은 화면이 아니라 payload 층에 있어야
// 등록·수정·연결관리 어느 경로로 들어와도 똑같이 지켜진다.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/services/place_party_link_service.dart';

const String _me = 'host-me';

Map<String, dynamic> _place({
  String name = 'OO 혼술바',
  String hostId = _me,
  double lat = 37.55,
  double lng = 126.92,
}) => <String, dynamic>{
  'hostId': hostId,
  'name': name,
  'address': '서울 마포구 와우산로 1',
  'roadAddress': '서울 마포구 와우산로 1',
  'detailAddress': '2층',
  'latitude': lat,
  'longitude': lng,
};

/// places 문서는 좌표 필드 이름이 다르다(`lat`/`lng`) — 읽는 쪽이 둘 다 받는다.
Map<String, dynamic> _rentalPlace({String name = 'OO 파티룸'}) =>
    <String, dynamic>{
      'hostId': _me,
      'name': name,
      'address': '서울 강남구 테헤란로 2',
      'roadAddress': '서울 강남구 테헤란로 2',
      'lat': 37.50,
      'lng': 127.03,
      'coverImageUrl': 'https://example.test/cover.jpg',
    };

void main() {
  group('연결 payload — 종류에 맞는 필드에만 쓴다', () {
    test('플레이스 연결은 linkedEventId에 쓰고 linkedPlaceId를 지운다', () {
      final update = PlacePartyLink.linkUpdate(
        target: PartyLinkTarget.place,
        targetId: 'E1',
        place: _place(),
        previousLocation: const {},
      );

      expect(update['linkedEventId'], 'E1');
      expect(
        update['linkedPlaceId'],
        FieldValue.delete(),
        reason: '반대쪽 필드는 값이 없더라도 명시적으로 지워야 두 연결이 남지 않습니다.',
      );
      expect(update[PlacePartyLink.usesRegisteredPlaceField], isTrue);
    });

    test('장소대여 연결은 linkedPlaceId에 쓰고 linkedEventId를 지운다', () {
      final update = PlacePartyLink.linkUpdate(
        target: PartyLinkTarget.rental,
        targetId: 'P1',
        place: _rentalPlace(),
        previousLocation: const {},
      );

      expect(update['linkedPlaceId'], 'P1');
      expect(update['linkedEventId'], FieldValue.delete());
    });

    test('장소 정보가 파티 문서로 복사된다 — 컬렉션마다 다른 좌표 필드도 읽는다', () {
      final update = PlacePartyLink.linkUpdate(
        target: PartyLinkTarget.rental,
        targetId: 'P1',
        place: _rentalPlace(),
        previousLocation: const {},
      );

      expect(update['placeName'], 'OO 파티룸');
      expect(update['address'], '서울 강남구 테헤란로 2');
      // places는 lat/lng로 저장한다 — 0,0이 되면 지도에서 사라진다.
      expect(update['latitude'], 37.50);
      expect(update['longitude'], 127.03);
    });

    test('스냅샷에 어느 컬렉션의 문서인지가 함께 담긴다', () {
      final snapshot =
          PlacePartyLink.linkUpdate(
                target: PartyLinkTarget.rental,
                targetId: 'P1',
                place: _rentalPlace(),
                previousLocation: const {},
              )[PlacePartyLink.snapshotField]
              as Map<String, dynamic>;

      // 키 이름은 옛 문서와 호환을 위해 eventId 그대로 — 컬렉션은 따로 적힌다.
      expect(snapshot['eventId'], 'P1');
      expect(snapshot['detailCollection'], 'places');
      expect(snapshot['mainImageUrl'], 'https://example.test/cover.jpg');
    });

    test('연결 직전 장소는 previousPlaceSnapshot으로 보관된다', () {
      final update = PlacePartyLink.linkUpdate(
        target: PartyLinkTarget.place,
        targetId: 'E1',
        place: _place(),
        previousLocation: const {'address': '직접 입력했던 주소'},
      );
      expect(update[PlacePartyLink.previousSnapshotField], {
        'address': '직접 입력했던 주소',
      });
    });
  });

  group('해제 payload', () {
    test('두 연결 필드를 모두 지우고 스냅샷도 함께 정리한다', () {
      final update = PlacePartyLink.unlinkUpdate();

      expect(update['linkedEventId'], FieldValue.delete());
      expect(update['linkedPlaceId'], FieldValue.delete());
      expect(update[PlacePartyLink.snapshotField], FieldValue.delete());
      expect(update[PlacePartyLink.previousSnapshotField], FieldValue.delete());
      expect(update[PlacePartyLink.usesRegisteredPlaceField], isFalse);
    });

    test('되돌리기를 고르면 연결 전 장소가 다시 쓰인다', () {
      final update = PlacePartyLink.unlinkUpdate(
        restoreFrom: const {'address': '직접 입력했던 주소', 'latitude': 37.1},
      );
      expect(update['address'], '직접 입력했던 주소');
      expect(update['latitude'], 37.1);
    });

    test('되돌리지 않으면 장소 필드는 손대지 않는다', () {
      final update = PlacePartyLink.unlinkUpdate();
      for (final key in kPartyLocationFields) {
        expect(update.containsKey(key), isFalse, reason: '$key를 건드리면 안 됩니다.');
      }
    });
  });

  group('보조 배열 payload', () {
    test('연결은 arrayUnion, 해제는 arrayRemove', () {
      expect(
        PlacePartyLink.linkedPartyIdsUpdate(
          partyIds: ['a'],
          add: true,
        )[PlacePartyLink.linkedPartyIdsField],
        FieldValue.arrayUnion(['a']),
      );
      expect(
        PlacePartyLink.linkedPartyIdsUpdate(
          partyIds: ['a'],
          add: false,
        )[PlacePartyLink.linkedPartyIdsField],
        FieldValue.arrayRemove(['a']),
      );
    });
  });

  group('종류를 가로지르는 변경 — 이전 필드가 남지 않는다', () {
    test('linkedEventId=A → 장소대여 B : event 연결이 제거된다', () {
      final update = PlacePartyLink.linkUpdate(
        target: PartyLinkTarget.rental,
        targetId: 'B',
        place: _rentalPlace(),
        previousLocation: PlacePartyLink.previousLocationFor(const {
          'linkedEventId': 'A',
          'address': '플레이스 A 주소',
        }),
      );

      expect(update['linkedPlaceId'], 'B');
      expect(update['linkedEventId'], FieldValue.delete());
      // 동시에 유효한 두 연결이 만들어지지 않는다.
      expect(update['linkedEventId'], isNot('A'));
    });

    test('linkedPlaceId=B → 플레이스 A : place 연결이 제거된다', () {
      final update = PlacePartyLink.linkUpdate(
        target: PartyLinkTarget.place,
        targetId: 'A',
        place: _place(),
        previousLocation: PlacePartyLink.previousLocationFor(const {
          'linkedPlaceId': 'B',
          'address': '장소대여 B 주소',
        }),
      );

      expect(update['linkedEventId'], 'A');
      expect(update['linkedPlaceId'], FieldValue.delete());
    });

    test('어떤 종류로 연결하든 유효한 연결 필드는 정확히 하나다', () {
      for (final target in PartyLinkTarget.values) {
        final update = PlacePartyLink.linkUpdate(
          target: target,
          targetId: 'X',
          place: _place(),
          previousLocation: const {},
        );
        final live = PartyLinkTarget.values
            .where((t) => update[t.linkField] != FieldValue.delete())
            .toList();
        expect(live, [target], reason: '$target 연결에서 살아남은 필드가 하나가 아닙니다.');
      }
    });

    test('원래 직접 입력했던 주소는 공간을 옮겨도 계속 물려받는다', () {
      // 이미 previousPlaceSnapshot이 있으면 그것이 진짜 원본이다 — 지금 값
      // (= 이전 공간에서 가져온 주소)으로 덮어쓰면 "연결 전 주소"가 사라진다.
      final previous = PlacePartyLink.previousLocationFor(const {
        'address': '플레이스 A에서 가져온 주소',
        PlacePartyLink.previousSnapshotField: {'address': '내가 직접 친 주소'},
      });
      expect(previous['address'], '내가 직접 친 주소');
    });

    test('previous가 없으면 지금 장소를 그대로 뜬다', () {
      final previous = PlacePartyLink.previousLocationFor(const {
        'address': '내가 직접 친 주소',
        'title': '파티 제목',
      });
      expect(previous['address'], '내가 직접 친 주소');
      expect(previous.containsKey('title'), isFalse, reason: '장소 필드만 떠야 합니다.');
    });
  });

  group('연결 종류 판정', () {
    test('linkedEventId만 있으면 플레이스', () {
      final link = PlacePartyLink.linkOf(const {'linkedEventId': 'E1'});
      expect(link?.target, PartyLinkTarget.place);
      expect(link?.id, 'E1');
    });

    test('linkedPlaceId만 있으면 장소대여', () {
      final link = PlacePartyLink.linkOf(const {'linkedPlaceId': 'P1'});
      expect(link?.target, PartyLinkTarget.rental);
      expect(link?.id, 'P1');
    });

    test('둘 다 없으면 null', () {
      expect(PlacePartyLink.linkOf(const {}), isNull);
      expect(PlacePartyLink.linkOf(const {'linkedEventId': ''}), isNull);
    });
  });
}
