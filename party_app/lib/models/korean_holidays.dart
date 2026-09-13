/// 대한민국 공휴일 하루.
class KoreanHoliday {
  /// 시각이 잘린 날짜.
  final DateTime date;

  /// '설날' / '광복절' / '대체공휴일(어린이날)' 처럼 달력에 그대로 쓸 이름.
  final String name;

  /// 대체공휴일인지 — 원래 공휴일이 주말·다른 공휴일과 겹쳐 생긴 날.
  final bool substitute;

  const KoreanHoliday(this.date, this.name, {this.substitute = false});
}

/// 대한민국 **연도별 공휴일**을 한곳에서 관리하는 표.
///
/// 날짜를 화면에 흩어 적지 않는다 — 달력이든 목록이든 공휴일이 필요한 곳은
/// 전부 [of]/[isHoliday]/[nameOf]만 부른다. 해가 바뀌어도 아래 [_lunarDays]에
/// 한 해치 줄만 더하면 끝이다.
///
/// 세 갈래로 나뉜다.
/// 1. **양력 고정 공휴일**([_fixedDays]) — 신정·삼일절처럼 날짜가 매년 같다.
///    해마다 새로 적을 것이 없다.
/// 2. **음력 기반 공휴일**([_lunarDays]) — 설날·추석·부처님오신날은 음력을
///    양력으로 환산해야 해서 해마다 날짜가 다르다. 음력 변환기를 앱에 넣는
///    대신, **해당 연도의 양력 날짜만** 표로 둔다(설·추석의 앞뒤 하루는
///    연휴로 자동 계산하므로 '당일' 하나만 적는다).
/// 3. **대체공휴일**([_substitutesFor]) — 관공서의 공휴일에 관한 규정을 그대로
///    옮긴 규칙으로 계산한다(하드코딩하지 않는다).
///
/// 임시공휴일·선거일처럼 그해에만 생기는 날은 [_extraDays]에 넣는다.
class KoreanHolidays {
  KoreanHolidays._();

  /// 양력으로 날짜가 고정된 공휴일 — (월, 일, 이름).
  static const List<({int month, int day, String name})> _fixedDays = [
    (month: 1, day: 1, name: '신정'),
    (month: 3, day: 1, name: '삼일절'),
    (month: 5, day: 5, name: '어린이날'),
    (month: 6, day: 6, name: '현충일'),
    (month: 8, day: 15, name: '광복절'),
    (month: 10, day: 3, name: '개천절'),
    (month: 10, day: 9, name: '한글날'),
    (month: 12, day: 25, name: '성탄절'),
  ];

  /// 음력 기반 공휴일의 **양력 환산 날짜**(당일 기준).
  ///
  /// 설날·추석은 앞뒤 하루가 함께 공휴일이라 여기서는 당일만 적고 [of]가
  /// 연휴 사흘로 펼친다. 새 해를 지원하려면 이 표에 한 줄만 추가하면 된다.
  static const Map<int, ({String seollal, String chuseok, String buddha})>
  _lunarDays = {
    2025: (seollal: '2025-01-29', chuseok: '2025-10-06', buddha: '2025-05-05'),
    2026: (seollal: '2026-02-17', chuseok: '2026-09-25', buddha: '2026-05-24'),
    2027: (seollal: '2027-02-06', chuseok: '2027-09-15', buddha: '2027-05-13'),
    2028: (seollal: '2028-01-26', chuseok: '2028-10-03', buddha: '2028-05-02'),
    2029: (seollal: '2029-02-13', chuseok: '2029-09-22', buddha: '2029-05-20'),
    2030: (seollal: '2030-02-03', chuseok: '2030-09-12', buddha: '2030-05-09'),
  };

  /// 그해에만 생기는 공휴일(임시공휴일·선거일 등) — 확정될 때마다 추가한다.
  static const Map<int, List<({String date, String name})>> _extraDays = {};

  /// 주말·다른 공휴일과 겹치면 대체공휴일이 생기는 공휴일들.
  /// (관공서의 공휴일에 관한 규정 — 신정·현충일은 대상이 아니다.)
  static const Set<String> _substituteTargets = {
    '삼일절',
    '어린이날',
    '부처님오신날',
    '광복절',
    '개천절',
    '한글날',
    '성탄절',
  };

  /// 음력 기반 공휴일 데이터를 가진 연도들 — 달력이 "이 해는 공휴일 표가 아직
  /// 없다"를 알아야 할 때 쓴다(그래도 양력 고정 공휴일과 일요일은 그대로 뜬다).
  static Iterable<int> get knownYears => _lunarDays.keys;

  /// 음력 공휴일 표가 있는 첫 해 / 마지막 해.
  static int get minSupportedYear =>
      _lunarDays.keys.reduce((a, b) => a < b ? a : b);
  static int get maxSupportedYear =>
      _lunarDays.keys.reduce((a, b) => a > b ? a : b);

  /// [year]의 설·추석·부처님오신날을 알고 있는지.
  ///
  /// **false여도 공휴일이 없다는 뜻이 아니다** — 양력 고정 공휴일과 대체공휴일은
  /// 그대로 계산되지만 음력 공휴일이 빠진다. 화면은 이 값을 보고 "이 해는 음력
  /// 공휴일 정보가 아직 없다"고 알려야지, 조용히 평일처럼 보여주면 안 된다.
  static bool hasLunarData(int year) => _lunarDays.containsKey(year);

  /// 공휴일을 온전히 표시할 수 있는 마지막 날.
  static DateTime get lastSupportedDate => DateTime(maxSupportedYear, 12, 31);

  /// 고를 수 있는 마지막 날([last])을 공휴일 표가 아는 범위 안으로 줄인다 —
  /// 날짜 선택 범위와 공휴일 지원 범위를 맞춰 "표에 없는 해"가 아예 선택지에
  /// 나오지 않게 하기 위함이다.
  ///
  /// 다만 [notBefore](보통 오늘)보다 앞당기지는 않는다. 표를 갱신하지 않은 채
  /// 지원 마지막 해를 지나가 버리면 고를 수 있는 날이 없어져 화면이 잠기기
  /// 때문이다 — 그때는 원래 범위를 그대로 두고, 달력이 안내 문구를 띄운다.
  static DateTime clampToSupported(
    DateTime last, {
    required DateTime notBefore,
  }) {
    final limit = lastSupportedDate;
    if (limit.isBefore(notBefore)) return last;
    return last.isAfter(limit) ? limit : last;
  }

  static DateTime _dayOf(DateTime d) => DateTime(d.year, d.month, d.day);

  static DateTime _parse(String yyyyMMdd) => DateTime.parse(yyyyMMdd);

  /// 연도별 공휴일 표 — 한 번 만들면 캐시해 둔다(달력이 월을 넘길 때마다 다시
  /// 계산하지 않게).
  static final Map<int, Map<DateTime, KoreanHoliday>> _cache = {};

  /// [year]의 공휴일 전부(대체공휴일 포함).
  static Map<DateTime, KoreanHoliday> of(int year) =>
      _cache.putIfAbsent(year, () => _build(year));

  static Map<DateTime, KoreanHoliday> _build(int year) {
    // 겹침(추석 당일 ↔ 개천절)을 놓치지 않도록, 먼저 **날짜별로 이름을 모두**
    // 모은 다음 대표 이름을 고른다.
    final byDate = <DateTime, List<String>>{};
    void add(DateTime date, String name) =>
        byDate.putIfAbsent(date, () => []).add(name);

    // 설·추석 연휴는 3일(당일과 앞뒤 하루)이고, 겹칠 때 이름을 양보하지 않도록
    // 가장 먼저 담는다.
    final lunar = _lunarDays[year];
    final festivalDays = <String, List<DateTime>>{};
    if (lunar != null) {
      for (final (day, name) in [
        (_parse(lunar.seollal), '설날'),
        (_parse(lunar.chuseok), '추석'),
      ]) {
        final days = [
          day.subtract(const Duration(days: 1)),
          day,
          day.add(const Duration(days: 1)),
        ];
        festivalDays[name] = days;
        add(days[0], '$name 연휴');
        add(days[1], name);
        add(days[2], '$name 연휴');
      }
      add(_parse(lunar.buddha), '부처님오신날');
    }
    for (final f in _fixedDays) {
      add(DateTime(year, f.month, f.day), f.name);
    }
    for (final e in _extraDays[year] ?? const []) {
      add(_parse(e.date), e.name);
    }

    final result = <DateTime, KoreanHoliday>{
      // 한 날에 공휴일이 둘이면(어린이날·부처님오신날) 둘 다 적어준다.
      for (final e in byDate.entries)
        e.key: KoreanHoliday(e.key, e.value.join('·')),
    };
    for (final s in _substitutes(byDate, festivalDays)) {
      result.putIfAbsent(s.date, () => s);
    }
    return result;
  }

  /// 대체공휴일 계산 — 관공서의 공휴일에 관한 규정을 그대로 옮긴 규칙이다.
  ///
  /// - 설날·추석 연휴(사흘)가 **일요일 또는 다른 공휴일**과 겹치면 연휴 뒤로
  ///   하루가 밀린다. 사흘 중 몇 개가 겹치든 **하루만** 더해진다.
  /// - 그 밖의 대상 공휴일([_substituteTargets])은 **토·일 또는 다른 공휴일**과
  ///   겹치면 밀린다. 단, 설·추석 연휴 안에 든 날은 위에서 이미 처리했으므로
  ///   두 번 세지 않는다.
  ///
  /// 밀린 날이 또 공휴일이거나 주말이면 그다음 평일까지 계속 밀어 찾는다.
  static List<KoreanHoliday> _substitutes(
    Map<DateTime, List<String>> byDate,
    Map<String, List<DateTime>> festivalDays,
  ) {
    final added = <KoreanHoliday>[];
    bool taken(DateTime d) =>
        byDate.containsKey(d) || added.any((h) => h.date == d);

    DateTime nextFreeWeekday(DateTime from) {
      var d = from.add(const Duration(days: 1));
      while (d.weekday == DateTime.saturday ||
          d.weekday == DateTime.sunday ||
          taken(d)) {
        d = d.add(const Duration(days: 1));
      }
      return d;
    }

    // ① 설·추석 연휴.
    final inFestival = <DateTime>{};
    for (final entry in festivalDays.entries) {
      final days = entry.value..sort();
      inFestival.addAll(days);
      final clashes = days.any(
        (d) => d.weekday == DateTime.sunday || (byDate[d]?.length ?? 0) > 1,
      );
      if (clashes) {
        added.add(
          KoreanHoliday(
            nextFreeWeekday(days.last),
            '대체공휴일(${entry.key})',
            substitute: true,
          ),
        );
      }
    }

    // ② 나머지 대상 공휴일 — **날짜 하나에 대체 하루**다. 어린이날과
    // 부처님오신날이 같은 날에 겹쳐도 공휴일이 하루 줄어든 것이므로 대체도
    // 하루만 생긴다.
    final targets =
        byDate.entries
            .where(
              (e) =>
                  !inFestival.contains(e.key) &&
                  e.value.any(_substituteTargets.contains),
            )
            .toList()
          ..sort((a, b) => a.key.compareTo(b.key));
    for (final e in targets) {
      final date = e.key;
      final onWeekend =
          date.weekday == DateTime.saturday || date.weekday == DateTime.sunday;
      final overlapped = e.value.length > 1;
      if (!onWeekend && !overlapped) continue;
      final name = e.value.firstWhere(_substituteTargets.contains);
      added.add(
        KoreanHoliday(nextFreeWeekday(date), '대체공휴일($name)', substitute: true),
      );
    }
    return added;
  }

  /// 그날이 공휴일인지 — 일요일은 공휴일이 아니라 '주말'이라 여기서 걸리지
  /// 않는다(달력에서 빨갛게 칠하는 것은 화면 쪽 판단).
  static bool isHoliday(DateTime date) =>
      of(date.year).containsKey(_dayOf(date));

  /// 그날 공휴일의 이름. 공휴일이 아니면 null.
  static String? nameOf(DateTime date) => of(date.year)[_dayOf(date)]?.name;

  /// 달력에서 **빨간 날**인지 — 일요일이거나 공휴일.
  static bool isRedDay(DateTime date) =>
      date.weekday == DateTime.sunday || isHoliday(date);
}
