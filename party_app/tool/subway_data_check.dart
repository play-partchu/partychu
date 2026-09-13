// 변환된 지하철역 JSON을 점검한다.
//
//   dart run tool/subway_data_check.dart
//   dart run tool/subway_data_check.dart --focus 잠실 --focus 강남 \
//       --probe "잠실 롯데월드타워,37.5125,127.1025"
//
// 실제 데이터를 넣은 뒤 "제대로 들어갔는지"를 기계적으로 확인하는 용도다.
// 지도와 눈으로 대조해야 하는 항목(--probe)은 결과를 출력만 하고 판정하지
// 않는다 — 정답을 앱이 알 수 없기 때문이다.
//
// 탐색 로직은 lib/services/subway_station_index.dart 와 같은 규칙으로 여기서
// 다시 구현한다. 이 스크립트는 Flutter에 의존하지 않아야 해서(rootBundle 없이
// 파일을 직접 읽는다) 공유하지 않는다.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

const _maxMeters = 1500.0; // SubwayStationIndex.defaultMaxMeters 와 같은 값

void main(List<String> args) {
  var path = 'assets/data/subway_stations.json';
  final focus = <String>[];
  final probes = <_Probe>[];
  for (var i = 0; i < args.length; i++) {
    String next() => i + 1 < args.length ? args[++i] : '';
    switch (args[i]) {
      case '--in':
        path = next();
      case '--focus':
        focus.add(next());
      case '--probe':
        final p = _Probe.parse(next());
        if (p != null) probes.add(p);
      default:
        stdout.writeln(
          '사용법: dart run tool/subway_data_check.dart '
          '[--in <json>] [--focus <역명>]... [--probe "<이름>,<lat>,<lng>"]...',
        );
        exitCode = 64;
        return;
    }
  }

  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('파일이 없습니다: $path');
    exitCode = 66;
    return;
  }

  final rssBefore = ProcessInfo.currentRss;
  final bytes = file.lengthSync();
  final json = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
  final stations = [
    for (final s in (json['stations'] as List? ?? const []))
      _Station(
        name: s['name'] as String? ?? '',
        lines: [for (final l in (s['lines'] as List? ?? const [])) l as String],
        code: s['code'] as String?,
        city: s['city'] as String? ?? '',
        lat: (s['lat'] as num).toDouble(),
        lng: (s['lng'] as num).toDouble(),
      ),
  ];
  final rssAfter = ProcessInfo.currentRss;

  _section('규모');
  stdout.writeln('  파일          : $path');
  stdout.writeln('  파일 크기     : ${_kb(bytes)} ($bytes B)');
  stdout.writeln('  역            : ${stations.length}개');
  stdout.writeln(
    '  노선          : ${stations.expand((s) => s.lines).toSet().length}종',
  );
  stdout.writeln(
    '  생성일        : ${json['generatedAt']} / 출처: ${json['source']}',
  );
  stdout.writeln(
    '  로드 후 RSS 증가: ${_kb(rssAfter - rssBefore)} '
    '(Dart VM 기준 근사치 — 앱에서도 이 정도 상주한다)',
  );

  if (stations.isEmpty) {
    stdout.writeln('\n데이터가 비어 있어 나머지 점검을 건너뜁니다.');
    return;
  }

  // ── 1. 중복 ────────────────────────────────────────────────────────────
  _section('중복');
  final byName = <String, int>{};
  final byCoord = <String, List<String>>{};
  for (final s in stations) {
    byName['${s.city}|${s.name}'] = (byName['${s.city}|${s.name}'] ?? 0) + 1;
    final coord = '${s.lat.toStringAsFixed(5)},${s.lng.toStringAsFixed(5)}';
    (byCoord[coord] ??= []).add(s.name);
  }
  final dupNames = byName.entries.where((e) => e.value > 1).toList();
  final dupCoords = byCoord.entries.where((e) => e.value.length > 1).toList();
  stdout.writeln('  같은 도시+역명 중복   : ${dupNames.length}건');
  for (final d in dupNames.take(10)) {
    stdout.writeln('    - ${d.key} × ${d.value}');
  }
  stdout.writeln('  좌표가 완전히 같은 역 : ${dupCoords.length}쌍');
  for (final d in dupCoords.take(10)) {
    stdout.writeln('    - ${d.key} → ${d.value.join(' / ')}');
  }

  // ── 2. 환승역 ──────────────────────────────────────────────────────────
  _section('환승역(노선 2개 이상)');
  final transfers = stations.where((s) => s.lines.length > 1).toList()
    ..sort((a, b) => b.lines.length.compareTo(a.lines.length));
  stdout.writeln('  환승역 수: ${transfers.length}개');
  for (final s in transfers.take(12)) {
    stdout.writeln('    - ${s.name}역: ${s.lines.join(' · ')}');
  }

  // ── 3. 노선 없는 역 ────────────────────────────────────────────────────
  _section('노선 정보 누락');
  final noLine = stations.where((s) => s.lines.isEmpty).toList();
  stdout.writeln('  노선이 비어 있는 역: ${noLine.length}개');
  for (final s in noLine.take(10)) {
    stdout.writeln('    - ${s.name}역');
  }

  // ── 4. 좌표 이상치 ─────────────────────────────────────────────────────
  // 이름이 같은데 아주 멀리 떨어진 역(도시 구분 실패)이나, 서로 200m 안에 붙어
  // 있는 다른 이름의 역(같은 역이 두 번 들어간 경우)을 찾는다.
  _section('좌표 이상치');
  var tooClose = 0;
  for (var i = 0; i < stations.length; i++) {
    for (var j = i + 1; j < stations.length; j++) {
      final a = stations[i];
      final b = stations[j];
      if ((a.lat - b.lat).abs() > 0.003) continue;
      if ((a.lng - b.lng).abs() > 0.004) continue;
      final d = _meters(a.lat, a.lng, b.lat, b.lng);
      if (d < 200 && a.name != b.name) {
        tooClose++;
        if (tooClose <= 10) {
          stdout.writeln(
            '    - ${a.name}역 ↔ ${b.name}역: ${d.round()}m '
            '(같은 역이 다른 이름으로 두 번 들어갔을 수 있음)',
          );
        }
      }
    }
  }
  stdout.writeln('  200m 안에 붙어 있는 서로 다른 이름의 역: $tooClose쌍');

  // ── 5. 지정 역 상세 ────────────────────────────────────────────────────
  if (focus.isNotEmpty) {
    _section('지정 역 상세');
    for (final name in focus) {
      final key = name.replaceAll('역', '');
      final matches = stations.where((s) => s.name == key).toList();
      if (matches.isEmpty) {
        stdout.writeln('  - $name: 데이터에 없음');
        continue;
      }
      for (final s in matches) {
        stdout.writeln(
          '  - ${s.name}역 [${s.lines.join(' · ')}]'
          '${s.city.isEmpty ? '' : ' (${s.city})'}'
          '${s.code == null ? '' : ' 코드 ${s.code}'} '
          '→ ${s.lat}, ${s.lng}',
        );
      }
    }
  }

  // ── 6. 임의 좌표 조회 ──────────────────────────────────────────────────
  if (probes.isNotEmpty) {
    _section('좌표 조회 (지도와 대조용 — 판정하지 않음)');
    for (final p in probes) {
      final n = _nearest(stations, p.lat, p.lng);
      if (n == null) {
        stdout.writeln('  - ${p.label}: 반경 ${_maxMeters.round()}m 안에 역 없음');
        continue;
      }
      final d = _meters(p.lat, p.lng, n.lat, n.lng);
      stdout.writeln(
        '  - ${p.label} → [${n.lines.join(' · ')}] ${n.name}역 · ${d.round()}m '
        '(역 좌표 ${n.lat}, ${n.lng})',
      );
    }
  }
}

_Station? _nearest(List<_Station> stations, double lat, double lng) {
  _Station? best;
  var bestMeters = double.infinity;
  for (final s in stations) {
    final d = _meters(lat, lng, s.lat, s.lng);
    if (d < bestMeters) {
      bestMeters = d;
      best = s;
    }
  }
  return bestMeters > _maxMeters ? null : best;
}

double _meters(double lat1, double lng1, double lat2, double lng2) {
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

String _kb(int bytes) => '${(bytes / 1024).toStringAsFixed(1)} KB';

void _section(String title) =>
    stdout.writeln('\n── $title ${'─' * (58 - title.length)}');

class _Station {
  final String name;
  final List<String> lines;
  final String? code;
  final String city;
  final double lat;
  final double lng;
  const _Station({
    required this.name,
    required this.lines,
    required this.city,
    required this.lat,
    required this.lng,
    this.code,
  });
}

class _Probe {
  final String label;
  final double lat;
  final double lng;
  const _Probe(this.label, this.lat, this.lng);

  static _Probe? parse(String raw) {
    final parts = raw.split(',');
    if (parts.length < 3) return null;
    final lat = double.tryParse(parts[parts.length - 2].trim());
    final lng = double.tryParse(parts[parts.length - 1].trim());
    if (lat == null || lng == null) return null;
    return _Probe(parts.sublist(0, parts.length - 2).join(',').trim(), lat, lng);
  }
}
