import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:video_trimmer/video_trimmer.dart';

/// 30초를 넘는 동영상을 앱 안에서 바로 30초 이내로 잘라내는 편집 화면
/// (인스타그램 릴스/틱톡 스타일 타임라인 트리머).
///
/// 완료를 누르면 실제로 잘라낸 결과 파일의 로컬 경로를 pop으로 돌려주고,
/// 취소하면 null을 돌려준다 — 호출부(PartyMediaEditor)는 원본이 아니라 이
/// 결과 파일만 이후 압축·업로드 파이프라인에 태운다. 즉 서버로 원본을 올린
/// 뒤 자르는 방식이 아니라, 반드시 앱에서 먼저 잘라서 그 결과만 올린다.
///
/// **앱(Android/iOS) 전용 화면이다.** video_trimmer에는 웹 구현이 없어서
/// 웹에서는 이 화면을 열지 않는다 — 호출부가 [LocalMedia.canTrimVideo]로
/// 갈라, 웹에서는 30초를 넘는 영상을 자르는 대신 안내하고 받지 않는다.
/// 그래서 여기서는 dart:io를 그대로 쓴다.
class VideoTrimScreen extends StatefulWidget {
  /// 자를 원본. 앱 전용 화면이라 경로는 항상 실제 파일 경로다.
  final XFile sourceFile;

  static const maxDuration = Duration(seconds: 30);

  const VideoTrimScreen({super.key, required this.sourceFile});

  @override
  State<VideoTrimScreen> createState() => _VideoTrimScreenState();
}

class _VideoTrimScreenState extends State<VideoTrimScreen> {
  final Trimmer _trimmer = Trimmer();

  double _startValue = 0.0;
  double _endValue = 0.0;
  bool _isPlaying = false;
  bool _isSaving = false;
  bool _isReady = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    // 중요: Trimmer.eventStream은 브로드캐스트 스트림이라 이벤트를 다시
    // 재생해주지 않는다 — loadVideo()가 완료된 "뒤에" TrimViewer/VideoViewer를
    // 조건부로 트리에 넣으면, 그 위젯들의 initState가 구독을 시작하기 전에
    // TrimmerEvent.initialized가 이미 지나가버려서 영원히 빈 화면(SizedBox)만
    // 그려지는 문제가 있었다. 그래서 이 화면 자체의 구독을 loadVideo() 호출
    // "전"에 걸어두고, TrimViewer/VideoViewer는 아래 build()에서 항상(로딩
    // 중에도) 트리에 포함시켜 그 위젯들이 스스로 제때 구독하게 한다.
    _trimmer.eventStream.listen((event) {
      if (event != TrimmerEvent.initialized || !mounted) return;
      setState(() => _isReady = true);
      // 재생 버튼으로 시작한 뒤, 선택 구간 끝에 도달하면 처음으로 되돌아가
      // 계속 반복 재생되게 한다("선택한 구간만 반복 미리보기").
      _trimmer.videoPlayerController?.addListener(_onPlaybackPositionChanged);
    });
    _trimmer.loadVideo(videoFile: File(widget.sourceFile.path)).catchError((
      e,
    ) {
      if (mounted) setState(() => _loadFailed = true);
    });
  }

  @override
  void dispose() {
    _trimmer.videoPlayerController?.removeListener(_onPlaybackPositionChanged);
    _trimmer.dispose();
    super.dispose();
  }

  void _onPlaybackPositionChanged() {
    final ctrl = _trimmer.videoPlayerController;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (_endValue <= _startValue) return;
    if (ctrl.value.isPlaying &&
        ctrl.value.position.inMilliseconds >= _endValue.toInt()) {
      ctrl.seekTo(Duration(milliseconds: _startValue.toInt()));
      ctrl.play();
    }
  }

  double get _selectedSeconds {
    final ms = (_endValue - _startValue).clamp(
      0,
      VideoTrimScreen.maxDuration.inMilliseconds,
    );
    return ms / 1000;
  }

  String _fmtSeconds(double ms) => (ms / 1000).toStringAsFixed(1);

  Future<void> _togglePlayback() async {
    final playing = await _trimmer.videoPlaybackControl(
      startValue: _startValue,
      endValue: _endValue,
    );
    if (mounted) setState(() => _isPlaying = playing);
  }

  Future<void> _save() async {
    if (_isSaving || !_isReady) return;
    if (_endValue - _startValue < 500) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('선택한 구간이 너무 짧아요. 0.5초 이상 선택해주세요.')),
      );
      return;
    }

    setState(() => _isSaving = true);
    debugPrint(
      '[VideoTrim] 자르기 시작 — 원본: ${widget.sourceFile.path}, '
      '구간: ${_startValue}ms ~ ${_endValue}ms',
    );
    try {
      final outputPath = await _saveTrimmedVideo();
      if (!mounted) return;
      final file = outputPath != null ? File(outputPath) : null;
      final exists = file?.existsSync() ?? false;
      final size = exists ? file!.lengthSync() : -1;
      debugPrint(
        '[VideoTrim] 편집 완료 파일 경로: $outputPath '
        '(exists=$exists, size=${size}bytes)',
      );
      if (outputPath == null || outputPath.isEmpty || !exists || size <= 0) {
        debugPrint('[VideoTrim] 편집 결과 파일이 없거나 비어있어 실패 처리함');
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('영상을 자르는 데 실패했어요. 다시 시도해주세요.')),
        );
        return;
      }
      Navigator.pop(context, outputPath);
    } catch (e) {
      debugPrint('[VideoTrim] 자르기 실패: $e');
      if (mounted) {
        setState(() => _isSaving = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('영상을 자르는 데 실패했어요: $e')));
      }
    }
  }

  // saveTrimmedVideo는 콜백(onSave) 기반 API라 Future로 감싸서 await 가능하게 한다.
  Future<String?> _saveTrimmedVideo() {
    final completer = Completer<String?>();
    _trimmer
        .saveTrimmedVideo(
          startValue: _startValue,
          endValue: _endValue,
          onSave: (outputPath) {
            if (!completer.isCompleted) completer.complete(outputPath);
          },
        )
        .catchError((e) {
          if (!completer.isCompleted) completer.completeError(e);
        });
    return completer.future;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !Navigator.of(context).userGestureInProgress,
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black,
          foregroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            '동영상 편집',
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
          actions: [
            TextButton(
              onPressed: (!_isReady || _isSaving) ? null : _save,
              child: _isSaving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      '완료',
                      style: TextStyle(
                        color: _isReady
                            ? const Color(0xFFFF6FA0)
                            : Colors.white24,
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
            ),
          ],
        ),
        body: _loadFailed
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        color: Colors.white54,
                        size: 40,
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        '영상을 불러오지 못했어요.',
                        style: TextStyle(color: Colors.white70, fontSize: 14),
                      ),
                      const SizedBox(height: 16),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text(
                          '돌아가기',
                          style: TextStyle(color: Color(0xFFFF6FA0)),
                        ),
                      ),
                    ],
                  ),
                ),
              )
            : SafeArea(
                child: Column(
                  children: [
                    const SizedBox(height: 8),
                    // 현재 선택 구간 실시간 표시 — 예) 12.4초 ~ 42.4초 / 선택 길이 30.0초
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${_fmtSeconds(_startValue)}초 ~ ${_fmtSeconds(_endValue)}초',
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '선택 길이 ${_selectedSeconds.toStringAsFixed(1)}초 / '
                            '최대 ${VideoTrimScreen.maxDuration.inSeconds}초',
                            style: const TextStyle(
                              color: Colors.white60,
                              fontSize: 12,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 8),
                    // 선택 구간 실시간 미리보기 — Trimmer가 초기화되기 전에는
                    // VideoViewer가 알아서 빈 화면을 보여주고, 초기화되는 즉시
                    // 스스로 다시 그린다(이 위젯을 항상 트리에 둬야 이벤트를 놓치지 않음).
                    Expanded(
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          VideoViewer(trimmer: _trimmer),
                          if (!_isReady)
                            const CircularProgressIndicator(
                              color: Color(0xFFFF6FA0),
                            ),
                        ],
                      ),
                    ),
                    GestureDetector(
                      onTap: _isReady ? _togglePlayback : null,
                      child: Icon(
                        _isPlaying
                            ? Icons.pause_circle_filled
                            : Icons.play_circle_fill,
                        color: _isReady ? Colors.white : Colors.white24,
                        size: 56,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // 타임라인 — 썸네일 + 좌우 드래그 핸들. 영상이 충분히 길면
                    // (30초*1.4 이상) 자동으로 스크롤 가능한 확대 타임라인을 쓴다.
                    // 이 위젯도 VideoViewer와 마찬가지로 항상 트리에 있어야
                    // 초기화 이벤트를 놓치지 않는다.
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: TrimViewer(
                        trimmer: _trimmer,
                        viewerHeight: 60,
                        viewerWidth: MediaQuery.of(context).size.width - 24,
                        durationStyle: DurationStyle.FORMAT_MM_SS,
                        maxVideoLength: VideoTrimScreen.maxDuration,
                        editorProperties: const TrimEditorProperties(
                          borderPaintColor: Color(0xFFFF6FA0),
                          circlePaintColor: Color(0xFFFF6FA0),
                          scrubberPaintColor: Color(0xFFFF6FA0),
                          borderWidth: 3,
                        ),
                        onChangeStart: (v) => setState(() => _startValue = v),
                        onChangeEnd: (v) => setState(() => _endValue = v),
                        onChangePlaybackState: (v) =>
                            setState(() => _isPlaying = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        '가운데를 드래그하면 구간 전체를 이동, 양쪽 끝을 드래그하면 '
                        '시작·종료 지점을 최대 30초까지 조절할 수 있어요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 12, color: Colors.white54),
                      ),
                    ),
                    const SizedBox(height: 20),
                  ],
                ),
              ),
      ),
    );
  }
}
