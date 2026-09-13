import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:party_app/utils/nickname_service.dart';
import 'package:party_app/utils/user_session.dart';

/// 닉네임 설정/변경 다이얼로그를 띄운다.
/// 반환값 true = 저장 성공(이 시점에 UserSession.nickname이 이미 최신값으로
/// 갱신돼 있으니, 호출부는 곧바로 원래 하려던 동작을 이어서 실행하면 된다).
Future<bool> showNicknameEditDialog(
  BuildContext context, {
  String? title,
  String? description,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (_) => _NicknameEditDialog(
      title: title ?? '닉네임 변경',
      description: description,
      initialValue: UserSession.hasNickname ? UserSession.nickname : '',
    ),
  );
  return result ?? false;
}

class _NicknameEditDialog extends StatefulWidget {
  final String title;
  final String? description;
  final String initialValue;

  const _NicknameEditDialog({
    required this.title,
    required this.description,
    required this.initialValue,
  });

  @override
  State<_NicknameEditDialog> createState() => _NicknameEditDialogState();
}

class _NicknameEditDialogState extends State<_NicknameEditDialog> {
  late final TextEditingController _controller;
  String? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialValue);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final error = NicknameService.validate(_controller.text);
    if (error != null) {
      setState(() => _error = error);
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await NicknameService.save(_controller.text);
      if (mounted) Navigator.pop(context, true);
    } on StateError catch (e) {
      // 중복 닉네임("이미 사용 중인 닉네임이에요…")처럼 **무엇을 고쳐야 하는지**
      // 알려주는 문구가 여기로 온다. 예전처럼 일괄 '저장에 실패했어요'로 덮으면
      // 사용자는 몇 번을 다시 눌러도 같은 이름으로 계속 실패한다.
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = '저장에 실패했어요. 다시 시도해주세요.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.title,
        style: const TextStyle(
          fontFamily: 'SeoulHangang',
          fontSize: 16,
          fontWeight: FontWeight.w500,
          shadows: [
            Shadow(color: Colors.black87, offset: Offset(0.3, 0)),
            Shadow(color: Colors.black87, offset: Offset(-0.3, 0)),
            Shadow(color: Colors.black87, offset: Offset(0, 0.3)),
            Shadow(color: Colors.black87, offset: Offset(0, -0.3)),
          ],
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.description != null) ...[
            Text(
              widget.description!,
              style: const TextStyle(fontSize: 13, color: Colors.black54),
            ),
            const SizedBox(height: 12),
          ],
          TextField(
            controller: _controller,
            autofocus: true,
            maxLength: NicknameService.maxLength,
            enabled: !_saving,
            // 허용 문자만 입력되게 막는다 — 특수문자·공백·이모지가 아예 타이핑
            // 되지 않아, 저장을 눌러야 알게 되는 실패가 줄어든다. 검증 자체는
            // 이 포매터에 기대지 않는다(붙여넣기·IME 조합 중 값은 여기를 그대로
            // 통과할 수 있어서, 최종 판정은 validate와 서버가 한다).
            inputFormatters: [
              FilteringTextInputFormatter.allow(RegExp(r'[가-힣a-zA-Z0-9]')),
            ],
            decoration: InputDecoration(
              hintText:
                  '닉네임 입력 (${NicknameService.minLength}~${NicknameService.maxLength}자)',
              helperText: NicknameService.charsetHint,
              helperMaxLines: 2,
              errorText: _error,
              border: const OutlineInputBorder(),
            ),
            onSubmitted: (_) => _saving ? null : _save(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('취소'),
        ),
        ElevatedButton(
          onPressed: _saving ? null : _save,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF6FA0),
            foregroundColor: Colors.white,
          ),
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('저장'),
        ),
      ],
    );
  }
}
