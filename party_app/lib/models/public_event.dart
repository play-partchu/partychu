import 'package:cloud_firestore/cloud_firestore.dart';

/// 공공 축제·행사 한 건 — `publicEvents/{tour_<contentid>}`.
///
/// 한국관광공사 TourAPI(searchFestival2)에서 서버(functions/tourFestivals.js의
/// syncTourFestivals)가 **Admin SDK로만** 써 넣는다. 앱은 읽기만 한다 —
/// 규칙이 클라이언트 쓰기를 전부 막고(`allow write: if false`), 이 모델에도
/// toMap이 없다.
///
/// 사용자가 등록한 이벤트([PlacePromotion], placePromotions)와는 컬렉션부터
/// 다르다. 파티츄 장소에 매달리지 않고 자기 주소·좌표·사진을 직접 갖는다.
///
/// null 여부는 **서버 매핑**을 기준으로 정했다. 운영 문서에서 지금 비어
/// 있지 않은 필드라도 서버가 null로 쓸 수 있으면 nullable이다(예: 좌표·사진은
/// 원본에 없으면 null로 저장된다).
///   · 항상 있음 : source, sourceId, title, startAt/endAt, startDate/endDate,
///                attribution, status, isVisible
///   · 없을 수 있음: address, addressDetail, tel, zipcode, regionCode,
///                sigunguCode, 좌표(location), imageUrl, thumbnailUrl,
///                copyrightType, contentTypeId, sourceModifiedTime
///
/// 상세 보강 필드(서버가 TourAPI detailCommon2·Intro2·Image2·Info2로
/// 채운다)는 **전부 없을 수 있다.** 보강은 매일 호출 예산 안에서 차례로
/// 들어가서 보강 전 문서에는 필드 자체가 없고, 보강된 문서도 원본이 비어 있으면
/// null로 저장된다.
///   · 글자: overview, program, homepageUrl, organizer, host, contactName,
///          feeText, playTime, eventPlace — 서버에서 string 또는 null
///   · 사진: images — string 배열(대표 사진이 첫 장, 최대 10장), 없으면 []
///   · 보강 구성 2·3: ageLimit, spendTime, bookingInfo, bookingUrl,
///          discountInfo, subEvent, placeInfo, hostTel, festivalGrade,
///          performers — string 또는 null, extraInfo — {title, text} 배열
///
/// '선택안함'·'-' 같은 자리표시 값은 서버가 걸러 저장하지만, 예전에 저장된
/// 값이 있을 수 있어 읽을 때 한 번 더 null로 본다([_info]).
///
/// 서버 관리용 필드(contentHash, schemaVersion, missingCount, lastSyncRunId,
/// createdAt·updatedAt·lastSyncedAt, detailFetchedModifiedTime)는 화면에 쓸
/// 일이 없어 담지 않는다.
class PublicEvent {
  const PublicEvent({
    required this.id,
    required this.source,
    required this.sourceId,
    required this.title,
    required this.startAt,
    required this.endAt,
    required this.startDate,
    required this.endDate,
    required this.attribution,
    required this.status,
    required this.isVisible,
    this.sourceType,
    this.contentTypeId,
    this.address,
    this.addressDetail,
    this.zipcode,
    this.tel,
    this.regionCode,
    this.sigunguCode,
    this.categoryCodes = const [],
    this.lat,
    this.lng,
    this.imageUrl,
    this.thumbnailUrl,
    this.copyrightType,
    this.sourceModifiedTime,
    this.overview,
    this.program,
    this.homepageUrl,
    this.organizer,
    this.host,
    this.contactName,
    this.feeText,
    this.playTime,
    this.eventPlace,
    this.images = const [],
    this.ageLimit,
    this.spendTime,
    this.bookingInfo,
    this.bookingUrl,
    this.discountInfo,
    this.subEvent,
    this.placeInfo,
    this.hostTel,
    this.festivalGrade,
    this.performers,
    this.extraInfo = const [],
  });

  static const String statusActive = 'active';
  static const String statusEnded = 'ended';
  static const String statusRemoved = 'removed';

  /// 문서 id — `tour_<contentid>`.
  final String id;

  /// 원본 — 지금은 'tourapi' 하나다.
  final String source;

  /// 원본 id(TourAPI contentid).
  final String sourceId;

  /// 원본 안에서의 종류 — 'festival'.
  final String? sourceType;

  /// TourAPI 콘텐츠 타입('15' = 축제·공연·행사).
  final String? contentTypeId;

  final String title;

  /// 시작일 00:00(KST). 서버가 원본 날짜(YYYYMMDD)를 한국 시각 하루
  /// 경계로 바꿔 저장한다.
  final DateTime startAt;

  /// 종료일 23:59:59.999(KST).
  final DateTime endAt;

  /// 원본 날짜 그대로(YYYYMMDD) — 표시용 기간 문자열을 만들 때 시간대 계산
  /// 없이 쓸 수 있다.
  final String startDate;
  final String endDate;

  final String? address;
  final String? addressDetail;
  final String? zipcode;
  final String? tel;

  /// 법정동 시도 코드 2자리(예 '11' 서울).
  final String? regionCode;

  /// 법정동 시군구 코드 5자리(시도 2 + 시군구 3, 예 '11740' 강동구).
  final String? sigunguCode;

  /// TourAPI 분류 코드(lclsSystm1~3, 예 ['EV', 'EV01', 'EV010400']).
  final List<String> categoryCodes;

  /// 좌표 — 원본에 없거나 한국 범위 밖이면 서버가 location을 null로 둔다.
  final double? lat;
  final double? lng;

  final String? imageUrl;
  final String? thumbnailUrl;

  /// 공공누리 유형(원본 cpyrhtDivCd, 예 'Type3').
  final String? copyrightType;

  /// 출처 표기 — '한국관광공사'.
  final String attribution;

  /// active / ended / removed.
  final String status;

  /// 서버가 계산한 노출 여부(active이면서 관리자 숨김이 아님).
  final bool isVisible;

  /// 원본 수정 시각(YYYYMMDDHHmmss, KST).
  final String? sourceModifiedTime;

  // ── 상세 보강(없을 수 있음) ──

  /// 축제 소개(detailCommon2 overview). 줄바꿈이 들어 있을 수 있다.
  final String? overview;

  /// 프로그램(detailIntro2 program). 원본 줄바꿈 그대로.
  final String? program;

  /// 공식 홈페이지 — 서버가 http(s) 주소만 저장한다.
  final String? homepageUrl;

  /// 주최(sponsor1).
  final String? organizer;

  /// 주관(sponsor2).
  final String? host;

  /// 문의처 이름(telname). 전화번호는 [tel].
  final String? contactName;

  /// 이용요금(자유 텍스트, 예 '무료(일부 유료)').
  final String? feeText;

  /// 운영 시간(자유 텍스트, 예 '10:00~22:00').
  final String? playTime;

  /// 행사 장소 이름(예 '서울 암사동 유적') — 주소와 별개.
  final String? eventPlace;

  /// 사진 주소들 — 대표 사진 + 상세 사진(서버가 중복 제거, 최대 10장).
  /// 보강 전 문서는 [].
  final List<String> images;

  /// 관람 연령(agelimit, 예 '전 연령'·'13세 이상').
  final String? ageLimit;

  /// 관람 소요시간(spendtimefestival, 예 '약 90분').
  final String? spendTime;

  /// 예매 정보 원문(bookingplace) — 글자만 올 수도 있다.
  final String? bookingInfo;

  /// 예매 링크 — 예매 정보 안에 안전한 http(s) 주소가 있을 때만.
  final String? bookingUrl;

  /// 할인 정보(discountinfofestival).
  final String? discountInfo;

  /// 부대행사(subevent). 줄바꿈이 있을 수 있다.
  final String? subEvent;

  /// 행사장 위치 안내(placeinfo).
  final String? placeInfo;

  /// 주관 쪽 전화(sponsor2tel). 주최 전화는 [tel]과 같아 따로 없다.
  final String? hostTel;

  /// 축제 등급(festivalgrade, 예 '문화관광축제').
  final String? festivalGrade;

  /// 출연진(detailInfo2 '출연' 줄).
  final String? performers;

  /// detailInfo2의 그 밖의 줄 — 소개·프로그램과 겹치지 않는 것만.
  final List<PublicEventInfoItem> extraInfo;

  bool get hasLocation => lat != null && lng != null;

  /// [at] 기준으로 아직 끝나지 않았는가.
  bool isOpenAt(DateTime at) => !endAt.isBefore(at);

  /// [at] 기준으로 진행 중인가(시작했고 끝나지 않음).
  bool isOngoingAt(DateTime at) => !startAt.isAfter(at) && isOpenAt(at);

  /// 📅 고른 날 [day](그 날 00:00~24:00, 기기 시간대)에 행사 기간이 걸치는가.
  ///
  /// 공공 축제는 기간만 있고 진행 시각이 없다 — 시각을 안 정한 이벤트는
  /// 전시간으로 보는 파티츄 이벤트 규칙과 같이, 🕐 시간 조건으로는 거르지
  /// 않고 날짜로만 거른다.
  bool overlapsDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = DateTime(day.year, day.month, day.day + 1);
    return startAt.isBefore(dayEnd) && !endAt.isBefore(dayStart);
  }

  /// 문서 한 건 → 모델. 서버가 항상 쓰는 필수값(제목·기간)이 없거나 형식이
  /// 깨졌으면 null — 화면에 그릴 수 없는 문서는 조회 단계에서 빠진다.
  static PublicEvent? tryFromMap(String id, Map<String, dynamic> d) {
    final title = _text(d['title']);
    final startAt = _dateFrom(d['startAt']);
    final endAt = _dateFrom(d['endAt']);
    if (title == null || startAt == null || endAt == null) return null;
    final location = d['location'];
    double? coord(String key) =>
        location is Map ? (location[key] as num?)?.toDouble() : null;
    return PublicEvent(
      id: id,
      source: _text(d['source']) ?? '',
      sourceId: _text(d['sourceId']) ?? '',
      sourceType: _text(d['sourceType']),
      contentTypeId: _text(d['contentTypeId']),
      title: title,
      startAt: startAt,
      endAt: endAt,
      startDate: _text(d['startDate']) ?? '',
      endDate: _text(d['endDate']) ?? '',
      address: _text(d['address']),
      addressDetail: _text(d['addressDetail']),
      zipcode: _text(d['zipcode']),
      tel: _text(d['tel']),
      regionCode: _text(d['regionCode']),
      sigunguCode: _text(d['sigunguCode']),
      categoryCodes: _list(d['categoryCodes']).whereType<String>().toList(),
      lat: coord('lat'),
      lng: coord('lng'),
      imageUrl: _text(d['imageUrl']),
      thumbnailUrl: _text(d['thumbnailUrl']),
      copyrightType: _text(d['copyrightType']),
      attribution: _text(d['attribution']) ?? '한국관광공사',
      status: _text(d['status']) ?? '',
      isVisible: d['isVisible'] as bool? ?? false,
      sourceModifiedTime: _text(d['sourceModifiedTime']),
      overview: _info(d['overview']),
      program: _info(d['program']),
      homepageUrl: _info(d['homepageUrl']),
      organizer: _info(d['organizer']),
      host: _info(d['host']),
      contactName: _info(d['contactName']),
      feeText: _info(d['feeText']),
      playTime: _info(d['playTime']),
      eventPlace: _info(d['eventPlace']),
      images: _list(d['images']).map(_text).whereType<String>().toList(),
      ageLimit: _info(d['ageLimit']),
      spendTime: _info(d['spendTime']),
      bookingInfo: _info(d['bookingInfo']),
      bookingUrl: _info(d['bookingUrl']),
      discountInfo: _info(d['discountInfo']),
      subEvent: _info(d['subEvent']),
      placeInfo: _info(d['placeInfo']),
      hostTel: _info(d['hostTel']),
      festivalGrade: _info(d['festivalGrade']),
      performers: _info(d['performers']),
      extraInfo: [
        for (final e in _list(d['extraInfo'])) ?PublicEventInfoItem.tryFrom(e),
      ],
    );
  }
}

/// 글자 — 앞뒤 공백만 걷는다(안의 줄바꿈은 그대로라 program 등에 그대로 쓴다).
String? _text(dynamic v) {
  if (v is! String) return null;
  final s = v.trim();
  return s.isEmpty ? null : s;
}

/// 배열 칸 — 배열이 아니면(없음·잘못된 타입) 빈 목록. 한 칸이 틀려도 문서
/// 전체를 못 읽는 일이 없게 한다.
List<dynamic> _list(dynamic v) => v is List ? v : const [];

/// 공공 데이터의 자리표시 값 — 값이 없는 것과 같다.
const Set<String> _placeholderValues = {
  '선택안함',
  '선택 안함',
  '없음',
  '해당없음',
  '해당 없음',
  '-',
  '--',
  '.',
  'x',
  'X',
  'n/a',
  'N/A',
};

/// 보강 필드 글자 — [_text]에 자리표시 값 거르기를 더한다.
String? _info(dynamic v) {
  final s = _text(v);
  return s == null || _placeholderValues.contains(s) ? null : s;
}

/// detailInfo2의 제목 있는 줄 하나(extraInfo 항목).
class PublicEventInfoItem {
  const PublicEventInfoItem({required this.title, required this.text});

  final String title;
  final String text;

  /// {title, text} 맵 → 항목. 둘 중 하나라도 비었으면 null(그리지 않는다).
  static PublicEventInfoItem? tryFrom(dynamic v) {
    if (v is! Map) return null;
    final title = _info(v['title']);
    final text = _info(v['text']);
    if (title == null || text == null) return null;
    return PublicEventInfoItem(title: title, text: text);
  }
}

DateTime? _dateFrom(dynamic v) {
  if (v == null) return null;
  if (v is Timestamp) return v.toDate();
  if (v is DateTime) return v;
  if (v is num) return DateTime.fromMillisecondsSinceEpoch(v.toInt());
  return null;
}
