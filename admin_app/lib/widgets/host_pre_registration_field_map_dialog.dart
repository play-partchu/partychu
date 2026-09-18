import 'package:flutter/material.dart';

import '../models/host_pre_registration.dart';
import '../services/host_pre_registration_service.dart';
import '../utils/responsive.dart';

/// FormHug 폼 필드 ↔ 신청서 항목 연결.
///
/// FormHug 웹훅은 값을 field_1…field_N 번호로만 보내고 라벨을 싣지 않는다.
/// 번호를 코드에 박으면 폼을 고칠 때마다 조용히 엉뚱한 칸이 저장되므로, 서버가
/// FormHug API로 폼 정의를 읽어 오고 **관리자가 눈으로 확인한 연결만** 저장한다.
/// 라벨로 만든 제안은 초기값일 뿐이다.
Future<void> showHostPreRegistrationFieldMapDialog(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const _FieldMapDialog());
}

class _FieldMapDialog extends StatefulWidget {
  const _FieldMapDialog();

  @override
  State<_FieldMapDialog> createState() => _FieldMapDialogState();
}

class _FormField {
  _FormField(this.apiCode, this.label, this.type, this.choices);
  final String apiCode;
  final String label;
  final String type;
  final List<(String, String)> choices; // (apiCode, label)
}

class _FieldMapDialogState extends State<_FieldMapDialog> {
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String _formName = '';
  List<_FormField> _fields = [];
  List<Map<String, dynamic>> _mappable = [];
  final Map<String, String?> _selected = {};
  final Map<String, bool?> _sameChoices = {};
  final Map<String, String?> _deviceChoices = {};

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final r = await HostPreRegistrationService.formSetup({'action': 'getFields'});
      final fields = asList(r['fields']).map((f) {
        final m = asStringMap(f);
        return _FormField(
          m['apiCode'] as String? ?? '',
          m['label'] as String? ?? '',
          m['type'] as String? ?? '',
          asList(m['choices']).map((c) {
            final cm = asStringMap(c);
            return (cm['apiCode'] as String? ?? '', cm['label'] as String? ?? '');
          }).toList(),
        );
      }).toList();
      // 저장된 연결이 있으면 그것을, 없으면 라벨 제안을 초기값으로 쓴다.
      final base = r['config'] != null ? asStringMap(r['config']) : asStringMap(r['suggestion']);
      final baseFields = asStringMap(base['fields']);
      final baseChoices = asStringMap(base['choices']);
      setState(() {
        _formName = r['formName'] as String? ?? '';
        _fields = fields;
        _mappable = asList(r['mappable']).map(asStringMap).toList();
        for (final m in _mappable) {
          final key = m['key'] as String;
          final code = baseFields[key] as String?;
          _selected[key] = fields.any((f) => f.apiCode == code) ? code : null;
        }
        asStringMap(baseChoices['sameAsRepresentative'])
            .forEach((k, v) => _sameChoices[k] = v as bool?);
        asStringMap(baseChoices['deviceType'])
            .forEach((k, v) => _deviceChoices[k] = v as String?);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = callableErrorMessage(e);
        _loading = false;
      });
    }
  }

  _FormField? _fieldFor(String key) {
    final code = _selected[key];
    for (final f in _fields) {
      if (f.apiCode == code) return f;
    }
    return null;
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final same = _fieldFor('sameAsRepresentative');
      final device = _fieldFor('deviceType');
      final r = await HostPreRegistrationService.formSetup({
        'action': 'saveConfig',
        'config': {
          'fields': {
            for (final e in _selected.entries)
              if (e.value != null) e.key: e.value,
          },
          'choices': {
            'sameAsRepresentative': {
              for (final c in same?.choices ?? const <(String, String)>[])
                if (_sameChoices[c.$1] != null) c.$1: _sameChoices[c.$1],
            },
            'deviceType': {
              for (final c in device?.choices ?? const <(String, String)>[])
                if (_deviceChoices[c.$1] != null) c.$1: _deviceChoices[c.$1],
            },
          },
        },
      });
      if (!mounted) return;
      final re = asStringMap(r['reimported']);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('저장했습니다. 대기 중이던 신청 ${re['ok'] ?? 0}건을 가져왔습니다'
            '${(re['failed'] ?? 0) != 0 ? ' (실패 ${re['failed']}건)' : ''}.'),
      ));
      Navigator.of(context).pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('저장 실패: ${callableErrorMessage(e)}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('FormHug 폼 필드 연결${_formName.isEmpty ? '' : ' — $_formName'}'),
      content: SizedBox(
        width: context.dialogWidth(760),
        child: _loading
            ? const SizedBox(height: 160, child: Center(child: CircularProgressIndicator()))
            : _error != null
                ? Text('폼 정의를 불러오지 못했습니다.\n$_error')
                : SingleChildScrollView(child: _form()),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('닫기')),
        if (!_loading && _error == null)
          ElevatedButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? '저장 중…' : '확인하고 저장'),
          ),
      ],
    );
  }

  Widget _form() {
    final same = _fieldFor('sameAsRepresentative');
    final device = _fieldFor('deviceType');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          '각 항목이 폼의 어느 질문인지 확인해주세요. 라벨로 추측한 값이 미리 채워져 있을 수 있으니 '
          '반드시 눈으로 확인한 뒤 저장해야 합니다.',
          style: TextStyle(fontSize: 12.5),
        ),
        const SizedBox(height: 12),
        for (final m in _mappable) _mappingRow(m),
        if (same != null) ...[
          const Divider(height: 28),
          const Text('"대표자와 동일" 선택지', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final c in same.choices)
            _choiceRow<bool>(
              c.$2,
              _sameChoices[c.$1],
              const [(true, '예(동일)'), (false, '아니오(다름)')],
              (v) => setState(() => _sameChoices[c.$1] = v),
            ),
        ],
        if (device != null) ...[
          const Divider(height: 28),
          const Text('사용 기기 선택지', style: TextStyle(fontWeight: FontWeight.bold)),
          for (final c in device.choices)
            _choiceRow<String>(
              c.$2,
              _deviceChoices[c.$1],
              const [('android', 'Android'), ('ios', 'iOS'), ('both', '둘 다')],
              (v) => setState(() => _deviceChoices[c.$1] = v),
            ),
        ],
      ],
    );
  }

  Widget _mappingRow(Map<String, dynamic> m) {
    final key = m['key'] as String;
    final required = m['required'] == true;
    final label = Text('${m['label']}${required ? ' *' : ''}', style: const TextStyle(fontSize: 13));
    // 좁은 화면에서는 라벨(190)과 드롭다운을 한 줄에 두면 드롭다운이 찌그러져
    // 글자가 안 보인다 — 라벨을 윗줄로 올린다.
    final stacked = context.isCompact;
    return Padding(
      padding: EdgeInsets.only(bottom: stacked ? 12 : 8),
      child: Flex(
        direction: stacked ? Axis.vertical : Axis.horizontal,
        crossAxisAlignment: stacked ? CrossAxisAlignment.stretch : CrossAxisAlignment.center,
        children: [
          if (stacked) label else SizedBox(width: 190, child: label),
          _fieldDropdownSlot(
            stacked: stacked,
            child: DropdownButton<String?>(
              isExpanded: true,
              value: _selected[key],
              items: [
                const DropdownMenuItem<String?>(value: null, child: Text('(연결 안 함)')),
                for (final f in _fields)
                  DropdownMenuItem<String?>(
                    value: f.apiCode,
                    child: Text('${f.label}  ·  ${f.apiCode}', overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: (v) => setState(() => _selected[key] = v),
            ),
          ),
        ],
      ),
    );
  }

  /// 드롭다운 자리 — 가로 배치일 때만 Expanded로 남는 폭을 채운다.
  /// (세로로 쌓을 때 Expanded를 쓰면 Column 안에서 높이를 무한히 먹는다.)
  Widget _fieldDropdownSlot({required bool stacked, required Widget child}) =>
      stacked ? child : Expanded(child: child);

  Widget _choiceRow<T>(String label, T? value, List<(T, String)> options, ValueChanged<T?> onChanged) {
    final dropdown = DropdownButton<T?>(
      isExpanded: true,
      value: value,
      items: [
        DropdownMenuItem<T?>(value: null, child: const Text('(지정 안 함)')),
        for (final o in options) DropdownMenuItem<T?>(value: o.$1, child: Text(o.$2, overflow: TextOverflow.ellipsis)),
      ],
      onChanged: onChanged,
    );
    final text = Text(label, style: const TextStyle(fontSize: 13));
    // 라벨 300px + 드롭다운은 좁은 화면에서 들어가지 않는다.
    if (context.isCompact) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [text, dropdown],
        ),
      );
    }
    return Row(
      children: [
        SizedBox(width: 300, child: text),
        Expanded(child: dropdown),
      ],
    );
  }
}
