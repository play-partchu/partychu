import 'package:flutter/material.dart';
import 'package:party_app/models/party_detail_decoration_intensity.dart';

const _kLabels = {
  PartyDetailDecorationIntensity.simple: '심플',
  PartyDetailDecorationIntensity.standard: '기본',
  PartyDetailDecorationIntensity.rich: '화려하게',
};

/// "꾸미기 강도"(심플/기본/화려하게) 3단 선택 — 블록형 상세페이지 에디터
/// (`party_detail_block_editor_screen.dart`)와 "간편 자동 꾸미기" 편집 화면
/// (`party_intro_screen.dart`) 양쪽에서 재사용한다.
class DecorationIntensityPicker extends StatelessWidget {
  final PartyDetailDecorationIntensity selected;
  final ValueChanged<PartyDetailDecorationIntensity> onChanged;
  final Color accentColor;

  const DecorationIntensityPicker({
    super.key,
    required this.selected,
    required this.onChanged,
    this.accentColor = const Color(0xFFFF6FA0),
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: PartyDetailDecorationIntensity.values.map((value) {
        final isSelected = value == selected;
        final isLast = value == PartyDetailDecorationIntensity.values.last;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: isLast ? 0 : 8),
            child: GestureDetector(
              onTap: () => onChanged(value),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected ? accentColor : const Color(0xFFF7F7FA),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: isSelected ? accentColor : const Color(0xFFE8EBF2)),
                ),
                alignment: Alignment.center,
                child: Text(
                  _kLabels[value]!,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: isSelected ? Colors.white : Colors.black54,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }
}
