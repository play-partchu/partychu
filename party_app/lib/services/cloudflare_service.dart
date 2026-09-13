import 'dart:convert';

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/utils/user_session.dart';

/// 사진(R2) · 동영상(Stream) 업로드 서비스.
///
/// ── 어떻게 바뀌었나 ───────────────────────────────────────────────────────
/// 예전에는 이 파일이 `.env`에 담긴 **계정 단위 API 토큰**으로 Cloudflare의
/// 관리 API를 직접 호출했다. 그 토큰은 배포된 APK/IPA에 평문으로 들어가
/// 누구나 추출할 수 있었고, R2에는 "이 자격증명은 이 경로만"이라는 개념이
/// 없어서 토큰만 있으면 남의 사진을 덮어쓰거나 버킷을 통째로 지울 수 있었다.
/// 경로에 들어가던 `party_images/{uid}/`의 uid도 앱이 만든 문자열일 뿐이라
/// 아무것도 보장하지 못했다.
///
/// (그 시절의 키 이름·엔드포인트는 여기 적지 않는다 — 디버그 빌드의
///  kernel_blob.bin에는 주석 원문이 그대로 실려서, 이 파일에 적어두면
///  "빌드 산출물에 자격증명 흔적이 0건인가"를 확인할 때 잡음이 된다.)
///
/// 지금은 **서버가 허가를 발급하고 앱은 바이트만 보낸다**:
///
///   사진   createUploadUrl   → presigned PUT(그 키 하나 · 그 크기 · 그 형식 ·
///                              5분) → R2로 직행
///   동영상 createVideoUploadUrl → Stream direct creator upload
///                                 (maxDurationSeconds=30을 서버가 강제)
///   삭제   deleteOwnUpload    → 경로의 uid / Stream creator가 본인일 때만
///
/// 경로의 uid는 서버가 `request.auth.uid`로 채운다 — 앱은 uid도 key도 보내지
/// 않는다. 자세한 배경은 functions/mediaUploads.js 상단 주석 참고.
///
/// ── 호출부는 그대로다 ─────────────────────────────────────────────────────
/// [uploadImage] · [uploadVideo] · [deleteImage] · [deleteVideo] 네 메서드의
/// **시그니처와 반환값 모양이 예전과 같다.** 공개 URL 형식도 같은 버킷·같은
/// 키 규칙이라 Firestore에 저장되는 값이 달라지지 않는다. 그래서 앱 곳곳의
/// 호출부 40여 곳은 한 줄도 바뀌지 않았다.
///
/// ── 앱에는 Cloudflare 자격증명이 없다 ─────────────────────────────────────
/// 이 파일은 `.env`를 **한 줄도 읽지 않는다.** 예전에 남겨 두었던 "옛 동영상
/// 삭제 폴백"(토큰으로 Stream API 직접 호출)도 제거했다 — [deleteVideo]를
/// 부르는 곳은 등록·수정 화면의 롤백 경로 네 곳뿐이고 전부 **그 제출에서
/// 방금 올린** 영상만 지우기 때문에, 옛 영상을 앱이 지울 일이 없다.
///
/// 옛 영상(=creator가 없는 영상)은 전부 서버가 Admin 권한으로 정리한다:
///   · 파티/플레이스/장소대여 삭제 → contentDelete(콜러블) → contentCleanup.js
///   · 만료 자동삭제               → deleteExpiredParties(지난 파티 14일) ·
///     deleteExpiredPlaces(숨긴 장소 30일) → 같은 경로
/// 둘 다 문서의 videoUid·coverVideoUid를 Stream에서 지운다(cloudflareCleanup.js).
class CloudflareUploadException implements Exception {
  /// 'r2' | 'stream'
  final String kind;

  /// HTTP 상태 코드. 응답 자체를 못 받았으면 null.
  ///
  /// 서버 콜러블에서 온 실패는 [_fromFunctions]가 같은 뜻의 상태 코드로
  /// 옮겨 담는다 — 아래 [isAuthFailure]/[isServerFailure]로 갈래를 나누는
  /// 기존 분류(MediaUploadService.classify)를 그대로 태우기 위해서다.
  final int? statusCode;

  /// 응답 본문/에러 배열(개발자용. 사용자에게 노출하지 않는다).
  final String detail;

  /// **사용자에게 그대로 보여줘도 되는** 문구가 있으면 여기 담긴다.
  ///
  /// 서버가 "파일이 너무 큽니다. 최대 10MB까지 올릴 수 있어요." 처럼 이미
  /// 사람이 읽을 문장을 만들어 주는 경우가 있다. 그런 실패까지 "문제가
  /// 발생했습니다"로 뭉개면 호스트는 무엇을 고쳐야 하는지 알 수 없다.
  /// null이면 예전과 똑같이 갈래별 기본 문구를 쓴다.
  final String? userMessage;

  const CloudflareUploadException({
    required this.kind,
    required this.detail,
    this.statusCode,
    this.userMessage,
  });

  /// 토큰 만료·권한 없음 — 사용자의 사진 잘못이 아니다.
  bool get isAuthFailure =>
      statusCode == 401 || statusCode == 403 || _hasAuthErrorCode;

  /// Cloudflare API는 200이 아닌 상태와 함께 code 10000(Authentication error) /
  /// 1000(Invalid API Token)을 본문에 담아 준다.
  bool get _hasAuthErrorCode =>
      detail.contains('"code":10000') ||
      detail.contains('"code":1000,') ||
      detail.contains('Authentication error') ||
      detail.contains('Invalid API Token');

  bool get isServerFailure => statusCode != null && statusCode! >= 500;

  @override
  String toString() =>
      'CloudflareUploadException($kind, status: $statusCode, $detail)';
}

class CloudflareService {
  CloudflareService._();

  /// 콜러블이 배포된 리전 — 다른 콜러블들과 같다.
  static const String functionsRegion = 'asia-northeast3';

  static const String _fnCreateUploadUrl = 'createUploadUrl';
  static const String _fnCreateVideoUploadUrl = 'createVideoUploadUrl';
  static const String _fnDeleteOwnUpload = 'deleteOwnUpload';

  /// 기본 저장 폴더 — 서버 whitelist의 'image' kind와 같은 값이다.
  static const String defaultImageFolder = 'party_images';

  // ── 테스트 주입점 ─────────────────────────────────────────────────────
  // 실제 Firebase/네트워크 없이 "무엇을 보내고 무엇을 받는지"를 검증하기
  // 위한 것. 운영 코드는 절대 건드리지 않는다(둘 다 null이면 실물을 쓴다).
  static Future<Map<String, dynamic>> Function(
    String name,
    Map<String, dynamic> data,
  )?
  _callableOverride;
  static http.Client? _clientOverride;

  @visibleForTesting
  static void debugSetTransport({
    Future<Map<String, dynamic>> Function(String, Map<String, dynamic>)?
    callable,
    http.Client? client,
  }) {
    _callableOverride = callable;
    _clientOverride = client;
  }

  @visibleForTesting
  static void debugResetTransport() {
    _callableOverride = null;
    _clientOverride = null;
  }

  static http.Client get _http => _clientOverride ?? _sharedClient;
  static final http.Client _sharedClient = http.Client();

  /// 콜러블 하나를 부르고 결과 맵을 돌려준다.
  static Future<Map<String, dynamic>> _call(
    String name,
    Map<String, dynamic> data,
  ) async {
    final override = _callableOverride;
    if (override != null) return override(name, data);
    final result = await FirebaseFunctions.instanceFor(
      region: functionsRegion,
    ).httpsCallable(name).call<Object?>(data);
    final raw = result.data;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    throw CloudflareUploadException(
      kind: 'callable',
      detail: '$name 응답 형식이 올바르지 않습니다: ${raw.runtimeType}',
    );
  }

  /// 콜러블 실패를 기존 예외 타입으로 옮겨 담는다.
  ///
  /// 상태 코드로 바꾸는 이유: 화면들은 이미 [CloudflareUploadException]의
  /// isAuthFailure/isServerFailure로 "사진을 바꿔야 하는 실패"와 "바꿔도
  /// 소용없는 실패"를 갈라 안내한다(RegisterValidation.failureMessage).
  /// 새 경로만 다른 타입을 던지면 그 분류가 통째로 무너진다.
  static CloudflareUploadException _fromFunctions(
    FirebaseFunctionsException e,
    String kind,
  ) {
    int? status;
    String? userMessage;
    switch (e.code) {
      // 로그인이 풀렸거나, 남의 파일이거나, 서버에 시크릿이 없다.
      // 셋 다 "사진을 바꿔도 소용없다"는 점에서 같은 갈래다.
      case 'unauthenticated':
      case 'permission-denied':
      case 'failed-precondition':
        status = 403;
        break;
      case 'unavailable':
      case 'deadline-exceeded':
      case 'internal':
        status = 503;
        break;
      // 서버가 형식·용량 문제를 사람이 읽을 문장으로 돌려준 경우다.
      case 'invalid-argument':
        status = 400;
        userMessage = (e.message ?? '').trim().isEmpty ? null : e.message;
        break;
      default:
        status = null;
    }
    return CloudflareUploadException(
      kind: kind,
      statusCode: status,
      detail: '${e.code}: ${e.message}',
      userMessage: userMessage,
    );
  }

  // ══════════════════════════════════════════════════════════════════════
  // 사진 — R2
  // ══════════════════════════════════════════════════════════════════════

  /// 이미지를 업로드하고 public URL을 반환합니다.
  ///
  /// [folder]는 서버 whitelist에 있는 값만 허용됩니다(기본
  /// `party_images`, 파티 상세 이미지는 `party_images/detail`). 다른 값은
  /// 서버가 거부합니다 — 앱이 임의 경로를 지정할 수 없다는 뜻입니다.
  ///
  /// 흐름: createUploadUrl로 허가를 받고, 서버가 알려준 헤더를 **그대로**
  /// 붙여 presigned URL에 PUT합니다. 헤더가 한 글자라도 다르면 서명이 안 맞아
  /// R2가 거부하므로, 여기서 임의로 헤더를 만들지 않습니다.
  static Future<String> uploadImage(
    XFile file, {
    String folder = defaultImageFolder,
  }) async {
    // 확장자는 경로가 아니라 [LocalMedia.extensionOf]가 정한다 — 웹에서
    // XFile.path는 `blob:...` 오브젝트 URL이라 확장자가 아예 없다(원본 이름은
    // XFile.name에, 그것도 없으면 mimeType에 있다). 서버가 ext·contentType으로
    // 허가를 발급하므로 이 판정이 틀리면 웹 업로드가 통째로 막힌다.
    final ext = LocalMedia.extensionOf(file);
    final bytes = await file.readAsBytes();

    final Map<String, dynamic> grant;
    try {
      grant = await _call(_fnCreateUploadUrl, {
        'folder': folder,
        'ext': ext,
        'contentType': _mimeType(ext),
        'contentLength': bytes.length,
        // uid·key는 보내지 않는다. 서버가 request.auth.uid로 직접 만든다.
      });
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[R2 Upload] 허가 발급 실패 code=${e.code}');
      throw _fromFunctions(e, 'r2');
    }

    final uploadUrl = grant['uploadUrl'] as String?;
    final publicUrl = grant['publicUrl'] as String?;
    if (uploadUrl == null || publicUrl == null) {
      throw CloudflareUploadException(
        kind: 'r2',
        detail: 'createUploadUrl 응답에 uploadUrl/publicUrl이 없습니다.',
      );
    }

    final headers = <String, String>{
      for (final e in (grant['requiredHeaders'] as Map? ?? {}).entries)
        e.key.toString(): e.value.toString(),
    };

    // 서버가 서명에 박아둔 크기와 실제 보낼 바이트 수가 다르면 R2가 403으로
    // 거부한다. 여기서 먼저 잡아야 "왜 403인지 모르는 실패"가 안 생긴다.
    final declared = headers['Content-Length'];
    if (declared != null && declared != '${bytes.length}') {
      throw CloudflareUploadException(
        kind: 'r2',
        detail: 'Content-Length 불일치 — 서명 $declared vs 실제 ${bytes.length}',
      );
    }

    final response = await _http
        .put(Uri.parse(uploadUrl), headers: headers, body: bytes)
        .timeout(const Duration(seconds: 120));

    debugPrint('[R2 Upload] status=${response.statusCode}');

    if (response.statusCode == 200 || response.statusCode == 201) {
      return publicUrl;
    }
    throw CloudflareUploadException(
      kind: 'r2',
      statusCode: response.statusCode,
      detail: response.body,
    );
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

  /// 이미지를 삭제합니다.
  ///
  /// 서버가 키의 uid 조각을 `request.auth.uid`와 대조해 **본인 파일만**
  /// 지웁니다. 남의 파일이거나 우리 버킷이 아니면 거부되는데, 그 경우는
  /// 예전(공개 URL 접두사가 다르면 조용히 무시)과 같은 결과가 되도록 여기서
  /// 로그만 남기고 넘어갑니다.
  ///
  /// **예외를 던지지 않습니다** — 호출부는 전부 정리(cleanup) 경로라
  /// 실패해도 본래 작업을 되돌리면 안 됩니다(예전 구현도 같았습니다).
  static Future<void> deleteImage(String imageUrl) async {
    if (imageUrl.trim().isEmpty) return;
    try {
      await _call(_fnDeleteOwnUpload, {'url': imageUrl});
      debugPrint('[R2 Delete] ok');
    } on FirebaseFunctionsException catch (e) {
      // permission-denied = 우리 버킷이 아니거나 남의 파일.
      // not-found = 이미 없음. 둘 다 "지울 것이 없다"와 같은 결과다.
      debugPrint('[R2 Delete] skipped code=${e.code} message=${e.message}');
    } catch (e) {
      debugPrint('[R2 Delete] 실패: $e');
    }
  }

  // ══════════════════════════════════════════════════════════════════════
  // 동영상 — Stream
  // ══════════════════════════════════════════════════════════════════════

  /// 동영상을 Cloudflare Stream에 업로드합니다.
  /// 반환: { videoUid, videoUrl, videoThumbnailUrl } — 예전과 같은 모양입니다.
  ///
  /// 길이 제한(30초)은 이제 **서버가** direct upload를 만들 때 박습니다.
  /// 앱의 편집/압축 단계를 우회해 콜러블을 직접 불러도 긴 영상은 Cloudflare가
  /// 업로드 자체를 거부합니다.
  static Future<Map<String, String>> uploadVideo(XFile file) async {
    debugPrint('[Stream Upload] 업로드 시작: ${LocalMedia.nameOf(file)}');

    final Map<String, dynamic> grant;
    try {
      grant = await _call(_fnCreateVideoUploadUrl, const <String, dynamic>{});
    } on FirebaseFunctionsException catch (e) {
      debugPrint('[Stream Upload] 허가 발급 실패 code=${e.code}');
      throw _fromFunctions(e, 'stream');
    }

    final uploadUrl = grant['uploadUrl'] as String?;
    final videoUid = grant['videoUid'] as String?;
    final videoUrl = grant['videoUrl'] as String?;
    final thumbnailUrl = grant['videoThumbnailUrl'] as String?;
    if (uploadUrl == null || videoUid == null) {
      throw CloudflareUploadException(
        kind: 'stream',
        detail: 'createVideoUploadUrl 응답에 uploadUrl/videoUid가 없습니다.',
      );
    }

    // direct creator upload URL은 그 자체가 일회용 허가라 인증 헤더가 없다.
    //
    // 파일 경로가 아니라 **스트림**으로 붙인다 — 웹의 XFile.path는 실제 파일이
    // 아니라 blob URL이라 `fromPath`가 통하지 않는다. [XFile.openRead]는 앱
    // (파일 스트림)과 웹(blob 조각) 양쪽에 구현이 있어서, 앱에서는 예전처럼
    // 통째로 메모리에 올리지 않고 흘려보낸다.
    final request = http.MultipartRequest('POST', Uri.parse(uploadUrl))
      ..files.add(
        http.MultipartFile(
          'file',
          file.openRead(),
          await file.length(),
          filename: LocalMedia.nameOf(file),
        ),
      );

    final streamed = await _http
        .send(request)
        .timeout(const Duration(minutes: 3));
    final responseBody = await streamed.stream.bytesToString();

    debugPrint('[Stream Upload] status: ${streamed.statusCode}');

    if (streamed.statusCode == 200 || streamed.statusCode == 201) {
      return {
        'videoUid': videoUid,
        'videoUrl':
            videoUrl ??
            'https://videodelivery.net/$videoUid/manifest/video.m3u8',
        'videoThumbnailUrl':
            thumbnailUrl ??
            'https://videodelivery.net/$videoUid/thumbnails/thumbnail.jpg',
      };
    }

    // 30초를 넘는 영상은 여기서 거부된다(maxDurationSeconds). 사용자가
    // 무엇을 고쳐야 하는지 알 수 있게 그 경우만 문구를 붙인다.
    throw CloudflareUploadException(
      kind: 'stream',
      statusCode: streamed.statusCode,
      detail: responseBody,
      userMessage: _isDurationRejection(responseBody)
          ? '동영상은 30초 이내만 올릴 수 있어요. 길이를 줄여 다시 시도해주세요.'
          : null,
    );
  }

  /// Cloudflare가 "길이 초과"로 거부했는가. 응답 본문의 표현이 버전에 따라
  /// 조금씩 달라 넉넉하게 본다(판정에 실패해도 기본 문구로 안내될 뿐이다).
  static bool _isDurationRejection(String body) {
    final lower = body.toLowerCase();
    return lower.contains('maxdurationseconds') ||
        lower.contains('duration exceeds') ||
        lower.contains('exceeds the maximum');
  }

  /// Cloudflare Stream 동영상을 삭제합니다.
  ///
  /// [videoUid]를 우선 사용하고, 없을 때만 [videoUrl] 파싱으로 폴백합니다.
  ///
  /// ── 앱은 "방금 올린 영상"만 지운다 ───────────────────────────────────
  /// 이 메서드를 부르는 곳은 등록·수정 화면의 **롤백 경로 네 곳뿐**이고,
  /// 전부 그 제출에서 방금 업로드한 영상을 되돌린다. 그 영상들은 새 경로로
  /// 올라가 Stream에 `creator`(=uid)가 박혀 있으므로 서버가 본인 확인을
  /// 할 수 있다.
  ///
  /// 이 기능 이전에 올라간(=creator가 없는) 옛 영상은 앱이 지울 일이 없다 —
  /// 파티/플레이스 삭제 · 만료 자동삭제가 전부 서버(contentCleanup.js)에서
  /// Admin 권한으로 처리한다. 그래서 예전에 있던 `.env` 토큰 폴백을
  /// 제거했고, 이제 **앱에는 Cloudflare 자격증명이 하나도 없다.**
  ///
  /// 실패해도 던지지 않는다 — 호출부가 전부 정리 경로다.
  static Future<void> deleteVideo({String? videoUid, String? videoUrl}) async {
    final uid = _resolveVideoUid(videoUid: videoUid, videoUrl: videoUrl);
    if (uid == null || uid.isEmpty) return;

    try {
      await _call(_fnDeleteOwnUpload, {'videoUid': uid});
      debugPrint('[Stream Delete] ok uid=$uid');
    } on FirebaseFunctionsException catch (e) {
      // permission-denied = 남의 영상이거나 소유자를 알 수 없는 옛 영상.
      // not-found = 이미 없음. 둘 다 "앱이 더 할 수 있는 일이 없다"와 같다.
      debugPrint('[Stream Delete] skipped code=${e.code} uid=$uid');
    } catch (e) {
      debugPrint('[Stream Delete] 실패: $e');
    }
  }

  /// [videoUid]가 없으면 URL에서 32자리 uid를 뽑는다(하위 호환).
  ///
  /// 지원 형식:
  ///   https://customer-xxxx.cloudflarestream.com/{uid}/manifest/video.m3u8
  ///   https://customer-xxxx.cloudflarestream.com/{uid}/thumbnails/thumbnail.jpg
  ///   https://videodelivery.net/{uid}/manifest/video.m3u8
  static String? _resolveVideoUid({String? videoUid, String? videoUrl}) {
    if (videoUid != null && videoUid.isNotEmpty) return videoUid;
    if (videoUrl == null || videoUrl.isEmpty) return null;
    final match = RegExp(
      r'(?:cloudflarestream\.com|videodelivery\.net)/([a-f0-9]{32})(?:/|$)',
    ).firstMatch(videoUrl);
    return match?.group(1);
  }

  // ══════════════════════════════════════════════════════════════════════
  // 준비 상태
  // ══════════════════════════════════════════════════════════════════════

  /// 지금 업로드를 시작할 수 있는가.
  ///
  /// 새 경로의 전제는 **로그인**뿐이다 — 콜러블이 request.auth를 요구한다.
  /// 예전에는 `.env`에 Cloudflare 키 4개가 있는지를 봤는데, 이제 앱은 그
  /// 키들로 업로드하지 않으므로 그 검사는 뜻이 없다.
  static bool get isConfigured => UserSession.isLoggedIn;

  /// 업로드를 시작할 수 없는 이유를 로그에 남긴다. 등록 화면들이 사용자
  /// 문구를 띄우기 직전에 부른다. 값은 절대 담지 않는다.
  static void logMissingConfig(String tag) {
    if (!isConfigured) {
      debugPrint('[$tag] 업로드 불가 — 로그인 상태가 아닙니다.');
    }
  }

  /// 응답 본문에서 사람이 읽을 만한 에러 메시지를 뽑아본다(로그용).
  static String? debugErrorSummary(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map && decoded['errors'] is List) {
        final errors = decoded['errors'] as List;
        if (errors.isNotEmpty) return errors.first.toString();
      }
    } catch (_) {}
    return null;
  }
}
