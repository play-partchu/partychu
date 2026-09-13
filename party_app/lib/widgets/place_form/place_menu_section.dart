import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import 'package:party_app/models/place_menu.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/services/place_menu_service.dart';

/// 등록/수정 화면의 "메뉴" 섹션 — 메뉴명/가격/사진/설명을 여러 줄 관리한다.
///
/// 프로모션 섹션([PlacePromotionSection])과 같은 골격이다: 부모가 리스트를
/// 소유하고 이 위젯이 직접 고치며, 추가·삭제·순서 변경과 접기/펼치기를 맡는다.
/// 다른 점은 사진을 **주소 입력이 아니라 갤러리에서 고른다**는 것뿐이다 —
/// 사장님이 자기 메뉴 사진을 URL로 갖고 있을 리 없기 때문이다.
///
/// 고른 사진은 여기서 업로드하지 않는다. 등록 화면이 대표/소개 이미지를 저장
/// 시점에 한꺼번에 올리는 것과 같은 정책이라, 여기서는 로컬 경로만
/// [PlaceMenu.localImagePath]에 담아 두고 업로드는 저장 때 한 번에 한다.
class PlaceMenuSection extends StatefulWidget {
  const PlaceMenuSection({
    super.key,
    required this.menus,
    required this.onChanged,
    required this.accent,
  });

  /// 부모가 소유하는 메뉴 목록 — 이 위젯이 직접 고친다.
  final List<PlaceMenu> menus;

  final VoidCallback onChanged;
  final Color accent;

  /// 플레이스 문서를 만든/수정한 직후에 호출한다.
  static Future<void> save({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required List<PlaceMenu> menus,
  }) => PlaceMenuService.syncForPlace(
    placeId: placeId,
    placeCollection: placeCollection,
    hostId: hostId,
    menus: menus,
  );

  @override
  State<PlaceMenuSection> createState() => _PlaceMenuSectionState();
}

class _PlaceMenuSectionState extends State<PlaceMenuSection> {
  final _picker = ImagePicker();
  int? _expanded;

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void _add() {
    widget.menus.add(
      PlaceMenu.empty(
        placeId: '',
        placeCollection: '',
        hostId: '',
        sortOrder: widget.menus.length,
      ),
    );
    _expanded = widget.menus.length - 1;
    _notify();
  }

  void _remove(int i) {
    widget.menus.removeAt(i);
    if (_expanded == i) {
      _expanded = null;
    } else if (_expanded != null && _expanded! > i) {
      _expanded = _expanded! - 1;
    }
    _resequence();
    _notify();
  }

  void _move(int i, int delta) {
    final to = i + delta;
    if (to < 0 || to >= widget.menus.length) return;
    final item = widget.menus.removeAt(i);
    widget.menus.insert(to, item);
    if (_expanded == i) _expanded = to;
    _resequence();
    _notify();
  }

  void _resequence() {
    for (var i = 0; i < widget.menus.length; i++) {
      widget.menus[i] = widget.menus[i].copyWith(sortOrder: i);
    }
  }

  void _update(int i, PlaceMenu next) {
    widget.menus[i] = next;
    _notify();
  }

  int get _featuredCount => widget.menus.where((m) => m.isFeatured).length;

  /// 대표 메뉴 켜기/끄기 — 상한을 넘기면 이유를 알려주고 켜지 않는다.
  void _toggleFeatured(int i) {
    final menu = widget.menus[i];
    if (!menu.isFeatured && _featuredCount >= PlaceMenu.maxFeatured) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('대표 메뉴는 최대 ${PlaceMenu.maxFeatured}개까지 지정할 수 있어요.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _update(i, menu.copyWith(isFeatured: !menu.isFeatured));
  }

  Future<void> _pickImage(int i) async {
    final f = await _picker.pickImage(source: ImageSource.gallery);
    if (f == null || !mounted) return;
    // 경로만 남기므로 원본 XFile을 기억해 둔다 — 웹에서는 blob URL만으로는
    // 형식을 알 수 없어 업로드 허가를 받지 못한다([LocalMedia.remember]).
    _update(i, widget.menus[i].copyWith(localImagePath: LocalMedia.remember(f).path));
  }

  /// 사진 지우기 — 아직 안 올린 것(localImagePath)이든 이미 올라간 것
  /// (imageUrl)이든 이 자리에서 함께 비운다.
  void _clearImage(int i) {
    _update(i, widget.menus[i].copyWith(imageUrl: '', clearLocalImage: true));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: widget.accent.withValues(alpha: 0.28),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🍽', style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              const Text(
                '메뉴',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
              const Spacer(),
              if (widget.menus.isNotEmpty)
                Text(
                  '${widget.menus.length}개',
                  style: const TextStyle(fontSize: 12, color: Colors.black45),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            '손님이 상세화면에서 바로 보는 메뉴예요. 사진과 설명은 선택이고, '
            '메뉴명만 있어도 등록됩니다.',
            style: TextStyle(fontSize: 12, height: 1.4, color: Colors.black45),
          ),
          const SizedBox(height: 14),
          for (var i = 0; i < widget.menus.length; i++) _menuCard(i),
          const SizedBox(height: 4),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('메뉴 추가'),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.accent,
                side: BorderSide(color: widget.accent.withValues(alpha: 0.6)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _menuCard(int i) {
    final menu = widget.menus[i];
    final open = _expanded == i;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        children: [
          // 접힌 줄 — 사진·이름·가격만 보여주고, 순서 이동/삭제는 항상 가능하다.
          InkWell(
            onTap: () => setState(() => _expanded = open ? null : i),
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(
                children: [
                  _thumb(menu, size: 44),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Row(
                          children: [
                            // 접힌 상태에서도 어느 게 대표인지 한눈에 보이게.
                            if (menu.isFeatured) ...[
                              const Text('⭐', style: TextStyle(fontSize: 12)),
                              const SizedBox(width: 4),
                            ],
                            Flexible(
                              child: Text(
                                menu.name.trim().isEmpty ? '새 메뉴' : menu.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                  color: menu.name.trim().isEmpty
                                      ? Colors.black38
                                      : Colors.black87,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (menu.priceLabel != null) ...[
                          const SizedBox(height: 2),
                          Text(
                            menu.priceLabel!,
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: widget.accent,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  _iconBtn(
                    Icons.keyboard_arrow_up,
                    i > 0 ? () => _move(i, -1) : null,
                  ),
                  _iconBtn(
                    Icons.keyboard_arrow_down,
                    i < widget.menus.length - 1 ? () => _move(i, 1) : null,
                  ),
                  _iconBtn(
                    Icons.delete_outline,
                    () => _remove(i),
                    color: Colors.redAccent,
                  ),
                  Icon(
                    open ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Colors.black26,
                  ),
                ],
              ),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Divider(height: 1),
                  const SizedBox(height: 12),
                  _field(
                    index: i,
                    label: '메뉴명',
                    value: menu.name,
                    hint: '예) 하이볼',
                    onChanged: (v) => _update(i, menu.copyWith(name: v)),
                  ),
                  const SizedBox(height: 10),
                  _field(
                    index: i,
                    label: '가격',
                    value: menu.price > 0 ? menu.price.toString() : '',
                    hint: '예) 8000',
                    suffix: '원',
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => _update(
                      i,
                      menu.copyWith(price: int.tryParse(v.trim()) ?? 0),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _field(
                    index: i,
                    label: '설명 (선택)',
                    value: menu.description,
                    hint: '예) 산토리 위스키 베이스',
                    maxLines: 2,
                    onChanged: (v) => _update(i, menu.copyWith(description: v)),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '메뉴 사진 (선택)',
                    style: TextStyle(fontSize: 12.5, color: Colors.black54),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _thumb(menu, size: 72),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            OutlinedButton.icon(
                              onPressed: () => _pickImage(i),
                              icon: const Icon(Icons.photo_outlined, size: 16),
                              label: Text(
                                _hasImage(menu) ? '사진 바꾸기' : '사진 선택',
                                style: const TextStyle(fontSize: 12.5),
                              ),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                side: const BorderSide(
                                  color: Color(0xFFE8EBF2),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                            ),
                            if (_hasImage(menu))
                              TextButton(
                                onPressed: () => _clearImage(i),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text(
                                  '사진 삭제',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.redAccent,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // 대표 메뉴 — 상세화면 맨 위에 사진 카드로 크게 나간다.
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              '대표 메뉴로 지정',
                              style: TextStyle(fontSize: 13),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '상세화면 맨 위에 크게 보여요 '
                              '($_featuredCount/${PlaceMenu.maxFeatured})',
                              style: const TextStyle(
                                fontSize: 11.5,
                                color: Colors.black38,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: menu.isFeatured,
                        activeThumbColor: widget.accent,
                        // 상한을 넘길 때 안내를 띄워야 해서 값 대신 콜백을 쓴다.
                        onChanged: (_) => _toggleFeatured(i),
                      ),
                    ],
                  ),
                  // 지우지 않고 잠시 감추는 스위치 — 품절·시즌 종료용.
                  Row(
                    children: [
                      const Expanded(
                        child: Text('손님에게 보이기', style: TextStyle(fontSize: 13)),
                      ),
                      Switch(
                        value: menu.isVisible,
                        activeThumbColor: widget.accent,
                        onChanged: (v) =>
                            _update(i, menu.copyWith(isVisible: v)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  bool _hasImage(PlaceMenu m) =>
      m.localImagePath != null || m.imageUrl.isNotEmpty;

  /// 아직 안 올린 로컬 사진이 있으면 그걸 먼저 보여준다 — 방금 고른 사진이
  /// 바로 보이지 않으면 골라졌는지 알 수 없다.
  Widget _thumb(PlaceMenu m, {required double size}) {
    final local = m.localImagePath;
    final ImageProvider? provider = local != null
        ? LocalMedia.imageProviderForPath(local)
        : (m.imageUrl.isNotEmpty ? NetworkImage(m.imageUrl) : null);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: const Color(0xFFF2F3F7),
        borderRadius: BorderRadius.circular(8),
        image: provider == null
            ? null
            : DecorationImage(image: provider, fit: BoxFit.cover),
      ),
      child: provider != null
          ? null
          : const Icon(Icons.restaurant_menu, size: 18, color: Colors.black26),
    );
  }

  Widget _iconBtn(IconData icon, VoidCallback? onTap, {Color? color}) =>
      IconButton(
        onPressed: onTap,
        icon: Icon(icon, size: 18),
        color: color ?? Colors.black45,
        visualDensity: VisualDensity.compact,
        constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
        padding: EdgeInsets.zero,
      );

  /// 프로모션 섹션의 `_text`와 같은 방식 — 순서를 바꾸면 인덱스가 달라지면서
  /// 키가 바뀌고, 그 자리에 온 메뉴의 값으로 다시 그려진다.
  Widget _field({
    required int index,
    required String label,
    required String value,
    required ValueChanged<String> onChanged,
    String? hint,
    String? suffix,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(fontSize: 12.5, color: Colors.black54),
        ),
        const SizedBox(height: 6),
        TextFormField(
          key: ValueKey('menu|$label|$index'),
          initialValue: value,
          onChanged: onChanged,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Colors.black26),
            suffixText: suffix,
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 10,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: widget.accent),
            ),
          ),
        ),
      ],
    );
  }
}
