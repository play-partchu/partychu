import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:party_app/models/party_detail_block.dart';

/// 체크리스트 한 항목의 편집 상태. [uiKey]는 Flutter 리스트 위젯의 Key로만
/// 쓰는 임시 식별자로, Firestore에는 저장되지 않는다(체크리스트 항목은
/// 예시 스키마대로 순수 문자열 배열).
class ChecklistItemDraft {
  final String uiKey;
  final TextEditingController textCtrl;

  ChecklistItemDraft({String? text})
    : uiKey = generatePartyDetailBlockId(),
      textCtrl = TextEditingController(text: text ?? '');

  ChecklistItemDraft copy() => ChecklistItemDraft(text: textCtrl.text);

  void dispose() => textCtrl.dispose();
}

/// FAQ 한 쌍(질문/답변)의 편집 상태.
class FaqItemDraft {
  final String uiKey;
  final TextEditingController questionCtrl;
  final TextEditingController answerCtrl;

  FaqItemDraft({String? question, String? answer})
    : uiKey = generatePartyDetailBlockId(),
      questionCtrl = TextEditingController(text: question ?? ''),
      answerCtrl = TextEditingController(text: answer ?? '');

  FaqItemDraft copy() =>
      FaqItemDraft(question: questionCtrl.text, answer: answerCtrl.text);

  void dispose() {
    questionCtrl.dispose();
    answerCtrl.dispose();
  }
}

/// 일정/타임라인 한 항목의 편집 상태.
class TimelineItemDraft {
  final String uiKey;
  final TextEditingController timeCtrl;
  final TextEditingController titleCtrl;
  final TextEditingController descriptionCtrl;

  TimelineItemDraft({String? time, String? title, String? description})
    : uiKey = generatePartyDetailBlockId(),
      timeCtrl = TextEditingController(text: time ?? ''),
      titleCtrl = TextEditingController(text: title ?? ''),
      descriptionCtrl = TextEditingController(text: description ?? '');

  TimelineItemDraft copy() => TimelineItemDraft(
    time: timeCtrl.text,
    title: titleCtrl.text,
    description: descriptionCtrl.text,
  );

  void dispose() {
    timeCtrl.dispose();
    titleCtrl.dispose();
    descriptionCtrl.dispose();
  }
}

/// 사진 콜라주(imageGroup) 한 칸의 편집 상태 — 단일 사진 블록과 동일하게
/// "새로 고른 로컬 파일" / "이미 업로드된 URL" 두 상태를 오가며, 정사각형
/// 프레임 안에서 독립적으로 위치조정(크롭)한다.
class ImageGroupItemDraft {
  final String uiKey;
  XFile? newImageFile;
  String? uploadedImageUrl;
  double? width;
  double? height;
  double? cropX;
  double? cropY;
  double? cropScale;

  ImageGroupItemDraft({
    String? uiKey,
    this.newImageFile,
    this.uploadedImageUrl,
    this.width,
    this.height,
    this.cropX,
    this.cropY,
    this.cropScale,
  }) : uiKey = uiKey ?? generatePartyDetailBlockId();

  ImageGroupItemDraft copy() => ImageGroupItemDraft(
    uiKey: uiKey,
    newImageFile: newImageFile,
    uploadedImageUrl: uploadedImageUrl,
    width: width,
    height: height,
    cropX: cropX,
    cropY: cropY,
    cropScale: cropScale,
  );

  bool get isEmpty =>
      newImageFile == null &&
      (uploadedImageUrl == null || uploadedImageUrl!.isEmpty);
}

/// 블록 에디터 화면에서만 쓰는 mutable 작업 단위 — `PartyRoundDraft`와 같은
/// 이유로 순수 직렬화 모델(`PartyDetailBlock`)과 분리한다: 텍스트 블록은
/// `TextEditingController`가 필요하고, 사진/동영상 블록은 "로컬에서 고른
/// 아직 업로드 안 된 파일"과 "이미 업로드된 URL" 두 상태를 오갈 수 있어야
/// 하며, 체크리스트/FAQ/타임라인은 길이가 가변인 항목 리스트를 들고 있어야
/// 한다.
///
/// 이 draft 리스트는 등록/수정 화면 → PartyIntroScreen → 블록 에디터 화면을
/// 오가므로, 컨트롤러 이중 dispose를 막기 위해 다음 소유권 규칙을 지킨다.
///   1. 리스트를 넘겨받는 화면은 즉시 `.map((d) => d.copy()).toList()`로 깊은
///      복사해서 자신만의 작업 리스트를 만들고, 넘겨받은 원본은 건드리지 않는다.
///   2. 확정(저장/완료)해서 pop할 때는 자신의 작업 리스트를 그대로 넘긴다.
///   3. dispose()는 "확정 없이 화면이 닫힌 경우"에만 자신의 작업 리스트를 정리한다.
///   4. 결과를 받은 쪽은 기존에 들고 있던 자기 리스트를 dispose하고 새 리스트로 교체한다.
class PartyDetailBlockDraft {
  final String id;
  final PartyDetailBlockType type;

  /// heading / subheading / paragraph / notice 본문. infoCard에서는 본문
  /// (payload의 `text`)으로 재사용한다.
  final TextEditingController? textCtrl;

  /// image 캡션(선택 입력). video에서는 캡션으로 재사용한다.
  final TextEditingController? captionCtrl;

  /// checklist / faq / timeline의 선택적 제목, infoCard의 제목(사실상 필수).
  final TextEditingController? titleCtrl;

  /// image — 새로 고른, 아직 R2에 업로드되지 않은 파일.
  XFile? newImageFile;

  /// image — 기존 URL이거나 이번 세션에 업로드가 끝난 URL.
  String? uploadedImageUrl;
  double? imageWidth;
  double? imageHeight;

  /// image — 4:5 프레임 안에서의 위치(초점, 0~1)/배율. null이면 아직
  /// 크롭을 지정하지 않은 것(하위 호환 렌더링).
  double? imageCropX;
  double? imageCropY;
  double? imageCropScale;

  /// checklist 항목들.
  final List<ChecklistItemDraft> checklistItems;

  /// faq 항목들.
  final List<FaqItemDraft> faqItems;

  /// timeline 항목들.
  final List<TimelineItemDraft> timelineItems;

  /// imageGroup(사진 콜라주) 항목들 — 2~4개일 때만 저장 시 살아남는다
  /// (`isEmpty` 참고). 그룹 전체 캡션은 [captionCtrl]을 재사용한다.
  final List<ImageGroupItemDraft> imageGroupItems;

  /// infoCard — [partyDetailInfoCardIconNames] 중 하나 또는 null(미선택).
  String? selectedIcon;

  /// video — 새로 고른, 아직 Cloudflare Stream에 업로드되지 않은 파일.
  XFile? newVideoFile;

  /// video — 기존 UID/URL이거나 이번 세션에 업로드가 끝난 값.
  String? uploadedVideoUid;
  String? uploadedVideoUrl;
  String? uploadedVideoThumbnailUrl;
  double? videoAspectRatio;

  /// type == unknown일 때만 non-null — 원본 데이터를 그대로 보존한다.
  final Map<String, dynamic>? rawUnknown;

  PartyDetailBlockDraft._({
    required this.id,
    required this.type,
    this.textCtrl,
    this.captionCtrl,
    this.titleCtrl,
    this.newImageFile,
    this.uploadedImageUrl,
    this.imageWidth,
    this.imageHeight,
    this.imageCropX,
    this.imageCropY,
    this.imageCropScale,
    this.checklistItems = const [],
    this.faqItems = const [],
    this.timelineItems = const [],
    this.imageGroupItems = const [],
    this.selectedIcon,
    this.newVideoFile,
    this.uploadedVideoUid,
    this.uploadedVideoUrl,
    this.uploadedVideoThumbnailUrl,
    this.videoAspectRatio,
    this.rawUnknown,
  });

  /// "+ 블록 추가"로 새로 만드는 빈 블록. unknown은 사용자가 새로 만들 수
  /// 있는 타입이 아니므로(타입 선택 시트에 존재하지 않음) 지원하지 않는다.
  factory PartyDetailBlockDraft.newBlock(PartyDetailBlockType type) {
    final id = generatePartyDetailBlockId();
    switch (type) {
      case PartyDetailBlockType.heading:
      case PartyDetailBlockType.subheading:
      case PartyDetailBlockType.paragraph:
      case PartyDetailBlockType.notice:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          textCtrl: TextEditingController(),
        );
      case PartyDetailBlockType.image:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          captionCtrl: TextEditingController(),
        );
      case PartyDetailBlockType.divider:
        return PartyDetailBlockDraft._(id: id, type: type);
      case PartyDetailBlockType.checklist:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(),
          checklistItems: [ChecklistItemDraft()],
        );
      case PartyDetailBlockType.faq:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(),
          faqItems: [FaqItemDraft()],
        );
      case PartyDetailBlockType.timeline:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(),
          timelineItems: [TimelineItemDraft()],
        );
      case PartyDetailBlockType.infoCard:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(),
          textCtrl: TextEditingController(),
        );
      case PartyDetailBlockType.video:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          captionCtrl: TextEditingController(),
        );
      case PartyDetailBlockType.imageGroup:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          captionCtrl: TextEditingController(),
        );
      case PartyDetailBlockType.unknown:
        throw UnsupportedError('unknown 타입은 새로 만들 수 없습니다.');
    }
  }

  /// Firestore에서 읽어온(또는 방금 미리보기로 만든) 순수 모델을 편집 가능한
  /// draft로 변환한다.
  factory PartyDetailBlockDraft.fromBlock(PartyDetailBlock b) {
    switch (b.type) {
      case PartyDetailBlockType.heading:
      case PartyDetailBlockType.subheading:
      case PartyDetailBlockType.paragraph:
      case PartyDetailBlockType.notice:
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          textCtrl: TextEditingController(text: b.text ?? ''),
        );
      case PartyDetailBlockType.image:
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          captionCtrl: TextEditingController(text: b.caption ?? ''),
          uploadedImageUrl: b.imageUrl,
          imageWidth: b.imageWidth,
          imageHeight: b.imageHeight,
          imageCropX: b.imageCropX,
          imageCropY: b.imageCropY,
          imageCropScale: b.imageCropScale,
        );
      case PartyDetailBlockType.divider:
        return PartyDetailBlockDraft._(id: b.id, type: b.type);
      case PartyDetailBlockType.checklist:
        final payload = b.checklist ?? const PartyDetailChecklistPayload();
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          titleCtrl: TextEditingController(text: payload.title ?? ''),
          checklistItems: payload.items.isEmpty
              ? [ChecklistItemDraft()]
              : payload.items.map((s) => ChecklistItemDraft(text: s)).toList(),
        );
      case PartyDetailBlockType.faq:
        final payload = b.faq ?? const PartyDetailFaqPayload();
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          titleCtrl: TextEditingController(text: payload.title ?? ''),
          faqItems: payload.items.isEmpty
              ? [FaqItemDraft()]
              : payload.items
                    .map(
                      (i) =>
                          FaqItemDraft(question: i.question, answer: i.answer),
                    )
                    .toList(),
        );
      case PartyDetailBlockType.timeline:
        final payload = b.timeline ?? const PartyDetailTimelinePayload();
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          titleCtrl: TextEditingController(text: payload.title ?? ''),
          timelineItems: payload.items.isEmpty
              ? [TimelineItemDraft()]
              : payload.items
                    .map(
                      (i) => TimelineItemDraft(
                        time: i.time,
                        title: i.title,
                        description: i.description,
                      ),
                    )
                    .toList(),
        );
      case PartyDetailBlockType.infoCard:
        final payload =
            b.infoCard ?? const PartyDetailInfoCardPayload(title: '', text: '');
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          titleCtrl: TextEditingController(text: payload.title),
          textCtrl: TextEditingController(text: payload.text),
          selectedIcon: payload.icon,
        );
      case PartyDetailBlockType.video:
        final payload = b.video ?? const PartyDetailVideoPayload(videoUrl: '');
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          captionCtrl: TextEditingController(text: payload.caption ?? ''),
          uploadedVideoUid: payload.videoUid,
          uploadedVideoUrl: payload.videoUrl.isNotEmpty
              ? payload.videoUrl
              : null,
          uploadedVideoThumbnailUrl: payload.thumbnailUrl,
          videoAspectRatio: payload.aspectRatio,
        );
      case PartyDetailBlockType.imageGroup:
        final payload = b.imageGroup ?? const PartyDetailImageGroupPayload();
        return PartyDetailBlockDraft._(
          id: b.id,
          type: b.type,
          captionCtrl: TextEditingController(text: payload.caption ?? ''),
          imageGroupItems: payload.items
              .map(
                (i) => ImageGroupItemDraft(
                  uploadedImageUrl: i.imageUrl,
                  width: i.width,
                  height: i.height,
                  cropX: i.cropX,
                  cropY: i.cropY,
                  cropScale: i.cropScale,
                ),
              )
              .toList(),
        );
      case PartyDetailBlockType.unknown:
        return PartyDetailBlockDraft._(
          id: b.id,
          type: PartyDetailBlockType.unknown,
          rawUnknown: b.rawUnknown,
        );
    }
  }

  /// 깊은 복사 — 화면 간 리스트를 주고받을 때 컨트롤러를 공유하지 않기
  /// 위해 반드시 이 메서드를 거쳐야 한다.
  PartyDetailBlockDraft copy() {
    switch (type) {
      case PartyDetailBlockType.heading:
      case PartyDetailBlockType.subheading:
      case PartyDetailBlockType.paragraph:
      case PartyDetailBlockType.notice:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          textCtrl: TextEditingController(text: textCtrl?.text ?? ''),
        );
      case PartyDetailBlockType.image:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          captionCtrl: TextEditingController(text: captionCtrl?.text ?? ''),
          newImageFile: newImageFile,
          uploadedImageUrl: uploadedImageUrl,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          imageCropX: imageCropX,
          imageCropY: imageCropY,
          imageCropScale: imageCropScale,
        );
      case PartyDetailBlockType.divider:
        return PartyDetailBlockDraft._(id: id, type: type);
      case PartyDetailBlockType.checklist:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(text: titleCtrl?.text ?? ''),
          checklistItems: checklistItems.map((i) => i.copy()).toList(),
        );
      case PartyDetailBlockType.faq:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(text: titleCtrl?.text ?? ''),
          faqItems: faqItems.map((i) => i.copy()).toList(),
        );
      case PartyDetailBlockType.timeline:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(text: titleCtrl?.text ?? ''),
          timelineItems: timelineItems.map((i) => i.copy()).toList(),
        );
      case PartyDetailBlockType.infoCard:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          titleCtrl: TextEditingController(text: titleCtrl?.text ?? ''),
          textCtrl: TextEditingController(text: textCtrl?.text ?? ''),
          selectedIcon: selectedIcon,
        );
      case PartyDetailBlockType.video:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          captionCtrl: TextEditingController(text: captionCtrl?.text ?? ''),
          newVideoFile: newVideoFile,
          uploadedVideoUid: uploadedVideoUid,
          uploadedVideoUrl: uploadedVideoUrl,
          uploadedVideoThumbnailUrl: uploadedVideoThumbnailUrl,
          videoAspectRatio: videoAspectRatio,
        );
      case PartyDetailBlockType.imageGroup:
        return PartyDetailBlockDraft._(
          id: id,
          type: type,
          captionCtrl: TextEditingController(text: captionCtrl?.text ?? ''),
          imageGroupItems: imageGroupItems.map((i) => i.copy()).toList(),
        );
      case PartyDetailBlockType.unknown:
        return PartyDetailBlockDraft._(
          id: id,
          type: PartyDetailBlockType.unknown,
          rawUnknown: rawUnknown,
        );
    }
  }

  /// 미리보기/저장용 순수 모델로 변환한다. 사진/동영상 블록이 아직
  /// 업로드되지 않은 상태면 url은 빈 문자열이 된다 — 이 경우의 호출은
  /// 에디터 내부 미리보기 전용이며, 실제 Firestore 저장 직전에는 반드시
  /// 먼저 업로드를 마쳐 uploaded* 필드를 채운 뒤 호출해야 한다(등록/수정
  /// 화면의 제출 로직에서 보장).
  PartyDetailBlock toBlock() {
    switch (type) {
      case PartyDetailBlockType.heading:
      case PartyDetailBlockType.subheading:
      case PartyDetailBlockType.paragraph:
      case PartyDetailBlockType.notice:
        return PartyDetailBlock(
          id: id,
          type: type,
          text: textCtrl?.text.trim() ?? '',
        );
      case PartyDetailBlockType.image:
        final cap = captionCtrl?.text.trim();
        return PartyDetailBlock(
          id: id,
          type: type,
          imageUrl: uploadedImageUrl ?? '',
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          caption: (cap == null || cap.isEmpty) ? null : cap,
          imageCropX: imageCropX,
          imageCropY: imageCropY,
          imageCropScale: imageCropScale,
        );
      case PartyDetailBlockType.divider:
        return PartyDetailBlock(id: id, type: type);
      case PartyDetailBlockType.checklist:
        final items = checklistItems
            .map((i) => i.textCtrl.text.trim())
            .where((s) => s.isNotEmpty)
            .toList();
        final t = titleCtrl?.text.trim();
        return PartyDetailBlock(
          id: id,
          type: type,
          checklist: PartyDetailChecklistPayload(
            title: (t == null || t.isEmpty) ? null : t,
            items: items,
          ),
        );
      case PartyDetailBlockType.faq:
        final items = faqItems
            .map(
              (i) => PartyDetailFaqItem(
                id: i.uiKey,
                question: i.questionCtrl.text.trim(),
                answer: i.answerCtrl.text.trim(),
              ),
            )
            .where((i) => !i.isEmpty)
            .toList();
        final t = titleCtrl?.text.trim();
        return PartyDetailBlock(
          id: id,
          type: type,
          faq: PartyDetailFaqPayload(
            title: (t == null || t.isEmpty) ? null : t,
            items: items,
          ),
        );
      case PartyDetailBlockType.timeline:
        final items = timelineItems
            .map(
              (i) => PartyDetailTimelineItem(
                id: i.uiKey,
                time: i.timeCtrl.text.trim(),
                title: i.titleCtrl.text.trim(),
                description: i.descriptionCtrl.text.trim(),
              ),
            )
            .where((i) => !i.isEmpty)
            .toList();
        final t = titleCtrl?.text.trim();
        return PartyDetailBlock(
          id: id,
          type: type,
          timeline: PartyDetailTimelinePayload(
            title: (t == null || t.isEmpty) ? null : t,
            items: items,
          ),
        );
      case PartyDetailBlockType.infoCard:
        return PartyDetailBlock(
          id: id,
          type: type,
          infoCard: PartyDetailInfoCardPayload(
            title: titleCtrl?.text.trim() ?? '',
            text: textCtrl?.text.trim() ?? '',
            icon: selectedIcon,
          ),
        );
      case PartyDetailBlockType.video:
        final cap = captionCtrl?.text.trim();
        return PartyDetailBlock(
          id: id,
          type: type,
          video: PartyDetailVideoPayload(
            videoUid: uploadedVideoUid,
            videoUrl: uploadedVideoUrl ?? '',
            thumbnailUrl: uploadedVideoThumbnailUrl,
            aspectRatio: videoAspectRatio,
            caption: (cap == null || cap.isEmpty) ? null : cap,
          ),
        );
      case PartyDetailBlockType.imageGroup:
        final cap = captionCtrl?.text.trim();
        final items = imageGroupItems
            .where((i) => !i.isEmpty)
            .map(
              (i) => PartyDetailImageGroupItem(
                id: i.uiKey,
                imageUrl: i.uploadedImageUrl ?? '',
                width: i.width,
                height: i.height,
                cropX: i.cropX,
                cropY: i.cropY,
                cropScale: i.cropScale,
              ),
            )
            .toList();
        return PartyDetailBlock(
          id: id,
          type: type,
          imageGroup: PartyDetailImageGroupPayload(
            items: items,
            caption: (cap == null || cap.isEmpty) ? null : cap,
          ),
        );
      case PartyDetailBlockType.unknown:
        return PartyDetailBlock(
          id: id,
          type: PartyDetailBlockType.unknown,
          rawUnknown: rawUnknown,
        );
    }
  }

  /// 저장 시 걸러낼 "내용 없는" 블록인지. 구분선과 unknown(보존 대상)은
  /// 항상 false — 사용자가 실수로 지우지 않는 한 그대로 유지한다.
  bool get isEmpty {
    switch (type) {
      case PartyDetailBlockType.heading:
      case PartyDetailBlockType.subheading:
      case PartyDetailBlockType.paragraph:
      case PartyDetailBlockType.notice:
        return (textCtrl?.text.trim().isEmpty) ?? true;
      case PartyDetailBlockType.image:
        return newImageFile == null &&
            (uploadedImageUrl == null || uploadedImageUrl!.isEmpty);
      case PartyDetailBlockType.divider:
      case PartyDetailBlockType.unknown:
        return false;
      case PartyDetailBlockType.checklist:
        return checklistItems.every((i) => i.textCtrl.text.trim().isEmpty);
      case PartyDetailBlockType.faq:
        return faqItems.every(
          (i) =>
              i.questionCtrl.text.trim().isEmpty &&
              i.answerCtrl.text.trim().isEmpty,
        );
      case PartyDetailBlockType.timeline:
        return timelineItems.every(
          (i) =>
              i.timeCtrl.text.trim().isEmpty &&
              i.titleCtrl.text.trim().isEmpty &&
              i.descriptionCtrl.text.trim().isEmpty,
        );
      case PartyDetailBlockType.infoCard:
        return (titleCtrl?.text.trim().isEmpty ?? true) &&
            (textCtrl?.text.trim().isEmpty ?? true);
      case PartyDetailBlockType.video:
        return newVideoFile == null &&
            (uploadedVideoUrl == null || uploadedVideoUrl!.isEmpty);
      case PartyDetailBlockType.imageGroup:
        // 2장 미만이면 콜라주로서 의미가 없으므로 저장 시 걸러낸다.
        return imageGroupItems.where((i) => !i.isEmpty).length < 2;
    }
  }

  void dispose() {
    textCtrl?.dispose();
    captionCtrl?.dispose();
    titleCtrl?.dispose();
    for (final i in checklistItems) {
      i.dispose();
    }
    for (final i in faqItems) {
      i.dispose();
    }
    for (final i in timelineItems) {
      i.dispose();
    }
  }
}
