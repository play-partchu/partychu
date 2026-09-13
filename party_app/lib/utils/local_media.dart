import 'dart:io' as io;

import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/widgets.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:video_player/video_player.dart';

/// "아직 업로드되지 않은, 방금 고른 로컬 미디어"를 플랫폼에 상관없이 다루는 곳.
///
/// ── 왜 필요한가 ──────────────────────────────────────────────────────────
/// 앱(Android/iOS)에서 image_picker가 돌려주는 [XFile]의 `path`는 실제 파일
/// 경로라, 화면들이 그동안 `File(x.path)`로 바로 열어 왔다. 그런데 **웹에서는
/// 같은 `path`가 `blob:https://.../uuid` 형태의 오브젝트 URL**이다. 파일이
/// 아니다. 그래서 웹에서 `File(...)`을 만지는 순간 `dart:io`가 통째로
/// `UnsupportedError`를 던지고, 사진 한 장 고르는 것조차 되지 않는다.
///
/// 여기 모아둔 함수들은 전부 **XFile 하나만 받는다.** 앱에서는 예전과 똑같이
/// dart:io 경로를 타고, 웹에서는 blob URL/바이트 경로를 탄다. 화면 코드에는
/// `kIsWeb`이 흩어지지 않는다.
///
/// ── 규칙 ─────────────────────────────────────────────────────────────────
///  * **`dart:io`는 이 파일과 `kIsWeb == false` 가지 안에서만 만진다.**
///    (import 자체는 웹에서도 컴파일된다 — 터지는 건 실행할 때다.)
///  * 업로드는 항상 바이트로 한다([XFile.readAsBytes]) — presigned PUT /
///    Stream direct upload 구조는 그대로다. 서버·자격증명·정책은 건드리지
///    않는다.
///  * 웹에서 blob URL은 **그 페이지가 살아 있는 동안만** 유효하다. 새로고침
///    하면 죽는다 — 임시저장에 담긴 로컬 경로를 복원할 때 [exists]가 false를
///    돌려주는 이유이고, 이는 앱에서 OS가 캐시를 비운 경우와 같은 갈래다
///    (호출부는 이미 그 경우를 "그 미디어만 조용히 빼기"로 처리한다).
class LocalMedia {
  LocalMedia._();

  /// 앱 안에서 동영상 압축(video_compress)을 쓸 수 있는가.
  /// 웹에는 플러그인 구현이 없어 호출하면 MissingPluginException이 난다.
  static bool get canCompressVideo => !kIsWeb;

  /// 앱 안에서 동영상 자르기(video_trimmer)를 쓸 수 있는가. 위와 같은 이유.
  static bool get canTrimVideo => !kIsWeb;

  // ── 경로 ↔ 파일 (웹 전용 기억장치) ──────────────────────────────────────
  //
  // 임시저장·중간 모델 몇 군데는 고른 파일을 **경로 문자열 하나로 납작하게**
  // 만들어 들고 있다가(예: PlaceMenu.localImagePath, 등록 화면들의
  // 'newFilePaths'), 저장할 때 다시 XFile로 되살려 업로더에 넘긴다. 앱에서는
  // 경로만 있으면 파일을 온전히 되찾을 수 있어서 아무 문제가 없었다.
  //
  // 웹에서는 그 경로가 `blob:...` 오브젝트 URL이라 **파일 이름도 형식도 담고
  // 있지 않다.** 되살린 XFile은 확장자를 모르고, 그러면 사진인지 동영상인지
  // 가리지 못하고 업로드 허가(ext·contentType)도 받지 못한다.
  //
  // 그래서 납작하게 만드는 **바로 그 자리에서** 원본 XFile을 기억해 두고
  // ([remember]), 되살릴 때 그것을 돌려준다([resolve]). 세션 안에서만 산다 —
  // 새로고침하면 blob 자체가 죽으므로 기억해봐야 소용이 없고, 그때는 예전과
  // 같이 "그 미디어만 빠진 채 복원"이 된다.
  static final Map<String, XFile> _rememberedByPath = <String, XFile>{};

  /// 경로만 남기기 직전에 부른다 — 넘긴 파일을 그대로 돌려주므로
  /// `LocalMedia.remember(f).path` 처럼 한 줄에 끼워 쓸 수 있다.
  static XFile remember(XFile file) {
    if (kIsWeb && file.path.isNotEmpty) _rememberedByPath[file.path] = file;
    return file;
  }

  /// 경로에서 파일을 되살린다 — `XFile(path)` 자리에 그대로 쓴다.
  /// 기억해 둔 것이 있으면 이름·형식까지 살아 있는 원본을 돌려준다.
  static XFile resolve(String path) => _rememberedByPath[path] ?? XFile(path);

  static List<XFile> resolveAll(Iterable<String> paths) => [
    for (final p in paths) resolve(p),
  ];

  // ── 존재/크기 ───────────────────────────────────────────────────────────

  /// 업로드 직전 검사용 — 읽을 수 있는지와 몇 바이트인지.
  ///
  /// 앱: `File.existsSync()` + `lengthSync()` (예전과 같다).
  /// 웹: blob을 실제로 한 번 조회한다([XFile.length]). 오브젝트 URL이 이미
  ///     회수됐으면 여기서 예외가 나므로 "없는 파일"로 판정된다.
  static Future<LocalMediaStat> stat(XFile file) async {
    final path = file.path;
    if (path.trim().isEmpty) {
      return const LocalMediaStat(LocalMediaAvailability.invalidPath);
    }
    if (kIsWeb) {
      try {
        return LocalMediaStat(
          LocalMediaAvailability.ok,
          size: await file.length(),
        );
      } catch (e) {
        debugPrint('[LocalMedia] blob 조회 실패 — 사라진 오브젝트 URL: $e');
        return const LocalMediaStat(LocalMediaAvailability.missing);
      }
    }
    // content:// · file:// 같은 URI는 dart:io File이 열지 못한다.
    // (웹의 blob URL도 '://'를 담고 있지만 위에서 이미 갈라져 나갔다.)
    if (path.contains('://')) {
      return const LocalMediaStat(LocalMediaAvailability.invalidPath);
    }
    try {
      final f = io.File(path);
      if (!f.existsSync()) {
        return const LocalMediaStat(LocalMediaAvailability.missing);
      }
      return LocalMediaStat(LocalMediaAvailability.ok, size: f.lengthSync());
    } catch (e) {
      debugPrint('[LocalMedia] stat 실패 path=$path error=$e');
      return const LocalMediaStat(LocalMediaAvailability.unreadable);
    }
  }

  /// 임시저장 복원용 — 경로만 들고 있을 때 "지금도 열 수 있는가".
  ///
  /// 예전 코드의 `File(path).existsSync()`를 **같은 동기 호출로** 대체한다
  /// (복원 코드가 값을 세우는 도중에 부르는 자리라 async로 바꾸면 복원 순서가
  /// 통째로 흔들린다).
  ///
  /// 웹에서는 blob을 동기적으로 조회할 방법이 없어 [remember]해 둔 것이 있는지
  /// 로 판단한다 — 새로고침하면 기억도 blob도 함께 사라지므로 "새로고침 후
  /// 복원에서는 로컬 미디어가 빠진다"는 결과가 되고, 이는 앱에서 OS가 캐시를
  /// 비운 경우와 같은 갈래다(호출부가 이미 안내를 띄운다).
  ///
  /// 업로드 직전 검사는 이것이 아니라 [stat]이 한다 — 그쪽은 blob을 실제로
  /// 조회하는 진짜 검사다.
  static bool exists(String path) {
    if (path.trim().isEmpty) return false;
    if (kIsWeb) return _rememberedByPath.containsKey(path);
    if (path.contains('://')) return false;
    try {
      return io.File(path).existsSync();
    } catch (e) {
      debugPrint('[LocalMedia] exists 실패 path=$path error=$e');
      return false;
    }
  }

  // ── 표시 ────────────────────────────────────────────────────────────────

  /// 로컬 미디어를 그릴 [ImageProvider].
  /// 앱은 [FileImage], 웹은 blob URL을 그대로 읽는 [NetworkImage].
  static ImageProvider imageProvider(XFile file) =>
      imageProviderForPath(file.path);

  /// 경로 문자열만 있을 때. (앱의 파일 경로 / 웹의 blob URL 둘 다)
  static ImageProvider imageProviderForPath(String path) {
    if (kIsWeb) return NetworkImage(path);
    return FileImage(io.File(path));
  }

  /// 로컬 사진 위젯 — `Image.file(File(x.path))`를 그대로 대체한다.
  /// 인자는 [Image]와 같은 뜻이다(크롭 정렬을 쓰는 곳이 있어 [alignment]도
  /// 그대로 받는다 — 빠뜨리면 카드 노출 위치가 조용히 가운데로 되돌아간다).
  static Widget image(
    XFile file, {
    BoxFit? fit,
    double? width,
    double? height,
    Alignment alignment = Alignment.center,
    int? cacheWidth,
    int? cacheHeight,
    ImageErrorWidgetBuilder? errorBuilder,
  }) => imageForPath(
    file.path,
    fit: fit,
    width: width,
    height: height,
    alignment: alignment,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    errorBuilder: errorBuilder,
  );

  static Widget imageForPath(
    String path, {
    BoxFit? fit,
    double? width,
    double? height,
    Alignment alignment = Alignment.center,
    int? cacheWidth,
    int? cacheHeight,
    ImageErrorWidgetBuilder? errorBuilder,
  }) => Image(
    // Image.file/Image.network의 cacheWidth와 같은 것 — 그 생성자들이 안에서
    // 하는 일을 그대로 한다(세로가 아주 긴 상세 이미지의 디코드 메모리를
    // 화면 폭 기준으로 제한하는 자리에서 쓴다).
    image: ResizeImage.resizeIfNeeded(
      cacheWidth,
      cacheHeight,
      imageProviderForPath(path),
    ),
    fit: fit,
    width: width,
    height: height,
    alignment: alignment,
    errorBuilder: errorBuilder,
  );

  // ── 동영상 재생 ─────────────────────────────────────────────────────────

  /// 로컬 동영상 컨트롤러 — `VideoPlayerController.file(File(x.path))` 대체.
  ///
  /// 웹의 blob URL은 `<video src="blob:...">`로 그대로 재생되므로
  /// [VideoPlayerController.networkUrl]을 쓴다. 길이(30초) 검증이 웹에서도
  /// 그대로 동작하는 이유다.
  static VideoPlayerController videoController(XFile file) =>
      videoControllerForPath(file.path);

  static VideoPlayerController videoControllerForPath(String path) {
    if (kIsWeb) return VideoPlayerController.networkUrl(Uri.parse(path));
    return VideoPlayerController.file(io.File(path));
  }

  // ── 이름/확장자 ─────────────────────────────────────────────────────────

  /// 확장자(소문자, 점 없음).
  ///
  /// 웹에서 `path`는 blob URL이라 확장자가 **없다.** 대신 [XFile.name]이 원본
  /// 파일명을 들고 있으므로 그쪽을 먼저 본다. 둘 다 실패하면 mimeType에서
  /// 뽑는다. 업로드 허가(createUploadUrl)가 ext·contentType을 요구하므로 이
  /// 판정이 틀리면 웹 업로드가 통째로 막힌다.
  static String extensionOf(XFile file) {
    for (final candidate in [file.name, file.path]) {
      final ext = _extFrom(candidate);
      if (ext != null) return ext;
    }
    final mime = (file.mimeType ?? '').toLowerCase();
    switch (mime) {
      case 'image/jpeg':
        return 'jpg';
      case 'image/png':
        return 'png';
      case 'image/gif':
        return 'gif';
      case 'image/webp':
        return 'webp';
      case 'image/heic':
        return 'heic';
      case 'video/mp4':
        return 'mp4';
      case 'video/quicktime':
        return 'mov';
    }
    return '';
  }

  static String? _extFrom(String? value) {
    if (value == null) return null;
    // 쿼리스트링/프래그먼트가 붙은 URL 형태도 있으므로 먼저 잘라낸다.
    var v = value.split('?').first.split('#').first;
    v = v.split('/').last.split(r'\').last;
    final dot = v.lastIndexOf('.');
    if (dot <= 0 || dot == v.length - 1) return null;
    final ext = v.substring(dot + 1).toLowerCase();
    // 확장자로 보기 어려운 것(예: blob UUID 조각)은 버린다.
    if (ext.length > 5 || !RegExp(r'^[a-z0-9]+$').hasMatch(ext)) return null;
    return ext;
  }

  /// 사용자에게 보여줄 파일 이름(로그·업로드 파트 이름용).
  static String nameOf(XFile file) {
    final name = file.name.trim();
    if (name.isNotEmpty && !name.startsWith('blob:')) return name;
    final ext = extensionOf(file);
    return ext.isEmpty ? 'upload' : 'upload.$ext';
  }
}

/// 로컬 미디어를 지금 읽을 수 있는가 — 읽을 수 없다면 어떤 갈래인가.
///
/// 업로드 실패 안내가 이 갈래를 따라 갈린다: 경로 자체가 틀린 것과, 있던
/// 파일이 사라진 것과, 권한 때문에 못 읽는 것은 사용자에게 할 말이 다르다.
enum LocalMediaAvailability {
  /// 읽을 수 있다.
  ok,

  /// 열어볼 수 있는 형태의 경로가 아니다(빈 문자열, content:// URI 등).
  invalidPath,

  /// 경로는 멀쩡한데 대상이 없다 — 앱은 OS가 캐시를 비운 경우,
  /// 웹은 새로고침으로 blob 오브젝트 URL이 회수된 경우.
  missing,

  /// 있긴 한데 읽지 못했다(권한 등).
  unreadable,
}

/// [LocalMedia.stat]의 결과.
class LocalMediaStat {
  final LocalMediaAvailability availability;

  /// 바이트 수(모르면 null).
  final int? size;

  const LocalMediaStat(this.availability, {this.size});

  /// 지금 열 수 있는가.
  bool get exists => availability == LocalMediaAvailability.ok;

  bool get isEmpty => exists && size == 0;
}
