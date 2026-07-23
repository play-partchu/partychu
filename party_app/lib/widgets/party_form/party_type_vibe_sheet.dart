import 'package:flutter/material.dart';
import 'package:party_app/models/party_constants.dart';

class PartyTypeVibeDraft {
  final Set<String> types;
  final Set<String> vibes;
  final List<String> tags;

  const PartyTypeVibeDraft({
    required this.types,
    required this.vibes,
    this.tags = const [],
  });
}

Future<PartyTypeVibeDraft?> showPartyTypeVibeSheet(
  BuildContext context, {
  required PartyTypeVibeDraft initial,
}) {
  return showModalBottomSheet<PartyTypeVibeDraft>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PartyTypeVibeSheetBody(initial: initial),
  );
}

class _PartyTypeVibeSheetBody extends StatefulWidget {
  final PartyTypeVibeDraft initial;

  const _PartyTypeVibeSheetBody({required this.initial});

  @override
  State<_PartyTypeVibeSheetBody> createState() => _PartyTypeVibeSheetBodyState();
}

class _PartyTypeVibeSheetBodyState extends State<_PartyTypeVibeSheetBody> {
  late final Set<String> _types = {...widget.initial.types};
  late final Set<String> _vibes = {...widget.initial.vibes};
  late final List<String> _tags = [...widget.initial.tags];

  final _tagInputCtrl = TextEditingController();
  bool _showTagInput = false;

  @override
  void dispose() {
    _tagInputCtrl.dispose();
    super.dispose();
  }

  void _showMessage(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Text(text, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
      );

  void _addTag() {
    final text = _tagInputCtrl.text.trim();
    if (text.isEmpty) return;
    if (_tags.contains(text)) {
      _showMessage('이미 추가된 태그예요');
      return;
    }
    if (_tags.length >= PartyConstants.maxTags) {
      _showMessage('태그는 최대 ${PartyConstants.maxTags}개까지 추가할 수 있어요');
      return;
    }
    setState(() {
      _tags.add(text);
      _tagInputCtrl.clear();
      _showTagInput = false;
    });
  }

  void _removeTag(String tag) => setState(() => _tags.remove(tag));

  void _confirm() {
    Navigator.pop(
      context,
      PartyTypeVibeDraft(types: _types, vibes: _vibes, tags: _tags),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(4)),
                ),
              ),
              const SizedBox(height: 16),
              const Text('파티 유형 및 분위기',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 18),
              _label('파티 유형 (최대 ${PartyConstants.maxPartyTypes}개 · ${_types.length}/${PartyConstants.maxPartyTypes} 선택)'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PartyConstants.partyTypes.map((type) {
                  final selected = _types.contains(type);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _types.remove(type);
                      } else if (_types.length < PartyConstants.maxPartyTypes) {
                        _types.add(type);
                      } else {
                        _showMessage('파티 유형은 최대 ${PartyConstants.maxPartyTypes}개까지 선택할 수 있어요');
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFF7F8FC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? const Color(0xFFFF6FA0) : const Color(0xFFDDE1EC),
                        ),
                      ),
                      child: Text(
                        PartyConstants.labelFor(type),
                        style: TextStyle(
                          fontFamily: 'SeoulHangang',
                          fontSize: 13,
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _label('분위기 (최대 ${PartyConstants.maxVibes}개 · ${_vibes.length}/${PartyConstants.maxVibes} 선택)'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: PartyConstants.vibes.map((vibe) {
                  final selected = _vibes.contains(vibe);
                  return GestureDetector(
                    onTap: () => setState(() {
                      if (selected) {
                        _vibes.remove(vibe);
                      } else if (_vibes.length < PartyConstants.maxVibes) {
                        _vibes.add(vibe);
                      } else {
                        _showMessage('분위기는 최대 ${PartyConstants.maxVibes}개까지 선택할 수 있어요');
                      }
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: selected ? const Color(0xFF7C5CBF) : const Color(0xFFF7F8FC),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: selected ? const Color(0xFF7C5CBF) : const Color(0xFFDDE1EC),
                        ),
                      ),
                      child: Text(
                        vibe,
                        style: TextStyle(
                          fontSize: 13,
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              _label('태그 (${_tags.length}/${PartyConstants.maxTags}개 · 자유 입력)'),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in _tags)
                    Container(
                      padding: const EdgeInsets.only(left: 12, right: 4, top: 4, bottom: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFF0F5),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: const Color(0xFFFF6FA0)),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '#$tag',
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: Color(0xFFFF6FA0),
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(width: 2),
                          GestureDetector(
                            onTap: () => _removeTag(tag),
                            child: const Padding(
                              padding: EdgeInsets.all(2),
                              child: Icon(Icons.close, size: 14, color: Color(0xFFFF6FA0)),
                            ),
                          ),
                        ],
                      ),
                    ),
                  if (_tags.length < PartyConstants.maxTags && !_showTagInput)
                    GestureDetector(
                      onTap: () => setState(() => _showTagInput = true),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF7F8FC),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: const Color(0xFFDDE1EC)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.add, size: 14, color: Colors.black54),
                            SizedBox(width: 2),
                            Text('자유기재', style: TextStyle(fontSize: 12.5, color: Colors.black54)),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
              if (_showTagInput) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _tagInputCtrl,
                        autofocus: true,
                        maxLength: 12,
                        decoration: const InputDecoration(
                          hintText: '예: 신입환영, 조용한',
                          counterText: '',
                          isDense: true,
                          contentPadding:
                              EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: _addTag,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF6FA0),
                        foregroundColor: Colors.white,
                      ),
                      child: const Text('추가'),
                    ),
                    IconButton(
                      onPressed: () => setState(() {
                        _showTagInput = false;
                        _tagInputCtrl.clear();
                      }),
                      icon: const Icon(Icons.close, size: 20),
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF6FA0),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text('선택 완료',
                      style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
