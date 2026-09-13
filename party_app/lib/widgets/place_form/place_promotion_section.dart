import 'package:flutter/material.dart';

import 'package:party_app/models/host_offering.dart';
import 'package:party_app/models/place_product.dart';
import 'package:party_app/models/place_promotion.dart';
import 'package:party_app/models/place_promotion_media_draft.dart';
import 'package:party_app/screens/party_media_picker_screen.dart';
import 'package:party_app/screens/place_event_edit_screen.dart'
    show kEventMaxImages;
import 'package:party_app/services/media_upload_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/services/place_promotion_service.dart';
import 'package:party_app/widgets/web_frame.dart';

/// 등록/수정 화면의 "매장 이벤트·프로모션" 섹션.
///
/// 상품 섹션([PlaceProductSection])과 **의도적으로 분리**돼 있다 — 여기 담기는
/// 건 파는 물건이 아니라 알리는 내용이라, 가격·재고·QR 같은 입력이 아예 없다.
/// 결제가 필요한 내용이면 상품으로 등록한 뒤 여기서 연결만 건다.
class PlacePromotionSection extends StatefulWidget {
  const PlacePromotionSection({
    super.key,
    required this.promotions,
    required this.onChanged,
    required this.accent,
    this.linkableProducts = const [],
  });

  /// 부모가 소유하는 프로모션 목록 — 이 위젯이 직접 고친다.
  final List<PlacePromotion> promotions;

  final VoidCallback onChanged;
  final Color accent;

  /// 연결할 수 있는 상품 목록(같은 화면에서 편집 중인 상품들).
  /// 아직 저장 전이라 id가 없는 상품은 연결 대상에서 빠진다.
  final List<PlaceProduct> linkableProducts;

  /// 플레이스 문서를 만든/수정한 직후에 호출한다.
  ///
  /// 아직 안 올린 사진·동영상([PlacePromotion.mediaDraft])이 있으면 **여기서**
  /// 올린다 — 장소 문서가 방금 생겼으므로 이제 올릴 수 있다. 업로드도 대표
  /// 판정도 크롭 키 변환도 전부 매장 이벤트 수정 화면
  /// ([PlaceEventEditScreen])이 쓰는 **같은 공용 함수**를 그대로 지난다.
  ///
  /// 업로드를 부모 등록 화면이 아니라 이 자리에 두는 이유: 초안이 프로모션
  /// 객체에 붙어 있어서, 순서를 바꾸거나 하나를 지워도 미디어가 저절로 따라
  /// 움직인다. 부모가 목록을 따로 하나 더 들면 그 둘이 어긋난다.
  static Future<void> save({
    required String placeId,
    required String placeCollection,
    required String hostId,
    required List<PlacePromotion> promotions,
  }) async {
    for (var i = 0; i < promotions.length; i++) {
      promotions[i] = await uploadDraft(promotions[i]);
    }
    return PlacePromotionService.syncForPlace(
      placeId: placeId,
      placeCollection: placeCollection,
      hostId: hostId,
      promotions: promotions,
    );
  }

  /// 초안 미디어를 올려 **저장 가능한** 이벤트로 바꾼다.
  ///
  /// 초안이 없으면 손대지 않고 그대로 돌려준다 — 이미 URL을 갖고 있는 옛
  /// 이벤트나 미디어를 안 고른 이벤트가 재업로드되는 일이 없다.
  ///
  /// [uploadImage]/[uploadVideo]는 공용 업로더가 이미 갖고 있는 주입점이다
  /// (기본값은 Cloudflare) — 테스트가 실제 업로드 없이 이 경로를 그대로 탄다.
  @visibleForTesting
  static Future<PlacePromotion> uploadDraft(
    PlacePromotion p, {
    ImageUploader? uploadImage,
    VideoUploader? uploadVideo,
  }) async {
    final draft = p.mediaDraft;
    if (draft == null || draft.isEmpty) {
      // 초안 자체는 비었어도 대표를 고른 상태일 수 있다(기존 사진 중 하나).
      // 그 경우에도 cover 필드는 채워 둔다 — 카드가 읽는 정본이다.
      return draft == null ? p : p.copyWith(clearMediaDraft: true);
    }

    final existingImageUrls = [...p.imageUrls];
    final newMedia = draft.newMedia;

    final upload = await MediaUploadService.uploadNewMedia(
      media: newMedia,
      logTag: 'place-event-inline',
      uploadImage: uploadImage,
      uploadVideo: uploadVideo,
    );

    final imageUrls = [...existingImageUrls, ...upload.imageUrls];
    final videoUrl = upload.hasVideo ? upload.videoUrl : p.videoUrl;
    final videoUid = upload.hasVideo ? upload.videoUid : p.videoUid;
    final videoThumbnailUrl = upload.hasVideo
        ? upload.videoThumbnailUrl
        : p.videoThumbnailUrl;

    final cover = MediaUploadService.resolveCoverFields(
      coverPick: draft.coverPick,
      imageUrls: imageUrls,
      uploadedImageUrls: upload.imageUrls,
      videoUrl: videoUrl,
      videoUid: videoUid,
      videoThumbnailUrl: videoThumbnailUrl,
    );
    // 크롭 값의 키는 로컬 경로 → 최종 URL로 옮겨 담는다.
    final photoCrops = MediaUploadService.resolvePhotoCropKeys(
      crops: draft.photoCrops,
      existingImageUrls: existingImageUrls,
      newMedia: newMedia,
      uploadedImageUrls: upload.imageUrls,
    );

    return p.copyWith(
      imageUrls: imageUrls,
      videoUrl: videoUrl,
      videoUid: videoUid,
      videoThumbnailUrl: videoThumbnailUrl,
      coverMediaType: cover['coverMediaType'] as String?,
      coverImageUrl: cover['coverImageUrl'] as String?,
      coverVideoUrl: cover['coverVideoUrl'] as String?,
      coverVideoUid: cover['coverVideoUid'] as String?,
      coverThumbnailUrl: cover['coverThumbnailUrl'] as String?,
      basicCardPhotoCrops: photoCrops,
      // 다 올렸으니 초안은 비운다 — 남겨 두면 저장을 다시 눌렀을 때 같은
      // 파일을 한 번 더 올린다.
      clearMediaDraft: true,
    );
  }

  @override
  State<PlacePromotionSection> createState() => _PlacePromotionSectionState();
}

class _PlacePromotionSectionState extends State<PlacePromotionSection> {
  int? _expanded;

  void _notify() {
    widget.onChanged();
    setState(() {});
  }

  void _add() {
    widget.promotions.add(
      PlacePromotion.empty(
        placeId: '',
        placeCollection: '',
        hostId: '',
        sortOrder: widget.promotions.length,
      ),
    );
    _expanded = widget.promotions.length - 1;
    _notify();
  }

  void _remove(int i) {
    widget.promotions.removeAt(i);
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
    if (to < 0 || to >= widget.promotions.length) return;
    final item = widget.promotions.removeAt(i);
    widget.promotions.insert(to, item);
    if (_expanded == i) _expanded = to;
    _resequence();
    _notify();
  }

  void _resequence() {
    for (var i = 0; i < widget.promotions.length; i++) {
      widget.promotions[i] = widget.promotions[i].copyWith(sortOrder: i);
    }
  }

  void _update(int i, PlacePromotion next) {
    widget.promotions[i] = next;
    _notify();
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
              // 🎪 — 매장 이벤트의 표시([HostOffering.placeEvent]). 참가자를
              // 모집하는 🎉 파티는 이 폼에서 만들지 않는다.
              const Text(kPlaceEventEmoji, style: TextStyle(fontSize: 18)),
              const SizedBox(width: 8),
              Text(
                '매장 이벤트·프로모션',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: widget.accent,
                ),
              ),
              const SizedBox(width: 8),
              const Text(
                '선택',
                style: TextStyle(fontSize: 11.5, color: Colors.black38),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            '"오늘 혼술 환영", "직장인 할인"처럼 결제 없이 알리는 내용이에요.\n'
            '돈을 받는 항목은 위의 "상품·이용권 판매"로 등록해주세요.',
            style: TextStyle(
              fontSize: 12.5,
              color: Colors.black54,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < widget.promotions.length; i++) ...[
            _PromotionCard(
              key: ValueKey('promo_$i'),
              index: i,
              promotion: widget.promotions[i],
              accent: widget.accent,
              expanded: _expanded == i,
              linkableProducts: widget.linkableProducts,
              onToggleExpand: () =>
                  setState(() => _expanded = _expanded == i ? null : i),
              onChanged: (next) => _update(i, next),
              onRemove: () => _remove(i),
              onMoveUp: i == 0 ? null : () => _move(i, -1),
              onMoveDown: i == widget.promotions.length - 1
                  ? null
                  : () => _move(i, 1),
            ),
            const SizedBox(height: 10),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _add,
              icon: const Icon(Icons.add, size: 18),
              label: Text(
                widget.promotions.isEmpty ? '매장 이벤트 추가' : '매장 이벤트 더 추가',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: widget.accent,
                side: BorderSide(color: widget.accent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 13),
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
}

class _PromotionCard extends StatelessWidget {
  const _PromotionCard({
    super.key,
    required this.index,
    required this.promotion,
    required this.accent,
    required this.expanded,
    required this.linkableProducts,
    required this.onToggleExpand,
    required this.onChanged,
    required this.onRemove,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final int index;
  final PlacePromotion promotion;
  final Color accent;
  final bool expanded;
  final List<PlaceProduct> linkableProducts;
  final VoidCallback onToggleExpand;
  final ValueChanged<PlacePromotion> onChanged;
  final VoidCallback onRemove;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: promotion.isVisible ? Colors.white : const Color(0xFFF4F4F6),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: expanded ? accent : const Color(0xFFE8EBF2),
          width: expanded ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: onToggleExpand,
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 8, 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          promotion.title.isEmpty ? '(제목 없음)' : promotion.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w700,
                            color: promotion.title.isEmpty
                                ? Colors.black38
                                : Colors.black87,
                          ),
                        ),
                        if (promotion.tags.isNotEmpty ||
                            promotion.periodLabel != null) ...[
                          const SizedBox(height: 3),
                          Text(
                            [
                              if (promotion.periodLabel != null)
                                promotion.periodLabel!,
                              ...promotion.tags,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.black45,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (!promotion.isVisible)
                    const Padding(
                      padding: EdgeInsets.only(right: 4),
                      child: Icon(
                        Icons.visibility_off,
                        size: 16,
                        color: Colors.black26,
                      ),
                    ),
                  _iconBtn(Icons.arrow_upward, onMoveUp),
                  _iconBtn(Icons.arrow_downward, onMoveDown),
                  Icon(
                    expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.black38,
                  ),
                  const SizedBox(width: 4),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
              child: _form(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _form(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      _text(
        '이벤트 제목',
        promotion.title,
        (v) => onChanged(promotion.copyWith(title: v)),
        hint: '예: 오늘 혼술 환영!',
      ),
      _text(
        '설명',
        promotion.description,
        (v) => onChanged(promotion.copyWith(description: v)),
        maxLines: 3,
      ),
      // 사진·동영상 — 매장 이벤트 수정 화면과 **같은 공용 편집기**로 간다
      // ([PartyMediaPickerScreen] → [PartyMediaEditor]). 크롭·대표 지정·
      // 동영상 트리밍이 전부 그 안에 있어서, 등록 중에 고른 이벤트와 나중에
      // 고친 이벤트가 다르게 동작하지 않는다.
      //
      // 여기서는 올리지 않는다 — 장소 문서가 아직 없다. 고른 파일은 초안
      // ([PlacePromotion.mediaDraft])에 담아 두고 저장 때 한 번에 올린다.
      //
      // 예전에는 이 자리가 '이미지 주소' 한 칸이었다. 사장님이 자기 사진의
      // URL을 갖고 있을 리 없어서 사실상 비워 두는 칸이었고, 그래서 등록 중에
      // 만든 이벤트만 사진도 대표도 없이 저장됐다(모델의 [imageUrl]은 그대로
      // 남아 있어 그 시절 문서는 예전처럼 읽힌다).
      _MediaRow(promotion: promotion, accent: accent, onChanged: onChanged),
      const SizedBox(height: 14),
      _text(
        '대상 조건',
        promotion.audience,
        (v) => onChanged(promotion.copyWith(audience: v)),
        hint: '예: 2인 이상 방문 시, 평일 오후 6시 이전',
      ),

      _label('태그'),
      Wrap(
        spacing: 7,
        runSpacing: 7,
        children: [
          for (final t in kPromotionTagPresets)
            _tagChip(t, promotion.tags.contains(t), () {
              final next = [...promotion.tags];
              next.contains(t) ? next.remove(t) : next.add(t);
              onChanged(promotion.copyWith(tags: next));
            }),
        ],
      ),
      const SizedBox(height: 14),

      _label('진행 기간'),
      Row(
        children: [
          Expanded(
            child: _dateBox(
              context,
              promotion.startAt,
              '시작일',
              (d) => onChanged(
                promotion.copyWith(startAt: d, endAt: promotion.endAt),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Text('~'),
          ),
          Expanded(
            child: _dateBox(
              context,
              promotion.endAt,
              '종료일',
              (d) => onChanged(
                promotion.copyWith(startAt: promotion.startAt, endAt: d),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(height: 4),
      const Text(
        '비워두면 상시 진행이에요',
        style: TextStyle(fontSize: 11.5, color: Colors.black38),
      ),

      SwitchListTile(
        value: promotion.isVisible,
        onChanged: (v) => onChanged(promotion.copyWith(isVisible: v)),
        activeThumbColor: accent,
        contentPadding: EdgeInsets.zero,
        title: const Text(
          '손님에게 노출',
          style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
        subtitle: const Text(
          '끄면 플레이스 상세에 보이지 않아요',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        ),
      ),

      // ── 관련 상품 연결 ──
      ...() {
        // 아직 저장 전이라 문서 id가 없는 상품은 연결할 수 없다.
        final linkable = linkableProducts
            .where((p) => p.id.isNotEmpty && p.name.trim().isNotEmpty)
            .toList();
        if (linkable.isEmpty) {
          return [
            const SizedBox(height: 6),
            const Text(
              '결제가 필요한 내용이면 위의 "상품·이용권 판매"에 먼저 등록해주세요.\n'
              '등록을 저장한 뒤 다시 들어오면 여기서 연결할 수 있어요.',
              style: TextStyle(
                fontSize: 11.5,
                color: Colors.black38,
                height: 1.5,
              ),
            ),
          ];
        }
        return [
          const SizedBox(height: 8),
          _label('관련 상품 연결'),
          const Text(
            '연결하면 손님이 이 이벤트에서 바로 상품 구매로 넘어갈 수 있어요.',
            style: TextStyle(fontSize: 11.5, color: Colors.black38),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              for (final p in linkable)
                _tagChip(
                  '${p.type.emoji} ${p.name}',
                  promotion.linkedProductIds.contains(p.id),
                  () {
                    final next = [...promotion.linkedProductIds];
                    next.contains(p.id) ? next.remove(p.id) : next.add(p.id);
                    onChanged(promotion.copyWith(linkedProductIds: next));
                  },
                ),
            ],
          ),
        ];
      }(),

      const SizedBox(height: 6),
      Align(
        alignment: Alignment.centerRight,
        child: TextButton.icon(
          onPressed: onRemove,
          icon: const Icon(Icons.delete_outline, size: 18),
          label: const Text('이 이벤트 삭제'),
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
        ),
      ),
    ],
  );

  Widget _label(String t) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      t,
      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
    ),
  );

  Widget _text(
    String label,
    String value,
    ValueChanged<String> onSet, {
    String? hint,
    int maxLines = 1,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label(label),
        TextFormField(
          key: ValueKey('promo|$label|$index'),
          initialValue: value,
          maxLines: maxLines,
          style: const TextStyle(fontSize: 14),
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: const TextStyle(fontSize: 13, color: Colors.black26),
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            filled: true,
            fillColor: const Color(0xFFF7F7FA),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide.none,
            ),
          ),
          onChanged: onSet,
        ),
      ],
    ),
  );

  Widget _tagChip(String text, bool selected, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? accent : const Color(0xFFF3F4F8),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? accent : const Color(0xFFDDE1EC),
            ),
          ),
          child: Text(
            text,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: selected ? Colors.white : Colors.black54,
            ),
          ),
        ),
      );

  Widget _dateBox(
    BuildContext context,
    DateTime? value,
    String placeholder,
    ValueChanged<DateTime?> onPick,
  ) => InkWell(
    onTap: () async {
      final now = DateTime.now();
      final picked = await showDatePicker(
        context: context,
        initialDate: value ?? now,
        firstDate: DateTime(now.year - 1),
        lastDate: DateTime(now.year + 3),
      );
      if (picked != null) onPick(picked);
    },
    borderRadius: BorderRadius.circular(10),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 13),
      decoration: BoxDecoration(
        color: const Color(0xFFF7F7FA),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(Icons.calendar_today, size: 15, color: accent),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              value == null
                  ? placeholder
                  : '${value.year}.${value.month}.${value.day}',
              style: TextStyle(
                fontSize: 13.5,
                color: value == null ? Colors.black26 : Colors.black87,
              ),
            ),
          ),
          if (value != null)
            GestureDetector(
              onTap: () => onPick(null),
              child: const Icon(Icons.close, size: 15, color: Colors.black26),
            ),
        ],
      ),
    ),
  );

  Widget _iconBtn(IconData icon, VoidCallback? onTap) => IconButton(
    icon: Icon(icon, size: 18),
    color: onTap == null ? Colors.black12 : Colors.black38,
    onPressed: onTap,
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    padding: EdgeInsets.zero,
    visualDensity: VisualDensity.compact,
  );
}

/// 이벤트 한 건의 **사진·동영상 줄**.
///
/// 이 위젯은 고르는 자리를 열어 주고 결과를 초안에 담을 뿐, 편집기도 업로드도
/// 직접 만들지 않는다 — 크롭·대표·트리밍은 전부
/// [PartyMediaPickerScreen]/[PartyMediaEditor] 안에 이미 있다.
///
/// ⚠️ 편집기를 이 자리에 **인라인으로 심을 수는 없다.** [PartyMediaEditor]는
///    상시 마운트를 전제로 만들어졌는데(AutomaticKeepAliveClientMixin), 이
///    섹션의 카드는 접히면 통째로 사라져서 고른 파일이 함께 날아간다. 그래서
///    파티 등록과 같은 방식으로 **별도 화면으로 열고 스냅샷을 돌려받는다**.
class _MediaRow extends StatelessWidget {
  const _MediaRow({
    required this.promotion,
    required this.accent,
    required this.onChanged,
  });

  final PlacePromotion promotion;
  final Color accent;
  final ValueChanged<PlacePromotion> onChanged;

  PlacePromotionMediaDraft get _draft =>
      promotion.mediaDraft ?? const PlacePromotionMediaDraft();

  Future<void> _open(BuildContext context) async {
    final draft = _draft;
    final picked = await Navigator.push<PartyMediaSelection>(
      context,
      webFramedRoute(
        (_) => PartyMediaPickerScreen(
          // 등록 중에 만드는 이벤트라 이미 올라간 미디어는 없다 — 편집기에는
          // 지금까지 고른 파일 스냅샷만 되돌려준다.
          existingImageUrls: const [],
          existingVideoUrl: null,
          existingVideoUid: null,
          existingVideoThumbnailUrl: null,
          newMedia: draft.newMedia,
          coverPick: draft.coverPick,
          photoCrops: draft.photoCrops,
          // 사진 상한은 매장 이벤트 수정 화면과 같은 값 하나를 쓴다.
          maxImages: kEventMaxImages,
        ),
      ),
    );
    if (picked == null) return;
    onChanged(
      promotion.copyWith(
        mediaDraft: PlacePromotionMediaDraft(
          // 경로만 남기므로 원본 XFile을 기억해 둔다 — 웹에서는 blob URL만으로는
          // 사진·동영상 구분도 형식도 알 수 없다([LocalMedia.remember]).
          newMediaPaths: [
            for (final f in picked.newMedia) LocalMedia.remember(f).path,
          ],
          coverPick: picked.coverPick,
          photoCrops: picked.photoCrops,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final draft = _draft;
    final images = draft.imageFiles;
    final hasVideo = draft.videoFile != null;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(bottom: 6),
            child: Text(
              '사진 · 동영상',
              style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
            ),
          ),
          if (draft.isNotEmpty) ...[
            SizedBox(
              height: 62,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: images.length + (hasVideo ? 1 : 0),
                separatorBuilder: (_, _) => const SizedBox(width: 6),
                itemBuilder: (_, i) {
                  if (i >= images.length) {
                    return _tile(
                      const Icon(
                        Icons.videocam_rounded,
                        size: 22,
                        color: Colors.black38,
                      ),
                    );
                  }
                  return _tile(
                    LocalMedia.image(
                      images[i],
                      width: 62,
                      height: 62,
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) => const Icon(
                        Icons.image_not_supported_outlined,
                        size: 20,
                        color: Colors.black26,
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _open(context),
              icon: const Icon(Icons.photo_library_outlined, size: 17),
              label: Text(
                draft.isEmpty ? '사진 · 동영상 선택' : '사진 · 동영상 편집 (대표 · 크롭)',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                side: BorderSide(color: accent.withValues(alpha: 0.5)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
            ),
          ),
          const SizedBox(height: 5),
          const Text(
            '고른 화면에서 대표를 지정하고 카드에 보일 위치를 맞출 수 있어요. '
            '저장할 때 함께 올라갑니다.',
            style: TextStyle(fontSize: 11, height: 1.4, color: Colors.black38),
          ),
        ],
      ),
    );
  }

  Widget _tile(Widget child) => ClipRRect(
    borderRadius: BorderRadius.circular(9),
    child: Container(
      width: 62,
      height: 62,
      color: const Color(0xFFF1F2F5),
      alignment: Alignment.center,
      child: child,
    ),
  );
}
