import 'package:flutter/material.dart';

import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/screens/host_inbox_screen.dart';
import 'package:party_app/screens/my_visit_reservations_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/services/host_inbox_service.dart';

/// 알림 하나가 가리키는 화면을 고르는 **단 하나의 규칙**.
///
/// 같은 알림을 두 곳에서 누를 수 있기 때문에 규칙을 여기 모았다 — 알림함
/// (notifications_screen.dart)과 푸시 알림(push_notification_service.dart).
/// 두 곳이 각자 판단하면 "알림함에서 누르면 파티가 열리는데 푸시로 누르면
/// 아무 데도 안 가는" 어긋남이 생기고, 알림 종류가 늘 때마다 한쪽만 고치게 된다.
///
/// 서버가 푸시 data에 실어 보내는 키와 알림 문서의 필드 이름을 일부러 똑같이
/// 맞춰뒀다(functions/pushDispatch.js의 routeData). 그래서 어느 쪽에서 왔든
/// 같은 Map 하나로 이 함수를 부를 수 있다.
///
/// 갈 곳이 없으면 null — 부르는 쪽은 탭 자체를 막거나 알림함을 연다.
Widget? notificationTarget(Map<String, dynamic> data) {
  String read(String key) => (data[key] ?? '').toString();

  final type = read('type');

  // ── 채팅 ────────────────────────────────────────────────────────────
  // 알림함에는 쌓이지 않고 푸시로만 오는 종류다(메시지마다 알림 문서를 남기면
  // 알림함이 대화로 뒤덮인다). 방을 열려면 roomId 하나로는 부족해서 서버가
  // 이름과 대화 제목을 함께 실어 보낸다.
  if (type == 'chat') {
    final roomId = read('roomId');
    if (roomId.isEmpty) return null;
    return ChatRoomScreen(
      roomId: roomId,
      otherName: read('otherName').isEmpty ? '상대방' : read('otherName'),
      relatedTitle: read('relatedTitle'),
    );
  }

  // ── 호스트가 처리해야 하는 신청·예약 알림 ───────────────────────────
  //
  // 종류를 가리지 않고 **통합 신청자·예약자 관리**로 보낸다. 이 알림들은 예외
  // 없이 "누가 신청/예약했으니 처리해달라"는 말이고, 그 일을 하는 곳이 이제
  // 한 화면이기 때문이다. '처리 필요'로 열어 알림이 말한 그 건을 먼저 보여준다.
  //
  // 예전에는 방문예약만 업주 화면으로 갔고, 장소대여·숙박+파티 콤보 알림은
  // partyId가 없어 **아무 데도 가지 못했다**(아래 파티 분기로 떨어져 null).
  // 파티 신청 알림을 파티 상세로 보내는 것도 틀리다 — 호스트가 가야 할 곳은
  // 파티 소개가 아니라 신청자 목록이다.
  //
  // role만으로 판정하지 않는 이유: 호스트에게 가는 알림 중에도 처리할 일이
  // 아닌 것이 있다(최소 인원 미달 자동 취소 — 그건 파티 상세로 가야 한다).
  const hostInboxTypes = [
    'party_application_',
    'party_deposit_',
    'visit_reservation',
    'place_reservation',
    'package_booking',
  ];
  if (read('role') == 'host' && hostInboxTypes.any(type.startsWith)) {
    return const HostInboxScreen(initialFilter: HostInboxFilter.needsAction);
  }

  // ── 플레이스 방문 예약(이용자) ──────────────────────────────────────
  if (type.startsWith('visit_reservation')) {
    return const MyVisitReservationsScreen();
  }

  // ── 그 밖의 파티 알림 ───────────────────────────────────────────────
  final partyId = read('partyId');
  return partyId.isEmpty ? null : PartyDetailScreen(docId: partyId);
}
