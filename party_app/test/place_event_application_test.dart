// 매장 이벤트 **신청 데이터**의 정본 확인.
//
// ── 이 파일이 막는 재발 ─────────────────────────────────────────────────────
// ① 처음 만든 신청하기는 이벤트 채팅방에 "[신청] …" 한 줄을 보내는 것으로
//    끝났다. 신청이 **어디에도 남지 않아서** 호스트는 채팅 목록을 눈으로 세야
//    했고, 게스트는 자기가 신청했는지 알 수 없었다.
// ② 그 다음 판은 앱이 신청 문서를 직접 썼다. 위조는 규칙으로 막았지만
//    **종료된 이벤트를 막을 수 없었다** — 종료 판정이 "endAt이 속한 날의
//    23:59:59"를 접는 계산이라 규칙으로 옮기면 앱과 어긋나기 때문이다.
//    변조된 클라이언트는 버튼을 거치지 않으므로 "버튼이 안 보인다"는 방어가
//    아니었다.
//
// 여기서 고정하는 것:
//   ① 신청은 자기 컬렉션에 남는다 — 이름이 `applications`가 **아니다**
//   ② 문서 id가 곧 중복 방지다(`{eventId}_{guestId}`), 앱과 서버가 같은 식
//   ③ 취소는 삭제가 아니라 상태 전환이고, 취소는 신청자 수에 안 들어간다
//   ④ **앱은 이 컬렉션에 쓰지 못한다** — 규칙이 클라이언트 쓰기를 전면 차단
//   ⑤ 목록에 뜨는 값은 서버가 원본에서 베낀 스냅샷이다(위조 입력이 없다)
//
// 실제 규칙 엔진으로 도는 권한 검증은 functions 쪽에 있다
// (placeEventApplicationRules.selfcheck.js — Firestore 에뮬레이터).
// 여기서는 앱이 기대하는 조건이 규칙·서버에서 조용히 사라지지 않았는지 본다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/models/place_event_application.dart';
import 'package:party_app/screens/my_guest_hub_screen.dart';

String get _rules => File('../firestore.rules').readAsStringSync();
String get _server =>
    File('../functions/placeEventApplications.js').readAsStringSync();

/// firestore.rules에서 placeEventApplications 블록만 잘라 온다.
String get _rulesBlock {
  final start = _rules.indexOf('match /placeEventApplications/');
  expect(start, greaterThan(-1), reason: 'placeEventApplications 규칙 블록이 없다');
  final block = _rules.substring(start);
  return block.substring(0, block.indexOf('\n    }'));
}

PlaceEventApplication _app({
  String eventId = 'EV1',
  String guestId = 'guest-1',
  PlaceEventApplicationStatus status = PlaceEventApplicationStatus.applied,
  bool isAlways = false,
  DateTime? endAt,
}) => PlaceEventApplication(
  id: '${eventId}_$guestId',
  eventId: eventId,
  placeId: 'PL1',
  hostId: 'host-1',
  guestId: guestId,
  status: status,
  eventTitle: '생일 이벤트',
  placeName: '혼술바',
  eventIsAlways: isAlways,
  eventEndAt: endAt,
);

void main() {
  // ── 어디에 남는가 ───────────────────────────────────────────────────────

  group('저장 위치', () {
    test('신청은 자기 최상위 컬렉션에 남는다', () {
      expect(PlaceEventApplication.collection, 'placeEventApplications');
    });

    // 파티 신청은 `parties/{id}/applications`이고, 규칙에는 재귀 와일드카드
    // `/{path=**}/applications/{id}`가, 서버에는 `collectionGroup('applications')`
    // 집계가 여럿 있다(탈퇴 차단·매출 통계). 이름을 공유하는 순간 매장 이벤트
    // 신청이 파티 신청으로 세어진다 — 탈퇴가 막히고 매출에 빈 건이 섞인다.
    test('파티 신청과 이름을 공유하지 않는다', () {
      expect(PlaceEventApplication.collection, isNot('applications'));
      expect(
        PlaceEventApplication.collection.endsWith('/applications'),
        isFalse,
      );
    });

    test('서버가 보는 컬렉션 이름과 같다', () {
      expect(
        _server,
        contains("const COLLECTION = '${PlaceEventApplication.collection}'"),
      );
    });
  });

  // ── 중복 방지 ───────────────────────────────────────────────────────────

  group('문서 id', () {
    test('같은 사람 · 같은 이벤트는 언제나 같은 문서다', () {
      final a = PlaceEventApplication.docIdFor(
        eventId: 'EV1',
        guestId: 'guest-1',
      );
      final b = PlaceEventApplication.docIdFor(
        eventId: 'EV1',
        guestId: 'guest-1',
      );
      expect(a, b);
      expect(a, 'EV1_guest-1');
    });

    test('사람이 다르거나 이벤트가 다르면 다른 문서다', () {
      final mine = PlaceEventApplication.docIdFor(
        eventId: 'EV1',
        guestId: 'guest-1',
      );
      expect(
        mine,
        isNot(
          PlaceEventApplication.docIdFor(eventId: 'EV1', guestId: 'guest-2'),
        ),
      );
      expect(
        mine,
        isNot(
          PlaceEventApplication.docIdFor(eventId: 'EV2', guestId: 'guest-1'),
        ),
      );
    });

    // 문서를 만드는 쪽은 이제 서버다. 두 식이 갈리면 앱이 지켜보는 문서와
    // 서버가 쓰는 문서가 달라져서, 신청해도 버튼이 '신청하기' 그대로 남는다.
    test('서버가 쓰는 식과 같다', () {
      expect(_server, contains('return `\${eventId}_\${guestId}`;'));
    });
  });

  // ── 상태 ────────────────────────────────────────────────────────────────

  group('상태', () {
    test('키는 문서에 그대로 남는 값이라 바뀌면 안 된다', () {
      expect(PlaceEventApplicationStatus.applied.key, 'applied');
      expect(PlaceEventApplicationStatus.cancelled.key, 'cancelled');
    });

    // 여기서만은 fail-open이다 — 모르는 상태를 '취소'로 보면 호스트의 목록에서
    // 실제 신청자가 조용히 사라진다.
    test('모르는 값·빈 값은 신청으로 본다', () {
      for (final raw in [null, '', 'someday']) {
        expect(
          PlaceEventApplicationStatus.fromKey(raw),
          PlaceEventApplicationStatus.applied,
          reason: '$raw',
        );
      }
    });

    test('취소는 신청자 수에 들어가지 않는다', () {
      final list = [
        _app(guestId: 'g1'),
        _app(guestId: 'g2'),
        _app(guestId: 'g3', status: PlaceEventApplicationStatus.cancelled),
      ];
      expect(PlaceEventApplication.countApplied(list), 2);
      expect(list.where((a) => a.isApplied).length, 2);
    });
  });

  // ── 문서 모양 ───────────────────────────────────────────────────────────

  group('신청 문서', () {
    test('서버가 쓴 값이 그대로 되읽힌다', () {
      final read = PlaceEventApplication.fromMap('EV1_guest-1', {
        'eventId': 'EV1',
        'placeId': 'PL1',
        'placeCollection': 'events',
        'hostId': 'host-1',
        'guestId': 'guest-1',
        'status': 'applied',
        'eventTitle': '생일 이벤트',
        'placeName': '혼술바',
        'eventIsAlways': false,
        'eventEndAt': DateTime(2026, 9, 30).millisecondsSinceEpoch,
        'createdAt': DateTime(2026, 8, 30, 12).millisecondsSinceEpoch,
      });
      expect(read.eventId, 'EV1');
      expect(read.hostId, 'host-1');
      expect(read.guestId, 'guest-1');
      expect(read.eventTitle, '생일 이벤트');
      expect(read.placeName, '혼술바');
      expect(read.status, PlaceEventApplicationStatus.applied);
      expect(read.createdAt, DateTime(2026, 8, 30, 12));
      expect(read.eventEndAt, DateTime(2026, 9, 30));
    });

    test('필드가 빠진 문서도 터지지 않는다', () {
      final read = PlaceEventApplication.fromMap('X', const {});
      expect(read.eventId, '');
      expect(read.guestId, '');
      expect(read.status, PlaceEventApplicationStatus.applied);
      expect(read.createdAt, isNull);
      expect(read.scheduleLabel, '');
    });

    test('일정 한 줄은 상시 진행과 기간을 가른다', () {
      expect(_app(isAlways: true).scheduleLabel, '상시 진행');
      expect(_app(endAt: DateTime(2026, 9, 30)).scheduleLabel, '9.30까지');
    });

    // 앱이 쓰기용 헬퍼를 다시 만들면 "앱도 쓸 수 있다"는 착각이 돌아온다.
    // 쓰기 경로는 서버 콜러블 하나뿐이다.
    test('앱에는 쓰기용 헬퍼가 없다', () {
      // 주석에는 "예전에 이랬다"는 기록이 남아도 된다 — 실제 코드만 본다.
      final src = File('lib/models/place_event_application.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(src, isNot(contains('createMap')));
      expect(src, isNot(contains('toMap')));
    });
  });

  // ── 게스트 신청 내역의 상태 접기 ────────────────────────────────────────
  //
  // 종료일이 있는 이벤트는 **그 날 하루가 살아 있다**(PlacePromotion.statusAt과
  // 같은 경계). 하루 일찍 '완료'로 접히면 오늘 열리는 이벤트가 진행중 목록에서
  // 사라진다.

  group('내 신청 내역 상태', () {
    final now = DateTime(2026, 8, 30, 12);

    test('취소한 신청은 취소', () {
      expect(
        guestStatusOfPlaceEventApplication(
          _app(status: PlaceEventApplicationStatus.cancelled),
          now,
        ),
        GuestStatusFilter.cancelled,
      );
    });

    test('상시 진행은 끝나지 않는다', () {
      expect(
        guestStatusOfPlaceEventApplication(_app(isAlways: true), now),
        GuestStatusFilter.ongoing,
      );
    });

    test('종료일 당일은 아직 진행중이다', () {
      expect(
        guestStatusOfPlaceEventApplication(
          _app(endAt: DateTime(2026, 8, 30)),
          now,
        ),
        GuestStatusFilter.ongoing,
      );
    });

    test('종료일이 지나면 완료', () {
      expect(
        guestStatusOfPlaceEventApplication(
          _app(endAt: DateTime(2026, 8, 29)),
          now,
        ),
        GuestStatusFilter.done,
      );
    });

    test('미래 이벤트는 진행중', () {
      expect(
        guestStatusOfPlaceEventApplication(
          _app(endAt: DateTime(2026, 9, 30)),
          now,
        ),
        GuestStatusFilter.ongoing,
      );
    });
  });

  // ── 보안 (규칙·서버 드리프트) ───────────────────────────────────────────

  group('규칙', () {
    // 여기가 열리면 종료된 이벤트 차단이 통째로 무력해진다 — 변조된
    // 클라이언트가 신청 문서를 직접 쓰면 서버 판정을 건너뛴다.
    test('클라이언트 쓰기가 전면 차단되어 있다', () {
      expect(_rulesBlock, contains('allow write: if false'));
      expect(_rulesBlock, isNot(contains('allow create')));
      expect(_rulesBlock, isNot(contains('allow update')));
      expect(_rulesBlock, isNot(contains('allow delete')));
    });

    test('읽기는 본인 · 호스트 · 관리자뿐이다', () {
      expect(
        _rulesBlock,
        contains("resource.data.get('guestId', '') == uid()"),
      );
      expect(_rulesBlock, contains("resource.data.get('hostId', '') == uid()"));
      expect(_rulesBlock, contains('isAdmin()'));
      expect(_rulesBlock, isNot(contains('allow read: if true')));
    });
  });

  group('서버 판정', () {
    test('종료 여부를 서버가 직접 본다', () {
      expect(_server, contains('function isEndedAt('));
      expect(_server, contains('isEndedAt(eventData, nowMs)'));
    });

    test('신청 가능 판정이 여섯 가지를 모두 본다', () {
      final at = _server.indexOf('function evaluateApplyEligibility(');
      expect(at, greaterThan(-1));
      final body = _server.substring(at, _server.indexOf('\n}', at));
      expect(body, contains('eventData.hostId === uid')); // 내 이벤트가 아님
      expect(body, contains('isVisible !== true')); // 숨김
      expect(body, contains('acceptsApplications(')); // applyMode
      expect(body, contains('isEndedAt(')); // 종료
      expect(body, contains('not-found')); // 존재
    });

    test('본인확인 게이트를 거친다', () {
      expect(_server, contains('assertIdentityVerified(db, uid)'));
    });

    // 파생 필드를 클라이언트가 보내면 위조가 가능해진다. 서버는 eventId만
    // 받아야 한다.
    test('클라이언트에게서 받는 값은 eventId 하나뿐이다', () {
      final at = _server.indexOf('const applyToPlaceEvent =');
      final body = _server.substring(at, _server.indexOf('\n});', at));
      expect(body, contains("(request.data || {}).eventId"));
      for (final forgeable in ['hostId', 'placeId', 'eventTitle', 'guestId']) {
        expect(
          body,
          isNot(contains('request.data || {}).$forgeable')),
          reason: '$forgeable을 클라이언트에게서 받는다',
        );
      }
    });

    test('이벤트가 지워지면 신청도 함께 지워진다', () {
      expect(_server, contains('onDocumentDeleted('));
      expect(_server, contains(r'${EVENT_COLLECTION}/{promotionId}'));
      expect(_server, contains("const EVENT_COLLECTION = 'placePromotions'"));
      expect(_server, contains('deleteApplicationsForEvent('));
    });
  });
}
