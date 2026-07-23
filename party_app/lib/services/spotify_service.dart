import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:party_app/models/spotify_track.dart';

/// Spotify가 앱 소유(Dashboard에 등록한) 계정이 Premium이 아닐 때
/// /v1/search 등에서 돌려주는 403을 구분하기 위한 전용 예외.
///
/// Client Credentials Flow에는 최종 사용자 로그인이 전혀 없는데도, Spotify는
/// "앱을 만든 계정"의 구독 등급으로 Web API 접근 자체를 게이트한다(2025년
/// 정책 변경). Client ID/Secret이나 요청 형식 문제가 아니라 계정 등급
/// 문제이므로, 재시도로 해결되지 않는다는 걸 호출부가 구분할 수 있게 한다.
class SpotifyPremiumRequiredException implements Exception {
  final String message;
  const SpotifyPremiumRequiredException([
    this.message =
        'Spotify 앱을 등록한 계정이 Premium이 아니어서 검색을 사용할 수 없어요.\n'
        'developer.spotify.com/dashboard에서 이 앱을 만든 계정을 확인하고 Premium으로 업그레이드해주세요.',
  ]);

  @override
  String toString() => message;
}

/// Spotify Web API 연동 — Client Credentials Flow로 트랙을 검색한다.
///
/// .env 필요:
///   SPOTIFY_CLIENT_ID     - Spotify Developer Dashboard(developer.spotify.com)에서 발급
///   SPOTIFY_CLIENT_SECRET - 위와 동일 앱의 Client Secret
///
/// 반드시 실제 Spotify 미리듣기(preview_url)만 재생 대상으로 쓴다 — mp3 직접
/// 업로드나 임의 음원을 붙이는 기능은 의도적으로 만들지 않았다.
class SpotifyService {
  SpotifyService._();

  static String get _clientId => dotenv.env['SPOTIFY_CLIENT_ID'] ?? '';
  static String get _clientSecret => dotenv.env['SPOTIFY_CLIENT_SECRET'] ?? '';

  static bool get isConfigured =>
      _clientId.isNotEmpty &&
      !_clientId.contains('여기에') &&
      _clientSecret.isNotEmpty &&
      !_clientSecret.contains('여기에');

  static String? _cachedToken;
  static DateTime? _tokenExpiresAt;

  static Future<String> _getAccessToken() async {
    if (_cachedToken != null &&
        _tokenExpiresAt != null &&
        DateTime.now().isBefore(_tokenExpiresAt!)) {
      return _cachedToken!;
    }

    final basicAuth = base64Encode(utf8.encode('$_clientId:$_clientSecret'));
    final response = await http
        .post(
          Uri.parse('https://accounts.spotify.com/api/token'),
          headers: {
            'Authorization': 'Basic $basicAuth',
            'Content-Type': 'application/x-www-form-urlencoded',
          },
          body: {'grant_type': 'client_credentials'},
        )
        .timeout(const Duration(seconds: 15));

    debugPrint(
      '[Spotify] POST accounts.spotify.com/api/token → ${response.statusCode}',
    );
    if (response.statusCode != 200) {
      debugPrint('[Spotify] token 발급 실패 body: ${response.body}');
      throw Exception(
        'Spotify 인증 실패: ${response.statusCode} ${response.body}',
      );
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final token = body['access_token'] as String;
    final expiresIn = (body['expires_in'] as num?)?.toInt() ?? 3600;
    _cachedToken = token;
    // 만료 60초 전에 미리 갱신해 경계 근처 요청이 401로 실패하지 않게 한다.
    _tokenExpiresAt = DateTime.now().add(Duration(seconds: expiresIn - 60));
    return token;
  }

  /// ⚠️ Spotify 공식 문서상 /v1/search의 limit 허용 범위는 1~50이지만, 이
  /// 앱(Client ID)으로 실제 curl 테스트해보면 limit=10까지는 200이 오고
  /// limit=11부터는(50 이하여도 전부) "400 Invalid limit"이 돌아온다 —
  /// 문서화된 제한이 아니라, 앱 소유 계정의 접근 등급이 제한된 상태일 때
  /// Spotify가 문서상 한도보다 훨씬 낮은 값에서 이 에러 메시지로 막는
  /// 것으로 보인다(SpotifyPremiumRequiredException 설명과 같은 2025년
  /// 정책 변경). 코드의 limit 파라미터 자체는 잘못이 없었다 — 실측으로
  /// 확인된 안전한 상한(10)을 기본값 겸 하드 캡으로 둔다.
  static const int _maxSafeLimit = 10;

  /// 트랙 검색 — preview_url 유무와 무관하게 검색 결과를 그대로 반환한다.
  /// 선택 UI(SpotifyTrackPicker)에서 preview_url이 없는 곡은 선택 불가로
  /// 표시해야 한다("직접 MP3 업로드/임의 음원 금지" 요건).
  static Future<List<SpotifyTrack>> searchTracks(
    String query, {
    int limit = _maxSafeLimit,
  }) async {
    if (!isConfigured) {
      throw Exception(
        'Spotify 연동이 아직 설정되지 않았습니다. 관리자에게 문의해주세요.',
      );
    }
    final q = query.trim();
    if (q.isEmpty) return [];

    final safeLimit = limit.clamp(1, _maxSafeLimit);
    final token = await _getAccessToken();
    final uri = Uri.parse('https://api.spotify.com/v1/search').replace(
      queryParameters: {
        'q': q,
        'type': 'track',
        'limit': '$safeLimit',
        'market': 'KR',
      },
    );

    debugPrint('[Spotify] GET $uri (limit=$safeLimit, offset=0)');
    final response = await http
        .get(uri, headers: {'Authorization': 'Bearer $token'})
        .timeout(const Duration(seconds: 15));
    debugPrint('[Spotify] GET $uri → ${response.statusCode}');

    if (response.statusCode != 200) {
      debugPrint('[Spotify] 검색 실패 body: ${response.body}');
      if (response.statusCode == 403 &&
          response.body.contains('premium subscription required')) {
        throw const SpotifyPremiumRequiredException();
      }
      // 문서상 limit=1~50이 전부 허용돼야 하는데도 400 Invalid limit이
      // 온다면 실제 limit 값 문제가 아니라 위 _maxSafeLimit 주석과 같은
      // 앱 접근 등급 제한이 원인일 가능성이 높다 — 같은 안내로 묶는다.
      if (response.statusCode == 400 &&
          response.body.contains('Invalid limit')) {
        throw const SpotifyPremiumRequiredException(
          'Spotify 앱을 등록한 계정의 접근 등급이 제한돼 있어 검색이 제한돼요.\n'
          'developer.spotify.com/dashboard에서 이 앱을 만든 계정을 확인하고 Premium으로 업그레이드해주세요.',
        );
      }
      throw Exception('Spotify 검색 실패: ${response.statusCode} ${response.body}');
    }

    final body = jsonDecode(response.body) as Map<String, dynamic>;
    final items =
        (body['tracks'] as Map<String, dynamic>?)?['items'] as List? ?? [];
    return items
        .map((e) => SpotifyTrack.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
