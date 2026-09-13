import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:party_app/widgets/map_app_picker_sheet.dart';
import 'package:party_app/widgets/place_access_info.dart';

/// 주소 옆 "복사 · 길찾기" 버튼 한 쌍 — 앱의 모든 상세 화면이 공유하는
/// **유일한** 주소 액션 구현이다.
///
/// 화면 레이아웃이 서로 다른 곳(예: 파티 상세의 라벨 달린 `_miniInfoRow`)에서는
/// 이 위젯만 떼어 `trailing` 자리에 끼우고, 그 밖에는 [PlaceAddressRow]를
/// 통째로 쓴다 — 어느 쪽이든 복사 문구·툴팁·접근성 라벨·지도 앱 선택 시트·
/// 실패 안내가 완전히 동일하다.
class PlaceAddressActions extends StatelessWidget {
  /// 복사·길찾기에 쓰는 전체 주소(도로명 + 상세주소). 화면에 보이는 값과
  /// 반드시 같은 값을 넘긴다.
  final String address;

  /// 길찾기 검색어에 함께 붙일 플레이스/파티 장소명(선택).
  final String? placeName;

  final double? latitude;
  final double? longitude;

  final Color actionColor;
  final double iconSize;

  /// 길찾기 아이콘만 복사 버튼보다 조금 크게 — 눈에 더 잘 띄게 하려는 의도라
  /// 복사 버튼 크기는 건드리지 않는다.
  double get _directionsIconSize => iconSize + 4;

  const PlaceAddressActions({
    super.key,
    required this.address,
    this.placeName,
    this.latitude,
    this.longitude,
    this.actionColor = const Color(0xFFFF6FA0),
    this.iconSize = 16,
  });

  bool get _hasAddress => address.trim().isNotEmpty;

  /// 좌표가 실제로 쓸 만한지 — null이거나 (0, 0)이면 장소명+주소 검색으로
  /// 자동 전환된다(판정은 MapDirectionsService도 동일하게 한다).
  bool get _hasCoords =>
      latitude != null &&
      longitude != null &&
      !(latitude == 0 && longitude == 0);

  bool get _canNavigate => _hasAddress || _hasCoords;

  Future<void> _copy(BuildContext context) async {
    final text = address.trim();
    if (text.isEmpty) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('주소를 복사했습니다.'),
        duration: Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  /// 지도 앱을 강제하지 않는다 — 설치된 앱 목록을 시트로 띄우고 사용자가
  /// 고른 앱을 연다(하나뿐이면 시트 없이 바로 열린다).
  Future<void> _navigate(BuildContext context) => MapAppPickerSheet.start(
    context,
    placeName: placeName,
    address: address,
    latitude: latitude,
    longitude: longitude,
  );

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _button(
          icon: Icons.content_copy,
          label: '주소 복사',
          onTap: _hasAddress ? () => _copy(context) : null,
        ),
        _button(
          icon: Icons.directions,
          label: '길찾기',
          onTap: _canNavigate ? () => _navigate(context) : null,
          size: _directionsIconSize,
        ),
      ],
    );
  }

  Widget _button({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
    double? size,
  }) {
    final enabled = onTap != null;
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: label,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            child: Icon(
              icon,
              size: size ?? iconSize,
              color: enabled ? actionColor : Colors.black26,
            ),
          ),
        ),
      ),
    );
  }
}

/// 상세 화면 상단 정보 영역의 "주소 한 줄" + 그 아래 접근성 보조 정보.
///
///     [📍] [주소 텍스트 ............] [복사] [길찾기]
///     📌 내 위치에서 2.3km
///
/// 주소가 길면 텍스트만 줄바꿈되고 두 버튼은 항상 오른쪽에 보인다.
/// 둘째 줄([PlaceAccessInfo])은 보여줄 것이 없으면(좌표 없음·위치 권한 없음)
/// 통째로 사라진다.
class PlaceAddressRow extends StatelessWidget {
  /// 화면에 보이고, 복사·길찾기에도 그대로 쓰이는 전체 주소.
  /// [joinAddress]로 만들어 넘기면 상세주소가 중복되지 않는다.
  final String address;

  final String? placeName;
  final double? latitude;
  final double? longitude;

  // ── 화면별 기존 디자인에 맞추기 위한 값들 ──────────────────────────
  final IconData leadingIcon;
  final double leadingIconSize;
  final Color leadingIconColor;

  /// 아이콘과 주소 텍스트 사이 간격.
  final double gap;

  final TextStyle textStyle;

  /// 아이콘 버튼 색 — 화면별 포인트 컬러를 그대로 넘겨 쓴다.
  final Color actionColor;

  const PlaceAddressRow({
    super.key,
    required this.address,
    this.placeName,
    this.latitude,
    this.longitude,
    this.leadingIcon = Icons.location_on_outlined,
    this.leadingIconSize = 14,
    this.leadingIconColor = Colors.black38,
    this.gap = 4,
    this.textStyle = const TextStyle(fontSize: 13, color: Colors.black54),
    this.actionColor = const Color(0xFFFF6FA0),
  });

  /// 도로명(또는 지번) 주소와 상세주소를 **중복 없이** 합친다.
  ///
  /// 상세주소가 이미 기본 주소에 포함돼 있으면(예전 데이터에서 흔하다) 다시
  /// 붙이지 않는다. 표시·복사·길찾기가 모두 이 한 값을 쓰게 하는 것이 목적이다.
  static String joinAddress(String? base, String? detail) {
    final b = (base ?? '').trim();
    final d = (detail ?? '').trim();
    if (b.isEmpty) return d;
    if (d.isEmpty || b.contains(d)) return b;
    return '$b $d';
  }

  @override
  Widget build(BuildContext context) {
    // 주소가 아예 없으면 이 줄 자체를 그리지 않는다.
    if (address.trim().isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(
                leadingIcon,
                size: leadingIconSize,
                color: leadingIconColor,
              ),
            ),
            SizedBox(width: gap),
            Expanded(child: Text(address, style: textStyle)),
            const SizedBox(width: 2),
            PlaceAddressActions(
              address: address,
              placeName: placeName,
              latitude: latitude,
              longitude: longitude,
              actionColor: actionColor,
            ),
          ],
        ),
        // 주소 아이콘과 세로선을 맞춘다 — 아이콘 폭 + 간격만큼 들여쓴다.
        Padding(
          padding: EdgeInsets.only(left: leadingIconSize + gap),
          child: PlaceAccessInfo(latitude: latitude, longitude: longitude),
        ),
      ],
    );
  }
}
