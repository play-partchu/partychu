import 'package:flutter/material.dart';

import 'package:party_app/models/party_application_form.dart';

/// 파티 등록/수정 화면의 **승인 방식 + 사전질문** 섹션.
///
/// 승인제를 고른 경우에만 질문 편집이 열린다. 즉시확정으로 되돌리면 질문
/// 편집은 접히고, 저장 시 서버가 질문 정의를 비운다
/// (`setPartyApplicationForm`) — 남겨두면 나중에 다시 승인제를 켰을 때
/// 호스트가 기억하지 못하는 옛 질문이 되살아난다.
///
/// 개인정보 경고는 **승인제를 고르면 항상** 보인다(질문을 아직 하나도 만들지
/// 않았을 때도 보인다 — 만들기 전에 읽어야 뜻이 있다).
class ApplicationFormSection extends StatelessWidget {
  final PartyApprovalMode mode;
  final List<PartyApplicationQuestion> questions;

  /// 신청자에게 프로필 사진을 요청할지 — **기본은 꺼짐**.
  final bool requirePhotos;

  final ValueChanged<PartyApprovalMode> onModeChanged;
  final ValueChanged<List<PartyApplicationQuestion>> onQuestionsChanged;
  final ValueChanged<bool> onRequirePhotosChanged;

  const ApplicationFormSection({
    super.key,
    required this.mode,
    required this.questions,
    required this.requirePhotos,
    required this.onModeChanged,
    required this.onQuestionsChanged,
    required this.onRequirePhotosChanged,
  });

  static const _accent = Color(0xFF7C5CBF);

  bool get _isManual => mode == PartyApprovalMode.manual;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '신청 방식',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 10),
        for (final m in PartyApprovalMode.values) _modeTile(m),
        if (_isManual) ...[
          const SizedBox(height: 18),
          _photoRequestTile(),
          const SizedBox(height: 18),
          _privacyNotice(),
          const SizedBox(height: 14),
          _questionsHeader(),
          const SizedBox(height: 10),
          if (questions.isEmpty)
            _emptyHint()
          else
            for (var i = 0; i < questions.length; i++)
              _questionCard(context, i),
          const SizedBox(height: 8),
          if (questions.length < PartyApplicationLimits.maxQuestions)
            _addButton(context),
        ],
      ],
    );
  }

  /// 📷 프로필 사진 등록 요청 — 사전질문과 **독립된 옵션**이다.
  /// 승인제일 때만 보이고, 기본값은 꺼짐이다.
  Widget _photoRequestTile() => Container(
    padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
    decoration: BoxDecoration(
      color: requirePhotos ? _accent.withValues(alpha: 0.06) : Colors.white,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: requirePhotos ? _accent : const Color(0xFFE3E5EC),
        width: requirePhotos ? 1.4 : 1,
      ),
    ),
    child: Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '📷 프로필 사진 등록 요청',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: requirePhotos ? _accent : Colors.black87,
                ),
              ),
              const SizedBox(height: 2),
              const Text(
                '승인 심사를 위해 신청자에게 프로필 사진 제출을 요청합니다.',
                style: TextStyle(fontSize: 12.5, color: Colors.black54),
              ),
            ],
          ),
        ),
        Switch(
          value: requirePhotos,
          onChanged: onRequirePhotosChanged,
          activeThumbColor: _accent,
        ),
      ],
    ),
  );

  Widget _modeTile(PartyApprovalMode m) {
    final selected = m == mode;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => onModeChanged(m),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          decoration: BoxDecoration(
            color: selected ? _accent.withValues(alpha: 0.06) : Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: selected ? _accent : const Color(0xFFE3E5EC),
              width: selected ? 1.4 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                size: 20,
                color: selected ? _accent : const Color(0xFFB9BDC9),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      m.label,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                        color: selected ? _accent : Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      m.description,
                      style: const TextStyle(
                        fontSize: 12.5,
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

  /// 개인정보 경고 — 승인제에서는 접거나 숨길 수 없다.
  Widget _privacyNotice() => Container(
    padding: const EdgeInsets.all(13),
    decoration: BoxDecoration(
      color: const Color(0xFFFFF4F4),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: const Color(0xFFFFD5D5)),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          Icons.privacy_tip_outlined,
          size: 19,
          color: Color(0xFFD94A4A),
        ),
        const SizedBox(width: 9),
        const Expanded(
          child: Text(
            kApplicationQuestionPrivacyNotice,
            style: TextStyle(
              fontSize: 12.5,
              height: 1.45,
              color: Color(0xFF8B2F2F),
            ),
          ),
        ),
      ],
    ),
  );

  Widget _questionsHeader() => Row(
    children: [
      const Text(
        '사전질문',
        style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
      ),
      const SizedBox(width: 7),
      Text(
        '${questions.length}/${PartyApplicationLimits.maxQuestions}',
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: _accent,
        ),
      ),
    ],
  );

  Widget _emptyHint() => Container(
    width: double.infinity,
    padding: const EdgeInsets.symmetric(vertical: 18),
    alignment: Alignment.center,
    decoration: BoxDecoration(
      color: const Color(0xFFF7F7FA),
      borderRadius: BorderRadius.circular(12),
    ),
    child: const Text(
      '신청자에게 물어볼 질문을 추가해보세요.\n질문이 없으면 승인만 받게 돼요.',
      textAlign: TextAlign.center,
      style: TextStyle(fontSize: 12.5, height: 1.5, color: Colors.black54),
    ),
  );

  Widget _questionCard(BuildContext context, int index) {
    final q = questions[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(13, 11, 8, 11),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE3E5EC)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: _accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  '${index + 1}',
                  style: const TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w800,
                    color: _accent,
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Text(
                  q.text,
                  style: const TextStyle(fontSize: 14, height: 1.35),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              // 필수/선택 — 탭 한 번으로 뒤집는다.
              InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => _replace(index, q.copyWith(required: !q.required)),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: q.required
                        ? const Color(0xFFFFEDF3)
                        : const Color(0xFFF2F3F7),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    q.required ? '필수' : '선택',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      color: q.required
                          ? const Color(0xFFE0407A)
                          : Colors.black54,
                    ),
                  ),
                ),
              ),
              const Spacer(),
              _iconAction(
                icon: Icons.keyboard_arrow_up_rounded,
                tooltip: '위로',
                enabled: index > 0,
                onTap: () => _move(index, index - 1),
              ),
              _iconAction(
                icon: Icons.keyboard_arrow_down_rounded,
                tooltip: '아래로',
                enabled: index < questions.length - 1,
                onTap: () => _move(index, index + 1),
              ),
              _iconAction(
                icon: Icons.edit_outlined,
                tooltip: '수정',
                enabled: true,
                onTap: () => _edit(context, index: index),
              ),
              _iconAction(
                icon: Icons.delete_outline_rounded,
                tooltip: '삭제',
                enabled: true,
                danger: true,
                onTap: () {
                  final next = [...questions]..removeAt(index);
                  onQuestionsChanged(next);
                },
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _iconAction({
    required IconData icon,
    required String tooltip,
    required bool enabled,
    required VoidCallback onTap,
    bool danger = false,
  }) => IconButton(
    tooltip: tooltip,
    onPressed: enabled ? onTap : null,
    icon: Icon(icon, size: 20),
    visualDensity: VisualDensity.compact,
    padding: const EdgeInsets.symmetric(horizontal: 4),
    constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
    color: danger ? const Color(0xFFD94A4A) : Colors.black54,
  );

  Widget _addButton(BuildContext context) => SizedBox(
    width: double.infinity,
    child: OutlinedButton.icon(
      onPressed: () => _edit(context, index: null),
      icon: const Icon(Icons.add, size: 18),
      label: const Text(
        '질문 추가',
        style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700),
      ),
      style: OutlinedButton.styleFrom(
        foregroundColor: _accent,
        side: BorderSide(color: _accent.withValues(alpha: 0.45)),
        minimumSize: const Size(0, 46),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    ),
  );

  void _replace(int index, PartyApplicationQuestion q) {
    final next = [...questions];
    next[index] = q;
    onQuestionsChanged(next);
  }

  void _move(int from, int to) {
    if (to < 0 || to >= questions.length) return;
    final next = [...questions];
    final item = next.removeAt(from);
    next.insert(to, item);
    onQuestionsChanged(next);
  }

  /// 질문 추가/수정 시트. [index]가 null이면 새 질문이다.
  Future<void> _edit(BuildContext context, {required int? index}) async {
    final existing = index == null ? null : questions[index];
    final result = await showModalBottomSheet<PartyApplicationQuestion>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _QuestionEditSheet(existing: existing),
    );
    if (result == null) return;
    if (index == null) {
      onQuestionsChanged([...questions, result]);
    } else {
      _replace(index, result);
    }
  }
}

/// 등록/수정 화면의 `SectionSummaryRow`가 여는 시트.
///
/// 취소하면 null, 저장하면 고른 값이 나온다 — 두 화면이 같은 시트를 쓴다.
typedef ApplicationFormResult = ({
  PartyApprovalMode mode,
  List<PartyApplicationQuestion> questions,
  bool requirePhotos,
});

Future<ApplicationFormResult?> showApplicationFormSheet(
  BuildContext context, {
  required PartyApprovalMode mode,
  required List<PartyApplicationQuestion> questions,
  required bool requirePhotos,
}) {
  return showModalBottomSheet<ApplicationFormResult>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ApplicationFormSheet(
      mode: mode,
      questions: questions,
      requirePhotos: requirePhotos,
    ),
  );
}

class _ApplicationFormSheet extends StatefulWidget {
  final PartyApprovalMode mode;
  final List<PartyApplicationQuestion> questions;
  final bool requirePhotos;

  const _ApplicationFormSheet({
    required this.mode,
    required this.questions,
    required this.requirePhotos,
  });

  @override
  State<_ApplicationFormSheet> createState() => _ApplicationFormSheetState();
}

class _ApplicationFormSheetState extends State<_ApplicationFormSheet> {
  late PartyApprovalMode _mode = widget.mode;
  late List<PartyApplicationQuestion> _questions = [...widget.questions];
  late bool _requirePhotos = widget.requirePhotos;

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.75,
      maxChildSize: 0.95,
      builder: (_, controller) => Column(
        children: [
          const SizedBox(height: 14),
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: const Color(0xFFE0E2EA),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: ListView(
              controller: controller,
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 12),
              children: [
                ApplicationFormSection(
                  mode: _mode,
                  questions: _questions,
                  requirePhotos: _requirePhotos,
                  onModeChanged: (m) => setState(() => _mode = m),
                  onQuestionsChanged: (q) => setState(() => _questions = q),
                  onRequirePhotosChanged: (v) =>
                      setState(() => _requirePhotos = v),
                ),
              ],
            ),
          ),
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 6, 20, 12),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(context, (
                    mode: _mode,
                    questions: _questions,
                    // 즉시확정으로 되돌리면 사진 요청도 함께 꺼진다 —
                    // 질문 정의를 비우는 것과 같은 이유다.
                    requirePhotos:
                        _mode == PartyApprovalMode.manual && _requirePhotos,
                  )),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF7C5CBF),
                    minimumSize: const Size(0, 52),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: const Text(
                    '확인',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuestionEditSheet extends StatefulWidget {
  final PartyApplicationQuestion? existing;
  const _QuestionEditSheet({this.existing});

  @override
  State<_QuestionEditSheet> createState() => _QuestionEditSheetState();
}

class _QuestionEditSheetState extends State<_QuestionEditSheet> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.existing?.text ?? '',
  );
  late bool _required = widget.existing?.required ?? false;

  /// 금지어 안내 — 저장을 누르기 전에도 입력하는 동안 계속 보여준다.
  String? _banned;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onChanged(String v) {
    final reason = bannedQuestionReason(v);
    if (reason != _banned) setState(() => _banned = reason);
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    // 여기서 막아도 **정본은 서버**다 — setPartyApplicationForm이 같은 규칙으로
    // 다시 판정하고, 통과하지 못하면 저장 자체가 거부된다.
    if (bannedQuestionReason(text) != null) return;
    Navigator.pop(
      context,
      PartyApplicationQuestion(
        // 기존 질문은 id를 그대로 유지한다 — 이미 접수된 신청의 답변이 이
        // id로 묶여 있어서, 새로 발급하면 답변이 통째로 미아가 된다.
        id:
            widget.existing?.id ??
            'q${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}',
        text: text,
        required: _required,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final text = _controller.text.trim();
    final canSubmit = text.isNotEmpty && _banned == null;
    return Padding(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 18,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.existing == null ? '질문 추가' : '질문 수정',
            style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _controller,
            onChanged: _onChanged,
            autofocus: true,
            maxLength: PartyApplicationLimits.maxQuestionLength,
            maxLines: 2,
            minLines: 1,
            decoration: InputDecoration(
              hintText: '예) 이 파티에 참여하고 싶은 이유가 무엇인가요?',
              hintStyle: const TextStyle(fontSize: 13.5, color: Colors.black38),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              errorText: _banned,
              errorMaxLines: 3,
            ),
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              const Text('필수 답변', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 6),
              const Tooltip(
                message: '필수로 두면 답변하지 않고는 신청할 수 없어요.',
                child: Icon(
                  Icons.info_outline,
                  size: 15,
                  color: Colors.black38,
                ),
              ),
              const Spacer(),
              Switch(
                value: _required,
                activeThumbColor: const Color(0xFF7C5CBF),
                onChanged: (v) => setState(() => _required = v),
              ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: canSubmit ? _submit : null,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF7C5CBF),
                minimumSize: const Size(0, 50),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text(
                '저장',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
