import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/widgets/party_media_editor.dart';
import 'package:video_compress/video_compress.dart';

class PartyMediaSelection {
  final List<String> existingImageUrls;
  final String? existingVideoUrl;
  final String? existingVideoUid;
  final String? existingVideoThumbnailUrl;
  final List<XFile> newMedia;
  final PartyCoverPick? coverPick;
  final double basicCardFocalX;
  final double basicCardFocalY;
  final double basicCardScale;
  final Map<String, Map<String, double>> photoCrops;
  final bool videoCropConfirmed;

  const PartyMediaSelection({
    required this.existingImageUrls,
    required this.existingVideoUrl,
    required this.existingVideoUid,
    required this.existingVideoThumbnailUrl,
    required this.newMedia,
    required this.coverPick,
    this.basicCardFocalX = 0.5,
    this.basicCardFocalY = 0.5,
    this.basicCardScale = 1.0,
    this.photoCrops = const {},
    this.videoCropConfirmed = false,
  });
}

/// "사진 / 동영상 등록" 행 — `PartyMediaEditor`를 감싼 화면.
/// `PartyMediaEditor`는 AutomaticKeepAliveClientMixin으로 상시
/// 마운트를 전제하므로, 이 화면을 pop할 때 그 State가 사라지기 전에 반드시
/// 여기서 스냅샷을 읽어 부모(등록 화면)에 돌려준다 — 부모는 다음에 이
/// 화면을 다시 열 때 그 스냅샷을 initial* 파라미터로 그대로 되돌려준다.
class PartyMediaPickerScreen extends StatefulWidget {
  final List<String> existingImageUrls;
  final String? existingVideoUrl;
  final String? existingVideoUid;
  final String? existingVideoThumbnailUrl;
  final List<XFile> newMedia;
  final PartyCoverPick? coverPick;
  final double basicCardFocalX;
  final double basicCardFocalY;
  final double basicCardScale;
  final Map<String, Map<String, double>> photoCrops;
  final bool videoCropConfirmed;

  /// true(기본값)면 동영상 타일에 "카드 노출 위치 조정" 버튼을 보여준다.
  /// 장소대여처럼 "기본 카드" 개념이 없는 화면은 false로 끈다.
  final bool showVideoCropButton;

  /// 사진 업로드 최대 개수 — 화면마다 다르다(파티 8장, 장소대여 10장 등).
  final int maxImages;

  const PartyMediaPickerScreen({
    super.key,
    required this.existingImageUrls,
    required this.existingVideoUrl,
    required this.existingVideoUid,
    required this.existingVideoThumbnailUrl,
    required this.newMedia,
    required this.coverPick,
    this.basicCardFocalX = 0.5,
    this.basicCardFocalY = 0.5,
    this.basicCardScale = 1.0,
    this.photoCrops = const {},
    this.videoCropConfirmed = false,
    this.showVideoCropButton = true,
    this.maxImages = 5,
  });

  @override
  State<PartyMediaPickerScreen> createState() => _PartyMediaPickerScreenState();
}

class _PartyMediaPickerScreenState extends State<PartyMediaPickerScreen> {
  final _mediaEditorKey = GlobalKey<PartyMediaEditorState>();
  bool _isCompressing = false;

  @override
  void dispose() {
    // 압축이 진행 중인 채로 이 화면을 벗어나면(뒤로가기 등) 취소한다 —
    // 기존에는 등록 화면 dispose()에서 처리했지만, 압축은 이제 이 화면
    // 안에서만 일어나므로 취소 책임도 여기로 옮긴다.
    // 웹에는 플러그인이 없어 애초에 압축을 시작하지 않는다.
    if (LocalMedia.canCompressVideo) VideoCompress.cancelCompression();
    super.dispose();
  }

  /// 이 화면에서 **고쳐진 것이 있는지** — 뒤로가기로 조용히 버려지면 안 되는
  /// 상태가 남아 있는가.
  ///
  /// 들어올 때 받은 스냅샷과 지금 편집기 상태를 비교한다. "새로 고른 파일이
  /// 있으면"만 보면 부족하다 — 기존 사진을 지우거나 대표를 바꾼 것도 사용자가
  /// 한 작업이고, 뒤로가기 한 번에 되돌아가면 똑같이 당황스럽다.
  bool get _hasUnsavedChanges {
    final s = _mediaEditorKey.currentState;
    if (s == null) return false;
    if (s.newMediaFiles.length != widget.newMedia.length) return true;
    for (var i = 0; i < s.newMediaFiles.length; i++) {
      if (s.newMediaFiles[i].path != widget.newMedia[i].path) return true;
    }
    if (s.existingImageUrls.length != widget.existingImageUrls.length) {
      return true;
    }
    for (var i = 0; i < s.existingImageUrls.length; i++) {
      if (s.existingImageUrls[i] != widget.existingImageUrls[i]) return true;
    }
    if (s.existingVideoUrl != widget.existingVideoUrl) return true;
    if (s.basicCardFocalX != widget.basicCardFocalX) return true;
    if (s.basicCardFocalY != widget.basicCardFocalY) return true;
    if (s.basicCardScale != widget.basicCardScale) return true;
    if (s.photoCrops.length != widget.photoCrops.length) return true;
    // 대표 미디어를 바꾼 것만으로도 돌려줄 값이 달라진다.
    final before = widget.coverPick;
    final now = s.coverPick;
    if ((before == null) != (now == null)) return true;
    if (before != null && now != null) {
      if (before.existingImageUrl != now.existingImageUrl) return true;
      if (before.isExistingVideo != now.isExistingVideo) return true;
      if (before.newImageOrdinal != now.newImageOrdinal) return true;
      if (before.isNewVideo != now.isNewVideo) return true;
    }
    return false;
  }

  /// 뒤로가기 — 고른 미디어가 **조용히 사라지지 않게** 한 번 묻는다.
  ///
  /// 이 화면은 '선택 완료'를 눌러 pop할 때만 부모에게 값을 돌려준다
  /// (클래스 주석 참고). 그래서 뒤로가기는 곧 "고른 것 전부 버리기"인데,
  /// 예전에는 아무 경고 없이 그대로 버렸다 — 사진을 고르고 뒤로 나온 사람은
  /// "선택했는데 등록이 안 됐다"고 느낀다.
  Future<bool> _confirmDiscard() async {
    if (!_hasUnsavedChanges) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text('고른 미디어를 버릴까요?'),
        content: const Text(
          '아직 "선택 완료"를 누르지 않아서, 지금 나가면 이 화면에서 고른 '
          '사진·동영상이 등록 화면에 반영되지 않아요.',
          style: TextStyle(height: 1.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('계속 편집'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('버리고 나가기'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  void _confirm() {
    final s = _mediaEditorKey.currentState!;
    if (widget.showVideoCropButton && !s.isThumbnailCropConfirmed) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('썸네일 위치조정 필수')));
      return;
    }
    Navigator.pop(
      context,
      PartyMediaSelection(
        existingImageUrls: s.existingImageUrls,
        existingVideoUrl: s.existingVideoUrl,
        existingVideoUid: s.existingVideoUid,
        existingVideoThumbnailUrl: s.existingVideoThumbnailUrl,
        newMedia: s.newMediaFiles,
        coverPick: s.coverPick,
        basicCardFocalX: s.basicCardFocalX,
        basicCardFocalY: s.basicCardFocalY,
        basicCardScale: s.basicCardScale,
        photoCrops: s.photoCrops,
        videoCropConfirmed: s.videoCropConfirmed,
      ),
    );
  }

  // 동영상 등록 권유 카드 — 위 "사진을 눌러 대표이미지로 설정할 수 있습니다"
  // 안내와 동일한 팔레트(배경 #FFF8E1 / 테두리 #FFCC02 / 글자·아이콘 #9A7D00)와
  // 카드 모양(radius 8)을 그대로 쓴다.
  Widget _buildVideoPromoCard() {
    const accent = Color(0xFF9A7D00);
    const benefits = [
      '✨ 파티 분위기를 한눈에 전달',
      '👀 목록에서 더욱 눈에 띄어 클릭률 증가',
      '❤️ 참가자가 신뢰하기 쉬움',
      '🚀 사진보다 더 높은 참여율 기대',
    ];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: const Color(0xFFFFCC02)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.videocam_outlined, size: 14, color: accent),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  '동영상을 대표로 설정해보세요!',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(left: 20, top: 5),
            child: Text(
              '사진보다 파티 분위기를 더 생생하게 전달할 수 있어 참가 신청률을 '
              '높이는 데 도움이 됩니다.',
              style: TextStyle(fontSize: 11.5, color: accent, height: 1.45),
            ),
          ),
          const SizedBox(height: 7),
          for (final benefit in benefits)
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 3),
              child: Text(
                benefit,
                style: const TextStyle(
                  fontSize: 11.5,
                  color: accent,
                  height: 1.35,
                ),
              ),
            ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              // 아래 미디어 편집기의 "사진/동영상" 추가 버튼과 완전히 같은
              // 흐름을 탄다 — 선택·30초 자르기·압축까지 그대로 재사용.
              onPressed: () => _mediaEditorKey.currentState?.pickMedia(),
              icon: const Icon(Icons.videocam_rounded, size: 16),
              label: const Text(
                '동영상 추가하기',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.bold),
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor: accent,
                backgroundColor: Colors.white,
                side: const BorderSide(color: Color(0xFFFFCC02)),
                padding: const EdgeInsets.symmetric(vertical: 9),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// 지금 동영상이 하나라도 있는지.
  ///
  /// 첫 프레임에는 자식(PartyMediaEditor)의 State가 아직 없어서
  /// `currentState`가 null이다 — 그때 무조건 false로 보면, 이미 동영상이
  /// 있는 파티를 수정하러 들어와도 "동영상을 추가하세요" 안내가 한 번
  /// 깜빡인다. 그래서 State가 생기기 전에는 넘겨받은 초기값으로 판단하고,
  /// 이후에는 편집기의 실제 상태를 따른다(onMediaChanged가 갱신해준다).
  bool get _hasVideo =>
      _mediaEditorKey.currentState?.hasVideo ??
      (widget.existingVideoUrl != null ||
          widget.newMedia.any(PartyMediaEditorState.isVideoFile));

  @override
  Widget build(BuildContext context) {
    final hasVideo = _hasVideo;
    return PopScope(
      // 고른 것이 없으면 예전 그대로 곧장 닫힌다 — 확인창은 실제로 버려질
      // 작업이 있을 때만 뜬다.
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirmDiscard() && mounted) {
          if (!context.mounted) return;
          Navigator.pop(context);
        }
      },
      child: _buildScaffold(context, hasVideo),
    );
  }

  Widget _buildScaffold(BuildContext context, bool hasVideo) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          '사진 / 동영상 등록',
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
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF8E1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFFCC02)),
                  ),
                  child: const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        size: 14,
                        color: Color(0xFF9A7D00),
                      ),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          '사진을 눌러 대표이미지로 설정할 수 있습니다.',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF9A7D00),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                // 아직 동영상이 없을 때만 보이는 권유 카드 — 동영상을 하나라도
                // 넣으면(hasVideo) 곧바로 사라진다. PartyMediaEditor가 내부
                // setState마다 onMediaChanged로 알려주므로 추가/삭제가 바로
                // 반영된다. 위 "대표이미지 설정" 안내와 색·아이콘·카드 모양을
                // 그대로 맞춰 통일감을 유지한다.
                if (!hasVideo) _buildVideoPromoCard(),
                Expanded(
                  child: SingleChildScrollView(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PartyMediaEditor(
                          key: _mediaEditorKey,
                          initialImageUrls: widget.existingImageUrls,
                          initialVideoUrl: widget.existingVideoUrl,
                          initialVideoUid: widget.existingVideoUid,
                          initialVideoThumbnailUrl:
                              widget.existingVideoThumbnailUrl,
                          initialNewMedia: widget.newMedia,
                          initialCoverPick: widget.coverPick,
                          initialBasicCardFocalX: widget.basicCardFocalX,
                          initialBasicCardFocalY: widget.basicCardFocalY,
                          initialBasicCardScale: widget.basicCardScale,
                          initialPhotoCrops: widget.photoCrops,
                          initialVideoCropConfirmed: widget.videoCropConfirmed,
                          showVideoCropButton: widget.showVideoCropButton,
                          maxImages: widget.maxImages,
                          onCompressingChanged: (v) =>
                              setState(() => _isCompressing = v),
                          onMediaChanged: () => setState(() {}),
                        ),
                        const SizedBox(height: 16),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton(
                            onPressed: _isCompressing ? null : _confirm,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF6FA0),
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text(
                              '선택 완료',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_isCompressing)
            Container(
              color: Colors.black45,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(color: Colors.white),
                    SizedBox(height: 16),
                    Text(
                      '동영상을 최적화하는 중입니다...',
                      style: TextStyle(color: Colors.white, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
