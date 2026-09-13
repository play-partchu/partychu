// 통합 신청자·예약자 관리 — **판정과 이동**만 확인한다.
//
// 화면 그리기는 여기서 보지 않는다. 이 기능이 실제로 깨지는 자리는 둘이다.
//   1. 필터/배지 판정 — 취소·거절이 '처리 필요'에 새면 호스트에게 "3건 남았다"고
//      떠 있는데 들어가면 할 일이 없다. 반대로 승인 대기가 새면 신청자가 며칠씩
//      답을 못 받는다.
//   2. 알림 라우팅 — 알림을 눌렀는데 아무 데도 안 가거나(장소대여·콤보가 실제로
//      그랬다) 엉뚱한 화면이 열리면 알림을 붙인 의미가 없다.

import 'package:flutter_test/flutter_test.dart';

import 'package:party_app/screens/host_inbox_screen.dart';
import 'package:party_app/screens/my_visit_reservations_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/services/host_inbox_service.dart';
import 'package:party_app/utils/applicant_identity.dart';
import 'package:party_app/utils/notification_route.dart';

HostInboxEntry entry(HostInboxState state) => HostInboxEntry(
  kind: HostInboxKind.party,
  id: 'a',
  contentTitle: '파티',
  personLabel: '냥냥이',
  statusLabel: '승인 대기',
  state: state,
);

void main() {
  group('필터는 세 상태를 겹치지 않게 나눈다', () {
    test('전체는 무엇이든 담고, 나머지 셋은 자기 상태만 담는다', () {
      for (final state in HostInboxState.values) {
        final e = entry(state);
        final matched = HostInboxFilter.values
            .where((f) => f.matches(e))
            .toList();
        // '전체' + 자기 상태 필터 = 정확히 2개. 한 건이 두 묶음에 동시에
        // 나타나면 필터 숫자의 합이 전체보다 커진다.
        expect(matched.length, 2, reason: '$state → $matched');
        expect(matched.contains(HostInboxFilter.all), isTrue);
      }
    });

    test('미처리는 처리 필요 상태 하나뿐이다', () {
      expect(entry(HostInboxState.needsAction).unhandled, isTrue);
      expect(entry(HostInboxState.confirmed).unhandled, isFalse);
      // 취소·거절은 처리가 끝난 것이라 배지 숫자에서 빠진다(요구사항).
      expect(entry(HostInboxState.closed).unhandled, isFalse);
    });

    test('미처리 건수는 처리 필요 필터의 개수와 같다', () {
      const snapshot = HostInboxSnapshot(entries: []);
      expect(snapshot.unhandledCount, 0);

      final mixed = HostInboxSnapshot(
        entries: [
          entry(HostInboxState.needsAction),
          entry(HostInboxState.needsAction),
          entry(HostInboxState.confirmed),
          entry(HostInboxState.closed),
        ],
      );
      expect(mixed.unhandledCount, 2);
      expect(
        mixed.entries.where(HostInboxFilter.needsAction.matches).length,
        mixed.unhandledCount,
      );
    });
  });

  group('알림을 누르면 갈 곳', () {
    Map<String, dynamic> data(String type, String role) => {
      'type': type,
      'role': role,
      'partyId': 'p1',
    };

    test('호스트의 신청·예약 알림은 통합 관리 화면의 처리 필요로 간다', () {
      const hostTypes = [
        // 이번에 새로 생긴 파티 신청 알림 — 승인제 pending이 가장 중요하다.
        'party_application_pending',
        'party_application_new',
        'party_deposit_sent',
        'visit_reservation_requested',
        'visit_reservation_deposit_sent',
        // 예전에는 partyId가 없어 **아무 데도 못 가던** 두 종류.
        'place_reservation_requested',
        'package_booking_requested',
      ];
      for (final type in hostTypes) {
        final target = notificationTarget(data(type, 'host'));
        expect(target, isA<HostInboxScreen>(), reason: type);
        expect(
          (target as HostInboxScreen).initialFilter,
          HostInboxFilter.needsAction,
          reason: type,
        );
      }
    });

    test('호스트 알림이라도 처리할 일이 아니면 파티 상세로 간다', () {
      // 최소 인원 미달 자동 취소 — 호스트가 승인할 것이 없는 통보다.
      final target = notificationTarget(
        data('partyAutoCancelledMinCapacity', 'host'),
      );
      expect(target, isA<PartyDetailScreen>());
    });

    test('같은 종류라도 이용자에게 간 알림은 내 예약으로 간다', () {
      expect(
        notificationTarget(data('visit_reservation_approved', 'guest')),
        isA<MyVisitReservationsScreen>(),
      );
    });

    test('파티 알림은 예전 그대로 파티 상세로 간다', () {
      expect(
        notificationTarget(data('party_open', 'guest')),
        isA<PartyDetailScreen>(),
      );
    });

    test('갈 곳이 없으면 null이다', () {
      expect(notificationTarget({'type': 'unknown', 'role': 'guest'}), isNull);
    });
  });

  group('신청자 이름은 uid로 물러서지 않는다', () {
    test('닉네임(실명) 한 덩어리로 그린다', () {
      const id = ApplicantIdentity(
        state: ApplicantIdentityState.ok,
        nickname: '냥냥이',
        name: '홍길동',
      );
      expect(id.personLabel, '냥냥이(홍길동)');
    });

    test('닉네임만 있으면 닉네임만', () {
      const id = ApplicantIdentity(
        state: ApplicantIdentityState.ok,
        nickname: '냥냥이',
      );
      expect(id.personLabel, '냥냥이');
    });

    test('탈퇴·미확인은 정해진 문구로 — uid가 새면 안 된다', () {
      expect(ApplicantIdentity.withdrawn.personLabel, '탈퇴한 회원');
      expect(ApplicantIdentity.unknown.personLabel, '정보 없음');
      // 신원은 왔는데 닉네임도 실명도 비어 있는 경우.
      expect(
        const ApplicantIdentity(state: ApplicantIdentityState.ok).personLabel,
        '정보 없음',
      );
    });
  });
}
