import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'package:party_app/models/custom_amenity.dart';

/// 등록 화면의 **자동완성 후보**를 위해 "이미 쓰이고 있는 기타 편의 서비스"를
/// 읽어 온다.
///
/// ── 왜 전용 조회가 필요한가 ───────────────────────────────────────────────
/// 게스트 화면(목록·지도)은 events/places를 이미 통째로 메모리에 들고 있어서
/// 목록을 만드는 데 추가 읽기가 필요 없다([CustomAmenities.catalogOf]에 그
/// 문서를 그대로 넘긴다). 하지만 **등록 화면**은 자기 문서 하나만 다루므로
/// 후보를 만들려면 따로 읽어야 한다.
///
/// ── 무제한으로 읽지 않는 두 가지 장치 ─────────────────────────────────────
///  1. `orderBy(customAmenities)` — Firestore는 정렬 필드가 **없는 문서를
///     제외**한다. 그래서 기타를 하나라도 등록한 문서만 내려온다(대부분의
///     문서는 이 필드가 없다).
///  2. [_perCollectionLimit] — 컬렉션당 상한을 둔다. 후보는 "새 말을 만들기
///     전에 기존 말을 보여주는" 용도라 전수가 필요 없다.
///
/// 결과는 **앱 실행 중 한 번만** 읽고 캐시한다. 등록 화면을 열고 닫을 때마다
/// 같은 쿼리를 반복하지 않기 위함이다.
class CustomAmenityCatalogService {
  CustomAmenityCatalogService._();

  /// 컬렉션당 읽기 상한.
  static const int _perCollectionLimit = 200;

  static List<CustomAmenityEntry>? _cache;
  static Future<List<CustomAmenityEntry>>? _inFlight;

  /// 테스트·재조회용 — 다음 호출에서 다시 읽는다.
  @visibleForTesting
  static void resetCache() {
    _cache = null;
    _inFlight = null;
  }

  /// 이미 읽어 둔 후보가 있으면 그것 — 없으면 빈 목록(조회를 기다리지 않는다).
  /// 첫 프레임을 후보 때문에 막지 않으려는 동기 접근자다.
  static List<CustomAmenityEntry> get cached => _cache ?? const [];

  /// 후보 목록. 실패하면 빈 목록 — 자동완성이 없다고 등록을 막을 이유는 없다.
  static Future<List<CustomAmenityEntry>> load() {
    final cached = _cache;
    if (cached != null) return Future.value(cached);
    return _inFlight ??= _load()
        .then((v) {
          _cache = v;
          _inFlight = null;
          return v;
        })
        .catchError((Object e) {
          debugPrint('[CustomAmenityCatalog] 후보 조회 실패: $e');
          _inFlight = null;
          return const <CustomAmenityEntry>[];
        });
  }

  static Future<List<CustomAmenityEntry>> _load() async {
    final db = FirebaseFirestore.instance;
    final docs = <Map<String, dynamic>>[];
    for (final collection in const ['events', 'places']) {
      try {
        final snap = await db
            .collection(collection)
            // 이 필드가 없는 문서는 정렬에서 통째로 빠진다 — 곧 필터다.
            .orderBy(CustomAmenities.field)
            .limit(_perCollectionLimit)
            .get();
        docs.addAll(snap.docs.map((d) => d.data()));
      } catch (e) {
        // 한쪽 컬렉션이 실패해도 나머지 후보는 보여준다.
        debugPrint('[CustomAmenityCatalog] $collection 조회 실패: $e');
      }
    }
    return CustomAmenities.catalogOf(docs);
  }
}
