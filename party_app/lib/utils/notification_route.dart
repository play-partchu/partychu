import 'package:flutter/material.dart';

import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/screens/my_visit_reservations_screen.dart';
import 'package:party_app/screens/party_detail_screen.dart';
import 'package:party_app/screens/visit_reservation_manage_screen.dart';

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

  // ── 플레이스 방문 예약 ──────────────────────────────────────────────
  // 업주에게 간 알림('host')은 승인 화면으로, 이용자 알림은 내 예약으로.
  if (type.startsWith('visit_reservation')) {
    return read('role') == 'host'
        ? const VisitReservationManageScreen()
        : const MyVisitReservationsScreen();
  }

  // ── 그 밖의 파티 알림 ───────────────────────────────────────────────
  final partyId = read('partyId');
  return partyId.isEmpty ? null : PartyDetailScreen(docId: partyId);
}
