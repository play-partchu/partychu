import 'package:flutter/material.dart';
import 'package:party_app/models/party_schedule.dart';
import 'package:party_app/widgets/party_form/party_date_list_sheet.dart';
import 'package:party_app/widgets/party_form/party_recurring_schedule_sheet.dart';
import 'package:party_app/widgets/party_form/party_schedule_type_selector.dart';
import 'package:party_app/widgets/party_form/section_summary_row.dart';

/// 파티 일정 입력 공통 섹션 — 일반 파티 등록 / 플레이스+파티 / 숙박+파티가
/// **모두 이 위젯 하나**를 쓴다. 여기에 기능을 더하면 세 화면에 함께 반영된다.
///
/// 구성은 두 부분뿐이다.
///   1. 일정 방식 선택 — 날짜 직접 선택 / 매주 반복
///   2. 고른 방식의 입력 진입 행(요약 + 오류 표시)
///      - 날짜 직접 선택 → [showPartyDateListSheet] (여러 일정 추가/수정/삭제)
///      - 매주 반복      → [showPartyRecurringScheduleSheet] (요일·시간 규칙)
///
/// 값은 [PartyScheduleDraft] 하나로 오간다 — 화면은 그 값을 상태로 들고 있다가
/// 저장할 때 그대로 쓰면 되고, 방식별 분기 로직을 각자 갖지 않는다.
class PartyScheduleSection extends StatelessWidget {
  final PartyScheduleDraft value;
  final ValueChanged<PartyScheduleDraft> onChanged;

  /// 저장 시도 후 입력이 비어 있으면 true — 요약 행이 빨갛게 바뀐다.
  final bool showError;

  /// 오류 발생 시 이 행으로 스크롤하기 위한 앵커 키(화면이 넘긴다).
  final Key? rowKey;

  /// 수정 화면처럼 일정 방식을 바꾸면 곤란한 경우 잠근다.
  final bool typeChangeEnabled;

  /// 화면마다 소제목 스타일이 달라 라벨 위젯을 넘길 수 있게 한다.
  /// 넘기지 않으면 기본 라벨을 쓴다.
  final Widget Function(String text)? labelBuilder;

  const PartyScheduleSection({
    super.key,
    required this.value,
    required this.onChanged,
    this.showError = false,
    this.rowKey,
    this.typeChangeEnabled = true,
    this.labelBuilder,
  });

  Widget _label(String text) =>
      labelBuilder?.call(text) ??
      Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 4),
        child: Text(
          text,
          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
        ),
      );

  Future<void> _openDateList(BuildContext context) async {
    final result = await showPartyDateListSheet(
      context,
      initial: PartyDateListDraft(
        slots: value.slots,
        openRule: value.openRule,
        deadlineRule: value.deadlineRule,
      ),
    );
    if (result == null) return;
    onChanged(
      value.copyWith(
        slots: result.slots,
        openRule: result.openRule,
        deadlineRule: result.deadlineRule,
      ),
    );
  }

  Future<void> _openRecurring(BuildContext context) async {
    final result = await showPartyRecurringScheduleSheet(
      context,
      initial: value.recurring,
    );
    if (result == null) return;
    onChanged(value.copyWith(recurring: result));
  }

  @override
  Widget build(BuildContext context) {
    final error = value.errorText;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _label('일정 방식'),
        PartyScheduleTypeSelector(
          value: value.type,
          enabled: typeChangeEnabled,
          // 방식을 바꿔도 반대편 입력값은 지우지 않는다 — 잘못 눌렀다가
          // 되돌아왔을 때 입력이 사라지면 안 되기 때문.
          onChanged: (type) => onChanged(value.copyWith(type: type)),
        ),
        const SizedBox(height: 14),
        if (value.isRecurring)
          SectionSummaryRow(
            rowKey: rowKey,
            title: '정기 일정 (요일·시간)',
            isRequired: true,
            summary: value.summaryLabel,
            hasError: showError,
            errorText: showError ? error : null,
            onTap: () => _openRecurring(context),
          )
        else
          SectionSummaryRow(
            rowKey: rowKey,
            title: '날짜 및 시간 선택',
            isRequired: true,
            summary: value.summaryLabel,
            hasError: showError,
            errorText: showError ? error : null,
            onTap: () => _openDateList(context),
          ),
      ],
    );
  }
}
