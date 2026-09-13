import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:party_app/models/party_detail_image.dart';
import 'package:party_app/utils/image_dimensions.dart';
import 'package:party_app/utils/local_media.dart';
import 'package:party_app/widgets/party_detail_image_view.dart';

/// 등록·수정 화면이 들고 다니는 **상세 이미지 한 장**의 상태.
///
/// 값이 사는 곳이 두 군데다: 이미 R2에 올라간 [uploadedUrl](수정/재등록/
/// 임시저장 복원)과, 방금 고른 [newFile](아직 업로드 전). **[newFile]이
/// 있으면 그것이 최종값**이다 — 교체는 새 파일을 넣는 것이고, 삭제는 둘 다
/// 비우는 것([empty])이다. 이 규칙 하나로 "교체 / 삭제 / 그대로 두기"가 전부
/// 표현된다.
@immutable
class PartyDetailImageDraft {
  /// 이미 업로드되어 파티 문서에 저장돼 있던 URL.
  final String? uploadedUrl;

  /// 새로 고른 로컬 파일. non-null이면 저장 시 이것을 올려 [uploadedUrl]을
  /// 대체한다.
  final XFile? newFile;

  /// 지금 유효한 이미지의 원본 픽셀 크기(새 파일이 있으면 그 파일의 것).
  final double? width;
  final double? height;

  const PartyDetailImageDraft({
    this.uploadedUrl,
    this.newFile,
    this.width,
    this.height,
  });

  static const empty = PartyDetailImageDraft();

  bool get isEmpty => uploadedUrl == null && newFile == null;
  bool get hasNewFile => newFile != null;

  /// 파티 문서에서 복원 — 수정 화면과 재등록(복사) 흐름이 함께 쓴다.
  static PartyDetailImageDraft fromPartyData(Map<String, dynamic> data) {
    final image = PartyDetailImage.fromData(data);
    if (image == null) return empty;
    return PartyDetailImageDraft(
      uploadedUrl: image.url,
      width: image.width,
      height: image.height,
    );
  }

  /// 저장할 최종 값. [newUploadedUrl]은 이번 저장에서 방금 올린 URL이다.
  PartyDetailImage? resolve({String? newUploadedUrl}) {
    final url = newUploadedUrl ?? uploadedUrl;
    if (url == null || url.isEmpty) return null;
    return PartyDetailImage(url: url, width: width, height: height);
  }

  /// 저장이 끝난 뒤의 상태 — 새 파일은 이미 올라갔으므로 URL만 남긴다.
  /// (수정 화면에서 저장 → 계속 편집 → 다시 저장할 때 같은 파일을 두 번
  /// 올리지 않게 한다.)
  PartyDetailImageDraft settled({String? newUploadedUrl}) {
    final url = newUploadedUrl ?? uploadedUrl;
    if (url == null || url.isEmpty) return empty;
    return PartyDetailImageDraft(
      uploadedUrl: url,
      width: width,
      height: height,
    );
  }

  // ── 임시저장 ────────────────────────────────────────────────────────
  Map<String, dynamic> toDraftMap() => {
    'uploadedUrl': uploadedUrl,
    'newFilePath': newFile == null
        ? null
        : LocalMedia.remember(newFile!).path,
    'width': width,
    'height': height,
  };

  /// 임시저장에서 복원. 로컬 파일이 사라졌으면(OS가 캐시를 비운 경우) 그
  /// 경로는 버린다 — 없는 파일을 업로드에 태우면 정체 불명의 실패가 된다.
  /// 파일이 사라졌다는 사실은 [missingFile]로 알린다(화면이 안내를 띄운다).
  static PartyDetailImageDraft fromDraftMap(
    Object? raw, {
    void Function()? missingFile,
  }) {
    if (raw is! Map) return empty;
    final path = raw['newFilePath'] as String?;
    XFile? file;
    if (path != null && path.isNotEmpty) {
      if (LocalMedia.exists(path)) {
        file = LocalMedia.resolve(path);
      } else {
        missingFile?.call();
      }
    }
    final url = raw['uploadedUrl'] as String?;
    if (file == null && (url == null || url.isEmpty)) return empty;
    return PartyDetailImageDraft(
      uploadedUrl: url,
      newFile: file,
      width: (raw['width'] as num?)?.toDouble(),
      height: (raw['height'] as num?)?.toDouble(),
    );
  }

  /// 수정 화면의 "바뀐 게 있나" 판정에 쓰는 값.
  String get signature => '${uploadedUrl ?? ''}|${newFile?.path ?? ''}';
}

/// 등록·수정 화면의 **"상세 이미지 (선택)"** 카드.
///
/// 대표 사진/동영상 편집기(PartyMediaEditor)를 재사용하지 않는다 — 그쪽은
/// 여러 장·동영상·대표 선택·기본카드 크롭을 함께 다루는 편집기라, 여기서
/// 필요한 "1장 · 이미지 전용 · 크롭 없음"과 규칙이 정면으로 어긋난다. 대신
/// 업로드 자체는 두 화면 모두 기존 경로(CloudflareService.uploadImage)를
/// 그대로 쓰므로 업로드 로직이 새로 생기지는 않는다.
class PartyDetailImageSection extends StatefulWidget {
  final PartyDetailImageDraft draft;
  final ValueChanged<PartyDetailImageDraft> onChanged;

  const PartyDetailImageSection({
    super.key,
    required this.draft,
    required this.onChanged,
  });

  @override
  State<PartyDetailImageSection> createState() =>
      _PartyDetailImageSectionState();
}

class _PartyDetailImageSectionState extends State<PartyDetailImageSection> {
  static const _accent = Color(0xFFFF6FA0);

  /// 미리보기에서 보여줄 최대 높이 — 상세 이미지는 화면 몇 개 분량으로 길 수
  /// 있어, 등록 폼 안에 원본 길이 그대로 넣으면 폼 자체를 스크롤하기 어려워진다.
  /// 위에서부터 이만큼만 보여주고 "상세에서는 전체가 보인다"고 알린다.
  static const _previewMaxHeight = 320.0;

  bool _picking = false;

  void _msg(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _pick() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      // 동영상을 고를 수 없는 피커를 쓴다 — "동영상 불가"를 안내로만 막으면
      // 고른 뒤에 거절당하는 경험이 된다.
      final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;

      // 확장자는 경로가 아니라 원본 파일명/형식에서 본다 — 웹에서 XFile.path는
      // 확장자가 없는 blob URL이라 경로로 보면 전부 거절된다.
      if (!PartyDetailImage.allowedExtensions.contains(
        LocalMedia.extensionOf(picked),
      )) {
        _msg('JPG · PNG · WebP 이미지만 등록할 수 있어요.');
        return;
      }

      final length = await picked.length();
      if (length <= 0) {
        _msg('이미지를 읽을 수 없어요. 다른 파일로 시도해주세요.');
        return;
      }
      if (length > PartyDetailImage.maxFileBytes) {
        final mb = (length / (1024 * 1024)).toStringAsFixed(1);
        _msg(
          '상세 이미지는 최대 ${PartyDetailImage.maxFileMegabytes}MB까지 등록할 수 있어요. '
          '(고른 파일 ${mb}MB)',
        );
        return;
      }

      // 헤더만 읽어 크기를 확인한다 — 세로가 아주 긴 이미지를 원본 그대로
      // 디코드하면 고르는 순간 메모리가 튄다(probeImageFile 주석 참고).
      final probe = await probeImageFile(picked);
      if (probe == null) {
        _msg('이미지를 열 수 없어요. 파일이 손상됐는지 확인해주세요.');
        return;
      }

      widget.onChanged(
        PartyDetailImageDraft(
          // 새 파일이 최종값이지만 기존 URL은 그대로 들고 있는다 — 저장에
          // 성공한 뒤에야 옛 파일을 정리할 수 있기 때문이다(화면이 담당).
          uploadedUrl: widget.draft.uploadedUrl,
          newFile: picked,
          width: probe.width,
          height: probe.height,
        ),
      );
    } catch (e) {
      debugPrint('[PartyDetailImage] 선택 실패: $e');
      _msg('이미지를 불러오지 못했어요. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  void _remove() => widget.onChanged(PartyDetailImageDraft.empty);

  @override
  Widget build(BuildContext context) {
    final draft = widget.draft;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _accent.withValues(alpha: 0.25), width: 1.2),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Text('📄', style: TextStyle(fontSize: 18)),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  PartyDetailImage.pickGuideTitle,
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            PartyDetailImage.pickGuideBody,
            style: TextStyle(fontSize: 13, color: Colors.black54, height: 1.6),
          ),
          const SizedBox(height: 6),
          const Text(
            PartyDetailImage.pickGuideLimit,
            style: TextStyle(fontSize: 11, color: Colors.black38),
          ),
          const SizedBox(height: 14),
          if (draft.isEmpty) _emptyBox() else _preview(draft),
        ],
      ),
    );
  }

  Widget _emptyBox() => GestureDetector(
    onTap: _picking ? null : _pick,
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 26),
      decoration: BoxDecoration(
        color: const Color(0xFFF9F9FB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        children: [
          if (_picking)
            const SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(strokeWidth: 2, color: _accent),
            )
          else
            const Icon(
              Icons.add_photo_alternate_outlined,
              size: 28,
              color: Colors.black38,
            ),
          const SizedBox(height: 8),
          Text(
            _picking ? '이미지를 확인하는 중...' : '상세 이미지 등록하기',
            style: const TextStyle(fontSize: 13, color: Colors.black54),
          ),
        ],
      ),
    ),
  );

  Widget _preview(PartyDetailImageDraft draft) {
    final file = draft.newFile;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LayoutBuilder(
          builder: (context, constraints) {
            final w = draft.width;
            final h = draft.height;
            final aspect = (w != null && h != null && w > 0 && h > 0)
                ? w / h
                : null;
            final view = PartyDetailImageView(
              image: file == null
                  ? PartyDetailImage(
                      url: draft.uploadedUrl!,
                      width: w,
                      height: h,
                    )
                  : null,
              localFile: file,
              localWidth: w,
              localHeight: h,
            );

            // 원본 비율을 알면 위에서부터 _previewMaxHeight 만큼만 잘라
            // 보여준다. Align(heightFactor)는 자식을 원래 크기로 그린 뒤 상자
            // 높이만 줄이므로, 이미지가 축소되지 않고 아래쪽이 잘린다.
            final fullHeight = aspect != null
                ? constraints.maxWidth / aspect
                : null;
            final clipped =
                fullHeight != null && fullHeight > _previewMaxHeight;

            return ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: clipped
                  ? Align(
                      alignment: Alignment.topCenter,
                      heightFactor: _previewMaxHeight / fullHeight,
                      child: view,
                    )
                  : view,
            );
          },
        ),
        const SizedBox(height: 8),
        const Text(
          '미리보기는 위쪽 일부만 보여줘요. 파티 상세에서는 전체가 다 보입니다.',
          style: TextStyle(fontSize: 11, color: Colors.black38),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _picking ? null : _pick,
                icon: const Icon(Icons.swap_horiz, size: 18),
                label: const Text('교체'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _picking ? null : _remove,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('삭제'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red.shade400,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
