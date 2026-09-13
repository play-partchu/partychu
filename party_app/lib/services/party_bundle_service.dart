import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:party_app/models/party_pricing.dart';
import 'package:party_app/widgets/party_card_widget.dart';

// ══════════════════════════════════════════════════════════════════════════
// "플레이스(숙박)+파티 통합 등록"으로 **함께 만들어진** 파티 묶음 조회
//
// ── 연결 식별자 조사 결과 ─────────────────────────────────────────────────
// ⚠ **콤보 등록 화면은 없어졌다**(플레이스+파티를 한 폼에서 만드는 등록 방식
// 자체를 뺐다). 아래 필드 표는 그래서 "앞으로 이렇게 쓴다"가 아니라 **이미
// 만들어져 운영에 남아 있는 문서가 이렇게 생겼다**는 기록이다 — 이 서비스는
// 그 문서를 읽어 묶음(파티+공간)을 되찾는 일만 한다. 표를 지우면 남은 문서를
// 읽는 근거가 사라지므로 그대로 둔다.
//
// 실제로 쓰인 필드는 아래가 전부다(comboId / linkedPlaceId(events) /
// sourceType 같은 필드는 이 코드베이스에 존재한 적이 없다).
//
//   (옛) 숙박 + 파티 → places
//     parties: bundleId = places 문서 id, linkedPlaceId = places 문서 id,
//              isCombo = true, seriesId = 대표 파티 문서 id,
//              comboPlaceType = 'stay'
//     places : bundleId, linkedPartyId(대표 파티), isCombo = true
//
//   (옛) 매장 + 파티 → events
//     parties: bundleId = events 문서 id, linkedEventId = events 문서 id,
//              isCombo = true, seriesId = 대표 파티 문서 id,
//              comboPlaceType = 'venue'
//     events : bundleId, linkedPartyId(대표 파티), isCombo = true
//
// ⚠ `linkedEventId`는 **통합 등록 전용이 아니다** — 나중에 따로 등록한 일반
//   파티를 플레이스에 붙이는 사후 연결(place_party_link_service.dart)도 같은
//   필드를 쓴다. 그래서 "함께 등록된 파티"를 `linkedEventId`만으로 모으면
//   우연히 같은 플레이스를 쓰는 일반 파티가 섞인다. 이 서비스가 정본으로
//   삼는 기준은 **`bundleId`** 다 — 통합 등록에서만 찍히고, 한 번의 등록에서
//   나온 문서(플레이스 1 + 파티 N)에만 같은 값이 들어간다.
//
// ── 폴백 순서 ─────────────────────────────────────────────────────────────
// bundleId가 없는 예전 콤보 문서를 대비해 아래 순서로 내려간다. 폴백 단계는
// 모두 `isCombo == true`를 추가로 요구해서, 사후 연결된 일반 파티가 섞이지
// 않게 한다.
//
//   1. bundleId          — 정본. 이 값만으로 묶음이 정확히 결정된다.
//   2. seriesId          — 같은 등록에서 나온 날짜 슬롯 형제들(+isCombo)
//   3. linkedPlaceId     — 숙박 콤보 폴백(+isCombo)
//   4. linkedEventId     — 매장 콤보 폴백(+isCombo)
//   5. 없음              — 현재 파티 1건만
//
// ── 권한 ──────────────────────────────────────────────────────────────────
// 모든 쿼리에 `hostId == 내 uid` 동등 조건을 함께 건다(수정 진입점이므로
// 남의 파티가 목록에 뜨면 안 된다). **hostId를 뺀 폴백 쿼리는 두지 않는다** —
// 색인 오류를 이유로 조건을 빼면 남의 파티까지 읽어오게 되므로, 실패는 그대로
// 예외로 올린다. 네 가지 묶음 필드 × hostId 조합을 받쳐줄 복합 색인은
// `firestore.indexes.json`에 정의돼 있다.
// ══════════════════════════════════════════════════════════════════════════

/// 묶음을 찾아낸 기준 — 화면 안내 문구와 디버깅에 쓴다.
enum PartyBundleBasis {
  /// 통합 등록이 찍은 `bundleId`. 가장 정확하다.
  bundleId,

  /// 같은 등록에서 나온 날짜 슬롯 형제(`seriesId`).
  seriesId,

  /// 숙박 콤보 폴백(`linkedPlaceId`).
  linkedPlaceId,

  /// 매장 콤보 폴백(`linkedEventId`).
  linkedEventId,

  /// 묶음 식별자가 전혀 없는 파티 — 현재 파티 1건뿐이다.
  none,
}

extension PartyBundleBasisLabel on PartyBundleBasis {
  /// 폴백으로 모은 묶음인지 — true면 화면에 "추정" 안내를 덧붙인다.
  bool get isFallback =>
      this == PartyBundleBasis.seriesId ||
      this == PartyBundleBasis.linkedPlaceId ||
      this == PartyBundleBasis.linkedEventId;
}

/// 묶음에 속한 파티 1건.
class BundledParty {
  final String id;
  final Map<String, dynamic> data;

  /// 지금 수정 화면에 열려 있는 파티인지.
  final bool isCurrent;

  const BundledParty({
    required this.id,
    required this.data,
    required this.isCurrent,
  });

  String get title {
    final t = (data['title'] as String?)?.trim();
    if (t != null && t.isNotEmpty) return t;
    final n = (data['name'] as String?)?.trim();
    if (n != null && n.isNotEmpty) return n;
    return '(제목 없음)';
  }

  /// 모집중 / 모집마감 / 마감 / 취소 — 저장값과 날짜를 함께 본 실제 상태.
  String get status => PartyCard.effectiveStatus(data);

  /// '8월 9일(토) 오후 7:00' 또는 정기 파티의 반복 요약.
  String get dateTimeLabel => PartyCard.formatDate(data);

  /// 정기 파티면 '정기', 아니면 '일회성'.
  String get scheduleKindLabel =>
      PartyCard.recurringLabel(data).isNotEmpty ? '정기' : '일회성';

  /// 신청/모집 인원 — '3 / 10명'.
  String get capacityLabel => PartyCard.capacityLabel(data);

  /// 참가비 — 무료거나 성별로 다르면 그에 맞는 표기를 돌려준다.
  String get feeLabel {
    final pricing = PartyPricing.fromMap(data);
    if (pricing.isFree) return '무료';
    final min = pricing.displayPrice;
    final max = pricing.maxPrice;
    if (max > min) return '${_won(min)}~${_won(max)}원';
    return '${_won(min)}원';
  }

  static String _won(int v) => v.toString().replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+$)'),
    (m) => '${m[1]},',
  );
}

/// 조회 결과 — 묶인 파티 목록 + 어떤 기준으로 묶었는지.
class PartyBundle {
  final PartyBundleBasis basis;

  /// [basis]에 해당하는 값(bundleId 값 등). 기준이 없으면 빈 문자열.
  final String key;

  /// 날짜 오름차순으로 정렬된 묶음 파티들(현재 파티 포함).
  final List<BundledParty> parties;

  const PartyBundle({
    required this.basis,
    required this.key,
    required this.parties,
  });

  static const PartyBundle empty = PartyBundle(
    basis: PartyBundleBasis.none,
    key: '',
    parties: <BundledParty>[],
  );

  int get length => parties.length;

  /// 현재 파티 말고 형제 파티가 실제로 있는지 — 섹션 노출 판단에 쓴다.
  bool get hasSiblings => parties.where((p) => !p.isCurrent).isNotEmpty;
}

class PartyBundleService {
  PartyBundleService._();

  static FirebaseFirestore get _db => FirebaseFirestore.instance;

  /// [partyData]가 통합 등록으로 만들어진 파티라면, 같은 등록에서 나온 파티를
  /// 모두 모아 돌려준다. 통합 등록이 아니면 [PartyBundle.empty].
  ///
  /// [hostId]는 현재 로그인 사용자 uid — 이 값과 `hostId`가 같은 문서만 담는다.
  /// **장소와 한 번에 묶여 등록된 파티인지.** 묶음 조회의 진입 조건과 같다.
  ///
  /// `linkedPlaceId`가 있다고 콤보인 것이 아니다 — 그 필드는 "숙박+파티"
  /// 콤보만 쓰던 시절에는 콤보의 표식이나 다름없었지만, 지금은 일반 등록에서
  /// 장소대여를 골라도 같은 필드가 채워진다. 통합 등록만 남기는 흔적
  /// (`isCombo` / `bundleId`)으로만 판정해야, 사후 연결된 일반 파티가
  /// "함께 등록된 파티"로 오인돼 장소 연결 변경이 막히는 일이 없다.
  static bool isBundledRegistration(Map<String, dynamic> party) =>
      party['isCombo'] == true || _nonEmpty(party['bundleId']) != null;

  static Future<PartyBundle> load({
    required String partyId,
    required Map<String, dynamic> partyData,
    required String hostId,
  }) async {
    if (hostId.isEmpty) return PartyBundle.empty;

    final bundleId = _nonEmpty(partyData['bundleId']);
    final seriesId = _nonEmpty(partyData['seriesId']);
    final linkedPlaceId = _nonEmpty(partyData['linkedPlaceId']);
    final linkedEventId = _nonEmpty(partyData['linkedEventId']);

    // 통합 등록 흔적이 전혀 없으면 묶음이 아니다 — 사후 연결로 linkedEventId나
    // linkedPlaceId만 가진 일반 파티가 여기서 걸러진다.
    if (!isBundledRegistration(partyData)) return PartyBundle.empty;

    final ({PartyBundleBasis basis, String field, String value})? criteria;
    if (bundleId != null) {
      criteria = (
        basis: PartyBundleBasis.bundleId,
        field: 'bundleId',
        value: bundleId,
      );
    } else if (seriesId != null) {
      criteria = (
        basis: PartyBundleBasis.seriesId,
        field: 'seriesId',
        value: seriesId,
      );
    } else if (linkedPlaceId != null) {
      criteria = (
        basis: PartyBundleBasis.linkedPlaceId,
        field: 'linkedPlaceId',
        value: linkedPlaceId,
      );
    } else if (linkedEventId != null) {
      criteria = (
        basis: PartyBundleBasis.linkedEventId,
        field: 'linkedEventId',
        value: linkedEventId,
      );
    } else {
      criteria = null;
    }

    if (criteria == null) {
      // 콤보 표시는 있는데 묶음 id가 하나도 없는 예전 문서 — 현재 파티만.
      return PartyBundle(
        basis: PartyBundleBasis.none,
        key: '',
        parties: [BundledParty(id: partyId, data: partyData, isCurrent: true)],
      );
    }

    final docs = await _queryBundle(
      field: criteria.field,
      value: criteria.value,
      hostId: hostId,
    );

    final requireComboFlag = criteria.basis != PartyBundleBasis.bundleId;
    final parties = <BundledParty>[];
    for (final doc in docs) {
      final data = doc.data();
      if (data['isDeleted'] == true) continue;
      // 쿼리에서 이미 hostId로 걸렀지만, 예전 문서가 hostUid만 갖고 있는
      // 경우까지 감안해 한 번 더 확인한다(조건을 넓히지는 않는다).
      if (!_isMine(data, hostId)) continue;
      // 폴백 기준으로 모을 때는 콤보 문서만 남긴다 — 사후 연결된 일반 파티가
      // 섞이지 않게.
      if (requireComboFlag && data['isCombo'] != true) continue;
      parties.add(
        BundledParty(id: doc.id, data: data, isCurrent: doc.id == partyId),
      );
    }

    // 쿼리가 현재 파티를 못 집어왔더라도(색인 지연·필드 누락) 목록에는 항상
    // 현재 파티가 있어야 한다.
    if (!parties.any((p) => p.isCurrent) && _isMine(partyData, hostId)) {
      parties.add(BundledParty(id: partyId, data: partyData, isCurrent: true));
    }

    parties.sort(_byDate);

    return PartyBundle(
      basis: criteria.basis,
      key: criteria.value,
      parties: parties,
    );
  }

  /// 묶음 필드 + hostId 동등 조건으로 질의한다.
  ///
  /// hostId 조건은 어떤 경우에도 빠지지 않는다 — 빠뜨린 채 폴백하면 남의
  /// 파티까지 읽어오게 되므로, 색인 오류가 나면 그대로 예외를 올려서
  /// 호출부(수정 화면)가 목록을 비운 채 실패를 알리게 한다. 이 쿼리를 받쳐줄
  /// 복합 색인은 `firestore.indexes.json`에 정의돼 있다.
  static Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>>
  _queryBundle({
    required String field,
    required String value,
    required String hostId,
  }) async {
    final snap = await _db
        .collection('parties')
        .where(field, isEqualTo: value)
        .where('hostId', isEqualTo: hostId)
        .get();
    return snap.docs;
  }

  static bool _isMine(Map<String, dynamic> data, String hostId) =>
      data['hostId'] == hostId || data['hostUid'] == hostId;

  static int _byDate(BundledParty a, BundledParty b) {
    final da = PartyCard.parsePartyDateTime(a.data);
    final db = PartyCard.parsePartyDateTime(b.data);
    if (da != null && db != null && da != db) return da.compareTo(db);
    if (da != null && db == null) return -1;
    if (da == null && db != null) return 1;
    return a.id.compareTo(b.id);
  }

  static String? _nonEmpty(Object? v) =>
      (v is String && v.trim().isNotEmpty) ? v : null;
}
