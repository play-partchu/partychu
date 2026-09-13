import 'package:flutter/material.dart';

import 'package:party_app/services/map_directions_service.dart';

/// 길찾기 진입점 — 설치된 지도 앱 목록을 보여주고 사용자가 고른 앱을 연다.
///
/// 앱의 모든 "길찾기" 버튼은 [start]만 부르면 된다. 특정 지도 앱을 강제하지
/// 않는 것이 핵심이라, 어떤 앱을 열지는 언제나 사용자가 정한다.
///
/// - 설치된 지도 앱이 2개 이상 → 이 시트를 띄운다.
/// - 1개뿐(또는 하나도 없어 웹 지도만 남음) → 고를 게 없으니 바로 연다.
class MapAppPickerSheet extends StatelessWidget {
  final List<MapAppTarget> targets;

  const MapAppPickerSheet({super.key, required this.targets});

  /// 길찾기를 시작한다. 실패하거나 목적지가 없으면 안내 문구를 띄운다.
  static Future<void> start(
    BuildContext context, {
    String? placeName,
    String? address,
    double? latitude,
    double? longitude,
  }) async {
    final targets = await MapDirectionsService.resolveTargets(
      placeName: placeName,
      address: address,
      latitude: latitude,
      longitude: longitude,
    );
    if (!context.mounted) return;

    if (targets.isEmpty) {
      _toast(context, '길찾기를 실행할 수 없습니다.');
      return;
    }

    // 지도 앱이 없으면 웹 지도만 남는다 — 고를 것이 없으니 바로 연다.
    final nativeCount = targets.where((t) => !t.isWeb).length;
    if (nativeCount <= 1) {
      await _launch(context, targets.first, targets);
      return;
    }

    final picked = await showModalBottomSheet<MapAppTarget>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => MapAppPickerSheet(targets: targets),
    );
    if (picked == null || !context.mounted) return;
    await _launch(context, picked, targets);
  }

  /// 고른 대상을 연다. 지도 앱 실행이 실패하면 웹 지도로 한 번 더 시도한다
  /// (설치 확인을 통과했더라도 앱이 스킴을 거부하는 경우가 있다).
  static Future<void> _launch(
    BuildContext context,
    MapAppTarget target,
    List<MapAppTarget> all,
  ) async {
    if (await MapDirectionsService.launchTarget(target)) return;

    if (!target.isWeb) {
      for (final web in all.where((t) => t.isWeb)) {
        if (await MapDirectionsService.launchTarget(web)) return;
      }
    }
    if (!context.mounted) return;
    _toast(context, '길찾기를 실행할 수 없습니다.');
  }

  static void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 10),
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: const Color(0xFFE3E3E8),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 16, 20, 2),
            child: Text(
              '길찾기 앱 선택',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
          ),
          const Padding(
            padding: EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              '설치된 지도 앱만 표시됩니다.',
              style: TextStyle(fontSize: 12, color: Colors.black45),
            ),
          ),
          ...targets.map(
            (t) =>
                _TargetTile(target: t, onTap: () => Navigator.pop(context, t)),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _TargetTile extends StatelessWidget {
  final MapAppTarget target;
  final VoidCallback onTap;

  const _TargetTile({required this.target, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: target.color,
                borderRadius: BorderRadius.circular(11),
              ),
              child: target.icon != null
                  ? Icon(target.icon, size: 20, color: target.onColor)
                  : Text(
                      target.initial,
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: target.onColor,
                      ),
                    ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                target.label,
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                ),
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: Colors.black26),
          ],
        ),
      ),
    );
  }
}
