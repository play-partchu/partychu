// ─────────────────────────────────────────────────────────────────────────────
// 관리자 판매 통계 — 콜러블이 내려준 원자료를 **호스트 앱과 같은 코드로** 해석한다.
//
// 이 파일에도 매출 계산이 없다. `adminGetSalesEntries`가 신청/예약 문서를
// 읽어 넘겨주면, 그 맵을 그대로 `SalesEntryMapper.fromDocument`에 넣는다 —
// 호스트 앱(party_app의 HostSalesService)이 `doc.data()`를 넣는 것과 **같은
// 입력, 같은 함수**다. 그래서 호스트 화면의 이번 달 총수익이 320,000원이면
// 관리자가 같은 호스트·같은 기간을 조회해도 정확히 320,000원이 나온다.
//
// 금액 정본 선택·매출 포함 판정·일자별 집계는 전부
// packages/partychu_sales(Dart) 한 곳에만 있다. 여기서 다시 계산하지 말 것.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_functions/cloud_functions.dart';
import 'package:partychu_sales/partychu_sales.dart';

const _functionsRegion = 'asia-northeast3';

/// 판매자 한 명의 신원 — 판매자 표와 검색이 쓴다.
class SellerIdentity {
  const SellerIdentity({
    required this.uid,
    this.nickname,
    this.name,
    this.isTestAccount = false,
  });

  final String uid;
  final String? nickname;
  final String? name;
  final bool isTestAccount;

  /// 표에 그대로 넣는 표기. 닉네임도 실명도 없으면 uid 앞자리로 대신한다.
  String get displayLabel {
    final nick = (nickname ?? '').trim();
    final real = (name ?? '').trim();
    if (nick.isNotEmpty && real.isNotEmpty) return '$nick ($real)';
    if (nick.isNotEmpty) return nick;
    if (real.isNotEmpty) return real;
    return uid.length > 8 ? '${uid.substring(0, 8)}…' : uid;
  }

  /// 검색 대상 문자열 — 닉네임·실명·UID.
  bool matches(String lowerQuery) =>
      uid.toLowerCase().contains(lowerQuery) ||
      (nickname ?? '').toLowerCase().contains(lowerQuery) ||
      (name ?? '').toLowerCase().contains(lowerQuery);

  static const unknown = SellerIdentity(uid: '');
}

/// 한 번 읽어 온 결과.
class AdminSalesData {
  const AdminSalesData({
    this.entries = const [],
    this.sellers = const {},
    this.truncated = false,
    this.truncatedSources = const [],
    this.fetchedRange,
  });

  /// 기간·유형 필터는 [HostSalesStats.from]·[SellerSales.group]이 한다.
  final List<SalesEntry> entries;

  /// uid → 판매자 신원.
  final Map<String, SellerIdentity> sellers;

  /// 한 소스라도 상한(서버 5,000건)에 걸려 잘렸는지 — 숫자가 실제보다 작다는
  /// 뜻이므로 화면이 반드시 밝혀야 한다.
  final bool truncated;
  final List<String> truncatedSources;

  /// 이 데이터가 담고 있는 구간. 사용자가 더 넓은 기간을 고르면 다시 읽는다.
  final DateRange? fetchedRange;

  SellerIdentity sellerOf(String uid) =>
      sellers[uid] ?? SellerIdentity(uid: uid);
}

class AdminSalesService {
  AdminSalesService._();

  /// [range] 구간의 신청/예약 원자료를 받아 [SalesEntry]로 바꾼다.
  ///
  /// [hostId]를 주면 그 판매자 것만 읽는다 — 판매자 상세는 전체를 다시 받을
  /// 필요가 없다(서버 읽기와 응답 크기가 함께 줄어든다).
  static Future<AdminSalesData> fetch({
    required DateRange range,
    String? hostId,
  }) async {
    final result =
        await FirebaseFunctions.instanceFor(region: _functionsRegion)
            .httpsCallable('adminGetSalesEntries')
            .call<Map<Object?, Object?>>({
              'sinceMs': range.start.millisecondsSinceEpoch,
              'untilMs': range.end.millisecondsSinceEpoch,
              if (hostId != null && hostId.isNotEmpty) 'hostId': hostId,
            });

    final data = result.data;
    final rawRows = (data['rows'] as List<Object?>?) ?? const [];

    final entries = <SalesEntry>[];
    for (final raw in rawRows) {
      if (raw is! Map) continue;
      final row = raw.cast<Object?, Object?>();
      final source = SalesSource.fromCollection(row['collection'] as String?);
      if (source == null) continue;
      final doc = (row['data'] as Map?)?.map(
        (k, v) => MapEntry(k.toString(), v),
      );
      if (doc == null) continue;

      // ★ 호스트 앱과 같은 함수. 여기서 금액을 다시 계산하지 않는다.
      final entry = SalesEntryMapper.fromDocument(
        doc,
        source: source,
        id: row['id'] as String? ?? '',
        contentTitle: row['contentTitle'] as String?,
      );
      if (entry != null) entries.add(entry);
    }

    final rawHosts = (data['hosts'] as Map?) ?? const {};
    final sellers = <String, SellerIdentity>{};
    for (final e in rawHosts.entries) {
      final uid = e.key.toString();
      final v = (e.value as Map?)?.cast<Object?, Object?>() ?? const {};
      sellers[uid] = SellerIdentity(
        uid: uid,
        nickname: v['nickname'] as String?,
        name: v['name'] as String?,
        isTestAccount: v['isTestAccount'] == true,
      );
    }

    return AdminSalesData(
      entries: entries,
      sellers: sellers,
      truncated: data['truncated'] == true,
      truncatedSources: [
        for (final s in (data['truncatedSources'] as List<Object?>?) ?? const [])
          s.toString(),
      ],
      fetchedRange: range,
    );
  }
}
