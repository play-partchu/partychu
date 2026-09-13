import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:image_picker/image_picker.dart' show XFile;

import 'package:party_app/services/cloudflare_service.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/widgets/party_media_editor.dart' show PartyCoverPick;

/// 등록 화면들이 공유하는 "새로 고른 미디어 업로드" 경로.
///
/// 파티 등록 / 플레이스 등록 / 콤보(플레이스+파티·숙박+파티) 등록이 각자
/// 똑같은 for 루프를 복사해 쓰고 있었다. 복사본마다 로그도 검증도 조금씩
/// 달라서, 업로드가 실패해도 "어느 파일이 왜"인지 알 수 없었다. 그 루프를
/// 여기 하나로 모은다.
///
/// 규칙:
///  * **이미 업로드된 URL은 여기 들어오지 않는다.** 호출부가 기존 URL 목록과
///    신규 파일 목록을 따로 들고 있고, 이 함수는 신규 파일만 받는다.
///    (재업로드 방지는 호출부의 자료구조로 보장된다.)
///  * 업로드 **전에** 경로/존재/크기를 검사한다. 임시저장을 복원한 뒤 OS가
///    캐시를 비우면 경로만 남고 파일은 사라지는데, 예전에는 그대로 업로드에
///    들어가 정체 불명의 실패가 됐다.
///  * 도중에 실패하면 [MediaUploadException]에 **그때까지 올라간 것**을 담아
///    던진다. 호출부가 고아 파일을 정리할 수 있어야 하기 때문이다.
enum MediaUploadFailureReason {
  /// 경로가 비었거나 로컬 파일 경로가 아니다(예: 안드로이드 content:// URI).
  invalidPath,

  /// 경로는 있는데 파일이 없다(임시저장 복원 후 캐시 삭제 등).
  missingFile,

  /// 0바이트 파일.
  emptyFile,

  /// 파일을 읽을 수 없다(권한 등).
  unreadableFile,

  /// 업로드 서비스 인증 실패(토큰 만료/무효). 사용자의 사진 잘못이 아니다.
  auth,

  /// 네트워크/타임아웃.
  network,

  /// 그 외.
  unknown,
}

/// 업로드 실패. 어떤 파일이 왜 실패했는지와, 롤백에 필요한 "이미 올라간 것"을
/// 함께 들고 다닌다.
class MediaUploadException implements Exception {
  /// 실패한 항목의 [MediaUploadService.uploadNewMedia] 입력 인덱스.
  final int index;

  /// 실패한 파일 경로(로그·개발자용. 사용자에게 보여주지 않는다).
  final String path;

  final MediaUploadFailureReason reason;

  /// 원래 예외(있으면).
  final Object? cause;

  /// 실패 전까지 성공한 업로드 — 호출부가 정리(삭제)해야 하는 것들.
  final List<String> uploadedImageUrls;
  final String? uploadedVideoUid;

  const MediaUploadException({
    required this.index,
    required this.path,
    required this.reason,
    this.cause,
    this.uploadedImageUrls = const [],
    this.uploadedVideoUid,
  });

  /// 사용자가 "그 사진을 빼면 해결되는" 종류의 실패인가.
  /// 인증/네트워크 실패는 사진 잘못이 아니므로 여기서 제외한다 — 멀쩡한 사진을
  /// 지우라고 안내하면 안 된다.
  bool get isFileProblem =>
      reason == MediaUploadFailureReason.invalidPath ||
      reason == MediaUploadFailureReason.missingFile ||
      reason == MediaUploadFailureReason.emptyFile ||
      reason == MediaUploadFailureReason.unreadableFile;

  @override
  String toString() =>
      'MediaUploadException(index: $index, reason: ${reason.name}, '
      'path: $path, cause: $cause)';
}

/// 업로드 결과 — 신규 업로드분만 담는다(기존 URL은 호출부가 앞에 붙인다).
class MediaUploadResult {
  final List<String> imageUrls;
  final String? videoUid;
  final String? videoUrl;
  final String? videoThumbnailUrl;

  const MediaUploadResult({
    this.imageUrls = const [],
    this.videoUid,
    this.videoUrl,
    this.videoThumbnailUrl,
  });

  bool get hasVideo => videoUid != null;
}

typedef ImageUploader = Future<String> Function(XFile file);
typedef VideoUploader = Future<Map<String, String>> Function(XFile file);

class MediaUploadService {
  MediaUploadService._();

  /// 확장자로 동영상을 판별한다. 화면마다 흩어져 있던 `_isVideoFile`을 모은 것.
  ///
  /// **경로 문자열만 있을 때만 쓴다**(임시저장에 저장된 경로 등). 고른 파일이
  /// 손에 있으면 [isVideoFile]을 써야 한다 — 웹에서 XFile.path는 확장자가 없는
  /// blob URL이라 여기서는 사진과 동영상을 구분할 수 없다.
  static bool isVideoPath(String path) {
    final p = path.toLowerCase();
    return p.endsWith('.mp4') || p.endsWith('.mov');
  }

  /// 고른 파일이 동영상인가 — 확장자(원본 파일명 우선)와 mimeType으로 본다.
  ///
  /// 앱에서는 예전의 경로 판정과 결과가 같고, 웹에서는 blob URL 대신
  /// XFile.name/mimeType을 보므로 판정이 유지된다. 사진 순번(대표 미디어·크롭
  /// 키)이 전부 이 판정 위에 서 있어서, 여기가 틀리면 조용히 어긋난다.
  static bool isVideoFile(XFile file) {
    final ext = LocalMedia.extensionOf(file);
    if (ext == 'mp4' || ext == 'mov') return true;
    return (file.mimeType ?? '').toLowerCase().startsWith('video/');
  }

  /// 새로 고른 미디어를 순서대로 올린다.
  ///
  /// [media]는 **로컬 파일만** — 이미 업로드된 URL은 넣지 않는다.
  /// [logTag]는 로그 접두사(`[combo-media]` 등).
  /// [onImageProgress]/[onVideoStart]로 진행 상태를 화면에 반영한다.
  /// [uploadImage]/[uploadVideo]는 테스트용 주입점이며, 기본값은 Cloudflare다.
  static Future<MediaUploadResult> uploadNewMedia({
    required List<XFile> media,
    String logTag = 'media',
    void Function(int done, int total)? onImageProgress,
    void Function()? onVideoStart,
    ImageUploader? uploadImage,
    VideoUploader? uploadVideo,
  }) async {
    final doUploadImage = uploadImage ?? CloudflareService.uploadImage;
    final doUploadVideo = uploadVideo ?? CloudflareService.uploadVideo;

    final imageUrls = <String>[];
    String? videoUid;
    String? videoUrl;
    String? videoThumbnailUrl;

    final imageTotal = media.where((m) => !isVideoFile(m)).length;
    debugPrint(
      '[$logTag] start total=${media.length} images=$imageTotal '
      'videos=${media.length - imageTotal}',
    );

    var imageDone = 0;
    for (var index = 0; index < media.length; index++) {
      final item = media[index];
      final path = item.path;
      final isVideo = isVideoFile(item);
      debugPrint(
        '[$logTag] item index=$index type=${isVideo ? 'video' : 'image'} '
        'path=$path',
      );

      // ── 업로드 전 검사 ───────────────────────────────────────────────
      // 여기서 걸러야 "왜 실패했는지 모르는 실패"가 안 생긴다.
      // 앱은 파일 존재·크기를, 웹은 blob 오브젝트 URL이 아직 살아 있는지를
      // 본다([LocalMedia.stat]) — 판정 결과의 갈래는 양쪽이 같다.
      final stat = await LocalMedia.stat(item);
      debugPrint(
        '[$logTag] file availability=${stat.availability.name} '
        'size=${stat.size ?? '-'}',
      );
      MediaUploadFailureReason? preflight;
      switch (stat.availability) {
        case LocalMediaAvailability.invalidPath:
          preflight = MediaUploadFailureReason.invalidPath;
        case LocalMediaAvailability.missing:
          preflight = MediaUploadFailureReason.missingFile;
        case LocalMediaAvailability.unreadable:
          preflight = MediaUploadFailureReason.unreadableFile;
        case LocalMediaAvailability.ok:
          preflight = stat.size == 0
              ? MediaUploadFailureReason.emptyFile
              : null;
      }

      if (preflight != null) {
        debugPrint(
          '[$logTag] upload failed index=$index error=${preflight.name}',
        );
        throw MediaUploadException(
          index: index,
          path: path,
          reason: preflight,
          uploadedImageUrls: List.unmodifiable(imageUrls),
          uploadedVideoUid: videoUid,
        );
      }

      // ── 업로드 ───────────────────────────────────────────────────────
      debugPrint('[$logTag] upload start');
      try {
        if (isVideo) {
          onVideoStart?.call();
          final result = await doUploadVideo(item);
          videoUid = result['videoUid'];
          videoUrl = result['videoUrl'];
          videoThumbnailUrl = result['videoThumbnailUrl'];
          debugPrint('[$logTag] upload success url=$videoUrl');
        } else {
          imageDone++;
          onImageProgress?.call(imageDone, imageTotal);
          final url = await doUploadImage(item);
          imageUrls.add(url);
          debugPrint('[$logTag] upload success url=$url');
        }
      } catch (e, stackTrace) {
        debugPrint('[$logTag] upload failed index=$index error=$e');
        logUploadError(e, stackTrace, logTag: logTag);
        throw MediaUploadException(
          index: index,
          path: path,
          reason: classify(e),
          cause: e,
          uploadedImageUrls: List.unmodifiable(imageUrls),
          uploadedVideoUid: videoUid,
        );
      }
    }

    debugPrint(
      '[$logTag] complete images=${imageUrls.length} '
      'video=${videoUid != null}',
    );
    return MediaUploadResult(
      imageUrls: imageUrls,
      videoUid: videoUid,
      videoUrl: videoUrl,
      videoThumbnailUrl: videoThumbnailUrl,
    );
  }

  /// 업로드 도중 난 예외를 갈래로 나눈다.
  /// 사진 크롭 맵의 **키를 최종 URL로 바꾼다.**
  ///
  /// 편집 화면은 크롭 값을 "그 사진의 식별자"로 들고 있는데, 기존 사진은 URL이
  /// 지만 새로 고른 사진은 **로컬 파일 경로**다. 저장되는 문서는 URL로만
  /// 말해야 하므로(카드가 `basicCardPhotoCrops[coverImageUrl]`로 찾는다),
  /// 업로드가 끝난 뒤 이 함수가 경로 → URL로 옮겨 담는다.
  ///
  /// 짝을 맞추는 근거는 **순서**다 — [uploadNewMedia]가 [newMedia]의 사진을
  /// 순서 그대로 올리므로, 동영상을 건너뛴 n번째 사진이 곧
  /// `uploadedImageUrls[n]`이다(대표 사진 순번 계산과 같은 규칙).
  ///
  /// 화면마다 이 루프를 따로 적으면 한쪽만 순서가 어긋나 "다른 사진의 크롭이
  /// 걸리는" 조용한 버그가 된다. 그래서 업로더 옆에 둔다.
  static Map<String, Map<String, double>> resolvePhotoCropKeys({
    required Map<String, Map<String, double>> crops,
    required List<String> existingImageUrls,
    required List<XFile> newMedia,
    required List<String> uploadedImageUrls,
  }) {
    final result = <String, Map<String, double>>{};
    for (final url in existingImageUrls) {
      final c = crops[url];
      if (c != null) result[url] = c;
    }
    var ordinal = 0;
    for (final file in newMedia) {
      if (isVideoFile(file)) continue;
      final c = crops[file.path];
      if (c != null && ordinal < uploadedImageUrls.length) {
        result[uploadedImageUrls[ordinal]] = c;
      }
      ordinal++;
    }
    return result;
  }

  /// 호스트가 고른 대표 미디어를 **문서 필드로** 옮긴다.
  ///
  /// 돌려주는 키는 앱 전체가 이미 쓰는 이름 그대로다 —
  /// `coverMediaType` / `coverImageUrl` / `coverVideoUrl` / `coverVideoUid` /
  /// `coverThumbnailUrl`. 읽는 쪽은 [getPartyCoverMedia] 하나이므로 파티든
  /// 플레이스든 이벤트든 같은 규칙으로 해석된다.
  ///
  /// 고르지 않았으면(coverPick이 null) **사진 우선 → 없으면 동영상**이라는
  /// 기존 기본값을 따른다. 파티·플레이스 등록 화면이 각자 적어 두었던 이
  /// 분기를 여기 한 곳으로 모은 것이라, 화면이 늘어도 대표 판정이 갈라지지
  /// 않는다.
  static Map<String, dynamic> resolveCoverFields({
    required PartyCoverPick? coverPick,
    required List<String> imageUrls,
    required List<String> uploadedImageUrls,
    String? videoUrl,
    String? videoUid,
    String? videoThumbnailUrl,
  }) {
    String type = 'image';
    String? coverImageUrl;
    String? coverVideoUid;
    String? coverVideoUrl;
    String? coverThumbnailUrl;

    void useVideo() {
      type = 'video';
      coverVideoUid = videoUid;
      coverVideoUrl = videoUrl;
      coverThumbnailUrl = videoThumbnailUrl;
    }

    if (coverPick?.isExistingVideo == true || coverPick?.isNewVideo == true) {
      useVideo();
    } else if (coverPick?.existingImageUrl != null) {
      coverImageUrl = coverPick!.existingImageUrl;
      coverThumbnailUrl = coverImageUrl;
    } else if (coverPick?.newImageOrdinal != null) {
      final ordinal = coverPick!.newImageOrdinal!;
      coverImageUrl = ordinal < uploadedImageUrls.length
          ? uploadedImageUrls[ordinal]
          : (imageUrls.isNotEmpty ? imageUrls.first : null);
      coverThumbnailUrl = coverImageUrl;
    } else if (imageUrls.isNotEmpty) {
      coverImageUrl = imageUrls.first;
      coverThumbnailUrl = coverImageUrl;
    } else if ((videoUrl ?? '').isNotEmpty) {
      useVideo();
    }

    // 고른 대표가 동영상인데 영상이 없어진 경우(편집에서 지웠다) 사진으로
    // 되돌린다 — 'video'인데 coverVideoUrl이 비면 읽는 쪽이 대표를 못 찾아
    // 카드가 빈 채로 남는다.
    if (type == 'video' && (coverVideoUrl ?? '').isEmpty) {
      type = 'image';
      coverImageUrl = imageUrls.isNotEmpty ? imageUrls.first : null;
      coverThumbnailUrl = coverImageUrl;
    }

    return {
      'coverMediaType': type,
      'coverImageUrl': coverImageUrl,
      'coverVideoUid': coverVideoUid,
      'coverVideoUrl': coverVideoUrl,
      'coverThumbnailUrl': coverThumbnailUrl,
    };
  }

  static MediaUploadFailureReason classify(Object error) {
    if (error is MediaUploadException) return error.reason;
    if (error is CloudflareUploadException) {
      if (error.isAuthFailure) return MediaUploadFailureReason.auth;
      if (error.isServerFailure) return MediaUploadFailureReason.network;
      return MediaUploadFailureReason.unknown;
    }
    if (error is FileSystemException) {
      return MediaUploadFailureReason.unreadableFile;
    }
    if (error is TimeoutException) return MediaUploadFailureReason.network;

    // http 패키지의 ClientException 등은 타입 이름으로 판별한다(의존성 없이).
    final typeName = error.runtimeType.toString();
    if (typeName.contains('SocketException') ||
        typeName.contains('ClientException') ||
        typeName.contains('HandshakeException')) {
      return MediaUploadFailureReason.network;
    }
    return MediaUploadFailureReason.unknown;
  }

  /// 예외 타입별 상세를 콘솔에 남긴다 — 사용자 문구에는 절대 넣지 않는다.
  static void logUploadError(
    Object e,
    StackTrace stackTrace, {
    String logTag = 'media',
    String label = '미디어 업로드 실패',
  }) {
    debugPrint('$label: $e');
    debugPrintStack(stackTrace: stackTrace);

    if (e is CloudflareUploadException) {
      debugPrint(
        '[$logTag] CloudflareUploadException status=${e.statusCode} '
        'kind=${e.kind} body=${e.detail}',
      );
    } else if (e is FirebaseException) {
      debugPrint(
        '[$logTag] FirebaseException code=${e.code} plugin=${e.plugin} '
        'message=${e.message}',
      );
    } else if (e is PlatformException) {
      debugPrint(
        '[$logTag] PlatformException code=${e.code} '
        'message=${e.message} details=${e.details}',
      );
    } else if (e is FileSystemException) {
      debugPrint(
        '[$logTag] FileSystemException path=${e.path} '
        'message=${e.message} osError=${e.osError}',
      );
    } else if (e is SocketException) {
      debugPrint(
        '[$logTag] SocketException address=${e.address} '
        'message=${e.message} osError=${e.osError}',
      );
    } else {
      debugPrint('[$logTag] ${e.runtimeType}: $e');
    }
  }
}
