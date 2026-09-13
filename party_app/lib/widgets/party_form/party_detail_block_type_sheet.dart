import 'package:flutter/material.dart';
import 'package:party_app/models/party_detail_block.dart';

const _kAccent = Color(0xFFFF6FA0);

class _BlockTypeOption {
  final PartyDetailBlockType type;
  final String title;
  final String subtitle;
  final IconData icon;

  const _BlockTypeOption({
    required this.type,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

const _kOptions = [
  _BlockTypeOption(
    type: PartyDetailBlockType.heading,
    title: '큰 제목',
    subtitle: '굵고 큰 글씨의 제목',
    icon: Icons.title,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.subheading,
    title: '소제목',
    subtitle: '핑크색 굵은 글씨',
    icon: Icons.short_text,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.paragraph,
    title: '일반 글',
    subtitle: '읽기 편한 기본 문단',
    icon: Icons.notes,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.image,
    title: '사진',
    subtitle: '가로폭 전체, 원본 비율 유지',
    icon: Icons.image_outlined,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.imageGroup,
    title: '사진 콜라주',
    subtitle: '2~4장을 그리드로 배치',
    icon: Icons.grid_view_rounded,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.divider,
    title: '구분선',
    subtitle: '연회색 얇은 선',
    icon: Icons.horizontal_rule,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.notice,
    title: '주의사항',
    subtitle: '연핑크 배경의 강조 카드',
    icon: Icons.info_outline,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.checklist,
    title: '체크리스트',
    subtitle: '이런 점이 좋아요 같은 항목 나열',
    icon: Icons.checklist,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.faq,
    title: 'FAQ',
    subtitle: '자주 묻는 질문과 답변',
    icon: Icons.help_outline,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.timeline,
    title: '일정/타임라인',
    subtitle: '시간 순서로 진행 안내',
    icon: Icons.schedule,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.infoCard,
    title: '정보 카드',
    subtitle: '장소·준비물 등 아이콘 카드',
    icon: Icons.badge_outlined,
  ),
  _BlockTypeOption(
    type: PartyDetailBlockType.video,
    title: '동영상',
    subtitle: '동영상 1개 업로드',
    icon: Icons.videocam_outlined,
  ),
];

/// 파티 상세페이지 에디터의 "+ 블록 추가" 바텀시트 — `date_time_sheet.dart`와
/// 동일한 표준 스타일(흰 배경, 상단 둥근 모서리, isScrollControlled)을 따른다.
///
/// [videoBlockLimitReached]가 true면 동영상 옵션을 비활성화한다 — 상세페이지
/// 동영상 블록은 파티당 최대 1개로 제한된다(대표 동영상 1개와는 별개).
Future<PartyDetailBlockType?> showPartyDetailBlockTypeSheet(
  BuildContext context, {
  bool videoBlockLimitReached = false,
}) {
  return showModalBottomSheet<PartyDetailBlockType>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) =>
        _BlockTypeSheetBody(videoBlockLimitReached: videoBlockLimitReached),
  );
}

class _BlockTypeSheetBody extends StatelessWidget {
  final bool videoBlockLimitReached;

  const _BlockTypeSheetBody({required this.videoBlockLimitReached});

  @override
  Widget build(BuildContext context) {
    // 블록 종류가 11개로 늘어나 작은 화면에서는 다 펼치면 화면을 넘칠 수
    // 있다 — 시트 자체 높이를 화면의 85%로 제한하고 옵션 목록만 스크롤되게 한다.
    final maxHeight = MediaQuery.of(context).size.height * 0.85;
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0E0E0),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const Text(
                '블록 추가',
                style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              Flexible(
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      for (final option in _kOptions)
                        _optionTile(context, option),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _optionTile(BuildContext context, _BlockTypeOption option) {
    final disabled =
        videoBlockLimitReached && option.type == PartyDetailBlockType.video;
    return ListTile(
      contentPadding: EdgeInsets.zero,
      enabled: !disabled,
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: disabled ? const Color(0xFFF5F5F5) : const Color(0xFFFFF3F7),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Icon(
          option.icon,
          color: disabled ? Colors.black26 : _kAccent,
          size: 20,
        ),
      ),
      title: Text(
        option.title,
        style: TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w600,
          color: disabled ? Colors.black38 : null,
        ),
      ),
      subtitle: Text(
        disabled ? '동영상 블록은 1개만 추가할 수 있어요' : option.subtitle,
        style: const TextStyle(fontSize: 12, color: Colors.black45),
      ),
      onTap: disabled ? null : () => Navigator.pop(context, option.type),
    );
  }
}
