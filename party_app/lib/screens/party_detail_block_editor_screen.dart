import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:party_app/models/party_detail_block.dart';
import 'package:party_app/models/party_detail_theme_key.dart';
import 'package:party_app/screens/photo_crop_screen.dart';
import 'package:party_app/screens/video_trim_screen.dart';
import 'package:party_app/utils/image_dimensions.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/video_crop.dart';
import 'package:party_app/utils/video_dimensions.dart';
import 'package:party_app/widgets/party_detail_block_preview.dart';
import 'package:party_app/widgets/party_detail_theme.dart';
import 'package:party_app/widgets/party_form/party_detail_block_draft.dart';
import 'package:party_app/widgets/party_form/party_detail_block_type_sheet.dart';
import 'package:party_app/widgets/party_form/decoration_intensity_picker.dart';
import 'package:party_app/widgets/party_form/party_detail_theme_picker.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';
import 'package:party_app/widgets/web_frame.dart';

const _kAccent = Color(0xFFFF6FA0);

/// 블록 에디터가 확정 시 돌려주는 결과 — 블록 리스트, 선택된 디자인 테마,
/// 자동 꾸미기 강도, "디자인 새로고침" 변형 시드를 함께 담는다.
typedef PartyDetailBlockEditorResult = (
  List<PartyDetailBlockDraft> blocks,
  PartyDetailThemeKey theme,
  PartyDetailDecorationIntensity intensity,
  int variantSeed,
);

/// 파티 상세페이지 블록 에디터 — 블록 추가/편집/삭제/순서변경 + 디자인
/// 테마 선택 + 미리보기를 제공하는 전체 화면. 확정 시 자신의 draft
/// 리스트와 선택된 테마를 [PartyDetailBlockEditorResult]로 그대로
/// pop한다(블록 소유권 규칙은 `party_detail_block_draft.dart` 문서 참고 —
/// 테마/강도/시드는 단순 값 타입이라 별도 소유권 규칙이 필요 없다).
class PartyDetailBlockEditorScreen extends StatefulWidget {
  final List<PartyDetailBlockDraft> initialBlocks;
  final PartyDetailThemeKey initialTheme;
  final PartyDetailDecorationIntensity initialIntensity;

  /// "디자인 새로고침" 변형 시드 — 배경 장식/구분 장식의 선택을 결정적으로
  /// 바꾼다(`PartyDetailBlockPreview.variantSeed` 참고). 기본 0이면 기존
  /// 파티(이 필드가 생기기 전에 저장된)와 완전히 동일하게 렌더링된다.
  final int initialVariantSeed;

  const PartyDetailBlockEditorScreen({
    super.key,
    required this.initialBlocks,
    this.initialTheme = PartyDetailThemeKey.partychu,
    this.initialIntensity = PartyDetailDecorationIntensity.standard,
    this.initialVariantSeed = 0,
  });

  @override
  State<PartyDetailBlockEditorScreen> createState() =>
      _PartyDetailBlockEditorScreenState();
}

class _PartyDetailBlockEditorScreenState
    extends State<PartyDetailBlockEditorScreen> {
  late List<PartyDetailBlockDraft> _blocks;
  late PartyDetailThemeKey _theme;
  late PartyDetailDecorationIntensity _intensity;
  late int _variantSeed;
  bool _handedOff = false;
  bool _isProcessingVideo = false;
  final _picker = ImagePicker();

  @override
  void initState() {
    super.initState();
    _blocks = widget.initialBlocks.map((d) => d.copy()).toList();
    _theme = widget.initialTheme;
    _intensity = widget.initialIntensity;
    _variantSeed = widget.initialVariantSeed;
  }

  @override
  void dispose() {
    if (!_handedOff) {
      for (final d in _blocks) {
        d.dispose();
      }
    }
    super.dispose();
  }

  void _confirm() {
    _handedOff = true;
    Navigator.pop(context, (_blocks, _theme, _intensity, _variantSeed));
  }

  Future<void> _addBlock() async {
    final hasVideoBlock = _blocks.any(
      (d) => d.type == PartyDetailBlockType.video,
    );
    final type = await showPartyDetailBlockTypeSheet(
      context,
      videoBlockLimitReached: hasVideoBlock,
    );
    if (type == null) return;
    setState(() => _blocks.add(PartyDetailBlockDraft.newBlock(type)));
  }

  void _removeBlock(int index) {
    final removed = _blocks.removeAt(index);
    setState(() {});
    removed.dispose();
  }

  void _moveUp(int index) {
    if (index <= 0) return;
    setState(() {
      final item = _blocks.removeAt(index);
      _blocks.insert(index - 1, item);
    });
  }

  void _moveDown(int index) {
    if (index >= _blocks.length - 1) return;
    setState(() {
      final item = _blocks.removeAt(index);
      _blocks.insert(index + 1, item);
    });
  }

  void _reorder(int oldIndex, int newIndex) {
    setState(() {
      if (newIndex > oldIndex) newIndex -= 1;
      final item = _blocks.removeAt(oldIndex);
      _blocks.insert(newIndex, item);
    });
  }

  // 사진 블록은 4:5 세로 프레임에 핀치줌+드래그로 위치를 맞춘다 —
  // PartyMediaEditor의 "썸네일 위치조정"(기본카드 크롭)과 동일한 수학
  // (matrixForCrop/cropFromMatrix, lib/utils/video_crop.dart)을 그대로
  // 재사용한다. 실제 프레임 픽셀 크기는 렌더링 폭과 달라도 되고, 오직
  // 가로세로 비율만 일치하면 편집 화면과 실제 렌더링이 항상 같은
  // 결과를 낸다(프레임 크기 무관 — 위 유틸 문서 참고).
  static const double _kImageBlockAspectRatio = 4 / 5;

  Size _imageFrameSize(BuildContext context) {
    final frameWidth = MediaQuery.of(context).size.width - 32;
    return Size(frameWidth, frameWidth / _kImageBlockAspectRatio);
  }

  /// 사진 블록의 위치(크롭)를 새로 잡거나 다시 연다. [draft]에 이미 크롭
  /// 값이 있으면 이어서 수정할 수 있게 그대로 넘긴다. 완료하면 true.
  Future<bool> _openPhotoCropEditor(PartyDetailBlockDraft draft) async {
    final frame = _imageFrameSize(context);
    final result = await Navigator.push<Map<String, double>>(
      context,
      webFramedRoute(
        (_) => PhotoCropScreen(
          imageUrl: draft.newImageFile == null ? draft.uploadedImageUrl : null,
          imageFile: draft.newImageFile,
          frameWidth: frame.width,
          frameHeight: frame.height,
          initialCropX: draft.imageCropX ?? 0.5,
          initialCropY: draft.imageCropY ?? 0.5,
          initialCropScale: draft.imageCropScale ?? 1.0,
          title: '사진 위치 조정',
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return false;
    setState(() {
      draft.imageCropX = result['cropX'];
      draft.imageCropY = result['cropY'];
      draft.imageCropScale = result['cropScale'];
    });
    return true;
  }

  Future<void> _pickImageFor(PartyDetailBlockDraft draft) async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final dims = await decodeImageDimensions(file);
    if (!mounted) return;

    // 취소 시 되돌릴 이전 상태 — "사진 변경"으로 기존 사진을 바꾸다가
    // 위치 조정을 취소하면 원래 사진/크롭으로 되돌아가야 한다.
    final prevFile = draft.newImageFile;
    final prevUrl = draft.uploadedImageUrl;
    final prevW = draft.imageWidth;
    final prevH = draft.imageHeight;
    final prevCropX = draft.imageCropX;
    final prevCropY = draft.imageCropY;
    final prevCropScale = draft.imageCropScale;

    setState(() {
      draft.newImageFile = file;
      draft.uploadedImageUrl = null;
      draft.imageWidth = dims?.$1;
      draft.imageHeight = dims?.$2;
      draft.imageCropX = null;
      draft.imageCropY = null;
      draft.imageCropScale = null;
    });

    // 사진을 고르면 바로 위치 조정 화면을 띄운다 — 크롭 없는 사진 블록을
    // 만들 수 없게, 취소하면 이전 상태로 되돌린다.
    final cropped = await _openPhotoCropEditor(draft);
    if (!cropped && mounted) {
      setState(() {
        draft.newImageFile = prevFile;
        draft.uploadedImageUrl = prevUrl;
        draft.imageWidth = prevW;
        draft.imageHeight = prevH;
        draft.imageCropX = prevCropX;
        draft.imageCropY = prevCropY;
        draft.imageCropScale = prevCropScale;
      });
    }
  }

  // 사진 콜라주(imageGroup)는 칸마다 항상 정사각형(1:1) 프레임으로 위치를
  // 맞춘다 — 단일 사진 블록의 4:5 프레임과 마찬가지로 프레임 "비율"만
  // 편집 화면과 렌더링이 같으면 되므로(video_crop.dart 참고), 화면폭 기준
  // 정사각형 크기를 그대로 크롭 편집 화면에 넘긴다.
  Size _imageGroupCellFrameSize(BuildContext context) {
    final side = MediaQuery.of(context).size.width - 32;
    return Size(side, side);
  }

  Future<bool> _openImageGroupItemCropEditor(ImageGroupItemDraft item) async {
    final frame = _imageGroupCellFrameSize(context);
    final result = await Navigator.push<Map<String, double>>(
      context,
      webFramedRoute(
        (_) => PhotoCropScreen(
          imageUrl: item.newImageFile == null ? item.uploadedImageUrl : null,
          imageFile: item.newImageFile,
          frameWidth: frame.width,
          frameHeight: frame.height,
          initialCropX: item.cropX ?? 0.5,
          initialCropY: item.cropY ?? 0.5,
          initialCropScale: item.cropScale ?? 1.0,
          title: '사진 위치 조정',
        ),
        fullscreenDialog: true,
      ),
    );
    if (result == null) return false;
    setState(() {
      item.cropX = result['cropX'];
      item.cropY = result['cropY'];
      item.cropScale = result['cropScale'];
    });
    return true;
  }

  /// "+ 사진 추가" — 새 칸을 만들어 목록에 넣고 바로 위치조정 화면을 띄운다.
  /// 취소하면(크롭을 확정하지 않으면) 방금 추가한 칸 자체를 목록에서 뺀다 —
  /// 콜라주 칸에는 "빈 칸" 상태가 없어야 하므로 단일 사진 블록의 되돌리기와
  /// 달리 아예 제거한다.
  Future<void> _pickImageForNewGroupItem(PartyDetailBlockDraft d) async {
    final file = await _picker.pickImage(source: ImageSource.gallery);
    if (file == null) return;
    final dims = await decodeImageDimensions(file);
    if (!mounted) return;

    final item = ImageGroupItemDraft(
      newImageFile: file,
      width: dims?.$1,
      height: dims?.$2,
    );
    setState(() => d.imageGroupItems.add(item));

    final cropped = await _openImageGroupItemCropEditor(item);
    if (!cropped && mounted) {
      setState(() => d.imageGroupItems.remove(item));
    }
  }

  /// 동영상 1개 선택 — 기존 파티 미디어 등록(`party_media_editor.dart`)과
  /// 동일하게 30초 초과 시 트림 화면으로 보내고, 이후 압축한다. 카드
  /// 노출 위치 조정(크롭) 단계는 본문 블록에는 필요 없어 가져오지 않는다.
  Future<void> _pickVideoFor(PartyDetailBlockDraft draft) async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;

    final info = await decodeVideoLocalInfo(file);
    var videoToUse = file;

    if (info != null && info.duration.inSeconds > 30) {
      if (!mounted) return;
      // 웹에는 video_trimmer 구현이 없다 — 자르기 대신 안내하고 받지 않는다
      // (PartyMediaEditor.pickMedia()와 같은 정책).
      if (!LocalMedia.canTrimVideo) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('30초 이내 동영상만 올릴 수 있어요. 영상을 먼저 편집해 주세요.'),
          ),
        );
        return;
      }
      final trimmedPath = await Navigator.push<String>(
        context,
        webFramedRoute(
          (_) => VideoTrimScreen(sourceFile: file),
          fullscreenDialog: true,
        ),
      );
      if (trimmedPath == null) return; // 사용자가 트림을 취소함
      videoToUse = XFile(trimmedPath);
    }

    if (!mounted) return;
    setState(() => _isProcessingVideo = true);
    final compressed = await _compressVideo(videoToUse);
    final finalVideo = compressed ?? videoToUse;

    if (!mounted) return;
    setState(() {
      draft.newVideoFile = finalVideo;
      draft.uploadedVideoUid = null;
      draft.uploadedVideoUrl = null;
      draft.uploadedVideoThumbnailUrl = null;
      draft.videoAspectRatio = info?.aspectRatio;
      _isProcessingVideo = false;
    });
  }

  Future<XFile?> _compressVideo(XFile file) async {
    // 웹에는 video_compress 구현이 없다 — 압축만 건너뛰고 원본을 그대로 쓴다.
    if (!LocalMedia.canCompressVideo) return null;
    if (!(await LocalMedia.stat(file)).exists) return null;
    try {
      final result = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      final path = result?.path;
      return path != null ? XFile(path) : null;
    } catch (e) {
      debugPrint('[DetailBlockEditor] 동영상 압축 실패: $e');
      return null;
    }
  }

  Future<void> _pickTimeFor(TimelineItemDraft item) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
      builder: (ctx, child) => MediaQuery(
        data: MediaQuery.of(ctx).copyWith(alwaysUse24HourFormat: true),
        child: child!,
      ),
    );
    if (picked == null) return;
    final hh = picked.hour.toString().padLeft(2, '0');
    final mm = picked.minute.toString().padLeft(2, '0');
    setState(() => item.timeCtrl.text = '$hh:$mm');
  }

  Future<void> _openPreview() async {
    final localImageOverrides = <String, XFile>{
      for (final d in _blocks)
        if (d.type == PartyDetailBlockType.image && d.newImageFile != null)
          d.id: d.newImageFile!,
      for (final d in _blocks)
        if (d.type == PartyDetailBlockType.imageGroup)
          for (final item in d.imageGroupItems)
            if (item.newImageFile != null) item.uiKey: item.newImageFile!,
    };
    final localVideoOverrides = <String, XFile>{
      for (final d in _blocks)
        if (d.type == PartyDetailBlockType.video && d.newVideoFile != null)
          d.id: d.newVideoFile!,
    };
    final resultSeed = await Navigator.push<int>(
      context,
      webFramedRoute(
        (_) => _PreviewScreen(
          blocks: _blocks.map((d) => d.toBlock()).toList(),
          theme: _theme,
          intensity: _intensity,
          initialVariantSeed: _variantSeed,
          localImageOverrides: localImageOverrides,
          localVideoOverrides: localVideoOverrides,
        ),
      ),
    );
    if (resultSeed == null || !mounted) return;
    setState(() => _variantSeed = resultSeed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF3F4F6),
      appBar: AppBar(
        title: const Text(
          '상세페이지 만들기',
          style: TextStyle(
            fontFamily: 'SeoulHangang',
            fontWeight: FontWeight.w500,
            shadows: [
              Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
              Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
              Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
            ],
          ),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.visibility_outlined),
            tooltip: '미리보기',
            onPressed: _blocks.isEmpty ? null : _openPreview,
          ),
        ],
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF8E1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: const Color(0xFFFFCC02)),
            ),
            child: const Row(
              children: [
                Icon(Icons.info_outline, size: 14, color: Color(0xFF9A7D00)),
                SizedBox(width: 6),
                Expanded(
                  child: Text(
                    '블록을 추가해 파티 소개를 꾸며보세요. 작성하지 않아도 등록할 수 있어요.',
                    style: TextStyle(fontSize: 12, color: Color(0xFF9A7D00)),
                  ),
                ),
              ],
            ),
          ),
          _themeSection(),
          Expanded(child: _blocks.isEmpty ? _emptyState() : _blockList()),
          _bottomBar(),
        ],
      ),
    );
  }

  Widget _themeSection() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            '디자인 테마',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          PartyDetailThemePicker(
            selected: _theme,
            onChanged: (key) => setState(() => _theme = key),
          ),
          const SizedBox(height: 16),
          const Text(
            '꾸미기 강도',
            style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          DecorationIntensityPicker(
            selected: _intensity,
            onChanged: (value) => setState(() => _intensity = value),
            accentColor: _kAccent,
          ),
        ],
      ),
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: const [
            Icon(
              Icons.dashboard_customize_outlined,
              size: 40,
              color: Colors.black26,
            ),
            SizedBox(height: 12),
            Text(
              '아직 블록이 없어요',
              style: TextStyle(fontSize: 14, color: Colors.black45),
            ),
          ],
        ),
      ),
    );
  }

  Widget _blockList() {
    return ReorderableListView.builder(
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      itemCount: _blocks.length,
      onReorder: _reorder,
      itemBuilder: (context, index) => _blockCard(index),
    );
  }

  Widget _blockCard(int index) {
    final d = _blocks[index];
    return Container(
      key: ValueKey(d.id),
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.only(right: 8),
                  child: Icon(
                    Icons.drag_indicator,
                    size: 18,
                    color: Colors.black26,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  _typeLabel(d.type),
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _kAccent,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_upward, size: 18),
                onPressed: index == 0 ? null : () => _moveUp(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_downward, size: 18),
                onPressed: index == _blocks.length - 1
                    ? null
                    : () => _moveDown(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
              IconButton(
                icon: const Icon(
                  Icons.delete_outline,
                  size: 18,
                  color: Colors.redAccent,
                ),
                onPressed: () => _removeBlock(index),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 6),
          _blockEditor(d),
        ],
      ),
    );
  }

  String _typeLabel(PartyDetailBlockType type) {
    switch (type) {
      case PartyDetailBlockType.heading:
        return '큰 제목';
      case PartyDetailBlockType.subheading:
        return '소제목';
      case PartyDetailBlockType.paragraph:
        return '일반 글';
      case PartyDetailBlockType.image:
        return '사진';
      case PartyDetailBlockType.divider:
        return '구분선';
      case PartyDetailBlockType.notice:
        return '주의사항';
      case PartyDetailBlockType.checklist:
        return '체크리스트';
      case PartyDetailBlockType.faq:
        return 'FAQ';
      case PartyDetailBlockType.timeline:
        return '일정/타임라인';
      case PartyDetailBlockType.infoCard:
        return '정보 카드';
      case PartyDetailBlockType.video:
        return '동영상';
      case PartyDetailBlockType.imageGroup:
        return '사진 콜라주';
      case PartyDetailBlockType.unknown:
        return '지원하지 않는 블록';
    }
  }

  Widget _blockEditor(PartyDetailBlockDraft d) {
    switch (d.type) {
      case PartyDetailBlockType.heading:
      case PartyDetailBlockType.subheading:
        return TextField(
          controller: d.textCtrl,
          maxLines: 2,
          decoration: _deco(
            d.type == PartyDetailBlockType.heading
                ? '큰 제목을 입력하세요'
                : '소제목을 입력하세요',
          ),
        );
      case PartyDetailBlockType.paragraph:
      case PartyDetailBlockType.notice:
        return TextField(
          controller: d.textCtrl,
          minLines: 3,
          maxLines: null,
          decoration: _deco(
            d.type == PartyDetailBlockType.notice ? '주의사항을 입력하세요' : '내용을 입력하세요',
          ),
        );
      case PartyDetailBlockType.divider:
        return Container(
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: const Color(0xFFE8EBF2),
        );
      case PartyDetailBlockType.image:
        return _imageEditor(d);
      case PartyDetailBlockType.checklist:
        return _checklistEditor(d);
      case PartyDetailBlockType.faq:
        return _faqEditor(d);
      case PartyDetailBlockType.timeline:
        return _timelineEditor(d);
      case PartyDetailBlockType.infoCard:
        return _infoCardEditor(d);
      case PartyDetailBlockType.video:
        return _videoEditor(d);
      case PartyDetailBlockType.imageGroup:
        return _imageGroupEditor(d);
      case PartyDetailBlockType.unknown:
        return const Text(
          '지원하지 않는 블록이에요. 이 버전에서는 내용을 수정할 수 없지만, 삭제하지 않으면 저장 시 그대로 보존돼요.',
          style: TextStyle(fontSize: 12, color: Colors.black45),
        );
    }
  }

  Widget _imageEditor(PartyDetailBlockDraft d) {
    final hasImage =
        d.newImageFile != null || (d.uploadedImageUrl?.isNotEmpty ?? false);
    final cropX = d.imageCropX;
    final cropY = d.imageCropY;
    final cropScale = d.imageCropScale;
    final hasCrop = cropX != null && cropY != null && cropScale != null;
    final naturalAspectRatio =
        (d.imageWidth != null && d.imageHeight != null && d.imageHeight! > 0)
        ? d.imageWidth! / d.imageHeight!
        : 4 / 3;

    Widget rawImage({required Alignment alignment}) => d.newImageFile != null
        ? LocalMedia.image(
            d.newImageFile!,
            fit: BoxFit.cover,
            alignment: alignment,
            width: double.infinity,
          )
        : Image.network(
            d.uploadedImageUrl!,
            fit: BoxFit.cover,
            alignment: alignment,
            width: double.infinity,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AspectRatio(
              aspectRatio: hasCrop
                  ? _kImageBlockAspectRatio
                  : naturalAspectRatio,
              child: hasCrop
                  ? CroppedMedia(
                      cropX: cropX,
                      cropY: cropY,
                      cropScale: cropScale,
                      child: rawImage(
                        alignment: videoCropAlignment(cropX, cropY),
                      ),
                    )
                  : rawImage(alignment: Alignment.center),
            ),
          ),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            TextButton.icon(
              onPressed: () => _pickImageFor(d),
              icon: const Icon(Icons.photo_library_outlined, size: 16),
              label: Text(hasImage ? '사진 변경' : '사진 선택'),
            ),
            if (hasImage)
              TextButton.icon(
                onPressed: () => _openPhotoCropEditor(d),
                icon: const Icon(Icons.crop, size: 16),
                label: const Text('위치 조정'),
              ),
            if (hasImage)
              TextButton.icon(
                onPressed: () => setState(() {
                  d.newImageFile = null;
                  d.uploadedImageUrl = null;
                  d.imageWidth = null;
                  d.imageHeight = null;
                  d.imageCropX = null;
                  d.imageCropY = null;
                  d.imageCropScale = null;
                }),
                icon: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  '사진 제거',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
        if (hasImage)
          TextField(controller: d.captionCtrl, decoration: _deco('사진 설명 (선택)')),
      ],
    );
  }

  // ── 사진 콜라주 ─────────────────────────────────────────────────────
  Widget _imageGroupEditor(PartyDetailBlockDraft d) {
    final items = d.imageGroupItems;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final item in items) _imageGroupItemTile(d, item),
            if (items.length < 4) _imageGroupAddTile(d),
          ],
        ),
        if (items.length < 2)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              '사진을 2장 이상 넣어야 콜라주로 저장돼요',
              style: TextStyle(fontSize: 11, color: Colors.redAccent),
            ),
          ),
        if (items.isNotEmpty) ...[
          const SizedBox(height: 8),
          TextField(
            controller: d.captionCtrl,
            decoration: _deco('사진 설명 (선택, 그룹 전체에 1개)'),
          ),
        ],
      ],
    );
  }

  Widget _imageGroupItemTile(
    PartyDetailBlockDraft d,
    ImageGroupItemDraft item,
  ) {
    final cropX = item.cropX;
    final cropY = item.cropY;
    final cropScale = item.cropScale;
    final hasCrop = cropX != null && cropY != null && cropScale != null;
    final alignment = hasCrop
        ? videoCropAlignment(cropX, cropY)
        : Alignment.center;

    Widget image = item.newImageFile != null
        ? LocalMedia.image(
            item.newImageFile!,
            fit: BoxFit.cover,
            alignment: alignment,
            width: 90,
            height: 90,
          )
        : Image.network(
            item.uploadedImageUrl!,
            fit: BoxFit.cover,
            alignment: alignment,
            width: 90,
            height: 90,
          );
    if (hasCrop) {
      image = CroppedMedia(
        cropX: cropX,
        cropY: cropY,
        cropScale: cropScale,
        child: image,
      );
    }

    return GestureDetector(
      onTap: () => _openImageGroupItemCropEditor(item),
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(width: 90, height: 90, child: image),
          ),
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: () => setState(() => d.imageGroupItems.remove(item)),
              child: Container(
                width: 22,
                height: 22,
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, size: 14, color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _imageGroupAddTile(PartyDetailBlockDraft d) {
    return GestureDetector(
      onTap: () => _pickImageForNewGroupItem(d),
      child: Container(
        width: 90,
        height: 90,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: const Icon(
          Icons.add_photo_alternate_outlined,
          size: 26,
          color: Colors.black38,
        ),
      ),
    );
  }

  // ── 체크리스트 ───────────────────────────────────────────────────────
  Widget _checklistEditor(PartyDetailBlockDraft d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: d.titleCtrl,
          decoration: _deco('제목 (선택, 예: 이런 점이 좋아요)'),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < d.checklistItems.length; i++)
          _checklistItemRow(d, i),
        _addItemButton(
          onTap: () =>
              setState(() => d.checklistItems.add(ChecklistItemDraft())),
        ),
      ],
    );
  }

  Widget _checklistItemRow(PartyDetailBlockDraft d, int i) {
    final item = d.checklistItems[i];
    return Padding(
      key: ValueKey(item.uiKey),
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: item.textCtrl,
              decoration: _deco('항목 입력 (예: 웰컴드링크 제공)'),
            ),
          ),
          _itemActions(
            onUp: i == 0
                ? null
                : () => setState(() {
                    final it = d.checklistItems.removeAt(i);
                    d.checklistItems.insert(i - 1, it);
                  }),
            onDown: i == d.checklistItems.length - 1
                ? null
                : () => setState(() {
                    final it = d.checklistItems.removeAt(i);
                    d.checklistItems.insert(i + 1, it);
                  }),
            onDelete: () =>
                setState(() => d.checklistItems.removeAt(i).dispose()),
          ),
        ],
      ),
    );
  }

  // ── FAQ ─────────────────────────────────────────────────────────────
  Widget _faqEditor(PartyDetailBlockDraft d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: d.titleCtrl,
          decoration: _deco('제목 (선택, 예: 자주 묻는 질문)'),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < d.faqItems.length; i++) _faqItemCard(d, i),
        _addItemButton(
          onTap: () => setState(() => d.faqItems.add(FaqItemDraft())),
        ),
      ],
    );
  }

  Widget _faqItemCard(PartyDetailBlockDraft d, int i) {
    final item = d.faqItems[i];
    return Container(
      key: ValueKey(item.uiKey),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Q${i + 1}',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: _kAccent,
                  ),
                ),
              ),
              _itemActions(
                onUp: i == 0
                    ? null
                    : () => setState(() {
                        final it = d.faqItems.removeAt(i);
                        d.faqItems.insert(i - 1, it);
                      }),
                onDown: i == d.faqItems.length - 1
                    ? null
                    : () => setState(() {
                        final it = d.faqItems.removeAt(i);
                        d.faqItems.insert(i + 1, it);
                      }),
                onDelete: () =>
                    setState(() => d.faqItems.removeAt(i).dispose()),
              ),
            ],
          ),
          TextField(controller: item.questionCtrl, decoration: _deco('질문')),
          const SizedBox(height: 6),
          TextField(
            controller: item.answerCtrl,
            minLines: 2,
            maxLines: null,
            decoration: _deco('답변'),
          ),
        ],
      ),
    );
  }

  // ── 일정/타임라인 ───────────────────────────────────────────────────
  Widget _timelineEditor(PartyDetailBlockDraft d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(
          controller: d.titleCtrl,
          decoration: _deco('제목 (선택, 예: 진행 일정)'),
        ),
        const SizedBox(height: 8),
        for (var i = 0; i < d.timelineItems.length; i++)
          _timelineItemCard(d, i),
        _addItemButton(
          onTap: () => setState(() => d.timelineItems.add(TimelineItemDraft())),
        ),
      ],
    );
  }

  Widget _timelineItemCard(PartyDetailBlockDraft d, int i) {
    final item = d.timelineItems[i];
    return Container(
      key: ValueKey(item.uiKey),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: const Color(0xFFFAFAFC),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: 96,
                child: TextField(
                  controller: item.timeCtrl,
                  decoration: _deco('19:00').copyWith(
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.access_time, size: 18),
                      onPressed: () => _pickTimeFor(item),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: item.titleCtrl,
                  decoration: _deco('제목 (예: BBQ 파티)'),
                ),
              ),
              _itemActions(
                onUp: i == 0
                    ? null
                    : () => setState(() {
                        final it = d.timelineItems.removeAt(i);
                        d.timelineItems.insert(i - 1, it);
                      }),
                onDown: i == d.timelineItems.length - 1
                    ? null
                    : () => setState(() {
                        final it = d.timelineItems.removeAt(i);
                        d.timelineItems.insert(i + 1, it);
                      }),
                onDelete: () =>
                    setState(() => d.timelineItems.removeAt(i).dispose()),
              ),
            ],
          ),
          const SizedBox(height: 6),
          TextField(
            controller: item.descriptionCtrl,
            decoration: _deco('설명 (선택)'),
          ),
        ],
      ),
    );
  }

  // ── 정보 카드 ───────────────────────────────────────────────────────
  Widget _infoCardEditor(PartyDetailBlockDraft d) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextField(controller: d.titleCtrl, decoration: _deco('제목 (예: 준비물)')),
        const SizedBox(height: 8),
        TextField(
          controller: d.textCtrl,
          minLines: 2,
          maxLines: null,
          decoration: _deco('본문 (예: 신분증을 반드시 지참해주세요.)'),
        ),
        const SizedBox(height: 10),
        const Text(
          '아이콘',
          style: TextStyle(
            fontSize: 12,
            color: Colors.black54,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final name in partyDetailInfoCardIconNames)
              _iconChoiceChip(d, name),
          ],
        ),
      ],
    );
  }

  Widget _iconChoiceChip(PartyDetailBlockDraft d, String name) {
    final selected = d.selectedIcon == name;
    return GestureDetector(
      onTap: () => setState(() => d.selectedIcon = selected ? null : name),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? _kAccent : const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? _kAccent : const Color(0xFFE8EBF2),
          ),
        ),
        child: Icon(
          partyDetailInfoCardIconData(name),
          size: 18,
          color: selected ? Colors.white : Colors.black54,
        ),
      ),
    );
  }

  // ── 동영상 ──────────────────────────────────────────────────────────
  Widget _videoEditor(PartyDetailBlockDraft d) {
    final hasVideo =
        d.newVideoFile != null || (d.uploadedVideoUrl?.isNotEmpty ?? false);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasVideo) ...[
          _VideoPreviewBox(draft: d),
          const SizedBox(height: 8),
        ],
        Row(
          children: [
            TextButton.icon(
              onPressed: _isProcessingVideo ? null : () => _pickVideoFor(d),
              icon: _isProcessingVideo
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.videocam_outlined, size: 16),
              label: Text(
                _isProcessingVideo
                    ? '처리 중...'
                    : (hasVideo ? '동영상 변경' : '동영상 선택'),
              ),
            ),
            if (hasVideo && !_isProcessingVideo)
              TextButton.icon(
                onPressed: () => setState(() {
                  d.newVideoFile = null;
                  d.uploadedVideoUid = null;
                  d.uploadedVideoUrl = null;
                  d.uploadedVideoThumbnailUrl = null;
                  d.videoAspectRatio = null;
                }),
                icon: const Icon(
                  Icons.close,
                  size: 16,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  '동영상 제거',
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
          ],
        ),
        if (hasVideo)
          TextField(
            controller: d.captionCtrl,
            decoration: _deco('동영상 설명 (선택)'),
          ),
      ],
    );
  }

  // ── 항목 리스트 공용 위젯 ───────────────────────────────────────────
  Widget _itemActions({
    required VoidCallback? onUp,
    required VoidCallback? onDown,
    required VoidCallback onDelete,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        IconButton(
          icon: const Icon(Icons.arrow_upward, size: 16),
          onPressed: onUp,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
        IconButton(
          icon: const Icon(Icons.arrow_downward, size: 16),
          onPressed: onDown,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
        IconButton(
          icon: const Icon(Icons.close, size: 16, color: Colors.redAccent),
          onPressed: onDelete,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(minWidth: 26, minHeight: 26),
        ),
      ],
    );
  }

  Widget _addItemButton({
    required VoidCallback onTap,
    String label = '+ 항목 추가',
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(
          color: const Color(0xFFFAFAFC),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFE8EBF2)),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 12,
            color: _kAccent,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _bottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Color(0xFFEDEDED))),
      ),
      child: Column(
        children: [
          GestureDetector(
            onTap: _addBlock,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3F7),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: _kAccent.withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add, size: 16, color: _kAccent),
                  SizedBox(width: 4),
                  Text(
                    '블록 추가',
                    style: TextStyle(
                      fontSize: 13,
                      color: _kAccent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: _confirm,
              style: ElevatedButton.styleFrom(
                backgroundColor: _kAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                '저장하고 나가기',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _deco(String hint) => InputDecoration(
    hintText: hint,
    filled: true,
    fillColor: const Color(0xFFF7F7FA),
    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(10),
      borderSide: const BorderSide(color: Color(0xFFE8EBF2)),
    ),
  );
}

/// 블록 에디터 미리보기 — "디자인 새로고침" 버튼으로 배경 장식/구분 장식의
/// 선택([_variantSeed])만 바꿔가며 마음에 드는 조합을 고를 수 있다(문단
/// 분류가 없는 블록 모드이므로 "간편 자동 꾸미기"의 다시 꾸미기와 달리
/// 블록 내용 자체는 전혀 영향받지 않는다). 화면을 나갈 때 최종 시드를
/// pop으로 돌려준다 — `_AutoDescriptionPreviewScreen`(party_intro_screen.dart)
/// 과 동일한 패턴.
class _PreviewScreen extends StatefulWidget {
  final List<PartyDetailBlock> blocks;
  final PartyDetailThemeKey theme;
  final PartyDetailDecorationIntensity intensity;
  final int initialVariantSeed;
  final Map<String, XFile> localImageOverrides;
  final Map<String, XFile> localVideoOverrides;

  const _PreviewScreen({
    required this.blocks,
    required this.theme,
    required this.intensity,
    required this.initialVariantSeed,
    required this.localImageOverrides,
    required this.localVideoOverrides,
  });

  @override
  State<_PreviewScreen> createState() => _PreviewScreenState();
}

class _PreviewScreenState extends State<_PreviewScreen> {
  late int _variantSeed = widget.initialVariantSeed;

  void _regenerate() => setState(() => _variantSeed++);

  @override
  Widget build(BuildContext context) {
    // 미리보기는 실제 상세화면과 완전히 같은 렌더러(PartyDetailBlockPreview)와
    // 테마 객체를 그대로 쓴다 — 별도 색상 계산이나 스타일 복제가 없다.
    final palette = PartyDetailThemeRegistry.fromKey(widget.theme);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) Navigator.pop(context, _variantSeed);
      },
      child: Scaffold(
        backgroundColor: palette.pageBackground,
        appBar: AppBar(
          title: const Text(
            '미리보기',
            style: TextStyle(
              fontFamily: 'SeoulHangang',
              fontWeight: FontWeight.w500,
              shadows: [
                Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
                Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
                Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
              ],
            ),
          ),
          centerTitle: true,
          actions: [
            TextButton.icon(
              onPressed: _regenerate,
              icon: const Icon(Icons.refresh, color: _kAccent, size: 18),
              label: const Text('디자인 새로고침', style: TextStyle(color: _kAccent)),
            ),
          ],
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: PartyDetailBlockPreview(
            blocks: widget.blocks,
            theme: widget.theme,
            intensity: widget.intensity,
            variantSeed: _variantSeed,
            localImageOverrides: widget.localImageOverrides,
            localVideoOverrides: widget.localVideoOverrides,
          ),
        ),
      ),
    );
  }
}

/// 동영상 블록 카드 안의 간단한 탭-재생 미리보기 — 로컬 파일이든(방금
/// 골라서 아직 업로드 전) 이미 업로드된 URL이든 그대로 재생해볼 수 있다.
/// 에디터는 화면이 하나뿐이라(스크롤 피드가 아님) `FeedVideoManager` 연동
/// 없이 이 위젯 하나만 독립적으로 재생/일시정지한다 — 실제 상세화면에서의
/// 재생 정책(전역 음소거·단일 재생·화면이탈 정지)은 `PartyDetailBlockPreview`
/// 안의 `_DetailVideoPlayer`가 담당한다.
class _VideoPreviewBox extends StatefulWidget {
  final PartyDetailBlockDraft draft;

  const _VideoPreviewBox({required this.draft});

  @override
  State<_VideoPreviewBox> createState() => _VideoPreviewBoxState();
}

class _VideoPreviewBoxState extends State<_VideoPreviewBox> {
  VideoPlayerController? _ctrl;

  String? get _source {
    final d = widget.draft;
    if (d.newVideoFile != null) return d.newVideoFile!.path;
    return d.uploadedVideoUrl;
  }

  bool get _isLocal => widget.draft.newVideoFile != null;

  Future<void> _togglePlay() async {
    var ctrl = _ctrl;
    if (ctrl == null) {
      final src = _source;
      if (src == null || src.isEmpty) return;
      final newCtrl = _isLocal
          ? LocalMedia.videoControllerForPath(src)
          : VideoPlayerController.networkUrl(Uri.parse(src));
      try {
        await newCtrl.initialize();
      } catch (e) {
        debugPrint('[DetailBlockEditor] 동영상 미리보기 초기화 실패: $e');
        return;
      }
      if (!mounted) {
        await newCtrl.dispose();
        return;
      }
      _ctrl = newCtrl;
      ctrl = newCtrl;
    }
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
    } else {
      await ctrl.play();
    }
    if (!mounted) return;
    setState(() {});
  }

  @override
  void dispose() {
    _ctrl?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.draft;
    final ratio = d.videoAspectRatio;
    final aspectRatio = (ratio != null && ratio > 0) ? ratio : 16 / 9;
    final ctrl = _ctrl;
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: AspectRatio(
        aspectRatio: aspectRatio,
        child: GestureDetector(
          onTap: _togglePlay,
          behavior: HitTestBehavior.opaque,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              if (ctrl != null && ctrl.value.isInitialized)
                VideoPlayer(ctrl)
              else if (!_isLocal &&
                  (d.uploadedVideoThumbnailUrl?.isNotEmpty ?? false))
                Image.network(
                  d.uploadedVideoThumbnailUrl!,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) =>
                      Container(color: Colors.black87),
                )
              else
                Container(color: Colors.black87),
              if (ctrl == null || !ctrl.value.isPlaying)
                Container(
                  width: 48,
                  height: 48,
                  decoration: const BoxDecoration(
                    color: Colors.black38,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.play_arrow,
                    color: Colors.white,
                    size: 28,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
