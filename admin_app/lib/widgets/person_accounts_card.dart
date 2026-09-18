import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../theme/admin_theme.dart';
import '../utils/person_identity.dart';

const _accountStatusLabels = {
  'active': '정상',
  'dormant': '휴면',
  'restricted': '이용제한',
  'withdrawn': '탈퇴',
};

/// 회원 상세 '보유 계정' — 실제 회원 1명이 가진 로그인 계정 전부.
///
/// 계정마다 로그인 수단 · 이메일 · UID · 가입일 · 최근 로그인/활동을 적는다.
/// CI와 그 해시는 **그리지 않는다** — 묶음의 근거일 뿐 운영이 볼 값이 아니다.
///
/// 표가 아니라 카드를 세로로 쌓는다 — 360px 폰에서도 가로 스크롤 없이 읽히게.
class PersonAccountsCard extends StatelessWidget {
  final PersonGroup person;

  /// 지금 상세를 보고 있는 계정.
  final String currentUid;

  /// 표시 이름(본인확인 이름, 없으면 닉네임).
  final String displayName;

  /// 다른 계정을 누르면 그 계정의 상세로 간다. null이면 누를 수 없다.
  final ValueChanged<String>? onOpenAccount;

  const PersonAccountsCard({
    super.key,
    required this.person,
    required this.currentUid,
    required this.displayName,
    this.onOpenAccount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(displayName, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
            const _Pill(text: '실제 회원 1명', strong: true),
            _Pill(text: '계정 ${person.accountCount}개'),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          person.key == null
              ? '본인확인(CI) 정보가 없는 계정이라 다른 계정과 같은 사람인지 판별할 수 없습니다 — 이 계정만 표시합니다.'
              : '같은 본인확인(CI)으로 확인된 계정들입니다. 계정마다 신청·채팅·게시글 기록은 따로 남아 있습니다.',
          style: const TextStyle(fontSize: 12, color: AdminTheme.textSecondary),
        ),
        const SizedBox(height: 12),
        for (final a in person.accounts) ...[
          _AccountTile(
            account: a,
            isCurrent: a.uid == currentUid,
            onTap: a.uid == currentUid || onOpenAccount == null ? null : () => onOpenAccount!(a.uid),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

class _AccountTile extends StatelessWidget {
  final MemberAccount account;
  final bool isCurrent;
  final VoidCallback? onTap;

  const _AccountTile({required this.account, required this.isCurrent, this.onTap});

  static String _date(DateTime? d) => d == null ? '-' : DateFormat('yyyy.MM.dd').format(d);

  @override
  Widget build(BuildContext context) {
    final a = account;
    return Material(
      color: isCurrent ? AdminTheme.accentLight.withValues(alpha: 0.45) : Colors.white,
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: isCurrent ? AdminTheme.accent : AdminTheme.cardBorder),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 8,
                runSpacing: 6,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  _Pill(text: a.providerLabel, strong: true),
                  Text(
                    a.email ?? '이메일 없음',
                    style: TextStyle(
                      fontSize: 13.5,
                      color: a.email == null ? AdminTheme.textSecondary : AdminTheme.textPrimary,
                    ),
                  ),
                  if (isCurrent) const _Pill(text: '지금 보는 계정'),
                  if (a.accountStatus != 'active')
                    _Pill(text: _accountStatusLabels[a.accountStatus] ?? a.accountStatus, warn: true),
                  if (a.isTestAccount) const _Pill(text: '테스트'),
                ],
              ),
              const SizedBox(height: 6),
              SelectableText(
                a.uid,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12, color: AdminTheme.textSecondary),
              ),
              const SizedBox(height: 4),
              Wrap(
                spacing: 12,
                runSpacing: 2,
                children: [
                  _Meta(label: '가입', value: _date(a.createdAt)),
                  _Meta(label: '최근 로그인', value: _date(a.lastLoginAt)),
                  _Meta(label: '최근 활동', value: _date(a.lastActiveAt)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Meta extends StatelessWidget {
  final String label;
  final String value;
  const _Meta({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Text.rich(
      TextSpan(children: [
        TextSpan(text: '$label ', style: const TextStyle(color: AdminTheme.textSecondary)),
        TextSpan(text: value),
      ]),
      style: const TextStyle(fontSize: 12),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final bool strong;
  final bool warn;
  const _Pill({required this.text, this.strong = false, this.warn = false});

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = warn
        ? (const Color(0xFFFDECEC), const Color(0xFFC62828))
        : strong
            ? (AdminTheme.accentLight, AdminTheme.accent)
            : (const Color(0xFFF3F4F6), AdminTheme.textSecondary);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: fg)),
    );
  }
}
