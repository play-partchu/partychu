import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;
import 'package:party_app/utils/user_session.dart';

/// Cloudflare R2 (사진) + Stream (동영상) 업로드 서비스
///
/// .env 필요:
///   CLOUDFLARE_ACCOUNT_ID    - Cloudflare 계정 ID
///   CLOUDFLARE_API_TOKEN     - Workers R2 Storage:Edit + Stream:Edit 권한 API 토큰
///   CLOUDFLARE_R2_BUCKET     - R2 버킷 이름 (예: partychu-images)
///   CLOUDFLARE_R2_PUBLIC_URL - R2 공개 URL (예: https://pub-xxxx.r2.dev)
class CloudflareService {
  static String get _accountId => dotenv.env['CLOUDFLARE_ACCOUNT_ID'] ?? '';
  static String get _apiToken => dotenv.env['CLOUDFLARE_API_TOKEN'] ?? '';
  static String get _r2Bucket => dotenv.env['CLOUDFLARE_R2_BUCKET'] ?? '';
  static String get _r2PublicUrl => dotenv.env['CLOUDFLARE_R2_PUBLIC_URL'] ?? '';

  static Map<String, String> get _authHeader => {
        'Authorization': 'Bearer $_apiToken',
      };

  // ── R2 (사진) ────────────────────────────────────────────────────────────

  /// 이미지를 Cloudflare R2에 업로드하고 public URL을 반환합니다.
  static Future<String> uploadImage(File file) async {
    final ext = file.path.split('.').last.toLowerCase();
    final uid = UserSession.userId.isNotEmpty ? UserSession.userId : 'anon';
    final key = 'party_images/$uid/${DateTime.now().millisecondsSinceEpoch}.$ext';

    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$_accountId/r2/buckets/$_r2Bucket/objects/$key',
    );

    final bytes = await file.readAsBytes();
    final response = await http
        .put(
          uri,
          headers: {..._authHeader, 'Content-Type': _mimeType(ext)},
          body: bytes,
        )
        .timeout(const Duration(seconds: 120));

    debugPrint('[R2 Upload] status=${response.statusCode}');

    if (response.statusCode == 200) {
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (body['success'] == true) return '$_r2PublicUrl/$key';
      throw Exception('R2 업로드 실패: ${body['errors']}');
    }
    throw Exception('R2 업로드 실패: ${response.statusCode} ${response.body}');
  }

  static String _mimeType(String ext) {
    switch (ext) {
      case 'jpg':
      case 'jpeg':
        return 'image/jpeg';
      case 'png':
        return 'image/png';
      case 'gif':
        return 'image/gif';
      case 'webp':
        return 'image/webp';
      case 'heic':
        return 'image/heic';
      default:
        return 'application/octet-stream';
    }
  }

  /// R2 이미지를 삭제합니다. URL이 R2 공개 URL로 시작하지 않으면 무시합니다.
  static Future<void> deleteImage(String imageUrl) async {
    final base = _r2PublicUrl.replaceAll(RegExp(r'/$'), '');
    if (base.isEmpty || !imageUrl.startsWith(base)) return;
    final key = imageUrl.substring(base.length + 1);
    if (key.isEmpty) return;

    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$_accountId/r2/buckets/$_r2Bucket/objects/$key',
    );
    final response = await http
        .delete(uri, headers: _authHeader)
        .timeout(const Duration(seconds: 30));

    debugPrint('[R2 Delete] status=${response.statusCode} key=$key');
  }

  // ── Stream (동영상) ───────────────────────────────────────────────────────

  /// 동영상을 Cloudflare Stream에 업로드합니다.
  /// 반환: { videoUid, videoUrl, videoThumbnailUrl }
  static Future<Map<String, String>> uploadVideo(File file) async {
    final uploadUrl = 'https://api.cloudflare.com/client/v4/accounts/$_accountId/stream';

    debugPrint('[Stream Upload] 업로드 시작: ${file.path.split('/').last}');

    final uri = Uri.parse(uploadUrl);

    final request = http.MultipartRequest('POST', uri)
      ..headers.addAll(_authHeader)
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamed = await request.send().timeout(const Duration(minutes: 3));
    final responseBody = await streamed.stream.bytesToString();

    debugPrint('[Stream Upload] status: ${streamed.statusCode}');

    final Map<String, dynamic> body;
    try {
      body = jsonDecode(responseBody) as Map<String, dynamic>;
    } catch (_) {
      throw Exception('동영상 업로드 실패: JSON 파싱 불가 — 응답: $responseBody');
    }

    if (body['success'] == true) {
      final result = body['result'] as Map<String, dynamic>;
      final uid = result['uid'] as String;
      final playback = result['playback'] as Map<String, dynamic>?;

      final videoUrl = playback?['hls'] as String? ??
          'https://videodelivery.net/$uid/manifest/video.m3u8';
      final thumbnailUrl = result['thumbnail'] as String? ??
          'https://videodelivery.net/$uid/thumbnails/thumbnail.jpg';

      return {'videoUid': uid, 'videoUrl': videoUrl, 'videoThumbnailUrl': thumbnailUrl};
    }

    final errors = body['errors'];
    throw Exception('동영상 업로드 실패: $errors');
  }

  /// Cloudflare Stream 동영상을 삭제합니다.
  ///
  /// [videoUid] 를 우선 사용하고, 없을 때만 [videoUrl] 파싱으로 폴백합니다.
  /// (기존 데이터 하위 호환: videoUid가 없는 게시글은 URL 파싱으로 동작)
  static Future<void> deleteVideo({String? videoUid, String? videoUrl}) async {
    String? uid = (videoUid?.isNotEmpty ?? false) ? videoUid : null;

    if (uid == null && (videoUrl?.isNotEmpty ?? false)) {
      // 폴백: URL 파싱으로 uid 추출
      // 지원 형식:
      //   https://customer-xxxx.cloudflarestream.com/{uid}/manifest/video.m3u8
      //   https://customer-xxxx.cloudflarestream.com/{uid}/thumbnails/thumbnail.jpg
      //   https://videodelivery.net/{uid}/manifest/video.m3u8
      final match = RegExp(
        r'(?:cloudflarestream\.com|videodelivery\.net)/([a-f0-9]{32})(?:/|$)',
      ).firstMatch(videoUrl!);
      uid = match?.group(1);
    }

    if (uid == null || uid.isEmpty) return;

    final uri = Uri.parse(
      'https://api.cloudflare.com/client/v4/accounts/$_accountId/stream/$uid',
    );
    final response = await http
        .delete(uri, headers: _authHeader)
        .timeout(const Duration(seconds: 30));

    debugPrint('[Stream Delete] status=${response.statusCode} uid=$uid');
  }

  // ── 설정 검증 ─────────────────────────────────────────────────────────────

  static bool get isConfigured =>
      _accountId.isNotEmpty &&
      !_accountId.contains('여기에') &&
      _apiToken.isNotEmpty &&
      !_apiToken.contains('여기에') &&
      _r2Bucket.isNotEmpty &&
      !_r2Bucket.contains('여기에') &&
      _r2PublicUrl.isNotEmpty &&
      !_r2PublicUrl.contains('여기에');
}
