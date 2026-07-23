import 'package:flutter/material.dart';
import 'package:party_app/models/spotify_track.dart';
import 'package:party_app/widgets/spotify_track_picker_sheet.dart';

/// 사진만 등록된 파티에 붙이는 Spotify 미리듣기(배경 음악) 섹션 —
/// 등록/수정 화면의 기존 `_spotifySection()`을 그대로 추출한 것.
class SpotifySection extends StatelessWidget {
  final SpotifyTrack? track;
  final ValueChanged<SpotifyTrack?> onChanged;

  const SpotifySection({super.key, required this.track, required this.onChanged});

  Future<void> _pick(BuildContext context) async {
    final picked = await showSpotifyTrackPicker(context);
    if (picked != null) onChanged(picked);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF9FAFC),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE8EBF2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.music_note, size: 18, color: Color(0xFFFF6FA0)),
              const SizedBox(width: 6),
              const Text(
                '배경 음악 (선택)',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
              ),
              const Spacer(),
              if (track != null)
                TextButton(
                  onPressed: () => onChanged(null),
                  child: const Text('제거', style: TextStyle(color: Colors.redAccent)),
                ),
            ],
          ),
          const SizedBox(height: 4),
          const Text(
            '사진만 등록된 파티는 Spotify 미리듣기 음악을 배경으로 자동재생할 수 있어요.',
            style: TextStyle(fontSize: 12, color: Colors.black45),
          ),
          const SizedBox(height: 10),
          if (track != null)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: track!.albumArtUrl != null
                    ? Image.network(
                        track!.albumArtUrl!,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 44,
                        height: 44,
                        color: const Color(0xFFFFEAF1),
                      ),
              ),
              title: Text(track!.name, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(
                track!.artistNames,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: TextButton(
                onPressed: () => _pick(context),
                child: const Text('변경'),
              ),
            )
          else
            OutlinedButton.icon(
              onPressed: () => _pick(context),
              icon: const Icon(Icons.search),
              label: const Text('Spotify에서 노래 찾기'),
            ),
        ],
      ),
    );
  }
}
