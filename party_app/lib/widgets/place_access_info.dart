import 'package:flutter/material.dart';

import 'package:party_app/services/subway_station_index.dart';
import 'package:party_app/services/user_location_service.dart';
import 'package:party_app/utils/geo_distance.dart';
import 'package:party_app/widgets/subway_line_badge.dart';

/// 주소 바로 아래 붙는 **접근성 보조 정보** 한 줄.
///
///     📍 서울 송파구 오금로11길 30-16 지하1층   [복사] [길찾기]
///     ② ⑧ 잠실역 · 770m   📌 내 위치에서 2.3km
///
/// 주소보다 눈에 띄면 안 되는 보조 정보라 글자를 작게·흐리게 두고, 폭이 모자라면
/// [Wrap]으로 다음 줄에 내려간다.
///
/// ## 두 정보의 성격이 다르다
///
/// - **가장 가까운 역**: 이 장소의 좌표만 있으면 나온다. 번들 데이터에서
///   찾으므로 네트워크·권한과 무관하다([SubwayStationIndex]).
/// - **내 위치에서 거리**: 이미 허용된 위치 권한이 있을 때만 나온다
///   ([UserLocationService] — 권한을 새로 요청하지 않는다).
///
/// 그래서 위치 권한을 거부해도 지하철 정보는 그대로 보이고, 반대로 데이터에 없는
/// 지역이어도 거리 문구는 나온다. 둘 다 없으면 이 줄 자체가 사라진다.
class PlaceAccessInfo extends StatefulWidget {
  final double? latitude;
  final double? longitude;

  /// 위쪽 주소 줄과의 간격.
  final double topGap;

  const PlaceAccessInfo({
    super.key,
    required this.latitude,
    required this.longitude,
    this.topGap = 4,
  });

  @override
  State<PlaceAccessInfo> createState() => _PlaceAccessInfoState();
}

class _PlaceAccessInfoState extends State<PlaceAccessInfo> {
  NearestSubwayStation? _station;
  String? _distanceLabel;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant PlaceAccessInfo old) {
    super.didUpdateWidget(old);
    // 같은 화면에서 다른 장소로 바뀌는 경우(스트림 갱신·수정 후 재조회 등)에만
    // 다시 계산한다. 이때 **먼저 지운다** — 다시 계산이 끝날 때까지 앞 장소의
    // 역·거리를 그대로 두면, 새 주소 아래에 남의 역 이름이 잠깐 붙어 있는
    // 것처럼 보인다. 이 줄은 비어 있어도 그냥 사라지므로 빈 상태가 안전하다.
    if (old.latitude != widget.latitude || old.longitude != widget.longitude) {
      _station = null;
      _distanceLabel = null;
      _load();
    }
  }

  void _load() {
    _loadSubway();
    _loadDistance();
  }

  Future<void> _loadSubway() async {
    if (!hasUsableCoords(widget.latitude, widget.longitude)) {
      if (mounted && _station != null) setState(() => _station = null);
      return;
    }
    final index = await SubwayStationIndex.load();
    if (!mounted) return;
    // 데이터가 아직 없거나 반경 밖이면 null — 오류 없이 행만 빠진다.
    setState(
      () => _station = index.nearest(widget.latitude!, widget.longitude!),
    );
  }

  Future<void> _loadDistance() async {
    if (!hasUsableCoords(widget.latitude, widget.longitude)) {
      if (mounted && _distanceLabel != null) {
        setState(() => _distanceLabel = null);
      }
      return;
    }
    final position = await UserLocationService.currentOrNull();
    if (!mounted) return;
    // 권한이 없거나 측위에 실패한 경우 — 오류를 띄우지 않고 문구만 없다.
    if (position == null) {
      setState(() => _distanceLabel = null);
      return;
    }
    final meters = distanceMetersBetween(
      position.latitude,
      position.longitude,
      widget.latitude!,
      widget.longitude!,
    );
    setState(() => _distanceLabel = formatDistanceLabel(meters));
  }

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[?_subwayLine(), ?_myDistanceLine()];
    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: widget.topGap),
      child: Wrap(
        spacing: 10,
        runSpacing: 3,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: items,
      ),
    );
  }

  /// '② ⑧ 잠실역 · 770m' — 노선 배지 + 역 이름 + 거리.
  Widget? _subwayLine() {
    final nearest = _station;
    if (nearest == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final line in nearest.lines) ...[
          SubwayLineBadge(lineName: line),
          const SizedBox(width: 3),
        ],
        const SizedBox(width: 1),
        Text(
          '${nearest.displayName} · ${nearest.distanceLabel}',
          style: const TextStyle(fontSize: 11.5, color: Colors.black54),
        ),
      ],
    );
  }

  Widget? _myDistanceLine() {
    final label = _distanceLabel;
    if (label == null) return null;
    return Text(
      '📌 내 위치에서 $label',
      style: const TextStyle(fontSize: 11.5, color: Colors.black45),
    );
  }
}
