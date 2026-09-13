/// 공간 평수(`areaPyeong`) — 플레이스(`events`)와 장소대여(`places`)가
/// **같은 필드명·같은 타입**으로 저장하는 값.
///
/// ── 왜 모델을 따로 두는가 ─────────────────────────────────────────────────
/// 이 값을 쓰는 자리가 여섯 군데다 — 플레이스 등록/수정, 장소대여 등록/수정,
/// 콤보 등록 두 갈래, 그리고 두 상세 화면. 검증 규칙(범위·단위)이나
/// 표기('20평')를 각자 갖고 있으면 어느 화면에서는 통과한 값이 다른
/// 화면에서는 안 통과하고, 카드마다 '20평'/'20.0평'이 섞인다.
///
/// ── 숫자로 저장한다 ───────────────────────────────────────────────────────
/// 문서에는 `areaPyeong: 20`처럼 **숫자**만 넣는다. '20평' 같은 문자열을
/// 넣으면 나중에 "30평 이상" 같은 조건으로 거를 수 없고, 단위 표기를 바꾸는
/// 순간 저장값까지 갈라진다. 단위는 읽는 쪽에서 붙인다([labelOf]).
///
/// 저장·검색에 쓰는 값은 **고른 평수 그대로**다 — '100평 이상' 같은 구간으로
/// 뭉개지 않는다. ㎡는 [sqmOf]로 그때그때 환산해 보여 줄 뿐, 따로 저장하지
/// 않는다(두 값을 다 저장하면 언젠가 서로 어긋난다).
///
/// ── 옛 문서에는 이 필드가 없다 ────────────────────────────────────────────
/// [of]는 없으면 null을 돌려주고, 상세 화면은 null이면 줄 자체를 그리지 않는다
/// — 값이 없는 플레이스도 예전과 똑같이 보인다. 다만 **수정 화면에 들어온
/// 순간에는 필수**라, 옛 문서도 다음 저장부터 값이 채워진다.
class PlaceArea {
  PlaceArea._();

  /// Firestore 필드 이름 — 두 컬렉션이 같은 이름을 쓴다.
  static const String field = 'areaPyeong';

  /// 입력칸 위 제목.
  static const String label = '공간 평수 (필수)';

  /// 제목 아래 한 줄 안내.
  static const String hint = '실제 이용 가능한 공간의 평수를 입력해주세요.';

  /// 입력칸 안 흐린 글씨.
  static const String placeholder = '예: 20';

  /// 화면에서 자동으로 붙는 단위 — 사용자는 숫자만 고른다.
  static const String unit = '평';

  /// 상세 화면에서 앞에 붙는 이모지.
  static const String emoji = '📐';

  /// 비어 있을 때의 안내.
  static const String requiredMessage = '공간 평수를 입력해주세요.';

  /// 숫자가 아닐 때의 안내.
  static const String invalidMessage = '평수는 숫자로 입력해주세요.';

  /// 하한 미만일 때의 안내.
  static const String tooSmallMessage = '평수는 $minPyeongLabel 이상이어야 해요.';

  /// 1평 단위가 아닐 때의 안내 — 휠에서는 나올 수 없는 값이라, 옛 문서에서
  /// 넘어온 소수점 값을 수정 화면에서 열었을 때만 보인다.
  static const String notWholeMessage = '평수는 1평 단위로 선택해주세요.';

  /// 상한을 넘을 때의 안내.
  static const String tooLargeMessage = '평수를 다시 확인해주세요. ($maxPyeongLabel 이하)';

  /// 선택 하한 — 1평. 그보다 작은 공간을 평수로 적는 일은 없다.
  static const double minPyeong = 1;

  /// 선택 상한 — 5,000평(약 16,529㎡). 이보다 큰 값은 오타(200 → 20000)로 보는
  /// 편이 맞다. 진짜 그만한 공간이라면 소개 글로 적는 편이 정확하다.
  static const double maxPyeong = 5000;

  static const String minPyeongLabel = '1평';
  static const String maxPyeongLabel = '5,000평';

  /// 선택 단위 — 1평. [minPyeong]~[maxPyeong] 사이 **모든 정수**를 고를 수 있고,
  /// 그 사이를 '100평 이상' 같은 구간으로 묶지 않는다.
  static const int stepPyeong = 1;

  /// 휠에 올라가는 값의 개수 — 1평부터 5,000평까지.
  static int get optionCount =>
      ((maxPyeong - minPyeong) ~/ stepPyeong).toInt() + 1;

  /// 휠 i번째 칸의 평수(0-based).
  static int optionAt(int index) =>
      (minPyeong.toInt() + index * stepPyeong).clamp(
        minPyeong.toInt(),
        maxPyeong.toInt(),
      );

  /// 평수 → 휠 인덱스. 범위 밖 값은 가장 가까운 칸으로 붙인다(값 자체를
  /// 바꾸지는 않는다 — 휠을 어디서 열지만 정한다).
  static int indexOfPyeong(double pyeong) {
    final clamped = pyeong.clamp(minPyeong, maxPyeong);
    return ((clamped - minPyeong) / stepPyeong).round();
  }

  /// 휠을 처음 열 때 서 있을 값 — 아직 고른 적이 없을 때.
  static const int defaultPyeong = 20;

  // ── ㎡ 환산 ──────────────────────────────────────────────────────────────
  // 1평 = 3.3058㎡. 환산값은 **보여 주기만** 하고 저장하지 않는다.

  static const double sqmPerPyeong = 3.3058;
  static const String sqmUnit = '㎡';

  /// ㎡ 표시 소수 자릿수 — 첫째 자리까지.
  static const int sqmDecimalDigits = 1;

  static double sqmOf(double pyeong) => pyeong * sqmPerPyeong;

  /// 평수 → '4,132.3' (단위 없음).
  static String formatSqm(double pyeong) =>
      _withThousands(sqmOf(pyeong).toStringAsFixed(sqmDecimalDigits));

  /// 평수 → '1,250평 · 약 4,132.3㎡' — 고른 값 옆에 붙는 한 줄.
  static String summary(double pyeong) =>
      '${formatDisplay(pyeong)}$unit · 약 ${formatSqm(pyeong)}$sqmUnit';

  /// 문서 → '1,250평 · 약 4,132.3㎡'. 값이 없으면 null.
  static String? summaryOf(Map<String, dynamic> data) {
    final value = of(data);
    return value == null ? null : summary(value);
  }

  /// 허용 소수 자릿수 — 이제 입력은 1평 단위(정수)다. 옛 문서에 남아 있는
  /// '12.5' 같은 값을 **읽어서 그대로 보여 줄 때**만 쓴다.
  static const int decimalDigits = 1;

  /// 입력 문자열 → 저장할 숫자. 형식이 어긋나면 null.
  ///
  /// **검증을 겸하지 않는다** — null이 "비었다"인지 "잘못됐다"인지 구분하지
  /// 못하므로, 화면은 [validate]로 사유를 먼저 확인하고 여기서 값을 꺼낸다.
  static double? parse(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return null;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return null;
    if (value < minPyeong || value > maxPyeong) return null;
    // 1평 단위가 아니면 **거절**한다 — 조용히 반올림하면 호스트가 고른 값과
    // 저장된 값이 달라진다.
    if (value != value.roundToDouble()) return null;
    return value;
  }

  /// 검증 — 통과하면 null, 아니면 사용자에게 보여줄 사유.
  ///
  /// 등록·수정·콤보 어느 화면에서 불러도 같은 답이 나온다. 화면은 이 함수의
  /// 결과를 입력칸 아래 빨간 문구로도, 스낵바로도 쓴다.
  static String? validate(String? raw) {
    final text = raw?.trim() ?? '';
    if (text.isEmpty) return requiredMessage;
    final value = double.tryParse(text);
    if (value == null || !value.isFinite) return invalidMessage;
    if (value < minPyeong) return tooSmallMessage;
    if (value > maxPyeong) return tooLargeMessage;
    if (value != value.roundToDouble()) return notWholeMessage;
    return null;
  }

  /// 입력값이 저장 가능한가 — [validate]와 같은 판정을 bool로.
  static bool isValid(String? raw) => validate(raw) == null;

  /// 문서에서 읽기. 필드가 없거나 값이 이상하면 null(= 표시하지 않음).
  ///
  /// **범위는 여기서 보지 않는다.** 상한을 낮췄다고 해서 이미 저장된
  /// 5,000평 초과 문서를 화면에서 숨기면, 값이 사라진 것처럼 보이면서도
  /// 문서에는 그대로 남아 아무도 손대지 못한다. 읽기는 있는 그대로 보여 주고,
  /// 범위는 **새로 고를 때**([validate]/휠)만 강제한다.
  ///
  /// 숫자 타입이 정본이지만, 어쩌다 문자열로 들어간 값도 읽어 준다 —
  /// 되살릴 수 있는 값을 화면에서 버릴 이유는 없다(쓰기는 언제나 숫자다).
  static double? of(Map<String, dynamic> data) {
    final raw = data[field];
    if (raw is num) {
      final value = raw.toDouble();
      if (!value.isFinite || value <= 0) return null;
      return value;
    }
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return null;
      final value = double.tryParse(text);
      if (value == null || !value.isFinite || value <= 0) return null;
      return value;
    }
    return null;
  }

  /// 숫자 → 저장·입력칸용 문자열('20' / '12.5'). 자릿수 구분 쉼표를 넣지
  /// 않는다 — 이 문자열은 다시 [parse]로 읽히기 때문이다.
  static String format(double value) {
    if (value == value.roundToDouble()) return value.toInt().toString();
    final fixed = value.toStringAsFixed(decimalDigits);
    return fixed.endsWith('.0') ? fixed.substring(0, fixed.length - 2) : fixed;
  }

  /// 숫자 → 화면 표기('1,250' / '12.5'). 쉼표가 들어가므로 [parse]에 넣지 않는다.
  static String formatDisplay(double value) => _withThousands(format(value));

  /// 문서 → '1,250평'. 값이 없으면 null이라 호출부가 줄을 통째로 뺄 수 있다.
  static String? labelOf(Map<String, dynamic> data) {
    final value = of(data);
    return value == null ? null : '${formatDisplay(value)}$unit';
  }

  /// 문서 → '📐 1,250평'. 상세 화면에서 이모지까지 붙여 쓸 때.
  static String? displayOf(Map<String, dynamic> data) {
    final text = labelOf(data);
    return text == null ? null : '$emoji $text';
  }

  /// 수정 화면 입력칸의 초기값 — 값이 없던 옛 문서는 빈 칸으로 시작해서
  /// 호스트가 이번에 채우게 된다. 쉼표 없는 [format] 쪽을 쓴다(저장 경로가
  /// 이 문자열을 그대로 [parse]한다).
  static String textOf(Map<String, dynamic> data) {
    final value = of(data);
    return value == null ? '' : format(value);
  }

  /// '4132.3' → '4,132.3'. 소수부는 건드리지 않는다.
  static String _withThousands(String number) {
    final dot = number.indexOf('.');
    final intPart = dot < 0 ? number : number.substring(0, dot);
    final rest = dot < 0 ? '' : number.substring(dot);
    final buffer = StringBuffer();
    for (var i = 0; i < intPart.length; i++) {
      if (i > 0 && (intPart.length - i) % 3 == 0) buffer.write(',');
      buffer.write(intPart[i]);
    }
    return '$buffer$rest';
  }
}
