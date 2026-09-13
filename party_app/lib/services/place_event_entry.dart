// ─────────────────────────────────────────────────────────────────────────────
// 🎪 매장 이벤트 등록 진입 — "어느 플레이스의 매장 이벤트인가"를 정하는
// 공용 관문.
//
// 여기서 만드는 것은 **매장 이벤트**다([HostOffering.placeEvent]) — 매장이
// 주체가 되어 여는 행사·프로모션·혜택. 참가자를 모집해 신청을 받는 🎉 파티는
// 컬렉션도 등록 흐름도 완전히 별개다(고르는 자리만 [HostOfferingChoice]에서
// 함께 둔다).
//
// ── 이벤트는 독립 콘텐츠가 아니다 ────────────────────────────────────────────
// 이름이 헷갈리므로 다시 못 박아 둔다(자세한 배경은 party_event_source.dart
// 상단 주석).
//
//   · `events`          = **플레이스 본체** 컬렉션(매장·즐길거리). 이벤트가 아니다.
//   · `places`          = 공간대여·숙박 본체 컬렉션.
//   · `placePromotions` = 그 플레이스가 여는 **매장 이벤트 한 건**([PlacePromotion]).
//
// 이벤트 문서는 언제나 원본 플레이스(`placeId` + `placeCollection`)에 붙는다.
// 그래서 이벤트 등록은 **내 플레이스가 있어야 시작되는 일**이고, 어느 입구로
// 들어오든 반드시 같은 순서를 지나야 한다:
//
//   내 플레이스 확인 → (0개면) 플레이스 등록 안내
//                   → (여러 개면) 어느 플레이스인지 선택
//                   → 이벤트 등록 폼([PlaceEventEditScreen])
//                   → 저장했으면 이벤트 관리([PlaceEventManageScreen])
//
// 등록 화면(등록 > 이벤트 등록)과 마이 > 파티츄 호스트가 이 순서를 각자 들고
// 있으면 한쪽만 고쳐져 두 입구가 다르게 동작한다. 그래서 흐름은 여기 하나뿐이고
// 화면들은 이 함수만 부른다.
//
// **새 컬렉션도 새 연결 필드도 만들지 않는다** — 여기서 하는 일은 기존 문서를
// 읽어 기존 화면을 여는 것뿐이다.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import 'package:party_app/models/business_verification.dart';
import 'package:party_app/models/combo_place_type.dart';
import 'package:party_app/screens/place_entry_register_screen.dart';
import 'package:party_app/screens/place_event_edit_screen.dart';
import 'package:party_app/screens/place_event_manage_screen.dart';
import 'package:party_app/services/business_verification_service.dart';
import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/services/place_create_eligibility.dart';
import 'package:party_app/services/registration_limits.dart';
import 'package:party_app/services/place_party_link_service.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 이벤트를 붙일 수 있는 **내 플레이스 한 곳**.
///
/// 값은 전부 원본 플레이스 문서에서 읽는다 — 이벤트 화면과 firestore.rules가
/// 보는 것과 같은 정본이다(rules의 `placePromotions` / `ownsSourcePlace`는
/// 원본 문서를 다시 읽어 소유자를 확인하므로, 여기서 다른 값을 넘겨봐야
/// 저장 단계에서 막힌다).
@immutable
class EventPlaceTarget {
  const EventPlaceTarget({
    required this.placeId,
    required this.placeCollection,
    required this.hostId,
    required this.placeName,
    this.address = '',
  });

  /// 원본 플레이스 문서 id.
  final String placeId;

  /// 'events'(플레이스) 또는 'places'(공간대여·숙박).
  final String placeCollection;

  /// 원본 문서에서 읽은 hostId.
  final String hostId;

  final String placeName;

  /// 주소 — 등록 폼 머리말에 "어디서 열리는 이벤트인지" 보여주는 용도.
  final String address;

  /// 공간 유형 정본 — 이모지·강조색을 여기서 가져온다. 이 흐름만의 기호를
  /// 새로 만들면 같은 플레이스가 화면마다 다른 얼굴을 갖게 된다.
  ComboPlaceType get spaceType {
    for (final t in ComboPlaceType.values) {
      if (t.placeCollection == placeCollection) return t;
    }
    return ComboPlaceType.venue;
  }

  Color get accent => spaceType.accent;

  String get emoji => spaceType.emoji;

  /// 목록 조회 결과 한 건. 이름이 비면 종류 이름으로 대신한다
  /// ([PartyLinkTarget.noun] — '플레이스' / '공간대여').
  factory EventPlaceTarget.fromDoc({
    required String id,
    required String collection,
    required Map<String, dynamic> data,
  }) {
    final name = (data['name'] as String? ?? '').trim();
    return EventPlaceTarget(
      placeId: id,
      placeCollection: collection,
      hostId: (data['hostId'] as String? ?? '').trim(),
      placeName: name.isNotEmpty ? name : _nounOf(collection),
      address: _addressOf(data),
    );
  }

  static String _nounOf(String collection) {
    for (final t in PartyLinkTarget.values) {
      if (t.collection == collection) return t.noun;
    }
    return '플레이스';
  }

  static String _addressOf(Map<String, dynamic> data) {
    for (final key in ['address', 'roadAddress', 'location', 'jibunAddress']) {
      final v = (data[key] as String? ?? '').trim();
      if (v.isNotEmpty) return v;
    }
    return '';
  }
}

/// 이벤트 등록·관리로 들어가는 유일한 문. 등록 화면과 마이페이지가 함께 쓴다.
class PlaceEventEntry {
  PlaceEventEntry._();

  // ── 테스트 주입점 ───────────────────────────────────────────────────────
  // 이 프로젝트의 Dart 테스트에는 Firestore 페이크가 없다
  // (place_party_link_payload_test.dart 상단 주석). 흐름 자체를 돌려보려면
  // "내 플레이스를 가져오는 부분"에 이음매가 필요하다. 운영 코드는 둘 다
  // null이라 실물 Firestore/FirebaseAuth를 그대로 쓴다.
  static Future<List<EventPlaceTarget>> Function(String uid)? _loaderOverride;
  static String? _uidOverride;
  static Future<bool?> Function(String collection, String placeId)?
  _ownsOverride;
  static Future<BusinessVerification> Function()? _verificationOverride;

  @visibleForTesting
  static void debugSetSource({
    Future<List<EventPlaceTarget>> Function(String uid)? loader,
    String? uid,
    Future<bool?> Function(String collection, String placeId)? owns,
    Future<BusinessVerification> Function()? verification,
  }) {
    _loaderOverride = loader;
    _uidOverride = uid;
    _ownsOverride = owns;
    _verificationOverride = verification;
  }

  @visibleForTesting
  static void debugResetSource() {
    _loaderOverride = null;
    _uidOverride = null;
    _ownsOverride = null;
    _verificationOverride = null;
  }

  /// 소유자 비교는 Firebase Auth uid를 정본으로 쓴다 — [UserSession.userId]는
  /// 앱 재시작 직후 잠깐 비어 있을 수 있다(place_owner.dart와 같은 규칙).
  static String _currentUid() {
    final override = _uidOverride;
    if (override != null) return override;
    final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
    return uid.isNotEmpty ? uid : UserSession.userId;
  }

  /// 이벤트를 붙일 수 있는 내 플레이스 전부(매장·즐길거리 + 공간대여·숙박).
  ///
  /// 삭제된 문서는 뺀다. **hostId가 나인 문서만** 남긴다 — 조회 조건이 이미
  /// 그렇지만 목록을 만드는 마지막 단계에서 한 번 더 거른다. 남의 플레이스가
  /// 선택지에 섞이는 사고는 화면이 아니라 여기서 막혀야 한다.
  static Future<List<EventPlaceTarget>> myPlaces() async {
    final uid = _currentUid();
    if (uid.isEmpty) return const [];

    final loader = _loaderOverride;
    final found = loader != null
        ? await loader(uid)
        : await _fetchFromFirestore(uid);

    return found.where((p) => p.hostId == uid).toList()
      ..sort((a, b) => a.placeName.compareTo(b.placeName));
  }

  static Future<List<EventPlaceTarget>> _fetchFromFirestore(String uid) async {
    final out = <EventPlaceTarget>[];
    // 두 컬렉션은 파티 연결 정본([PartyLinkTarget])이 이미 들고 있다 —
    // 여기서 컬렉션 이름을 다시 적으면 한쪽만 늘었을 때 말이 갈라진다.
    for (final target in PartyLinkTarget.values) {
      // ⚠️ orderBy를 붙이지 않는다 — where('hostId')와 함께 쓰면 복합 색인이
      // 필요하고, 색인이 빠지면 조회가 통째로 실패해 "플레이스가 없다"고
      // 잘못 안내하게 된다(my_host_hub_screen의 내 장소 목록과 같은 이유).
      final snap = await FirebaseFirestore.instance
          .collection(target.collection)
          .where('hostId', isEqualTo: uid)
          .get();
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['isDeleted'] == true || data['status'] == 'deleted') continue;
        out.add(
          EventPlaceTarget.fromDoc(
            id: doc.id,
            collection: target.collection,
            data: data,
          ),
        );
      }
    }
    return out;
  }

  // ── 저장 실패의 원인을 되묻는다 ─────────────────────────────────────────
  //
  // firestore.rules는 **어느 조건에서 막았는지 알려주지 않는다** —
  // permission-denied 한 줄뿐이다. 그래서 여기서 부모 플레이스와 사업자 권한을
  // 실제로 다시 읽고, **확인한 사실만** 말한다.
  //
  // ⚠️ 확인하지 않은 것을 원인으로 지목하면 안 된다. 소유권 문제인데 "사업자
  //    인증을 확인하세요"라고 하면 호스트는 멀쩡한 인증 화면만 들여다보다
  //    끝난다(플레이스 등록 무한 루프가 정확히 그 모양이었다).

  /// 이 계정이 그 부모 플레이스의 주인인가 — rules의 `ownsSourcePlace`와 같은
  /// 판정을 앱에서 한 번 더 물어본 값이다.
  ///
  /// `null`은 **모른다**는 뜻이다(읽기 실패 등). 모르는 것을 false로 접으면
  /// "이 장소의 호스트만 등록할 수 있어요"라고 잘못 단정하게 된다.
  static Future<bool?> ownsSourcePlace(
    String placeCollection,
    String placeId,
  ) async {
    final override = _ownsOverride;
    if (override != null) return override(placeCollection, placeId);

    // rules와 같은 화이트리스트 — 그 밖의 값은 애초에 부모가 될 수 없다.
    if (placeCollection != 'events' && placeCollection != 'places') return false;
    if (placeId.trim().isEmpty) return false;
    final uid = _currentUid();
    if (uid.isEmpty) return false;
    try {
      final doc = await FirebaseFirestore.instance
          .collection(placeCollection)
          .doc(placeId)
          .get();
      if (!doc.exists) return false; // 없는 부모 — rules의 exists()와 같다.
      return (doc.data()?['hostId'] as String? ?? '') == uid;
    } catch (_) {
      return null; // 모른다.
    }
  }

  static Future<BusinessVerification> _verification() {
    final override = _verificationOverride;
    if (override != null) return override();
    return BusinessVerificationService.fetch();
  }

  /// 일시적 실패에 쓰는 문구 — 사용자가 할 수 있는 일이 "다시 하기"뿐일 때만.
  static const String genericSaveFailure = '저장에 실패했어요. 잠시 후 다시 시도해주세요.';

  /// 이벤트 저장이 실패했을 때 **화면에 그대로 띄울 문구**.
  ///
  /// 갈래는 셋이다.
  ///   ① 미디어 업로드 실패 — 이벤트 내용은 멀쩡하다. 사진을 빼고 저장하면
  ///      되는 경우가 많아 그 길을 알려준다.
  ///   ② 권한 거부 — 무엇이 막았는지 되물어 그 사실만 말한다.
  ///   ③ 그 밖 — 네트워크·일시적 서버 오류. 여기서만 [genericSaveFailure].
  static Future<String> saveFailureMessage(
    Object error, {
    required String placeId,
    required String placeCollection,
  }) async {
    // ① 사진·동영상 업로드 — 저장 자체와 다른 단계다.
    if (error is CloudflareUploadException) {
      final fromServer = error.userMessage?.trim();
      if (fromServer != null && fromServer.isNotEmpty) return fromServer;
      return '사진·동영상을 올리지 못했어요. 입력하신 내용은 그대로예요 — '
          '사진을 빼고 저장하거나 잠시 후 다시 시도해주세요.';
    }

    if (!_isPermissionDenied(error)) return genericSaveFailure;

    // ② 권한 거부 — rules가 막은 조건을 앱에서 되짚는다.
    final owns = await ownsSourcePlace(placeCollection, placeId);
    if (owns == false) {
      return '이 장소의 호스트만 이벤트를 등록할 수 있어요.';
    }
    if (owns == null) return genericSaveFailure; // 모르면 단정하지 않는다.

    // 부모는 내 것이 맞다 — 남은 원인은 계정 쪽 권한이다.
    final v = await _verification();
    if (v.needsOwnerApproval) {
      return '대표자 확인이 완료되어야 이벤트를 등록할 수 있어요.';
    }
    if (!v.isVerified) {
      return '사업자 인증 상태를 다시 확인해주세요.';
    }
    // 사업자 권한도 멀쩡하다 — 본인확인이 풀렸거나 탈퇴 대기 상태다
    // (rules의 isVerifiedMember).
    return '계정 상태를 확인해주세요. 본인확인을 마친 계정만 이벤트를 등록할 수 있어요.';
  }

  static bool _isPermissionDenied(Object error) {
    if (error is FirebaseException) return error.code == 'permission-denied';
    // 타입을 잃고 올라온 경우까지 받아 준다(옛 호출부와 같은 판정).
    return error.toString().contains('permission-denied');
  }

  /// **이벤트 등록 시작** — 등록 화면과 마이페이지가 함께 쓰는 흐름.
  ///
  /// [target]을 주면(마이 > 파티츄 호스트처럼 어느 플레이스인지 이미 정해진
  /// 경우) 확인·선택 단계를 건너뛰고 곧장 폼을 연다. 주지 않으면 내 플레이스를
  /// 찾아 0개면 안내, 1개면 그대로, 여러 개면 고르게 한다.
  ///
  /// 1개뿐이어도 몰래 붙이지 않는다 — 폼 머리말이 어느 플레이스의 이벤트인지
  /// 항상 보여준다([PlaceEventEditScreen]의 장소 카드).
  static Future<void> startRegister(
    BuildContext context, {
    EventPlaceTarget? target,
    String? initialTitle,
    String? sourcePartyId,
    String? sourcePartyTitle,
    bool requirePeriod = false,
  }) async {
    // 이벤트도 **계정당 10개**다 — 매장별이 아니라 계정 전체 기준이라, 어느
    // 플레이스를 고르기 전에 먼저 본다([RegistrationLimits]). 고른 뒤에
    // 막으면 "어느 매장이냐"를 물어 놓고 등록을 못 하게 되는 순서가 된다.
    if (!await RegistrationLimits.ensure(context, RegistrationKind.promotion)) {
      return;
    }
    if (!context.mounted) return;

    var picked = target;
    if (picked == null) {
      picked = await _resolvePlace(context);
      if (picked == null) return;
    }

    if (!context.mounted) return;
    await _openEditor(
      context,
      target: picked,
      initialTitle: initialTitle,
      sourcePartyId: sourcePartyId,
      sourcePartyTitle: sourcePartyTitle,
      requirePeriod: requirePeriod,
    );
  }

  /// 이벤트를 붙일 **내 플레이스 한 곳**을 정하는 앞단 — 0개면 안내, 1개면
  /// 그대로, 여러 개면 고르게 한다.
  ///
  /// `null`은 "정하지 못했다"는 뜻이다(조회 실패 · 플레이스 없음 · 사용자가
  /// 시트를 닫음). 안내는 여기서 이미 띄웠으니 부르는 쪽은 그냥 돌아가면 된다.
  ///
  /// **관리** 쪽에는 이런 앞단이 없다. 등록한 이벤트는 마이 > 파티츄 호스트의
  /// 🎪 이벤트 탭에 내 플레이스별로 전부 펼쳐지므로, 관리하려고 어느
  /// 플레이스인지 먼저 고를 이유가 없다.
  static Future<EventPlaceTarget?> _resolvePlace(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);

    final List<EventPlaceTarget> mine;
    try {
      mine = await myPlaces();
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('플레이스 정보를 불러오지 못했어요. 잠시 후 다시 시도해주세요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return null;
    }
    if (!context.mounted) return null;

    if (mine.isEmpty) {
      await showNeedPlaceSheet(context);
      return null;
    }
    if (mine.length == 1) return mine.first;
    return pickPlace(context, mine);
  }

  /// 이벤트·혜택 **관리** 화면 — 이미 어느 플레이스인지 아는 자리에서 쓴다
  /// (호스트 카드의 '이벤트 · 혜택', 플레이스 수정 화면의 진입 카드).
  static Future<void> openManage(
    BuildContext context,
    EventPlaceTarget target,
  ) => Navigator.push(
    context,
    webFramedRoute(
      (_) => PlaceEventManageScreen(
        placeId: target.placeId,
        placeCollection: target.placeCollection,
        hostId: target.hostId,
        placeName: target.placeName,
        accent: target.accent,
      ),
    ),
  );

  /// 등록 폼 → (저장했으면) 관리 화면. 등록 직후 수정·종료로 이어지도록
  /// 두 입구가 같은 뒷길을 쓴다.
  static Future<void> _openEditor(
    BuildContext context, {
    required EventPlaceTarget target,
    String? initialTitle,
    String? sourcePartyId,
    String? sourcePartyTitle,
    bool requirePeriod = false,
  }) async {
    final navigator = Navigator.of(context);
    final saved = await navigator.push<bool>(
      webFramedRoute(
        (_) => PlaceEventEditScreen(
          placeId: target.placeId,
          placeCollection: target.placeCollection,
          hostId: target.hostId,
          placeName: target.placeName,
          placeAddress: target.address,
          accent: target.accent,
          initialTitle: initialTitle,
          sourcePartyId: sourcePartyId,
          sourcePartyTitle: sourcePartyTitle,
          requirePeriod: requirePeriod,
        ),
      ),
    );
    if (saved != true) return;

    await navigator.push(
      webFramedRoute(
        (_) => PlaceEventManageScreen(
          placeId: target.placeId,
          placeCollection: target.placeCollection,
          hostId: target.hostId,
          placeName: target.placeName,
          accent: target.accent,
        ),
      ),
    );
  }

  // ── 플레이스가 없을 때 ──────────────────────────────────────────────────
  // 폼으로 보내지 않는다. 폼은 원본 플레이스가 있어야만 저장되므로, 들여보내면
  // 다 쓰고 나서야 막힌다.

  @visibleForTesting
  static Future<void> showNeedPlaceSheet(BuildContext context) {
    const accent = Color(0xFFFF6FA0);
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFFFFF7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFD6E4),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text(
                  '플레이스를 먼저 등록해주세요',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 10),
                const Text(
                  '매장 이벤트는 등록된 플레이스와 연결해서 등록할 수 있어요.\n'
                  '플레이스를 먼저 등록한 뒤 매장 이벤트를 추가해주세요.',
                  style: TextStyle(
                    fontSize: 13.5,
                    height: 1.5,
                    color: Color(0xFF8A5A72),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      // 시트를 먼저 닫고 등록 화면을 연다 — 등록을 마치고
                      // 돌아왔을 때 안내 시트가 남아 있으면 안 된다.
                      Navigator.pop(ctx);
                      if (!context.mounted) return;
                      // 여기도 **새 플레이스를 만드는 길**이라 등록 화면과
                      // 같은 사업자 관문을 지난다 — 열어 두면 이벤트 등록이
                      // 그대로 우회로가 된다.
                      if (!await PlaceCreateEligibility.ensure(context)) {
                        return;
                      }
                      if (!context.mounted) return;
                      await Navigator.push(
                        context,
                        // 통합 진입점 — 유형(매장·즐길거리 / 공간대여·숙박)은
                        // 그 화면 맨 위에서 고른다. 옛 단독 등록 화면
                        // (EventRegisterScreen / PlaceRegisterScreen)을 직접
                        // 열면 그 선택이 통째로 사라진다.
                        webFramedRoute((_) => const PlaceEntryRegisterScreen()),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accent,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '플레이스 등록하기',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => Navigator.pop(ctx),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.black54,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    child: const Text('나중에', style: TextStyle(fontSize: 14)),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── 플레이스가 여러 개일 때 ────────────────────────────────────────────
  // 남의 플레이스는 애초에 목록에 없다([myPlaces]의 hostId 재확인).

  @visibleForTesting
  static Future<EventPlaceTarget?> pickPlace(
    BuildContext context,
    List<EventPlaceTarget> places,
  ) {
    return showModalBottomSheet<EventPlaceTarget>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(ctx).size.height * 0.72,
        ),
        decoration: const BoxDecoration(
          color: Color(0xFFFFF7FA),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFD6E4),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Text(
                  '어느 플레이스에서 진행하나요?',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ),
              const Padding(
                padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
                child: Text(
                  '이벤트는 고른 플레이스에 연결돼요.',
                  style: TextStyle(fontSize: 13, color: Color(0xFF8A5A72)),
                ),
              ),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  itemCount: places.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (_, i) {
                    final p = places[i];
                    return Material(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(14),
                        onTap: () => Navigator.pop(ctx, p),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 14,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: p.accent.withValues(alpha: 0.28),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(p.emoji, style: const TextStyle(fontSize: 18)),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      p.placeName,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.bold,
                                        color: p.accent,
                                      ),
                                    ),
                                    if (p.address.isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        p.address,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(
                                          fontSize: 12,
                                          color: Colors.black45,
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                              const Icon(
                                Icons.chevron_right,
                                color: Colors.black38,
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
