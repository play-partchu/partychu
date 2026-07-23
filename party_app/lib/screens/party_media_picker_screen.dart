import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/spotify_track.dart';
import 'package:party_app/widgets/party_form/spotify_section.dart';
import 'package:party_app/widgets/party_media_editor.dart';
import 'package:video_compress/video_compress.dart';

class PartyMediaSelection {
  final List<String> existingImageUrls;
  final String? existingVideoUrl;
  final String? existingVideoUid;
  final String? existingVideoThumbnailUrl;
  final List<XFile> newMedia;
  final PartyCoverPick? coverPick;
  final SpotifyTrack? spotifyTrack;
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
    required this.spotifyTrack,
    this.basicCardFocalX = 0.5,
    this.basicCardFocalY = 0.5,
    this.basicCardScale = 1.0,
    this.photoCrops = const {},
    this.videoCropConfirmed = false,
  });
}

/// "미디어 등록" 행 — 기존 `PartyMediaEditor` + Spotify 배경음악 섹션을
/// 감싼 화면. `PartyMediaEditor`는 AutomaticKeepAliveClientMixin으로 상시
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
  final SpotifyTrack? spotifyTrack;
  final double basicCardFocalX;
  final double basicCardFocalY;
  final double basicCardScale;
  final Map<String, Map<String, double>> photoCrops;
  final bool videoCropConfirmed;

  /// Spotify 배경음악 섹션은 파티 전용 기능이라, 파티가 아닌 다른 등록
  /// 화면(예: 장소대여)에서 이 픽커를 재사용할 때는 false로 꺼서 숨긴다.
  final bool showSpotifySection;

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
    this.spotifyTrack,
    this.basicCardFocalX = 0.5,
    this.basicCardFocalY = 0.5,
    this.basicCardScale = 1.0,
    this.photoCrops = const {},
    this.videoCropConfirmed = false,
    this.showSpotifySection = true,
    this.showVideoCropButton = true,
    this.maxImages = 5,
  });

  @override
  State<PartyMediaPickerScreen> createState() => _PartyMediaPickerScreenState();
}

class _PartyMediaPickerScreenState extends State<PartyMediaPickerScreen> {
  final _mediaEditorKey = GlobalKey<PartyMediaEditorState>();
  late SpotifyTrack? _spotifyTrack = widget.spotifyTrack;
  bool _isCompressing = false;

  @override
  void dispose() {
    // 압축이 진행 중인 채로 이 화면을 벗어나면(뒤로가기 등) 취소한다 —
    // 기존에는 등록 화면 dispose()에서 처리했지만, 압축은 이제 이 화면
    // 안에서만 일어나므로 취소 책임도 여기로 옮긴다.
    VideoCompress.cancelCompression();
    super.dispose();
  }

  void _confirm() {
    final s = _mediaEditorKey.currentState!;
    if (widget.showVideoCropButton && !s.isThumbnailCropConfirmed) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('썸네일 위치조정 필수')),
      );
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
        spotifyTrack: _spotifyTrack,
        basicCardFocalX: s.basicCardFocalX,
        basicCardFocalY: s.basicCardFocalY,
        basicCardScale: s.basicCardScale,
        photoCrops: s.photoCrops,
        videoCropConfirmed: s.videoCropConfirmed,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasVideo = _mediaEditorKey.currentState?.hasVideo ?? false;
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(title: const Text('미디어 등록', style: TextStyle(fontFamily: 'SeoulHangang', fontWeight: FontWeight.w500, shadows: [Shadow(color: Colors.black87, offset: Offset(0.3, 0)), Shadow(color: Colors.black87, offset: Offset(-0.3, 0)), Shadow(color: Colors.black87, offset: Offset(0, 0.3)), Shadow(color: Colors.black87, offset: Offset(0, -0.3))])), centerTitle: true),
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
                        if (widget.showSpotifySection && !hasVideo) ...[
                          const SizedBox(height: 12),
                          SpotifySection(
                            track: _spotifyTrack,
                            onChanged: (t) => setState(() => _spotifyTrack = t),
                          ),
                        ],
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
