import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:party_app/services/block_service.dart';
import 'package:party_app/utils/firestore_error_log.dart';
import 'package:party_app/utils/user_session.dart';
import 'package:party_app/widgets/user_safety_actions.dart';

/// 마이페이지 > 차단한 사용자.
///
/// 차단을 걸 수 있는 자리는 여러 곳(파티 상세·플레이스 상세·채팅방)이지만,
/// **푸는 자리는 여기 하나**여야 한다. 차단한 상대의 글은 목록에서 사라지므로,
/// 원래 있던 화면으로 돌아가 해제하는 것은 사실상 불가능하기 때문이다.
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = UserSession.userId;

    return Scaffold(
      backgroundColor: const Color(0xFFFFF4F8),
      appBar: AppBar(
        title: const Text('차단한 사용자', style: TextStyle(fontSize: 17)),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      body: uid.isEmpty
          ? const Center(
              child: Text(
                '로그인이 필요합니다.',
                style: TextStyle(fontSize: 15, color: Colors.black45),
              ),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: BlockService.watchMyBlocks(),
              builder: (context, snap) {
                // 오류를 먼저 본다 — 조회가 죽었는데 "차단한 사용자가 없어요"가
                // 뜨면, 차단이 풀린 것으로 오해하게 된다.
                if (snap.hasError) {
                  logFirestoreStreamError(
                    'BlockedUsers',
                    snap.error,
                    snap.stackTrace,
                  );
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Text(
                        '차단 목록을 불러오지 못했어요.\n잠시 후 다시 시도해주세요.',
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 14, color: Colors.black45),
                      ),
                    ),
                  );
                }
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: Color(0xFFFF6FA0)),
                  );
                }

                final docs = snap.data?.docs ?? [];
                if (docs.isEmpty) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 40),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.block, size: 48, color: Colors.black26),
                          SizedBox(height: 16),
                          Text(
                            '차단한 사용자가 없어요.',
                            style: TextStyle(
                              fontSize: 15,
                              color: Colors.black45,
                            ),
                          ),
                          SizedBox(height: 8),
                          Text(
                            '파티·플레이스 상세나 채팅방의 ⋮ 메뉴에서 차단할 수 있어요.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.black38,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  itemCount: docs.length,
                  separatorBuilder: (_, _) =>
                      const Divider(height: 1, indent: 16, endIndent: 16),
                  itemBuilder: (context, i) {
                    final d = docs[i].data();
                    final blockedId = d['blockedId'] as String? ?? '';
                    final name = (d['blockedName'] as String? ?? '').trim();
                    final at = (d['createdAt'] as Timestamp?)?.toDate();

                    return ListTile(
                      tileColor: Colors.white,
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFE3EE),
                        child: Icon(
                          Icons.person_off_outlined,
                          color: Color(0xFFFF6FA0),
                          size: 20,
                        ),
                      ),
                      title: Text(
                        name.isNotEmpty ? name : '이름 없는 사용자',
                        style: const TextStyle(fontSize: 14.5),
                      ),
                      subtitle: at == null
                          ? null
                          : Text(
                              '${at.year}.${at.month.toString().padLeft(2, '0')}.'
                              '${at.day.toString().padLeft(2, '0')} 차단',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.black45,
                              ),
                            ),
                      trailing: OutlinedButton(
                        onPressed: () =>
                            confirmUnblock(context, blockedId, name),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFFF6FA0),
                          side: const BorderSide(color: Color(0xFFFFC4DA)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(999),
                          ),
                        ),
                        child: const Text(
                          '차단 해제',
                          style: TextStyle(fontSize: 13),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }
}
