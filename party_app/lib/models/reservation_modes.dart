// ─────────────────────────────────────────────────────────────────────────────
// 장소대여 룸의 "예약 방식" — 숙박(1박) / 시간제 / 패키지를 복수 선택할 수 있는
// 구조. 호텔·모텔(대실)·게스트하우스·펜션·파티룸 등 업종마다 필요한 방식이
// 달라서 하나만 고르는 구조로는 표현할 수 없었다.
//
//   호텔/펜션      → 숙박
//   모텔           → 숙박 + 시간제(대실)
//   게스트하우스   → 숙박 + 패키지(도미토리 1인 요금 등)
//   파티룸         → 시간제 + 패키지
//
// Firestore 저장 형태 (placeRooms/{roomId}):
//   reservationModes: ['stay', 'hourly', 'package']  ← 새 정본(복수 선택)
//   reservationMode : 'stay'|'hourly'|'package'|'both'  ← 구버전 클라이언트용
//                     하위호환 미러(읽기 전용 취급, [legacyReservationMode])
// ─────────────────────────────────────────────────────────────────────────────

/// 예약 방식 한 가지. 화면 표시 순서도 이 선언 순서를 따른다(숙박 → 시간제 →
/// 패키지) — 공간대여·숙박 유형이 가장 먼저 만나는 방식이 숙박이기 때문.
enum ReservationMode {
  stay('stay', '🛏', '숙박'),
  hourly('hourly', '⏱', '시간제'),
  package('package', '📦', '패키지');

  const ReservationMode(this.key, this.emoji, this.label);

  /// Firestore에 저장되는 값.
  final String key;
  final String emoji;
  final String label;

  /// 칩/탭에 그대로 쓰는 문구 — "🛏 숙박".
  String get chipLabel => '$emoji $label';

  static ReservationMode? fromKey(String? key) {
    for (final m in ReservationMode.values) {
      if (m.key == key) return m;
    }
    return null;
  }
}

/// 시간제와 숙박이 **배타적이지 않다**는 안내 문구 — 목록 위 빠른 선택 시트와
/// 상세검색의 '예약 방식'이 같은 문장을 쓴다.
///
/// 한곳에 둔 이유는 문구 통일이 아니라 **판정과 설명이 갈리지 않게** 하려는
/// 것이다: 실제 판정([placeReservationModes])이 집합 포함 여부라서 두 방식을
/// 모두 받는 장소는 어느 쪽을 골라도 남는데, 한쪽 화면에서만 이 말을 지우면
/// 게스트는 그 화면을 '둘 중 하나로 분류하는 조건'으로 읽는다.
const String reservationModeOverlapHint = '시간제와 숙박을 모두 받는 장소는 어느 쪽을 골라도 보여요.';

/// 선택 집합을 항상 [ReservationMode] 선언 순서로 정렬해 돌려준다 — Set의
/// 순회 순서에 UI가 흔들리지 않게 하려는 것.
List<ReservationMode> sortedModes(Iterable<ReservationMode> modes) =>
    ReservationMode.values.where(modes.contains).toList();

/// 룸/장소 문서에서 예약 방식 목록을 읽는다.
///
/// 1. `reservationModes`(복수 선택 정본)가 있으면 그대로 쓴다.
/// 2. 없으면 구 스키마 `reservationMode` 문자열을 해석한다.
///    ('both'는 시간제+패키지였다.)
/// 3. 둘 다 없으면 패키지 데이터 유무로 추론한다 — 기존 문서는 이미 시간제
///    필드만 쓰고 있었으므로 'hourly'가 자연스러운 기본값이다.
Set<ReservationMode> parseReservationModes(Map<String, dynamic> data) {
  final raw = data['reservationModes'];
  if (raw is List) {
    final parsed = raw
        .map((e) => ReservationMode.fromKey(e as String?))
        .whereType<ReservationMode>()
        .toSet();
    if (parsed.isNotEmpty) return parsed;
  }

  switch (data['reservationMode'] as String?) {
    case 'both':
      return {ReservationMode.hourly, ReservationMode.package};
    case 'hourly':
      return {ReservationMode.hourly};
    case 'package':
      return {ReservationMode.package};
    // 'daily'는 옛 하루단위 대여 값 — 의미상 숙박에 가장 가깝다.
    case 'stay':
    case 'daily':
      return {ReservationMode.stay};
  }

  final packages = data['packages'];
  if (packages is List && packages.isNotEmpty) {
    return {ReservationMode.package};
  }
  return {ReservationMode.hourly};
}

/// 이 문서가 예약 방식을 **명시**했는가.
///
/// [parseReservationModes]는 명시가 없어도 반드시 한 가지를 돌려준다(옛 문서를
/// 위한 기본값 — 시간제). 그래서 값만 보면 "시간제다"와 "시간제라고 적혀
/// 있다"가 구별되지 않는데, 목록 필터에는 그 구별이 꼭 필요하다: 적혀 있지도
/// 않은 기본값이 장소 문서의 숙박 안내를 이기면 실제로 숙박을 받는 옛 장소가
/// '🛏 숙박'에서 통째로 빠진다([placeReservationModes] 참고).
///
/// 운영 `placeRooms` 문서에는 두 필드가 **아예 없다**(2026-08-26 확인) —
/// 지금은 이 함수가 false를 돌려주는 쪽이 오히려 정상이다.
bool declaresReservationModes(Map<String, dynamic> data) {
  final raw = data['reservationModes'];
  if (raw is List &&
      raw.any((e) => e is String && ReservationMode.fromKey(e) != null)) {
    return true;
  }
  // 'both'(시간제+패키지)·'daily'(옛 하루단위)도 명시로 친다 —
  // [parseReservationModes]가 뜻을 아는 값들이다.
  const legacyValues = {'stay', 'hourly', 'package', 'both', 'daily'};
  return legacyValues.contains(data['reservationMode']);
}

/// 요금 칸에 실제로 값이 들어 있는가 — 옛 룸의 예약 방식 근거.
bool _hasAmount(Object? value) => value is num && value > 0;

/// 예약 방식을 명시하지 않은 룸에서 **이미 저장돼 있는 값만으로** 읽어낼 수
/// 있는 예약 방식. 근거가 하나도 없으면 빈 집합이다 — 기본값은 여기서 만들지
/// 않는다(부르는 쪽이 더 나은 근거를 갖고 있을 수 있다).
///
/// 1박 요금이 적혀 있으면 숙박을, 시간당 요금이 적혀 있으면 시간제를 받는
/// 룸이다. 호스트는 쓰지 않는 방식의 요금 칸을 비워 두므로(빈 칸은 0으로
/// 저장된다) 이 둘은 서로를 배제하지 않는다 — 둘 다 적혀 있으면 둘 다다.
Set<ReservationMode> _inferredRoomModes(Map<String, dynamic> room) {
  final modes = <ReservationMode>{};
  if (_hasAmount(room['stayPricePerNight'])) modes.add(ReservationMode.stay);
  if (_hasAmount(room['pricePerHour'])) modes.add(ReservationMode.hourly);
  final packages = room['packages'];
  if (packages is List && packages.isNotEmpty) {
    modes.add(ReservationMode.package);
  }
  return modes;
}

/// 룸 하나가 **실제로 받는** 예약 방식 — 목록 필터([placeReservationModes]),
/// 이용 가능 판정([PlaceAvailability]), 상세의 요금 표기가 모두 이 하나를 쓴다.
/// 세 곳이 갈리면 "목록에는 숙박으로 떴는데 들어가면 숙박이 없는" 장소가 된다.
///
/// 명시값이 있으면 그것이 정본이고, 없으면 저장된 요금/패키지가 근거다.
/// 근거조차 없으면 예전 기본값 그대로([parseReservationModes] — 시간제).
Set<ReservationMode> roomReservationModes(Map<String, dynamic> room) {
  if (declaresReservationModes(room)) return parseReservationModes(room);
  final inferred = _inferredRoomModes(room);
  return inferred.isEmpty ? parseReservationModes(room) : inferred;
}

/// Firestore `reservationModes` 배열로 직렬화.
List<String> reservationModeKeys(Iterable<ReservationMode> modes) =>
    sortedModes(modes).map((m) => m.key).toList();

/// 구버전 클라이언트/서버가 읽는 `reservationMode` 문자열 미러.
///
/// 숙박은 옛 값에 없으므로, 함께 선택된 시간제/패키지가 있으면 그쪽을
/// 우선한다 — 업데이트 전 앱에서도 최소한 하나의 방식으로는 예약이 되게 하는
/// 안전한 축약이다.
String legacyReservationMode(Set<ReservationMode> modes) {
  final hourly = modes.contains(ReservationMode.hourly);
  final package = modes.contains(ReservationMode.package);
  if (hourly && package) return 'both';
  if (package) return 'package';
  if (hourly) return 'hourly';
  return 'stay';
}

// ─────────────────────────────────────────────────────────────────────────────
// 숙박(1박) 설정
// ─────────────────────────────────────────────────────────────────────────────

/// 숙박 예약에 필요한 값들 — 1박 요금과 체크인/체크아웃 시각, 숙박일 수 제한.
///
/// 체크인/체크아웃 시각은 "예약이 실제로 점유하는 시간 구간"을 정하는 값이라
/// 겹침 판정(서버 roomAvailability.js)에도 그대로 쓰인다. 예를 들어 체크인
/// 16:00 / 체크아웃 11:00 짜리 2박은 자정 기준 960분 ~ 3540분(2×1440+660)을
/// 점유하므로, 그 사이 어떤 시간제 예약도 받지 않는다.
class StayConfig {
  final int pricePerNight;

  /// 'HH:mm' 형식.
  final String checkInTime;
  final String checkOutTime;

  final int minNights;

  /// null이면 제한 없음.
  final int? maxNights;

  const StayConfig({
    required this.pricePerNight,
    required this.checkInTime,
    required this.checkOutTime,
    required this.minNights,
    required this.maxNights,
  });

  static const defaults = StayConfig(
    pricePerNight: 0,
    checkInTime: '16:00',
    checkOutTime: '11:00',
    minNights: 1,
    maxNights: null,
  );

  factory StayConfig.fromMap(Map<String, dynamic> d) => StayConfig(
    pricePerNight: (d['stayPricePerNight'] as num?)?.toInt() ?? 0,
    checkInTime: d['stayCheckInTime'] as String? ?? defaults.checkInTime,
    checkOutTime: d['stayCheckOutTime'] as String? ?? defaults.checkOutTime,
    minNights: (d['stayMinNights'] as num?)?.toInt() ?? 1,
    maxNights: (d['stayMaxNights'] as num?)?.toInt(),
  );

  Map<String, dynamic> toMap() => {
    'stayPricePerNight': pricePerNight,
    'stayCheckInTime': checkInTime,
    'stayCheckOutTime': checkOutTime,
    'stayMinNights': minNights,
    'stayMaxNights': maxNights,
  };

  int get checkInMinutes => parseHhmm(checkInTime);
  int get checkOutMinutes => parseHhmm(checkOutTime);

  int priceForNights(int nights) => pricePerNight * nights;

  /// [nights]박이 자정 기준으로 점유하는 분(minute) 구간의 길이.
  int minutesForNights(int nights) =>
      nights * 1440 + checkOutMinutes - checkInMinutes;

  /// 선택 가능한 숙박일 수 후보 — 최대가 없으면 [fallbackMax]박까지 제안한다.
  List<int> nightOptions({int fallbackMax = 14}) {
    final max = maxNights ?? fallbackMax;
    return [for (int n = minNights; n <= max; n++) n];
  }
}

/// 'HH:mm' → 자정 기준 분. 형식이 어긋나면 0.
int parseHhmm(String? t) {
  if (t == null || !t.contains(':')) return 0;
  final parts = t.split(':');
  final h = int.tryParse(parts[0]) ?? 0;
  final m = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
  return h * 60 + m;
}

// ─────────────────────────────────────────────────────────────────────────────
// 장소 문서 집계 — 상세검색 필터/카드 요금 표시에 쓰는 대표 가격
// ─────────────────────────────────────────────────────────────────────────────

/// 장소 카드/필터에 쓰는 대표 요금과 그 단위.
typedef PlacePriceSummary = ({int price, String unit});

/// 룸 목록에서 대표 요금을 뽑는다 — 시간제 룸이 하나라도 있으면 시간당 최저가,
/// 전부 숙박 전용이면 1박 최저가를 쓴다. 숙박 전용 장소의 카드가 "₩0 / 시간"
/// 으로 보이던 문제를 없애기 위한 것.
PlacePriceSummary placePriceSummary(List<Map<String, dynamic>> rooms) {
  final hourly = <int>[];
  final nightly = <int>[];
  for (final r in rooms) {
    final modes = roomReservationModes(r);
    if (modes.contains(ReservationMode.hourly)) {
      final p = (r['pricePerHour'] as num?)?.toInt() ?? 0;
      if (p > 0) hourly.add(p);
    }
    if (modes.contains(ReservationMode.stay)) {
      final p = (r['stayPricePerNight'] as num?)?.toInt() ?? 0;
      if (p > 0) nightly.add(p);
    }
  }
  if (hourly.isNotEmpty) {
    return (price: hourly.reduce((a, b) => a < b ? a : b), unit: 'hour');
  }
  if (nightly.isNotEmpty) {
    return (price: nightly.reduce((a, b) => a < b ? a : b), unit: 'night');
  }
  return (price: 0, unit: 'hour');
}

/// 장소 하나가 실제로 받는 예약 방식 — 목록 위 빠른 선택('전체/⏱ 시간제/
/// 🛏 숙박')과 상세검색의 "예약 방식"이 **같은 이 함수**를 쓴다.
///
/// **룸이 정본이다** — 예약 방식은 룸마다 다르다(모텔은 숙박+시간제, 파티룸은
/// 시간제만). 두 방식을 모두 받는 장소는 집합에 둘 다 담기므로 **두 조건
/// 모두에서 걸린다**. 하나로 줄이지 않는다.
///
/// 새 필드는 만들지 않는다. 근거는 아래 세 층이고, 위층이 있으면 아래층은
/// 보지 않는다:
///
/// 1. **룸이 명시한 값** — `reservationModes`(정본) 또는 구 스키마
///    `reservationMode`. 명시가 있으면 그것으로 끝이다: 장소 문서에 남아 있는
///    옛 숙박 안내로 **없는 숙박을 만들어내지 않는다**(호스트가 룸에서 숙박을
///    껐는데 목록에는 계속 뜨는 일이 생긴다).
/// 2. **룸에 저장된 값에서 읽어낸 근거** — 1박 요금/시간당 요금/패키지
///    ([_inferredRoomModes]). 옛 룸에는 1의 두 필드가 아예 없다.
/// 3. **장소 문서의 숙박 안내** — 체크인/체크아웃 시각. 이건 **1이 없는 룸이
///    있을 때만** 더한다. 이 한 줄이 없으면 "명시가 없으면 시간제"라는
///    [parseReservationModes]의 기본값이 장소 문서의 숙박 안내를 덮어써서,
///    실제로 숙박을 받는 옛 장소가 '🛏 숙박'에서 통째로 빠진다.
Set<ReservationMode> placeReservationModes(
  Map<String, dynamic> place, {
  List<Map<String, dynamic>> rooms = const [],
}) {
  final modes = <ReservationMode>{};

  // 1·2층 — 룸.
  var anyRoomUndeclared = false;
  for (final room in rooms) {
    if (declaresReservationModes(room)) {
      modes.addAll(parseReservationModes(room));
    } else {
      anyRoomUndeclared = true;
      // 기본값이 아니라 **근거만** 모은다 — 근거가 없는 룸이 시간제로
      // 굳어 버리면 3층(숙박 안내)이 무의미해진다.
      modes.addAll(_inferredRoomModes(room));
    }
  }

  // 장소 문서의 명시값은 룸이 하나도 없을 때만 쓴다(룸이 정본이므로).
  if (rooms.isEmpty && declaresReservationModes(place)) {
    modes.addAll(parseReservationModes(place));
  }

  // 3층 — 숙박 안내. 룸이 없거나, 예약 방식을 명시하지 않은 룸이 있을 때만.
  if ((rooms.isEmpty || anyRoomUndeclared) && placeDocSuggestsStay(place)) {
    modes.add(ReservationMode.stay);
  }

  if (modes.isNotEmpty) return modes;

  // 어느 층에도 근거가 없는 옛 문서 — 예전 그대로의 기본값(시간제).
  return parseReservationModes(place);
}

/// 목록에서 이 장소를 남길지 — 목록 위 빠른 선택과 상세검색이 **같은 한 줄**을
/// 쓴다(둘이 같은 조건 한 칸을 공유하므로 판정도 하나여야 한다).
///
/// [wanted]가 null('전체')이면 거르지 않고, 그 밖에는 **집합에 들어 있는지만**
/// 본다 — 그래서 시간제와 숙박을 모두 받는 장소는 어느 쪽을 골라도 남는다.
/// 여기에 "숙박이면 시간제에서 뺀다" 같은 양자택일을 넣으면
/// [reservationModeOverlapHint]가 거짓말이 된다.
///
/// [modes]는 [placeReservationModes]가 룸 문서에서 모아 준 집합이다.
bool placeMatchesReservationMode(
  Set<ReservationMode> modes,
  ReservationMode? wanted,
) => wanted == null || modes.contains(wanted);

/// 장소 **문서 자체가** 숙박을 말하고 있는가 — [placeReservationModes]의 3층.
///
/// 체크인/체크아웃 안내는 숙박에만 입력받는 값이라(통합 등록 화면과 장소
/// 등록 화면 모두 `accommodationCheckInTime`/`accommodationCheckOutTime`으로
/// 저장한다) 룸이 침묵할 때의 마지막 근거가 된다.
bool placeDocSuggestsStay(Map<String, dynamic> place) {
  if (declaresReservationModes(place) &&
      parseReservationModes(place).contains(ReservationMode.stay)) {
    return true;
  }
  bool has(String key) => (place[key] as String?)?.isNotEmpty == true;
  return has('accommodationCheckInTime') || has('accommodationCheckOutTime');
}

/// 이 장소가 **숙박을 받는 곳인지** — 화면 문구를 '숙박'으로 쓸지
/// '공간대여'로 쓸지 가르는 단 하나의 기준이다.
///
/// `places` 컬렉션은 숙박(호텔·펜션·게스트하우스)과 대관(파티룸·스튜디오·
/// 회의실)을 **같은 스키마로** 담는다([ComboPlaceType.stay] 하나가 둘 다
/// 맡는다). 그래서 컬렉션이나 콤보 유형만 보고 "숙박"이라고 쓰면 대관 공간에도
/// 숙박이라는 말이 붙는다. 실제로 갈리는 지점은 **룸이 받는 예약 방식**이다.
///
/// 목록의 '🛏 숙박' 필터와 **글자 그대로 같은 판정**이다 — 문구와 필터가
/// 갈리지 않도록 [placeReservationModes]를 그대로 되묻는다.
bool placeSupportsStay(
  Map<String, dynamic> place, {
  List<Map<String, dynamic>> rooms = const [],
}) => placeReservationModes(place, rooms: rooms).contains(ReservationMode.stay);
