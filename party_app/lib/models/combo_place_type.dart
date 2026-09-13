import 'package:flutter/material.dart';

import 'package:party_app/models/draft_type.dart';

/// 공간 등록 화면 최상단에서 고르는 **공간 유형** — "어떤 공간인가요?".
///
/// 이름에 `Combo`가 남아 있는 것은 Firestore 필드(`comboPlaceType`)와 맞추기
/// 위해서다 — **플레이스+파티 콤보 등록은 없어졌지만 이 enum은 남는다.**
/// 지금 하는 일은 둘이다.
///
///  1. 신규 플레이스 등록의 **공간 유형 선택**
///     (`place_entry_register_screen.dart` → 매장·즐길거리 / 공간대여·숙박).
///  2. 콤보로 **이미 만들어진 문서**를 읽을 때의 유형 판정
///     ([ofDoc]·[ofPartyDoc] — 목록 카드 배지 등).
///
/// 유형에 대한 판정은 어디서도 다시 만들지 않고 여기만 본다.
///
/// 예전에는 등록 유형 화면에 "플레이스+파티 등록"과 "숙박+파티 등록"이 서로
/// 다른 카드로 나뉘어 있었다. 사용자 입장에서는 "내 공간이 어떤 종류인가"를
/// 고르는 것이 자연스러워서, 진입은 하나로 합치고 화면 안에서 이 유형을
/// 고르게 바꿨다. 단독 등록도 같은 이유로 "플레이스 등록"/"파티 장소 등록"
/// 두 카드를 하나로 합쳤고, 지금은 그 단독 등록 하나만 남았다.
///
/// **저장 스키마는 유형별로 예전 그대로다.**
///  - [venue] : `events`
///  - [stay]  : `places` + `placeRooms`
///
/// (콤보로 등록된 옛 문서는 여기에 `parties`가 더 붙어 있고 `isCombo: true`를
///  갖는다 — 그 문서의 조회·예약·취소는 지금도 그대로 동작한다.)
///
/// 만들어진 문서에는 [key]가 `comboPlaceType` 필드로 함께 기록된다 — 예전
/// 문서에는 이 필드가 없으므로, 읽는 쪽은 반드시 [fromKey]처럼 "없으면
/// 컬렉션으로 판단"하는 하위호환 경로를 유지해야 한다.
/// 두 유형을 가르는 기준은 "손님이 어떻게 오는가"다 — 문 열고 들어오는
/// **방문형 플레이스**([venue])냐, 미리 잡고 오는 **예약형 공간**([stay])이냐.
/// 그래서 대관 공간처럼 예약을 받아야 하는 곳은 매장 쪽이 아니라 [stay]에
/// 속한다([kindLabel]로 선택 카드에도 이 기준을 드러낸다).
enum ComboPlaceType {
  /// 매장·즐길거리 — 예약 없이 방문해서 이용하는 플레이스.
  ///
  /// 홈의 플레이스 대분류([PlaceTaxonomy.all]) **전부**가 여기 들어온다 —
  /// 푸드·다이닝·카페·술집·혼술바·BAR·클럽·댄스·라이브·놀거리·체험/클래스.
  /// 은퇴한 대분류(BAR·라이브)도 예시에 남긴다 — 그 값으로 등록된 가게가
  /// 여전히 이 유형에 속하고, 사장님이 자기 가게를 알아보는 말이기 때문이다.
  /// 예전에는
  /// 이름과 예시가 "술집·바·카페"로 좁아, 클럽·라이브·놀거리·체험 사장님이
  /// 이 유형을 자기 것이 아니라고 지나쳤다.
  venue(
    key: 'venue',
    label: '매장·즐길거리',
    kindLabel: '방문형 플레이스',
    examples:
        '음식점, 다이닝, 카페, 술집, 혼술바, BAR, 클럽·댄스, 라이브, 놀거리, 체험·클래스 등',
    emoji: '🏪',
    accent: Color(0xFFFF6FA0),
    tint: Color(0xFFFFF0F5),
    soloDraftType: DraftType.event,
    typeSpecificResetNotice: '운영시간·특징 태그·좌석/공간·참가비 등 매장·즐길거리 전용 입력값',
  ),

  /// 공간대여·숙박 — 공간(룸) 단위로 예약을 받는 공간. 숙박 예약뿐 아니라
  /// 시간제 예약·패키지 예약까지 이 유형이 맡는다.
  stay(
    key: 'stay',
    label: '공간대여·숙박',
    kindLabel: '예약형 공간',
    examples:
        '파티룸, 스튜디오, 회의실, 연습실, 행사장, 대관 공간, '
        '호텔, 모텔, 펜션, 게스트하우스 등',
    emoji: '🏠',
    accent: Color(0xFF7C5CBF),
    tint: Color(0xFFF3EFFA),
    soloDraftType: DraftType.place,
    typeSpecificResetNotice:
        '공간(객실)·체크인/체크아웃·편의시설·참가비 등 '
        '공간대여·숙박 전용 입력값',
  );

  const ComboPlaceType({
    required this.key,
    required this.label,
    required this.kindLabel,
    required this.examples,
    required this.emoji,
    required this.accent,
    required this.tint,
    required this.soloDraftType,
    required this.typeSpecificResetNotice,
  });

  /// Firestore 문서(`comboPlaceType`)와 임시저장 payload에 쓰는 안정적 식별자.
  final String key;

  /// 선택 카드에 보이는 유형 이름.
  final String label;

  /// 유형 이름 옆 작은 배지 — 방문형/예약형 중 어느 쪽인지 한눈에 가른다.
  /// 대관 공간처럼 "카페 같기도, 대여 같기도" 한 곳을 사장님이 헷갈리지 않고
  /// 고르게 하는 게 목적이다.
  final String kindLabel;

  /// 선택 카드 두 번째 줄 — 어떤 공간이 여기 해당하는지 예시.
  final String examples;

  final String emoji;

  /// 유형별 강조 색 — 예전 두 화면이 각각 쓰던 색을 그대로 유지한다.
  final Color accent;

  /// [accent]의 옅은 배경색.
  final Color tint;

  /// 이 유형의 플레이스 등록이 쓰는 임시저장 종류.
  ///
  /// 새로 만들지 않고 예전부터 쓰던 두 종류를 그대로 가리킨다 — 그래야
  /// "플레이스 등록"/"파티 장소 등록"이 하나로 합쳐지기 전에 저장해둔
  /// 임시저장이 새 화면에서도 그대로 열린다([DraftType.event] = 옛 플레이스
  /// 등록, [DraftType.place] = 옛 파티 장소 등록).
  ///
  /// 이름의 `solo`는 "파티를 함께 만들지 않는다"는 뜻이었다 — 콤보 등록이
  /// 없어져 이제 플레이스 임시저장은 이것뿐이지만, 이름을 바꾸면 이 값을
  /// 읽는 자리가 전부 흔들려서 그대로 둔다.
  final DraftType soloDraftType;

  /// 유형을 바꿀 때 "어떤 입력값이 이 유형에만 남는지" 알려주는 문구.
  final String typeSpecificResetNotice;

  /// 이 유형이 만드는 플레이스 문서의 컬렉션 이름(문서 스키마 구분용).
  String get placeCollection => switch (this) {
    ComboPlaceType.venue => 'events',
    ComboPlaceType.stay => 'places',
  };

  /// 알 수 없는/없는 값이면 [venue]로 본다 — 통합 화면의 기본 선택과 같다.
  static ComboPlaceType fromKey(String? key) {
    for (final t in ComboPlaceType.values) {
      if (t.key == key) return t;
    }
    return ComboPlaceType.venue;
  }

  /// 임시저장 종류로 공간 유형을 되찾는다 — 임시저장 종류가 곧 공간 유형이라,
  /// 마이페이지 "이어서 작성"이 이 값으로 어느 유형을 열지 정한다.
  static ComboPlaceType fromDraftType(DraftType? type) {
    for (final t in ComboPlaceType.values) {
      if (t.soloDraftType == type) return t;
    }
    return ComboPlaceType.venue;
  }

  /// 콤보로 등록된 문서인지 + **어떤 유형의** 콤보인지 — 콤보가 아니면 null.
  ///
  /// `isCombo`는 두 유형이 **공유하는** 플래그다(플레이스+파티 콤보의
  /// `events`/`parties` 문서도 `true`). 그래서 `isCombo`만 보고 "숙박이다"라고
  /// 판단하면 매장·즐길거리(=[venue])까지 숙박으로 새어 나온다. 유형이 필요한
  /// 곳(숙박 전용 배지·문구 등)은 반드시 이 함수로만 판정한다.
  ///
  /// `comboPlaceType`이 없는 예전 문서는 [fallback]으로 본다 — 호출부가 문서가
  /// 어느 컬렉션/어느 연결 필드에서 왔는지로 정해서 넘긴다.
  static ComboPlaceType? ofDoc(
    Map<String, dynamic> data, {
    required ComboPlaceType fallback,
  }) {
    if (data['isCombo'] != true) return null;
    final key = data['comboPlaceType'] as String?;
    if (key == null || key.isEmpty) return fallback;
    return fromKey(key);
  }

  /// 파티 문서(`parties`)의 콤보 유형 — 콤보가 아니면 null.
  ///
  /// `comboPlaceType`이 없는 예전 문서는 연결 필드로 가른다 — 매장 콤보 파티는
  /// `linkedEventId`(events), 숙박 콤보 파티는 `linkedPlaceId`(places)를 갖는다.
  /// 둘 다 없으면 숙박이라고 단정할 근거가 없으므로 [venue]로 둔다.
  static ComboPlaceType? ofPartyDoc(Map<String, dynamic> data) => ofDoc(
    data,
    fallback: data['linkedEventId'] == null && data['linkedPlaceId'] != null
        ? ComboPlaceType.stay
        : ComboPlaceType.venue,
  );
}
