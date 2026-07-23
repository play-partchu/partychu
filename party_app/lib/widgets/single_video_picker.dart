import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_compress/video_compress.dart';
import 'package:video_player/video_player.dart';
import 'package:party_app/screens/video_trim_screen.dart';

/// 이벤트/파티샵 등록처럼 "대표 이미지 1장 + 소개 이미지" 구조를 쓰는 단순한
/// 등록 화면에 동영상 1개 업로드를 추가하기 위한 단일 슬롯 피커.
/// `PartyMediaEditor.pickMedia()`의 동영상 처리(30초 초과 시 트림 → 압축)와
/// 동일한 로직을 쓰되, 사진과 섞이지 않는 단일 슬롯 UI로 단순화했다.
///
/// 사용: `GlobalKey<SingleVideoPickerState>`로 접근해 저장 시 [newVideoFile]
/// (새로 고른 파일, 업로드 필요) 또는 [existingVideoUrl] 등(기존 값 그대로
/// 유지, 재업로드 불필요)을 읽는다.
class SingleVideoPicker extends StatefulWidget {
  final String? initialVideoUrl;
  final String? initialVideoUid;
  final String? initialVideoThumbnailUrl;

  /// 동영상 압축 시작/종료 시 호출 — 부모 화면의 제출 버튼 비활성화 등에 사용.
  final void Function(bool isCompressing)? onCompressingChanged;

  /// 동영상 추가/교체/삭제로 내부 상태가 바뀔 때마다 호출.
  final VoidCallback? onChanged;

  const SingleVideoPicker({
    super.key,
    this.initialVideoUrl,
    this.initialVideoUid,
    this.initialVideoThumbnailUrl,
    this.onCompressingChanged,
    this.onChanged,
  });

  @override
  State<SingleVideoPicker> createState() => SingleVideoPickerState();
}

class SingleVideoPickerState extends State<SingleVideoPicker> {
  final _picker = ImagePicker();
  String? _existingVideoUrl;
  String? _existingVideoUid;
  String? _existingVideoThumbnailUrl;
  XFile? _newVideo;
  bool _isCompressing = false;

  String? get existingVideoUrl => _existingVideoUrl;
  String? get existingVideoUid => _existingVideoUid;
  String? get existingVideoThumbnailUrl => _existingVideoThumbnailUrl;
  XFile? get newVideoFile => _newVideo;
  bool get hasVideo => _existingVideoUrl != null || _newVideo != null;
  bool get isCompressing => _isCompressing;

  @override
  void initState() {
    super.initState();
    _existingVideoUrl = widget.initialVideoUrl;
    _existingVideoUid = widget.initialVideoUid;
    _existingVideoThumbnailUrl = widget.initialVideoThumbnailUrl;
  }

  @override
  void dispose() {
    // 압축이 진행 중인 채로 부모 화면을 벗어나면(뒤로가기 등) 취소한다 —
    // party_media_picker_screen.dart의 동일한 안전장치 참고.
    VideoCompress.cancelCompression();
    super.dispose();
  }

  Future<void> _pick() async {
    final file = await _picker.pickVideo(source: ImageSource.gallery);
    if (file == null) return;

    final ctrl = VideoPlayerController.file(File(file.path));
    await ctrl.initialize();
    final secs = ctrl.value.duration.inSeconds;
    await ctrl.dispose();

    // 30초를 넘으면 앱 안에서 바로 30초 이내로 잘라낼 수 있게 편집 화면으로
    // 보낸다 — PartyMediaEditor.pickMedia()와 동일한 정책.
    var videoToUpload = file;
    if (secs > 30) {
      if (!mounted) return;
      final trimmedPath = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => VideoTrimScreen(sourceFile: File(file.path)),
          fullscreenDialog: true,
        ),
      );
      if (trimmedPath == null) return; // 사용자가 편집을 취소함
      videoToUpload = XFile(trimmedPath);
    }

    if (!mounted) return;
    setState(() => _isCompressing = true);
    widget.onCompressingChanged?.call(true);
    final compressed = await _compressVideo(videoToUpload);
    if (!mounted) return;
    setState(() {
      _isCompressing = false;
      // 압축이 실패해도 방금 고르거나 편집한 영상 자체를 잃어버리면 안 되므로,
      // 압축 전 파일(편집본 또는 원본)을 그대로 등록 흐름에 태운다.
      _newVideo = compressed ?? videoToUpload;
      _existingVideoUrl = null;
      _existingVideoUid = null;
      _existingVideoThumbnailUrl = null;
    });
    widget.onCompressingChanged?.call(false);
    widget.onChanged?.call();
  }

  Future<XFile?> _compressVideo(XFile file) async {
    if (!File(file.path).existsSync()) return null;
    try {
      final info = await VideoCompress.compressVideo(
        file.path,
        quality: VideoQuality.MediumQuality,
        deleteOrigin: false,
      );
      final resultPath = info?.path;
      return resultPath != null ? XFile(resultPath) : null;
    } catch (e) {
      debugPrint('[SingleVideoPicker] 압축 오류: $e');
      return null;
    }
  }

  void _remove() {
    setState(() {
      _newVideo = null;
      _existingVideoUrl = null;
      _existingVideoUid = null;
      _existingVideoThumbnailUrl = null;
    });
    widget.onChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    if (_isCompressing) {
      return Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EBF2)),
        ),
        child: const Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Color(0xFFFF6FA0),
                ),
              ),
              SizedBox(height: 8),
              Text('동영상 압축 중...', style: TextStyle(fontSize: 12, color: Colors.black45)),
            ],
          ),
        ),
      );
    }

    if (hasVideo) {
      final thumbnailUrl = _existingVideoThumbnailUrl;
      return Stack(clipBehavior: Clip.none, children: [
        Container(
          width: double.infinity,
          height: 140,
          decoration: BoxDecoration(
            color: Colors.black87,
            borderRadius: BorderRadius.circular(12),
          ),
          child: thumbnailUrl != null && thumbnailUrl.isNotEmpty
              ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.network(
                    thumbnailUrl,
                    width: double.infinity,
                    height: 140,
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) => const _VideoPlaceholderIcon(),
                  ),
                )
              : const _VideoPlaceholderIcon(),
        ),
        Positioned(
          top: 8,
          right: 8,
          child: GestureDetector(
            onTap: _remove,
            child: Container(
              width: 26,
              height: 26,
              decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.black54),
              child: const Icon(Icons.close, size: 14, color: Colors.white),
            ),
          ),
        ),
        Positioned(
          bottom: 8,
          right: 8,
          child: GestureDetector(
            onTap: _pick,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text('변경', style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
          ),
        ),
      ]);
    }

    return GestureDetector(
      onTap: _pick,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFFF7F7FA),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFE8EBF2)),
        ),
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.videocam_outlined, size: 32, color: Colors.black38),
            SizedBox(height: 6),
            Text('동영상 추가', style: TextStyle(fontSize: 13, color: Colors.black38)),
          ],
        ),
      ),
    );
  }
}

class _VideoPlaceholderIcon extends StatelessWidget {
  const _VideoPlaceholderIcon();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.videocam, size: 32, color: Colors.white70),
          SizedBox(height: 4),
          Text('동영상', style: TextStyle(color: Colors.white70, fontSize: 12)),
        ],
      ),
    );
  }
}
