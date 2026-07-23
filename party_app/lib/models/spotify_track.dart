/// Spotify Web API 검색 결과 트랙 하나.
///
/// [previewUrl]이 없는 곡은 미리듣기 음원이 없다는 뜻이라 자동재생 대상으로
/// 선택할 수 없다 — 선택 UI(SpotifyTrackPicker)에서 이 값이 없는 곡은
/// 비활성화해서 보여줘야 한다.
class SpotifyTrack {
  final String id;
  final String name;
  final String artistNames;
  final String? albumArtUrl;
  final String? previewUrl;

  const SpotifyTrack({
    required this.id,
    required this.name,
    required this.artistNames,
    this.albumArtUrl,
    this.previewUrl,
  });

  bool get hasPreview => previewUrl != null && previewUrl!.isNotEmpty;

  factory SpotifyTrack.fromJson(Map<String, dynamic> json) {
    final artists = (json['artists'] as List?)
            ?.map((a) => (a as Map<String, dynamic>)['name'] as String? ?? '')
            .where((n) => n.isNotEmpty)
            .join(', ') ??
        '';
    final albumImages =
        (json['album'] as Map<String, dynamic>?)?['images'] as List?;
    final albumArt = (albumImages != null && albumImages.isNotEmpty)
        ? (albumImages.first as Map<String, dynamic>)['url'] as String?
        : null;
    return SpotifyTrack(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      artistNames: artists,
      albumArtUrl: albumArt,
      previewUrl: json['preview_url'] as String?,
    );
  }

  Map<String, dynamic> toFirestoreFields() => {
        'spotifyTrackId': id,
        'spotifyTrackName': name,
        'spotifyArtistName': artistNames,
        'spotifyAlbumArt': albumArtUrl,
        'spotifyPreviewUrl': previewUrl,
      };
}
