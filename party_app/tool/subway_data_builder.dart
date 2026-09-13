// 지하철역 좌표 공공데이터(CSV) → 앱이 읽는 JSON 변환기.
//
//   dart run tool/subway_data_builder.dart --in stations.csv --city 서울 \
//       --out assets/data/subway_stations.json
//
// 앱에서 CSV를 직접 파싱하지 않는 이유는 시작 비용이다 — 무거운 정리(컬럼 인식·
// 환승역 병합·좌표 검증)는 여기서 한 번만 하고, 앱은 정리된 JSON만 읽는다.
// 형식과 원본 데이터셋 설명은 assets/data/README.md 참고.
//
// 이 파일은 개발용 스크립트라 앱 번들에 들어가지 않는다(lib/ 밖).

import 'dart:convert';
import 'dart:io';
import 'dart:math';

void main(List<String> args) {
  final opts = _Options.parse(args);
  if (opts == null) {
    stdout.writeln(_usage);
    exitCode = 64; // EX_USAGE
    return;
  }

  final stations = <String, _Station>{}; // 'city|역명' → 역
  var skipped = 0;

  for (var sourceIndex = 0; sourceIndex < opts.inputs.length; sourceIndex++) {
    final source = opts.inputs[sourceIndex];
    final file = File(source.path);
    if (!file.existsSync()) {
      stderr.writeln('입력 파일을 찾을 수 없습니다: ${source.path}');
      exitCode = 66; // EX_NOINPUT
      return;
    }
    final rows = _readCsv(file);
    if (rows.length < 2) {
      stderr.writeln('데이터 행이 없습니다: ${source.path}');
      continue;
    }

    final header = rows.first.map((h) => h.trim()).toList();
    final cols = _Columns.resolve(header, source);
    if (cols == null) {
      stderr.writeln(
        '컬럼을 찾지 못했습니다: ${source.path}\n'
        '  헤더: ${header.join(' | ')}\n'
        '  --col-station/--col-line/--col-lat/--col-lng 로 지정하세요.',
      );
      exitCode = 65; // EX_DATAERR
      return;
    }

    for (final row in rows.skip(1)) {
      final name = _normalizeStationName(cols.value(row, cols.station));
      final line = _normalizeLineName(cols.value(row, cols.line));
      final lat = double.tryParse(cols.value(row, cols.lat).trim());
      final lng = double.tryParse(cols.value(row, cols.lng).trim());
      final code = cols.code == null
          ? null
          : cols.value(row, cols.code!).trim();

      // 위경도가 아닌 좌표계(TM 등)나 빈 행은 버린다 — 잘못된 좌표로 "잠실역
      // 700m"를 그리면 사용자를 엉뚱한 곳으로 보낸다.
      final validCoords =
          lat != null &&
          lng != null &&
          lat > 32 &&
          lat < 39.5 &&
          lng > 124 &&
          lng < 132;
      if (name.isEmpty || !validCoords) {
        skipped++;
        continue;
      }

      // 도시는 컬럼(주소)에서 뽑는 것이 우선이고, 없으면 `--city` 값을 쓴다.
      // 파일마다 이 값이 어긋나면 같은 역이 둘로 갈라지므로 표기를 통일한다.
      final rowCity = cols.city == null
          ? source.city
          : (_normalizeCity(cols.value(row, cols.city!)).isEmpty
                ? source.city
                : _normalizeCity(cols.value(row, cols.city!)));

      final key = '$rowCity|$name';
      final station = stations.putIfAbsent(
        key,
        () => _Station(name: name, city: rowCity),
      );
      if (line.isNotEmpty && !station.lines.contains(line)) {
        station.lines.add(line);
      }
      if (code != null && code.isNotEmpty) station.code ??= code;
      station.coords.add(_Coord(lat, lng, sourceIndex, source.path));
    }
  }

  if (stations.isEmpty) {
    stderr.writeln('변환할 데이터가 없습니다.');
    exitCode = 65;
    return;
  }

  final orderedKeys = stations.keys.toList()..sort();
  final conflicts = <String>[];
  final json = <String, dynamic>{
    'version': 2,
    'generatedAt': DateTime.now().toIso8601String().split('T').first,
    'source': opts.sourceLabel,
    'stations': [
      for (final key in orderedKeys)
        () {
          final s = stations[key]!;
          final resolved = s.resolveCoord(onConflict: conflicts.add);
          return {
            'name': s.name,
            'lines': s.lines..sort(_compareLine),
            if (s.code != null) 'code': s.code,
            if (s.city.isNotEmpty) 'city': s.city,
            'lat': _round(resolved.lat),
            'lng': _round(resolved.lng),
          };
        }(),
    ],
  };

  final out = File(opts.output);
  out.parent.createSync(recursive: true);
  out.writeAsStringSync(const JsonEncoder.withIndent('  ').convert(json));

  stdout.writeln(
    '완료: ${out.path}\n'
    '  역 ${stations.length}개'
    '${skipped > 0 ? ' (좌표 없음/형식 오류로 건너뜀 $skipped행)' : ''}',
  );

  // 파일마다 좌표가 크게 다른 역 — 어느 쪽이 맞는지는 사람이 판단해야 한다.
  // 조용히 평균 내면 두 좌표의 중간이라는 **어디에도 없는 지점**이 만들어진다.
  if (conflicts.isNotEmpty) {
    stdout.writeln(
      '\n⚠ 파일 간 좌표가 ${_conflictMeters.round()}m 넘게 어긋난 역 '
      '${conflicts.length}개 — 앞에 넣은 파일 값을 썼다:',
    );
    for (final c in conflicts.take(20)) {
      stdout.writeln('    $c');
    }
    if (conflicts.length > 20) {
      stdout.writeln('    … 외 ${conflicts.length - 20}개');
    }
  }
}

/// 이 거리를 넘으면 "같은 역의 승강장 차이"가 아니라 서로 다른 지점으로 본다.
/// 환승역은 노선별 승강장이 100~200m 떨어지기도 해서 넉넉히 잡았다.
const double _conflictMeters = 300;

double _metersBetween(double lat1, double lng1, double lat2, double lng2) {
  const r = 6371000.0;
  final dLat = (lat2 - lat1) * pi / 180;
  final dLng = (lng2 - lng1) * pi / 180;
  final a =
      sin(dLat / 2) * sin(dLat / 2) +
      cos(lat1 * pi / 180) *
          cos(lat2 * pi / 180) *
          sin(dLng / 2) *
          sin(dLng / 2);
  return 2 * r * atan2(sqrt(a), sqrt(1 - a));
}

/// 소수점 6자리면 약 10cm — 그 아래는 파일만 키운다.
double _round(double v) => double.parse(v.toStringAsFixed(6));

/// '잠실역' → '잠실'. 앱이 표시할 때 '역'을 붙이므로 저장은 접미사 없이 통일한다.
String _normalizeStationName(String raw) {
  var s = raw.trim();
  // '잠실(송파구청)'처럼 괄호 부제가 붙은 데이터가 있다 — 역명만 남긴다.
  final paren = s.indexOf('(');
  if (paren > 0) s = s.substring(0, paren).trim();
  if (s.endsWith('역') && s.length > 1) s = s.substring(0, s.length - 1);
  return s;
}

/// 호선 표기를 사람이 읽는 이름으로 통일한다.
///
/// 데이터셋마다 같은 노선을 다르게 적는다.
///
/// - 서울교통공사: 숫자만(`1`, `02`)
/// - 국가철도공단: 운영기관을 붙인 긴 이름(`서울 도시철도 9호선`,
///   `수도권  도시철도 9호선`(공백 2개), `수도권 경량도시철도 신림선`)
///
/// 그대로 두면 노선 색 표([SubwayLineStyle])가 못 찾아 전부 회색이 되고, 작은
/// 원형 배지에는 '서울'·'수도'처럼 엉뚱한 두 글자가 찍힌다. 그래서 표시에 쓸
/// 짧은 이름으로 통일한다.
String _normalizeLineName(String raw) {
  final s = raw.trim().replaceAll(RegExp(r'\s+'), ' ');
  if (s.isEmpty) return '';

  final digits = RegExp(r'^0*(\d+)$').firstMatch(s);
  if (digits != null) return '${digits.group(1)}호선';

  final alias = _lineAliases[s];
  if (alias != null) return alias;

  // '부산 도시철도 2호선' / '광주도시철도 1호선' → '부산2호선' / '광주1호선'.
  // 지역을 떼면 서울 2호선과 뒤섞이므로 지역을 붙인 채로 줄인다.
  final region = RegExp(
    r'^(부산|대구|광주|대전|인천)\s*(?:도시철도|경량도시철도|지하철|교통공사)?\s*(\d+)호선$',
  ).firstMatch(s);
  if (region != null) return '${region.group(1)}${region.group(2)}호선';

  // '도시철도 7호선'(7호선 부천·인천 연장), '수도권 광역철도 8호선'(별내선)처럼
  // 운영 주체만 앞에 붙은 서울 노선 — 지역 이름이 없으므로 수식어만 떼면 된다.
  final qualified = RegExp(
    r'^(?:수도권|서울|도시철도|광역철도|경량도시철도|지하철|\s)+(\d+)호선$',
  ).firstMatch(s);
  if (qualified != null) return '${qualified.group(1)}호선';

  return s;
}

/// 같은 노선을 가리키는 다른 표기 → 앱에서 쓸 이름.
const Map<String, String> _lineAliases = {
  '서울 도시철도 9호선': '9호선',
  '수도권 도시철도 9호선': '9호선',
  '수도권 광역철도 신분당선': '신분당선',
  '수도권 경량도시철도 신림선': '신림선',
  '수도권 도시철도 우이신설선': '우이신설선',
  '인천국제공항선': '공항철도',
  '공항철도1호선': '공항철도',
  // 분당선·수인선은 2020년에 직결돼 한 노선으로 운행한다.
  '분당선': '수인분당선',
  '수인선': '수인분당선',
  '인천지하철 1호선': '인천1호선',
  '인천지하철 2호선': '인천2호선',
  '김포도시철도': '김포골드라인',
  '용인경량전철': '용인경전철',
  '의정부': '의정부경전철',
  '에버라인': '용인경전철',
  '용인경전철 에버라인': '용인경전철',
};

/// 주소 컬럼에서 도시를 뽑는다 — '서울특별시 강남구 …' → '서울'.
///
/// 도시는 **역을 합치는 키의 일부**다(시청역은 서울에도 부산에도 있다). 파일마다
/// 표기가 다르면 같은 역이 둘로 갈라지므로 접미사를 떼어 통일한다.
String _normalizeCity(String raw) {
  final first = raw.trim().split(RegExp(r'\s+')).first;
  if (first.isEmpty) return '';
  // 같은 데이터 안에서도 '서울특별시'와 '서울시'가 섞여 들어온다 — 접미사를
  // 모두 떼야 두 표기가 한 도시로 합쳐진다(안 그러면 홍대입구역이 2호선짜리와
  // 경의중앙선짜리로 갈라진다).
  final trimmed = first
      .replaceAll('특별자치시', '')
      .replaceAll('특별자치도', '')
      .replaceAll('특별시', '')
      .replaceAll('광역시', '')
      .replaceAll(RegExp(r'[시도]$'), '');
  return trimmed.isEmpty ? first : trimmed;
}

/// '2호선'이 '10호선'보다 앞에 오도록 숫자 노선을 숫자로 비교한다.
int _compareLine(String a, String b) {
  final na = int.tryParse(RegExp(r'^(\d+)').firstMatch(a)?.group(1) ?? '');
  final nb = int.tryParse(RegExp(r'^(\d+)').firstMatch(b)?.group(1) ?? '');
  if (na != null && nb != null) return na.compareTo(nb);
  if (na != null) return -1;
  if (nb != null) return 1;
  return a.compareTo(b);
}

// ── CSV 읽기 ────────────────────────────────────────────────────────────────

/// 따옴표로 감싼 필드와 그 안의 쉼표를 지원하는 최소 CSV 파서.
/// 공공데이터 CSV는 EUC-KR인 경우가 많아 UTF-8 디코딩이 실패하면 latin1으로
/// 읽고 안내한다(그 경우 UTF-8로 변환해 다시 돌리는 편이 안전하다).
List<List<String>> _readCsv(File file) {
  final bytes = file.readAsBytesSync();
  String text;
  try {
    text = utf8.decode(bytes);
  } catch (_) {
    stderr.writeln(
      '경고: ${file.path} 가 UTF-8이 아닙니다. 한글이 깨지면 파일을 UTF-8로 '
      '변환한 뒤 다시 실행하세요.',
    );
    text = latin1.decode(bytes);
  }
  // BOM 제거
  if (text.isNotEmpty && text.codeUnitAt(0) == 0xFEFF) text = text.substring(1);

  final rows = <List<String>>[];
  var field = StringBuffer();
  var row = <String>[];
  var inQuotes = false;
  for (var i = 0; i < text.length; i++) {
    final ch = text[i];
    if (inQuotes) {
      if (ch == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i++;
        } else {
          inQuotes = false;
        }
      } else {
        field.write(ch);
      }
      continue;
    }
    switch (ch) {
      case '"':
        inQuotes = true;
      case ',':
        row.add(field.toString());
        field = StringBuffer();
      case '\r':
        break;
      case '\n':
        row.add(field.toString());
        field = StringBuffer();
        if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
        row = <String>[];
      default:
        field.write(ch);
    }
  }
  row.add(field.toString());
  if (row.any((c) => c.trim().isNotEmpty)) rows.add(row);
  return rows;
}

// ── 컬럼 인식 ───────────────────────────────────────────────────────────────

class _Columns {
  final int station;
  final int line;
  final int lat;
  final int lng;
  final int? code;

  /// 도시를 담은 컬럼(보통 주소). `--col-city`로 **명시할 때만** 쓴다 —
  /// 자동 인식에 맡기면 엉뚱한 컬럼이 역 병합 키에 섞일 수 있다.
  final int? city;

  const _Columns({
    required this.station,
    required this.line,
    required this.lat,
    required this.lng,
    this.code,
    this.city,
  });

  String value(List<String> row, int i) => i < row.length ? row[i] : '';

  /// 헤더 이름으로 컬럼 위치를 찾는다. `--col-*`로 직접 준 이름이 우선이고,
  /// 없으면 흔한 이름 목록으로 자동 인식한다.
  static _Columns? resolve(List<String> header, _Input input) {
    int? find(String? explicit, List<String> candidates) {
      if (explicit != null) {
        final i = header.indexWhere((h) => h == explicit);
        return i >= 0 ? i : null;
      }
      for (final c in candidates) {
        final i = header.indexWhere(
          (h) => h.replaceAll(' ', '').toLowerCase() == c,
        );
        if (i >= 0) return i;
      }
      return null;
    }

    final station = find(input.colStation, const [
      '역명',
      '역사명',
      '지하철역명',
      '전철역명',
      'station_name',
      'statn_nm',
      'stn_nm',
    ]);
    final line = find(input.colLine, const [
      '호선',
      '노선명',
      '노선',
      '전철노선명',
      'line',
      'line_num',
      'statn_line',
      'route_nm',
    ]);
    final lat = find(input.colLat, const ['위도', 'lat', 'latitude', 'ycode', 'y']);
    final lng = find(input.colLng, const [
      '경도',
      'lng',
      'lon',
      'longitude',
      'xcode',
      'x',
    ]);
    final code = find(input.colCode, const [
      '역번호',
      '역코드',
      'station_cd',
      'statn_cd',
      'stn_cd',
    ]);
    // 도시는 자동 인식하지 않는다 — 병합 키라서 잘못 잡히면 역이 둘로 갈라진다.
    final city = input.colCity == null ? null : find(input.colCity, const []);

    if (station == null || line == null || lat == null || lng == null) {
      return null;
    }
    return _Columns(
      station: station,
      line: line,
      lat: lat,
      lng: lng,
      code: code,
      city: city,
    );
  }
}

// ── 인자 ────────────────────────────────────────────────────────────────────

/// 입력 파일 하나 + **그 파일에만 적용되는** 설정.
///
/// 컬럼 이름은 데이터셋마다 다르므로(`역명` vs `역사명`, `위도` vs `역위도`)
/// 전역 옵션으로 두면 파일을 두 개 이상 넣는 순간 한쪽이 반드시 어긋난다.
/// `--in` 뒤에 오는 `--city`·`--col-*`는 **직전 `--in`에 속한다.**
class _Input {
  final String path;
  String city = '';
  String? colStation;
  String? colLine;
  String? colLat;
  String? colLng;
  String? colCode;
  String? colCity;

  _Input(this.path);
}

class _Options {
  final List<_Input> inputs;
  final String output;
  final String sourceLabel;

  const _Options({
    required this.inputs,
    required this.output,
    required this.sourceLabel,
  });

  static _Options? parse(List<String> args) {
    final inputs = <_Input>[];
    var output = 'assets/data/subway_stations.json';
    var source = '공공데이터 지하철역 좌표';

    for (var i = 0; i < args.length; i++) {
      final a = args[i];
      String next() => i + 1 < args.length ? args[++i] : '';
      // --in 이후의 --city·--col-*는 그 파일에만 적용된다.
      final current = inputs.isEmpty ? null : inputs.last;
      switch (a) {
        case '--in':
          inputs.add(_Input(next()));
        case '--out':
          output = next();
        case '--source':
          source = next();
        case '--city':
          if (current == null) return null;
          current.city = next();
        case '--col-station':
          if (current == null) return null;
          current.colStation = next();
        case '--col-line':
          if (current == null) return null;
          current.colLine = next();
        case '--col-lat':
          if (current == null) return null;
          current.colLat = next();
        case '--col-lng':
          if (current == null) return null;
          current.colLng = next();
        case '--col-code':
          if (current == null) return null;
          current.colCode = next();
        case '--col-city':
          if (current == null) return null;
          current.colCity = next();
        default:
          return null;
      }
    }
    if (inputs.isEmpty) return null;
    return _Options(inputs: inputs, output: output, sourceLabel: source);
  }
}

const _usage = '''
지하철역 좌표 CSV → assets/data/subway_stations.json 변환기

사용법:
  dart run tool/subway_data_builder.dart --in <csv> [--city <도시>] [--in <csv> --city <도시> ...]
                                        [--out <경로>] [--source <출처 문구>]
                                        [--col-station <헤더>] [--col-line <헤더>]
                                        [--col-lat <헤더>] [--col-lng <헤더>]
                                        [--col-code <헤더>]

예:
  dart run tool/subway_data_builder.dart --in seoul.csv --city 서울
  dart run tool/subway_data_builder.dart --in seoul.csv --city 서울 --in busan.csv --city 부산

필요한 원본 컬럼과 데이터셋 설명은 assets/data/README.md 참고.
''';

class _Coord {
  final double lat;
  final double lng;

  /// 몇 번째 `--in` 파일에서 왔는지 — 값이 어긋날 때 **앞에 넣은 파일이 이긴다**.
  final int sourceIndex;
  final String sourcePath;

  const _Coord(this.lat, this.lng, this.sourceIndex, this.sourcePath);
}

class _Station {
  final String name;
  final String city;
  final List<String> lines = [];
  final List<_Coord> coords = [];
  String? code;
  _Station({required this.name, required this.city});

  /// 이 역의 대표 좌표를 정한다.
  ///
  /// **파일 안에서는 평균, 파일 사이에서는 우선순위.**
  ///
  /// 한 파일 안에서 같은 역이 여러 행인 것은 노선별 승강장이다(잠실역 2호선과
  /// 8호선은 400m쯤 떨어져 있다). 이건 오류가 아니라 역이 넓은 것이므로 평균을
  /// 내 역사 한가운데를 가리키게 한다.
  ///
  /// 반대로 **다른 파일이 아주 다른 좌표를 주면 둘 중 하나가 틀린 것**이고, 그때
  /// 평균은 어디에도 없는 지점을 만든다. 그래서 먼저 넣은 `--in` 파일의 값을
  /// 그대로 쓰고 [onConflict]로 알려 사람이 판단하게 한다.
  _Coord resolveCoord({required void Function(String) onConflict}) {
    // 1) 파일별로 평균 — 승강장 흩어짐을 먼저 하나로 접는다.
    final bySource = <int, List<_Coord>>{};
    for (final c in coords) {
      (bySource[c.sourceIndex] ??= []).add(c);
    }
    final perSource = <_Coord>[
      for (final entry in bySource.entries)
        _Coord(
          entry.value.map((c) => c.lat).reduce((a, b) => a + b) /
              entry.value.length,
          entry.value.map((c) => c.lng).reduce((a, b) => a + b) /
              entry.value.length,
          entry.key,
          entry.value.first.sourcePath,
        ),
    ]..sort((a, b) => a.sourceIndex.compareTo(b.sourceIndex));

    // 2) 파일이 하나뿐이면 그대로 끝.
    final primary = perSource.first;
    if (perSource.length == 1) return primary;

    // 3) 파일 사이 차이가 크면 알리고 우선순위 파일 값을 쓴다.
    for (final other in perSource.skip(1)) {
      final gap = _metersBetween(
        primary.lat,
        primary.lng,
        other.lat,
        other.lng,
      );
      if (gap > _conflictMeters) {
        onConflict(
          '$name역: ${gap.round()}m 차이 '
          '(${_round(primary.lat)},${_round(primary.lng)} ← 채택 '
          '${_fileName(primary.sourcePath)} / '
          '${_round(other.lat)},${_round(other.lng)} ← '
          '${_fileName(other.sourcePath)})',
        );
      }
    }
    return primary;
  }
}

String _fileName(String path) => path.split(RegExp(r'[\\/]')).last;
