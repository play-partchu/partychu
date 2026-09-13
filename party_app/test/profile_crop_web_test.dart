// 프로필 사진 크롭 — **웹에서만** 깨졌던 두 지점을 지킨다.
//
// ① image_cropper의 웹 구현(image_cropper_for_web)은 uiSettings 목록에
//    WebUiSettings가 없으면 `must provide WebUiSettings to run on Web`을 던진다.
//    안드로이드/iOS 구현은 자기 설정만 골라 쓰고 나머지를 무시하므로, 이 누락은
//    **웹에서만** 증상이 났다(사진을 골라도 크롭 화면이 안 뜨고 되돌아감).
//
// ② 크롭 결과의 경로가 플랫폼마다 다르다. 앱은 확장자가 붙은 임시 파일 경로지만,
//    웹은 `blob:.../uuid` 오브젝트 URL이라 이름도 확장자도 없다. 그대로 업로더에
//    넘기면 형식을 알 수 없어(빈 확장자) 업로드 허가를 받지 못한다.
//
// 둘 다 "앱에서는 멀쩡한데 웹에서만 조용히 실패"하는 종류라, 사람이 웹을 직접
// 열어보기 전에는 드러나지 않는다. 그래서 여기서 못박아 둔다.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:party_app/screens/my_page_screen.dart';
import 'package:party_app/utils/local_media.dart';

void main() {
  // 웹 크롭 결과가 실제로 이렇게 생겼다(image_cropper_for_web은
  // web.URL.createObjectURL(blob)을 그대로 돌려준다).
  const webCropResultPath = 'blob:http://localhost:5555/6f1b0c2a-4d9e-49e1';

  group('크롭 결과 형식 상수', () {
    test('형식·파일명·MIME이 서로 어긋나지 않는다', () {
      // 하나만 바꾸고 나머지를 두면 웹 업로드가 조용히 거부된다.
      expect(kProfileCropFormat, ImageCompressFormat.jpg);
      expect(kProfileCropFileName.toLowerCase(), endsWith('.jpg'));
      expect(kProfileCropMimeType, 'image/jpeg');
    });
  });

  group('크롭 결과를 업로더가 알아보는가', () {
    test('이름·MIME을 붙이면 확장자를 얻는다', () {
      final labelled = XFile(
        webCropResultPath,
        name: kProfileCropFileName,
        mimeType: kProfileCropMimeType,
      );
      // 업로더(CloudflareService.uploadImage)가 허가를 받을 때 쓰는 값이다.
      expect(LocalMedia.extensionOf(labelled), 'jpg');
    });

    test('그냥 감싸면 확장자를 못 얻는다 — 이것이 웹에서 났던 실패다', () {
      // blob URL에는 파일명도 확장자도 없다. 이 상태로 업로드에 들어가면
      // contentType이 application/octet-stream이 되어 서버가 거부한다.
      expect(LocalMedia.extensionOf(XFile(webCropResultPath)), '');
    });

    test('앱 경로(확장자 있는 임시 파일)는 예전 그대로 판정된다', () {
      // 안드로이드/iOS의 크롭 결과 모양 — 이름을 붙이든 안 붙이든 결과가 같다.
      const nativeCropResultPath = '/data/user/0/kr.partychu/cache/cropped_1.jpg';
      expect(LocalMedia.extensionOf(XFile(nativeCropResultPath)), 'jpg');
      expect(
        LocalMedia.extensionOf(
          XFile(
            nativeCropResultPath,
            name: kProfileCropFileName,
            mimeType: kProfileCropMimeType,
          ),
        ),
        'jpg',
      );
    });
  });

  group('cropImage 호출 구성', () {
    // 이 검사만 소스를 읽는다. WebUiSettings 누락은 **런타임에 예외로만** 드러나고
    // 그 예외는 화면이 삼켜버려서, 타입 검사로는 잡히지 않기 때문이다.
    // (실제 크롭 호출을 단위 테스트로 태우려면 플러그인 채널이 필요하다.)
    final source = File('lib/screens/my_page_screen.dart').readAsStringSync();

    test('uiSettings에 WebUiSettings가 있다', () {
      expect(
        source.contains('WebUiSettings('),
        isTrue,
        reason: '웹 크롭이 "must provide WebUiSettings to run on Web"으로 죽는다',
      );
    });

    test('안드로이드·iOS 설정을 계속 함께 넘긴다', () {
      // 웹을 고치면서 네이티브 설정을 지우면 앱의 원형 크롭 UI가 사라진다.
      expect(source.contains('AndroidUiSettings('), isTrue);
      expect(source.contains('IOSUiSettings('), isTrue);
      expect(source.contains('cropStyle: CropStyle.circle'), isTrue);
    });

    test('비율·품질은 예전 값 그대로다', () {
      expect(source.contains('CropAspectRatio(ratioX: 1, ratioY: 1)'), isTrue);
      expect(source.contains('compressQuality: 90'), isTrue);
      expect(source.contains('compressFormat: kProfileCropFormat'), isTrue);
    });
  });
}
