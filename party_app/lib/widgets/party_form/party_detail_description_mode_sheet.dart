import 'package:flutter/material.dart';
import 'package:party_app/models/party_description_mode.dart';

const _kAccent = Color(0xFFFF6FA0);

class _ModeOption {
  final PartyDescriptionMode mode;
  final String title;
  final String subtitle;
  final IconData icon;

  const _ModeOption({
    required this.mode,
    required this.title,
    required this.subtitle,
    required this.icon,
  });
}

const _kOptions = [
  _ModeOption(
    mode: PartyDescriptionMode.auto,
    title: '✨ 간편 자동 꾸미기',
    subtitle: '소개글만 작성하면 테마에 맞춰 자동으로 꾸며드려요.',
    icon: Icons.auto_awesome,
  ),
  _ModeOption(
    mode: PartyDescriptionMode.blocks,
    title: '▦ 직접 상세페이지 만들기',
    subtitle: '사진과 글 블록을 직접 배치해 상세페이지를 만들어요.',
    icon: Icons.dashboard_customize_outlined,
  ),
];

/// "상세 설명을 어떻게 만들까요?" 선택 시트 — 간편 자동 꾸미기 / 직접
/// 상세페이지 만들기 중 하나만 고른다(둘 다 동시에 쓸 수 없음).
/// `date_time_sheet.dart`/`party_detail_block_type_sheet.dart`와 동일한
/// 표준 바텀시트 스타일을 따른다. [current]로 지금 선택된 방식을 강조
/// 표시하고, 취소하면 null을 돌려준다.
Future<PartyDescriptionMode?> showPartyDetailDescriptionModeSheet(
  BuildContext context, {
  required PartyDescriptionMode current,
}) {
  return showModalBottomSheet<PartyDescriptionMode>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ModeSheetBody(current: current),
  );
}

class _ModeSheetBody extends StatelessWidget {
  final PartyDescriptionMode current;

  const _ModeSheetBody({required this.current});

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
              '상세 설명을 어떻게 만들까요?',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            for (final option in _kOptions) _optionCard(context, option),
          ],
        ),
      ),
    );
  }

  Widget _optionCard(BuildContext context, _ModeOption option) {
    final selected = option.mode == current;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.pop(context, option.mode),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: selected ? const Color(0xFFFFF3F7) : Colors.white,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? _kAccent : const Color(0xFFE8EBF2),
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF3F7),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(option.icon, color: _kAccent, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          option.title,
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (selected) ...[
                          const SizedBox(width: 6),
                          const Icon(
                            Icons.check_circle,
                            size: 16,
                            color: _kAccent,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      option.subtitle,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "상세 설명 방식을 변경할까요?" 확인 다이얼로그 — 지금 활성 방식에 이미
/// 작성한 내용이 있는데 다른 방식으로 바꾸려 할 때만 호출부가 띄운다.
/// 데이터는 지우지 않고 표시만 바뀐다는 점을 안내한다. true면 변경 확정.
Future<bool> confirmPartyDetailDescriptionModeSwitch(
  BuildContext context,
) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text(
        '상세 설명 방식을 변경할까요?',
        style: TextStyle(
          fontFamily: 'SeoulHangang',
          fontWeight: FontWeight.w500,
          shadows: [
            Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
            Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
            Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
            Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
          ],
        ),
      ),
      content: const Text('현재 작성한 내용은 삭제되지 않지만,\n상세 화면에는 새로 선택한 방식만 표시됩니다.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('취소'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text(
            '변경하기',
            style: TextStyle(color: _kAccent, fontWeight: FontWeight.bold),
          ),
        ),
      ],
    ),
  );
  return result ?? false;
}
