import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:party_app/models/place_rental_reservation.dart';
import 'package:party_app/models/place_visit_reservation.dart';
import 'package:party_app/models/shop_order.dart';
import 'package:party_app/screens/chat_list_screen.dart';
import 'package:party_app/screens/chat_room_screen.dart';
import 'package:party_app/screens/my_guest_hub_screen.dart'
    show
        GuestStatusFilter,
        guestStatusOfApplication,
        guestStatusOfOrder,
        guestStatusOfRental,
        guestStatusOfVisit;
import 'package:party_app/services/chat_service.dart';
import 'package:party_app/services/payment_service.dart';
import 'package:party_app/services/place_product_service.dart';
import 'package:party_app/services/place_rental_reservation_service.dart';
import 'package:party_app/services/place_visit_reservation_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/auth_rebuilder.dart';
import 'package:party_app/widgets/web_frame.dart';

// ─────────────────────────────────────────────────────────────────────────────
// 하단 '채팅' 탭의 첫 화면 — **대화 목록이 아니라 "지금 이용 중인 것" 목록**이다.
//
// 예전에는 이 탭이 곧바로 ChatListScreen(주고받은 대화 목록)이었다. 그런데
// 대화는 상세 화면에서 '채팅하기'를 눌러 방이 한 번 만들어진 뒤에야 생긴다 —
// 파티를 신청하거나 예약만 한 사람에게는 방이 없어서 "아직 채팅이 없습니다"만
// 떴고, 호스트에게 말을 걸 방법이 이 탭 안에 없었다.
//
// 그래서 순서를 뒤집었다. 진행 중인 신청·예약을 먼저 보여주고, 하나를 고르면
// 그 호스트와의 방을 열거나(없으면 만들어) 바로 대화로 들어간다. 이미 나눈
// 대화는 우상단 '대화 목록'으로 그대로 갈 수 있다.
//
// 여기 담는 것: 파티 신청 · 플레이스 방문예약 · 장소대여/패키지 예약 ·
//               플레이스·장소 이용권 · 파티샵 주문.
// 상태 판정은 **마이 > 게스트 허브와 똑같은 함수**를 그대로 쓴다
// (guestStatusOf*). 새 규칙을 만들지 않으므로 두 화면의 '진행중'이 어긋날 수
// 없고, 취소·완료된 건은 여기 오지 않는다.
// ─────────────────────────────────────────────────────────────────────────────

const Color _kAccent = Color(0xFFFF6FA0);

/// 채팅을 걸 수 있는 대상 1건.
///
/// [relatedType]·[relatedId]는 **채팅방의 열쇠**다. 예약 건마다가 아니라
/// "어느 게시글의 호스트인가"로 잡는다 — 같은 장소를 두 번 예약해도 대화는
/// 한 방에 이어지고, 상세 화면의 '채팅하기'로 이미 만든 방과도 같은 방을
/// 가리킨다(place_detail_screen·party_shop_detail_screen과 같은 값).
class ChatTarget {
  const ChatTarget({
    required this.section,
    required this.relatedType,
    required this.relatedId,
    required this.hostId,
    required this.title,
    required this.subtitle,
    required this.sourceCollection,
    required this.sortAt,
  });

  /// 목록에서 묶이는 구획 이름('파티' 등).
  final String section;

  /// 'party' | 'place' | 'shop'
  final String relatedType;

  /// 파티/플레이스/샵 문서 id.
  final String relatedId;

  final String hostId;
  final String title;
  final String subtitle;

  /// 호스트 이름을 되짚어 읽을 원본 게시글 컬렉션.
  final String sourceCollection;

  /// 정렬 기준(최근 것부터). 알 수 없으면 null.
  final DateTime? sortAt;

  /// 같은 방을 가리키는 항목이 여러 건 있을 수 있다(같은 장소 2회 예약 등).
  /// 목록에서는 한 줄로만 보여준다.
  String get dedupeKey => '${relatedType}_$relatedId';
}

class ChatTargetListScreen extends StatefulWidget {
  const ChatTargetListScreen({super.key});

  @override
  State<ChatTargetListScreen> createState() => _ChatTargetListScreenState();
}

class _ChatTargetListScreenState extends State<ChatTargetListScreen> {
  // 도메인마다 스트림이 따로다. StreamBuilder를 여섯 겹 중첩하면 한 곳이
  // 늦어질 때 화면 전체가 멈추므로, 각자 도착하는 대로 자기 구획만 채운다.
  final Map<String, List<ChatTarget>> _bySource = {};
  final Map<String, Object> _errors = {};
  final Set<String> _loaded = {};
  final List<StreamSubscription> _subs = [];

  /// 파티 제목은 신청 문서에 없어서 파티 문서에서 따로 읽는다.
  final Map<String, Map<String, dynamic>> _partyDocs = {};

  /// 이미 열려 있는 대화방 — **게스트로 연 방과 호스트로 받은 방을 모두** 담는다.
  ///
  /// 이 화면이 모으던 여섯 갈래(신청·방문예약·장소대여·패키지·이용권·주문)는
  /// 전부 **내가 게스트인 기록**이다. 그래서 호스트로 로그인하면 여기는 언제나
  /// 비어 있었고, 게스트가 보낸 문의가 chatRooms에 정상으로 들어와 있어도
  /// 호스트에게는 그것이 보이는 자리가 이 탭 안에 없었다 — 빈 화면 문구가
  /// "진행 중인 신청·예약이 없어요"였던 탓에 오히려 문의가 오지 않은 것처럼
  /// 읽혔다. 대화 자체를 목록 맨 위로 올려 그 사각지대를 없앤다.
  ///
  /// 방 목록은 participants array-contains로만 걸러서 **역할과 무관하게**
  /// 들어온다(ChatService.roomsStream) — 파티·플레이스·장소대여·파티샵·
  /// 파티크루가 같은 chatRooms를 쓰므로 한 번에 전부 덮인다.
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _rooms = const [];
  bool _roomsLoaded = false;

  /// 지금 방을 여는 중인 항목 — 연타로 방이 두 번 열리지 않게 한다.
  String? _opening;

  static const _sources = [
    'party',
    'visit',
    'rental',
    'package',
    'voucher',
    'shop',
  ];

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }

  void _put(String source, List<ChatTarget> items) {
    if (!mounted) return;
    setState(() {
      _bySource[source] = items;
      _loaded.add(source);
      _errors.remove(source);
    });
  }

  void _fail(String source, Object e, StackTrace? st) {
    logFirestoreStreamError('ChatTargets.$source', e, st);
    if (!mounted) return;
    setState(() {
      _errors[source] = e;
      _loaded.add(source);
    });
  }

  void _subscribe() {
    final uid = UserSession.userId;
    if (uid.isEmpty) return;
    final now = DateTime.now();

    // ── 0) 이미 열려 있는 대화 ──────────────────────────────────────
    // 아래 여섯 갈래보다 먼저 온다 — 여기에만 호스트가 받은 문의가 있다.
    _subs.add(
      ChatService.roomsStream(uid).listen(
        (docs) {
          if (!mounted) return;
          setState(() {
            _rooms = docs;
            _roomsLoaded = true;
            _errors.remove('rooms');
          });
        },
        onError: (e, st) {
          logFirestoreStreamError('ChatTargets.rooms', e, st);
          if (!mounted) return;
          setState(() {
            _errors['rooms'] = e;
            _roomsLoaded = true;
          });
        },
      ),
    );

    // ── 1) 파티 신청 ────────────────────────────────────────────────
    _subs.add(
      FirebaseFirestore.instance
          .collectionGroup('applications')
          .where('uid', isEqualTo: uid)
          .snapshots()
          .listen((snap) async {
            final live = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
            for (final doc in snap.docs) {
              final d = doc.data();
              // 패키지로 만들어진 신청은 공간대여 예약 카드 쪽에서 한 건으로
              // 나오므로 여기서 뺀다(게스트 허브와 같은 규칙).
              if (d['bundleBookingId'] != null) continue;
              if (guestStatusOfApplication(d, now) !=
                  GuestStatusFilter.ongoing) {
                continue;
              }
              live.add(doc);
            }

            // 제목·호스트 이름은 파티 문서에 있다 — 아직 안 읽은 것만 읽는다.
            final missing = live
                .map((d) => d.data()['partyId'] as String? ?? '')
                .where((id) => id.isNotEmpty && !_partyDocs.containsKey(id))
                .toSet();
            for (final id in missing) {
              try {
                final p = await FirebaseFirestore.instance
                    .collection('parties')
                    .doc(id)
                    .get();
                if (p.exists) _partyDocs[id] = p.data()!;
              } catch (_) {
                // 파티 문서를 못 읽어도 목록에서 빼지 않는다 — 제목만 기본값.
              }
            }

            _put('party', [
              for (final doc in live)
                () {
                  final d = doc.data();
                  final partyId = d['partyId'] as String? ?? '';
                  final party = _partyDocs[partyId];
                  final ts = d['partyDateTime'];
                  return ChatTarget(
                    section: '파티',
                    relatedType: 'party',
                    relatedId: partyId,
                    hostId:
                        d['hostId'] as String? ??
                        party?['hostId'] as String? ??
                        '',
                    title:
                        (party?['title'] as String?)?.trim().isNotEmpty == true
                        ? party!['title'] as String
                        : '파티',
                    subtitle: _partySubtitle(d),
                    sourceCollection: 'parties',
                    sortAt: ts is Timestamp ? ts.toDate() : null,
                  );
                }(),
            ]);
          }, onError: (e, st) => _fail('party', e, st)),
    );

    // ── 2) 플레이스 방문 예약 ───────────────────────────────────────
    _subs.add(
      PlaceVisitReservationService.myReservations(uid).snapshots().listen(
        (snap) => _put('visit', [
          for (final r in snap.docs.map(PlaceVisitReservation.fromDoc))
            if (guestStatusOfVisit(r, now) == GuestStatusFilter.ongoing)
              ChatTarget(
                section: '플레이스 예약',
                relatedType: 'place',
                relatedId: r.placeId,
                hostId: r.hostId,
                title: r.placeName,
                subtitle: '방문 예약 · ${_dateLabel(r.visitAt)}',
                sourceCollection: 'events',
                sortAt: r.visitAt,
              ),
        ]),
        onError: (e, st) => _fail('visit', e, st),
      ),
    );

    // ── 3) 장소대여 예약 ────────────────────────────────────────────
    _subs.add(
      PlaceRentalReservationService.myReservations(uid).snapshots().listen(
        (snap) => _put('rental', [
          for (final r in snap.docs.map(PlaceRentalReservation.fromDoc))
            if (guestStatusOfRental(r, now) == GuestStatusFilter.ongoing)
              _rentalTarget(r, '장소대여 예약'),
        ]),
        onError: (e, st) => _fail('rental', e, st),
      ),
    );

    // ── 4) 숙박·파티 패키지 예약 ────────────────────────────────────
    _subs.add(
      FirebaseFirestore.instance
          .collection(RentalSource.package.collection)
          .where('requesterId', isEqualTo: uid)
          .snapshots()
          .listen(
            (snap) => _put('package', [
              for (final r in snap.docs.map(
                (d) => PlaceRentalReservation.fromDoc(
                  d,
                  source: RentalSource.package,
                ),
              ))
                if (guestStatusOfRental(r, now) == GuestStatusFilter.ongoing)
                  _rentalTarget(r, '패키지 예약'),
            ]),
            onError: (e, st) => _fail('package', e, st),
          ),
    );

    // ── 5) 이용권(플레이스·장소에서 산 것) ──────────────────────────
    _subs.add(
      PlaceProductService.watchMyOrders().listen(
        (orders) => _put('voucher', [
          for (final o in orders)
            if (guestStatusOfOrder(o) == GuestStatusFilter.ongoing)
              ChatTarget(
                section: '이용권',
                relatedType: 'place',
                relatedId: o.placeId,
                hostId: o.hostId,
                title: o.placeName,
                subtitle: '이용권 · ${o.productName}',
                sourceCollection: o.placeCollection,
                sortAt: o.createdAt,
              ),
        ]),
        onError: (e, st) => _fail('voucher', e, st),
      ),
    );

    // ── 6) 파티샵 주문 ──────────────────────────────────────────────
    _subs.add(
      PaymentService.myPurchases(uid).snapshots().listen(
        (snap) => _put('shop', [
          for (final o in snap.docs.map(ShopOrder.fromDoc))
            if (o.status.isLive)
              ChatTarget(
                section: '파티샵 주문',
                relatedType: 'shop',
                relatedId: o.shopId,
                hostId: o.sellerId,
                title: o.shopName,
                subtitle: '${o.productName} · ${o.status.label}',
                sourceCollection: 'partyShops',
                sortAt: o.createdAt,
              ),
        ]),
        onError: (e, st) => _fail('shop', e, st),
      ),
    );
  }

  ChatTarget _rentalTarget(PlaceRentalReservation r, String section) =>
      ChatTarget(
        section: section,
        relatedType: 'place',
        relatedId: r.placeId,
        hostId: r.hostId,
        title: r.placeName,
        subtitle: [
          if (r.roomName != null && r.roomName!.isNotEmpty) r.roomName!,
          if (r.partyTitle != null && r.partyTitle!.isNotEmpty) r.partyTitle!,
          if (r.useStartAt != null) _dateLabel(r.useStartAt!),
        ].join(' · '),
        sourceCollection: 'places',
        sortAt: r.useStartAt,
      );

  static String _partySubtitle(Map<String, dynamic> d) {
    final ts = d['partyDateTime'];
    if (ts is Timestamp) return '파티 신청 · ${_dateLabel(ts.toDate())}';
    return '파티 신청';
  }

  /// 대화 줄의 시각 — 오늘은 시각, 이번 주는 요일, 그 밖은 날짜.
  static String _timeLabel(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0 && now.day == dt.day) {
      final h = dt.hour;
      final p = h < 12 ? '오전' : '오후';
      final hh = h % 12 == 0 ? 12 : h % 12;
      return '$p $hh:${dt.minute.toString().padLeft(2, '0')}';
    }
    if (diff.inDays < 7) {
      const w = ['월', '화', '수', '목', '금', '토', '일'];
      return '${w[dt.weekday - 1]}요일';
    }
    return '${dt.month}/${dt.day}';
  }

  static String _dateLabel(DateTime dt) {
    const w = ['월', '화', '수', '목', '금', '토', '일'];
    final h = dt.hour;
    final p = h < 12 ? '오전' : '오후';
    final hh = h % 12 == 0 ? 12 : h % 12;
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.month}월 ${dt.day}일(${w[dt.weekday - 1]}) $p $hh:$mm';
  }

  // ── 방 열기 ────────────────────────────────────────────────────────
  Future<void> _openChat(ChatTarget t) async {
    if (_opening != null) return;
    if (t.hostId.isEmpty) {
      _snack('호스트 정보를 찾을 수 없어요.');
      return;
    }
    if (t.hostId == UserSession.userId) {
      _snack('내가 호스트인 게시글이에요. 신청자 관리에서 대화할 수 있어요.');
      return;
    }

    setState(() => _opening = t.dedupeKey);
    try {
      // 호스트 이름은 원본 게시글에서 읽는다 — 사용자 문서는 본인만 읽을 수
      // 있어서(users 규칙) 상대 이름을 거기서 가져올 수 없다.
      var hostName = '호스트';
      try {
        final src = await FirebaseFirestore.instance
            .collection(t.sourceCollection)
            .doc(t.relatedId)
            .get();
        final n = (src.data()?['hostName'] as String?)?.trim();
        if (n != null && n.isNotEmpty) hostName = n;
      } catch (_) {
        // 이름을 못 읽어도 대화는 열 수 있어야 한다.
      }

      final roomId = await ChatService.getOrCreateRoom(
        hostId: t.hostId,
        hostName: hostName,
        guestId: UserSession.userId,
        guestName: UserSession.displayName,
        relatedType: t.relatedType,
        relatedId: t.relatedId,
        relatedTitle: t.title,
      );
      if (!mounted) return;
      await Navigator.push(
        context,
        webFramedRoute(
          (_) => ChatRoomScreen(
            roomId: roomId,
            otherName: hostName,
            relatedTitle: t.title,
          ),
        ),
      );
    } catch (e, st) {
      logFirestoreStreamError('ChatTargets.openChat', e, st);
      if (mounted) _snack('채팅방을 열지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _opening = null);
    }
  }

  void _snack(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), behavior: SnackBarBehavior.floating),
  );

  // ── 화면 ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) => AuthRebuilder(builder: _build);

  Widget _build(BuildContext context) {
    final uid = UserSession.userId;
    if (uid.isEmpty) {
      return const Scaffold(
        backgroundColor: Color(0xFFFFF4F8),
        body: Center(
          child: Text(
            '로그인이 필요합니다.',
            style: TextStyle(fontSize: 15, color: Colors.black45),
          ),
        ),
      );
    }

    // 이미 대화가 열린 게시글은 위쪽 '주고받은 대화' 줄이 **같은 방**을
    // 가리킨다 — 같은 것을 두 번 보여주지 않는다. 내가 게스트로 들어가 있는
    // 방만 센다(호스트로 받은 방은 애초에 신청·예약 목록에 오지 않는다).
    final openedAsGuest = <String>{};
    for (final doc in _rooms) {
      final d = doc.data();
      if (d['guestId'] != uid) continue;
      openedAsGuest.add('${d['relatedType'] ?? ''}_${d['relatedId'] ?? ''}');
    }

    // 같은 게시글을 가리키는 항목은 한 줄로 접는다 — 방이 하나이기 때문이다.
    final seen = <String>{};
    final items = <ChatTarget>[];
    for (final source in _sources) {
      for (final t in _bySource[source] ?? const <ChatTarget>[]) {
        if (t.relatedId.isEmpty) continue;
        if (openedAsGuest.contains(t.dedupeKey)) continue;
        if (!seen.add(t.dedupeKey)) continue;
        items.add(t);
      }
    }
    items.sort((a, b) {
      if (a.sortAt == null && b.sortAt == null) return 0;
      if (a.sortAt == null) return 1;
      if (b.sortAt == null) return -1;
      return a.sortAt!.compareTo(b.sortAt!);
    });

    final stillLoading = _loaded.length < _sources.length || !_roomsLoaded;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text(
          '채팅',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontSize: 18,
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: false,
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        actions: [
          // 이미 나눈 대화는 여기로 — 진행이 끝난 건의 대화도 그대로 남아 있고,
          // 이 화면에는 진행 중인 것만 오기 때문에 반드시 길을 열어둬야 한다.
          TextButton.icon(
            onPressed: () => Navigator.push(
              context,
              webFramedRoute((_) => const ChatListScreen()),
            ),
            icon: const Icon(Icons.forum_outlined, size: 18),
            label: const Text('대화 목록'),
            style: TextButton.styleFrom(foregroundColor: _kAccent),
          ),
        ],
      ),
      body: (_rooms.isEmpty && items.isEmpty && stillLoading)
          ? const Center(child: CircularProgressIndicator(color: _kAccent))
          : ListView(
              padding: const EdgeInsets.only(bottom: 24),
              children: [
                if (_errors.isNotEmpty) _errorBanner(),
                if (_rooms.isEmpty && items.isEmpty)
                  _emptyState()
                else ...[
                  if (_rooms.isNotEmpty) ...[
                    const _SectionTitle('주고받은 대화'),
                    ..._rooms.map((doc) => _roomTile(doc, uid)),
                  ],
                  if (items.isNotEmpty) ...[
                    const _SectionTitle('진행 중인 신청·예약'),
                    ...items.map(_tile),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: Text(
                        '누르면 해당 호스트와 바로 대화할 수 있어요.',
                        style: TextStyle(fontSize: 12, color: Colors.black38),
                      ),
                    ),
                  ],
                ],
              ],
            ),
    );
  }

  /// 이미 열려 있는 대화 한 줄.
  ///
  /// 내가 호스트인 방에는 '문의 받음' 표시를 단다 — 한 목록에 내가 건 대화와
  /// 내게 온 문의가 섞이므로, 답해야 할 쪽이 어느 것인지 한눈에 보여야 한다.
  Widget _roomTile(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
    String uid,
  ) {
    final d = doc.data();
    final iAmHost = (d['hostId'] as String?) == uid;
    final names = (d['participantNames'] as Map<String, dynamic>?) ?? const {};
    final otherId = iAmHost
        ? (d['guestId'] as String? ?? '')
        : (d['hostId'] as String? ?? '');
    final otherName = (names[otherId] as String?)?.trim().isNotEmpty == true
        ? names[otherId] as String
        : '상대방';
    final relatedTitle = (d['relatedTitle'] as String? ?? '').trim();
    final last = (d['lastMessage'] as String? ?? '').trim();
    final lastAt = d['lastMessageAt'] as Timestamp?;
    final unread = ChatService.isRoomUnread(d, uid);
    final section = switch (d['relatedType'] as String? ?? '') {
      'party' => '파티',
      'shop' => '파티샵',
      'place' => '파티장소',
      'crew' => '파티크루',
      _ => '채팅',
    };

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: () => Navigator.push(
          context,
          webFramedRoute(
            (_) => ChatRoomScreen(
              roomId: doc.id,
              otherName: otherName,
              relatedTitle: relatedTitle,
            ),
          ),
        ),
        leading: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFFFFE0EE),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              otherName.characters.first,
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _kAccent,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            _Badge(section),
            if (iAmHost) ...[const SizedBox(width: 4), const _Badge('문의 받음')],
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                otherName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            if (lastAt != null)
              Text(
                _timeLabel(lastAt.toDate()),
                style: const TextStyle(fontSize: 11, color: Colors.black38),
              ),
            // 하단 탭 숫자에 들어간 방이 어느 것인지 — 같은 판정을 그대로 쓴다.
            if (unread) ...[
              const SizedBox(width: 6),
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: _kAccent,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            last.isNotEmpty
                ? last
                : (relatedTitle.isNotEmpty ? relatedTitle : '대화를 시작해보세요.'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: unread ? Colors.black87 : Colors.black45,
              fontWeight: unread ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  Widget _tile(ChatTarget t) {
    final busy = _opening == t.dedupeKey;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        onTap: _opening != null ? null : () => _openChat(t),
        leading: Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            color: Color(0xFFFFE0EE),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(
              t.title.isNotEmpty ? t.title.characters.first : '?',
              style: const TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
                color: _kAccent,
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF0F5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                t.section,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: _kAccent,
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                t.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 3),
          child: Text(
            t.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 12, color: Colors.black45),
          ),
        ),
        trailing: busy
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: _kAccent,
                ),
              )
            : const Icon(Icons.chat_bubble_outline, color: _kAccent, size: 20),
      ),
    );
  }

  /// 일부 구획만 실패했을 때 — 나머지 목록은 그대로 두고 사실만 적는다.
  /// 빈 목록으로 위장하면 "예약이 없다"로 읽혀 호스트에게 연락할 방법을 잃는다.
  Widget _errorBanner() => Container(
    margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF5F5),
      borderRadius: BorderRadius.circular(12),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, size: 18, color: Color(0xFFE53935)),
        const SizedBox(width: 8),
        const Expanded(
          child: Text(
            '일부 목록을 불러오지 못했어요. 아래에 보이지 않는 예약이 있을 수 있어요.',
            style: TextStyle(
              fontSize: 12,
              color: Color(0xFFB71C1C),
              height: 1.4,
            ),
          ),
        ),
        TextButton(
          onPressed: () {
            for (final s in _subs) {
              s.cancel();
            }
            _subs.clear();
            setState(() {
              _errors.clear();
              _loaded.clear();
              _bySource.clear();
              _rooms = const [];
              _roomsLoaded = false;
            });
            _subscribe();
          },
          child: const Text('다시 시도'),
        ),
      ],
    ),
  );

  Widget _emptyState() => Padding(
    padding: const EdgeInsets.only(top: 80),
    child: Column(
      children: [
        const Text('💬', style: TextStyle(fontSize: 56)),
        const SizedBox(height: 16),
        const Text(
          '아직 주고받은 대화가 없어요.',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.black54,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          '파티를 신청하거나 플레이스·장소·파티샵을 예약하면\n여기서 호스트와 바로 대화할 수 있어요.\n내 게시글에 문의가 오면 여기에 바로 뜹니다.',
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 13, color: Colors.black38, height: 1.6),
        ),
        const SizedBox(height: 20),
        OutlinedButton.icon(
          onPressed: () => Navigator.push(
            context,
            webFramedRoute((_) => const ChatListScreen()),
          ),
          icon: const Icon(Icons.forum_outlined, size: 18),
          label: const Text('지난 대화 보기'),
          style: OutlinedButton.styleFrom(
            foregroundColor: _kAccent,
            side: const BorderSide(color: Color(0xFFFFC2D6)),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(11),
            ),
          ),
        ),
      ],
    ),
  );
}

/// 목록 구획 제목.
class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.bold,
        color: Colors.black45,
      ),
    ),
  );
}

/// 줄 앞에 붙는 작은 분류 표시.
class _Badge extends StatelessWidget {
  const _Badge(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF0F5),
      borderRadius: BorderRadius.circular(4),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w600,
        color: _kAccent,
      ),
    ),
  );
}
