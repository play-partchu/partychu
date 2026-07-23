import 'dart:async';

import 'package:flutter/material.dart';
import 'package:party_app/models/spotify_track.dart';
import 'package:party_app/services/spotify_service.dart'
    show SpotifyService, SpotifyPremiumRequiredException;

/// Spotify 트랙 검색 바텀시트 — 미리듣기(preview_url)가 있는 곡만 선택 가능.
/// 선택하면 [SpotifyTrack]을 pop해서 돌려주고, 취소하면 null을 돌려준다.
Future<SpotifyTrack?> showSpotifyTrackPicker(BuildContext context) {
  return showModalBottomSheet<SpotifyTrack>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _SpotifyTrackPickerSheet(),
  );
}

class _SpotifyTrackPickerSheet extends StatefulWidget {
  const _SpotifyTrackPickerSheet();

  @override
  State<_SpotifyTrackPickerSheet> createState() =>
      _SpotifyTrackPickerSheetState();
}

class _SpotifyTrackPickerSheetState extends State<_SpotifyTrackPickerSheet> {
  final _controller = TextEditingController();
  Timer? _debounce;
  List<SpotifyTrack> _results = [];
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 450), () => _search(value));
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      setState(() {
        _results = [];
        _error = null;
        _loading = false;
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final results = await SpotifyService.searchTracks(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on SpotifyPremiumRequiredException catch (e) {
      // Client ID/Secret이나 요청 형식 문제가 아니라 앱 소유 계정의 구독
      // 등급 문제라 재검색으로는 해결되지 않는다는 걸 명확히 구분해 보여준다.
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '검색에 실패했어요.\n$e';
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.75,
      child: Column(
        children: [
          const SizedBox(height: 10),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
            child: Row(
              children: [
                const Expanded(
                  child: Text(
                    '노래 추가',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _controller,
              autofocus: true,
              onChanged: _onChanged,
              onSubmitted: _search,
              decoration: InputDecoration(
                hintText: '곡명 또는 아티스트 검색',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: const Color(0xFFF5F5F7),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          if (!SpotifyService.isConfigured)
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Text(
                'Spotify 연동이 아직 설정되지 않았어요. 잠시 후 다시 시도해주세요.',
                style: TextStyle(fontSize: 12, color: Colors.redAccent),
              ),
            ),
          const SizedBox(height: 4),
          const Divider(height: 1),
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            _error!,
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.redAccent),
          ),
        ),
      );
    }
    if (_results.isEmpty) {
      return Center(
        child: Text(
          _controller.text.trim().isEmpty ? '곡을 검색해보세요' : '검색 결과가 없어요',
          style: const TextStyle(color: Colors.black45),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: _results.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (_, i) {
        final track = _results[i];
        final selectable = track.hasPreview;
        return Opacity(
          opacity: selectable ? 1 : 0.4,
          child: ListTile(
            enabled: selectable,
            leading: ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: track.albumArtUrl != null
                  ? Image.network(
                      track.albumArtUrl!,
                      width: 44,
                      height: 44,
                      fit: BoxFit.cover,
                    )
                  : Container(
                      width: 44,
                      height: 44,
                      color: const Color(0xFFFFEAF1),
                      child: const Icon(Icons.music_note, color: Color(0xFFFFB8CF)),
                    ),
            ),
            title: Text(track.name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              selectable ? track.artistNames : '${track.artistNames} · 미리듣기 없음',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: selectable
                ? const Icon(Icons.chevron_right, color: Colors.black26)
                : null,
            onTap: selectable ? () => Navigator.pop(context, track) : null,
          ),
        );
      },
    );
  }
}
