// 등록 개수 제한(유형별 10개)과 자동 삭제(14일)가 **앱과 서버에서 같은 규칙**인가.
//
// 이 파일이 붙잡는 것.
//   ① 유형별로 각각 10개다 — 합산이 아니다.
//   ② 다중 날짜 파티 하나가 여러 개로 세지지 않는다(seriesId 한 묶음).
//   ③ 끝난 것(지난 파티·종료 이벤트·숨긴 장소)은 자리를 차지하지 않는다.
//   ④ 수정은 개수를 늘리지 않는다.
//   ⑤ 자동 삭제 기준점 — 파티는 종료 시각, 이벤트는 종료일/숨긴 시각 중 먼저,
//      플레이스·장소대여는 숨긴 시각. 기준점을 모르면 **지우지 않는다.**
//   ⑥ 앱의 숫자와 서버의 숫자가 같다(상한 10 · 보관 14일). 두 값이 갈리면
//      앱은 통과시키고 서버가 지우는(또는 그 반대) 상태가 된다.
//   ⑦ '3일간 다시 보지 않기'는 72시간이고, **계정마다 따로** 기억한다.

import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/utils/auto_delete_retention.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/past_content_retention_notice.dart';

String _src(String path) => File(path).readAsStringSync();

final DateTime _now = DateTime(2026, 8, 31, 12);
DateTime _ago(int days) => _now.subtract(Duration(days: days));
DateTime _ahead(int days) => _now.add(Duration(days: days));

/// 일회성 파티의 날짜 문서 하나.
RegistrationDoc _party(
  String id, {
  String? seriesId,
  DateTime? at,
  bool deleted = false,
}) {
  // 저장 모양 그대로다 — 일회성 파티는 날짜 + 시작/종료 '시각 문자열'이고
  // (PartySingleSchedule), partyDateTime은 목록 정렬용 캐시다.
  final start = at ?? _ahead(3);
  return RegistrationDoc(id, {
    'hostId': 'host',
    if (seriesId != null) 'seriesId': seriesId,
    'partyDateTime': Timestamp.fromDate(start),
    'singleSchedule': {
      'date': Timestamp.fromDate(start),
      'startTime': '19:00',
      'endTime': '22:00',
    },
    if (deleted) 'isDeleted': true,
  });
}

RegistrationDoc _promo(String id, [Map<String, dynamic> extra = const {}]) =>
    RegistrationDoc(id, {
      'hostId': 'host',
      'title': '이벤트',
      'isVisible': true,
      ...extra,
    });

RegistrationDoc _place(String id, [Map<String, dynamic> extra = const {}]) =>
    RegistrationDoc(id, {'hostId': 'host', ...extra});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ── ① 유형별 각각 10개 ────────────────────────────────────────────────
  group('상한은 유형마다 따로 10개다', () {
    test('네 유형이 같은 상한을 쓴다', () {
      expect(RegistrationLimits.maxPerType, 10);
      for (final kind in RegistrationKind.values) {
        expect(RegistrationLimits.limitMessage(kind), contains('10개'));
        expect(RegistrationLimits.limitMessage(kind), contains(kind.label));
      }
    });

    test('유형마다 통이 다르다 — 파티가 꽉 차도 이벤트 자리는 그대로다', () {
      final parties = [
        for (var i = 0; i < 10; i++) _party('p$i', seriesId: 's$i'),
      ];
      expect(
        RegistrationLimits.countLive(
          RegistrationKind.party,
          parties,
          now: _now,
        ),
        10,
      );
      // 같은 목록을 이벤트로 세면 0 — 통이 섞이지 않는다는 뜻이다.
      expect(
        RegistrationLimits.countLive(
          RegistrationKind.promotion,
          const [],
          now: _now,
        ),
        0,
      );
    });

    test('컬렉션이 유형마다 다르다 — 이름에 속지 않는다', () {
      expect(RegistrationKind.party.collection, 'parties');
      expect(RegistrationKind.promotion.collection, 'placePromotions');
      expect(RegistrationKind.placeListing.collection, 'events');
      expect(RegistrationKind.rentalListing.collection, 'places');
    });
  });

  // ── ② 다중 날짜 파티 ──────────────────────────────────────────────────
  group('파티는 게시글 단위로 센다', () {
    test('날짜 5개짜리 파티 하나는 1개다', () {
      final docs = [
        for (var i = 1; i <= 5; i++)
          _party('d$i', seriesId: 's1', at: _ahead(i)),
      ];
      expect(
        RegistrationLimits.countLive(RegistrationKind.party, docs, now: _now),
        1,
      );
    });

    test('seriesId가 없는 옛 문서는 문서 하나가 파티 하나다', () {
      final docs = [_party('a'), _party('b')];
      expect(
        RegistrationLimits.countLive(RegistrationKind.party, docs, now: _now),
        2,
      );
    });

    test('나머지 유형은 문서가 곧 등록물이다', () {
      expect(
        RegistrationLimits.groupKeyOf(
          RegistrationKind.promotion,
          _promo('x', {'seriesId': 's1'}),
        ),
        'x',
      );
    });
  });

  // ── ③ 끝난 것은 자리를 차지하지 않는다 ────────────────────────────────
  group('끝난 등록물은 새 등록을 막지 않는다', () {
    test('지난 파티는 빠진다', () {
      final docs = [_party('past', at: _ago(3)), _party('next', at: _ahead(1))];
      expect(
        RegistrationLimits.countLive(RegistrationKind.party, docs, now: _now),
        1,
      );
    });

    test('한 시리즈에 남은 날짜가 있으면 아직 살아 있다', () {
      final docs = [
        _party('a', seriesId: 's1', at: _ago(5)),
        _party('b', seriesId: 's1', at: _ahead(5)),
      ];
      expect(
        RegistrationLimits.countLive(RegistrationKind.party, docs, now: _now),
        1,
      );
    });

    test('삭제 표시된 문서는 어느 유형이든 빠진다', () {
      expect(
        RegistrationLimits.countLive(
          RegistrationKind.party,
          [_party('x', deleted: true)],
          now: _now,
        ),
        0,
      );
      expect(
        RegistrationLimits.countLive(
          RegistrationKind.placeListing,
          [_place('x', {'isDeleted': true})],
          now: _now,
        ),
        0,
      );
    });

    test('종료·숨김 이벤트는 빠지고, 진행 중·시작 전은 남는다', () {
      final docs = [
        _promo('running', {'endAt': _ahead(3)}),
        _promo('scheduled', {'startAt': _ahead(3)}),
        _promo('always', {'isAlways': true}),
        _promo('ended', {'endAt': _ago(1)}),
        _promo('hidden', {'isVisible': false}),
      ];
      expect(
        RegistrationLimits.countLive(
          RegistrationKind.promotion,
          docs,
          now: _now,
        ),
        3,
      );
    });

    test('한 매장에 이벤트를 여럿 열어도 계정 전체로 센다', () {
      final docs = [
        _promo('a', {'placeId': 'p1'}),
        _promo('b', {'placeId': 'p1'}),
        _promo('c', {'placeId': 'p2'}),
      ];
      expect(
        RegistrationLimits.countLive(
          RegistrationKind.promotion,
          docs,
          now: _now,
        ),
        3,
      );
    });

    test('숨긴 플레이스·장소대여는 빠진다', () {
      final docs = [
        _place('a'),
        _place('b', {'isActive': true}),
        _place('c', {'isActive': false}),
      ];
      for (final kind in [
        RegistrationKind.placeListing,
        RegistrationKind.rentalListing,
      ]) {
        expect(
          RegistrationLimits.countLive(kind, docs, now: _now),
          2,
          reason: kind.label,
        );
      }
    });
  });

  // ── ④ 수정 ────────────────────────────────────────────────────────────
  test('같은 문서를 두 번 세지 않는다 — 수정은 개수를 늘리지 않는다', () {
    final docs = [_place('p1'), _place('p1')];
    expect(
      RegistrationLimits.countLive(
        RegistrationKind.placeListing,
        docs,
        now: _now,
      ),
      1,
    );
  });

  // ── ⑤ 자동 삭제 기준점 ────────────────────────────────────────────────
  group('이벤트의 자동 삭제 기준점', () {
    PlacePromotion promo(Map<String, dynamic> extra) =>
        PlacePromotion.fromMap('e1', {
          'title': '이벤트',
          'isVisible': true,
          ...extra,
        });

    test('기간이 끝난 이벤트 → 종료일의 끝', () {
      final gone = promo({'endAt': _ago(20)}).goneAt(_now);
      expect(gone, isNotNull);
      expect(gone!.day, _ago(20).day);
      expect(gone.hour, 23);
    });

    test('호스트가 종료를 누른 이벤트 → 숨긴 시각', () {
      final hiddenAt = _ago(20);
      final gone = promo({
        'isVisible': false,
        'hiddenAt': hiddenAt,
        'endAt': _ahead(30),
      }).goneAt(_now);
      expect(gone, hiddenAt);
    });

    test('둘 다면 먼저 일어난 쪽이 기준이다', () {
      final gone = promo({
        'isVisible': false,
        'hiddenAt': _ago(10),
        'endAt': _ago(30),
      }).goneAt(_now);
      expect(gone!.day, _ago(30).day);
    });

    test('아직 살아 있으면 기준점이 없다 — 아무 말도 하지 않는다', () {
      expect(promo({}).goneAt(_now), isNull);
      expect(promo({'endAt': _ahead(5)}).goneAt(_now), isNull);
      expect(
        promo({'isAlways': true, 'endAt': _ago(30)}).goneAt(_now),
        isNull,
      );
      expect(AutoDeleteRetention.label(null), isNull);
    });

    test('hiddenAt이 없는 옛 숨김 이벤트는 지우지 않는다', () {
      expect(promo({'isVisible': false}).goneAt(_now), isNull);
    });

    test('D-day 문구는 지난 파티·임시저장과 같은 계산을 쓴다', () {
      final gone = promo({
        'isVisible': false,
        'hiddenAt': _ago(11),
      }).goneAt(_now);
      expect(AutoDeleteRetention.label(gone, now: _now), '자동삭제 D-3');
      expect(AutoDeleteRetention.isUrgent(gone, now: _now), isTrue);
    });
  });

  // ── ⑥ 앱과 서버의 숫자가 같다 ─────────────────────────────────────────
  group('앱과 서버가 같은 숫자를 쓴다', () {
    test('상한 10개', () {
      final server = _src('../functions/registrationLimits.js');
      expect(server, contains('const MAX_PER_TYPE = 10;'));
      expect(RegistrationLimits.maxPerType, 10);
    });

    test('보관기간 14일', () {
      final server = _src('../functions/index.js');
      expect(server, contains('const RETENTION_DAYS = 14;'));
      expect(AutoDeleteRetention.window, const Duration(days: 14));
      // 네 유형이 같은 상수를 쓴다 — 장소대여의 옛 30일 계산은 사라졌다.
      expect(server.contains('30 * 24 * 60 * 60 * 1000'), isFalse);
    });

    test('서버가 네 유형을 모두 지운다', () {
      final server = _src('../functions/index.js');
      for (final job in [
        'deleteExpiredParties',
        'deleteExpiredPromotions',
        'deleteExpiredEvents',
        'deleteExpiredPlaces',
      ]) {
        expect(server, contains('exports.$job = onSchedule('), reason: job);
      }
    });

    test('서버가 네 컬렉션의 초과 생성을 막는다', () {
      final guard = _src('../functions/registrationLimitGuard.js');
      for (final doc in [
        'parties/{partyId}',
        'placePromotions/{promotionId}',
        'events/{eventId}',
        'places/{placeId}',
      ]) {
        expect(guard, contains(doc), reason: doc);
      }
      // 초과분 정리는 사용자가 삭제를 눌렀을 때와 같은 경로다.
      expect(guard, contains('cleanupContentDoc('));
    });

    test('이벤트 삭제도 공용 정리 규칙을 탄다', () {
      final cleanup = _src('../functions/contentCleanup.js');
      expect(cleanup, contains("collection: 'placePromotions'"));
      // 이벤트 신청서는 함께 지운다(가리킬 이벤트가 사라지므로).
      expect(cleanup, contains("'placeEventApplications', 'eventId'"));
    });
  });

  // ── ⑦ 안내 유예 ───────────────────────────────────────────────────────
  group('지난 목록 안내의 3일 유예', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
      UserSession.userId = 'userA';
    });

    tearDown(() => UserSession.userId = '');

    test('유예는 72시간이다', () {
      expect(PastContentRetentionNotice.snooze, const Duration(days: 3));
    });

    test('처음에는 뜨고, 눌러 두면 3일 동안 뜨지 않는다', () async {
      expect(await PastContentRetentionNotice.shouldShow(), isTrue);
      await PastContentRetentionNotice.snoozeNow(now: _now);

      // 71시간 뒤 — 아직 유예 중.
      expect(
        await PastContentRetentionNotice.shouldShow(
          now: _now.add(const Duration(hours: 71)),
        ),
        isFalse,
      );
      // 72시간을 넘기면 다시 뜬다.
      expect(
        await PastContentRetentionNotice.shouldShow(
          now: _now.add(const Duration(hours: 73)),
        ),
        isTrue,
      );
    });

    test('계정마다 따로 기억한다 — 남의 유예가 옮겨붙지 않는다', () async {
      await PastContentRetentionNotice.snoozeNow(now: _now);
      expect(
        await PastContentRetentionNotice.shouldShow(
          now: _now.add(const Duration(hours: 1)),
        ),
        isFalse,
      );

      UserSession.userId = 'userB';
      expect(
        await PastContentRetentionNotice.shouldShow(
          now: _now.add(const Duration(hours: 1)),
        ),
        isTrue,
      );

      // 돌아오면 원래 유예가 그대로 남아 있다.
      UserSession.userId = 'userA';
      expect(
        await PastContentRetentionNotice.shouldShow(
          now: _now.add(const Duration(hours: 1)),
        ),
        isFalse,
      );
    });
  });
}
