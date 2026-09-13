import 'package:cloud_functions/cloud_functions.dart';

const _functionsRegion = 'asia-northeast3';

/// 채팅 종류 — 서버(adminChatViewer.js의 KIND_LABELS)와 값이 1:1로 맞는다.
///
/// ⚠️ 패키지·이용권은 **여기에 없다.** 앱에서 플레이스 방문예약·장소대여·
/// 패키지·이용권 문의는 전부 같은 방 하나(relatedType:'place' + placeId)를
/// 공유하기 때문에(chat_target_list_screen.dart의 dedupeKey), 방 문서만 보고는
/// "이 대화가 패키지 건이었는지 이용권 건이었는지"를 되짚을 근거가 없다.
/// 없는 구분을 있는 척 만들지 않고, 대신 원본 글이 어느 컬렉션에 있는지로
/// 확실히 갈리는 만큼만(플레이스 / 장소대여·숙박) 나눈다.
enum ChatKind {
  all('all', '전체'),
  party('party', '파티'),
  venue('venue', '플레이스'),
  stay('stay', '장소대여/숙박'),
  shop('shop', '파티샵'),
  crew('crew', '파티크루'),
  other('other', '기타');

  const ChatKind(this.key, this.label);
  final String key;
  final String label;

  static ChatKind fromKey(String? key) {
    for (final k in ChatKind.values) {
      if (k.key == key) return k;
    }
    return ChatKind.other;
  }
}

/// 검색 축 — 서버가 받는 searchField 값과 같다.
enum ChatSearchField {
  uid('uid', '사용자 UID'),
  nickname('nickname', '닉네임'),
  roomId('roomId', '채팅방 ID'),
  relatedId('relatedId', '대상 ID'),
  title('title', '제목/장소명');

  const ChatSearchField(this.key, this.label);
  final String key;
  final String label;
}

/// 참여자 요약 — users 문서에서 서버가 붙여 보낸다(화면이 uid마다 따로 조회하지
/// 않도록). 문서가 없으면(탈퇴 등) null로 온다.
class ChatUserBrief {
  const ChatUserBrief({
    required this.uid,
    this.nickname,
    this.name,
    this.email,
    this.accountStatus,
    this.isTestAccount = false,
  });

  final String uid;
  final String? nickname;
  final String? name;
  final String? email;
  final String? accountStatus;
  final bool isTestAccount;

  static ChatUserBrief? fromMap(dynamic raw) {
    if (raw is! Map) return null;
    final m = Map<String, dynamic>.from(raw);
    return ChatUserBrief(
      uid: m['uid'] as String? ?? '',
      nickname: m['nickname'] as String?,
      name: m['name'] as String?,
      email: m['email'] as String?,
      accountStatus: m['accountStatus'] as String?,
      isTestAccount: m['isTestAccount'] == true,
    );
  }
}

class AdminChatRoom {
  const AdminChatRoom({
    required this.roomId,
    required this.kind,
    required this.relatedType,
    required this.relatedId,
    required this.relatedTitle,
    required this.sourceExists,
    required this.hostId,
    required this.hostNameInRoom,
    required this.host,
    required this.guestId,
    required this.guestNameInRoom,
    required this.guest,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.createdAt,
    required this.messageCount,
    required this.idScheme,
  });

  final String roomId;
  final ChatKind kind;
  final String? relatedType;
  final String? relatedId;
  final String? relatedTitle;

  /// 원본 글(파티/플레이스/장소/샵/크루)이 아직 존재하는지. 콘텐츠가 삭제되면
  /// 방도 함께 지워지지만(contentCleanup.js), 정리가 끊긴 방을 눈으로 잡기 위함.
  final bool sourceExists;

  final String? hostId;

  /// 방이 만들어질 때 박제된 이름. 지금 계정 닉네임과 다를 수 있다(닉네임 변경).
  final String? hostNameInRoom;
  final ChatUserBrief? host;
  final String? guestId;
  final String? guestNameInRoom;
  final ChatUserBrief? guest;

  final String lastMessage;
  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final int? messageCount;

  /// 'deterministic'("{guestId}_{relatedType}_{relatedId}") 또는 'legacy'(임의 id).
  /// 둘 다 이 화면에서 똑같이 조회된다 — 마이그레이션이 필요 없다는 근거.
  final String idScheme;

  String get hostLabel => _label(hostId, host, hostNameInRoom);
  String get guestLabel => _label(guestId, guest, guestNameInRoom);

  static String _label(String? uid, ChatUserBrief? brief, String? nameInRoom) {
    if (uid == null || uid.isEmpty) return '-';
    final nickname = brief?.nickname;
    if (nickname != null && nickname.isNotEmpty) return nickname;
    if (nameInRoom != null && nameInRoom.isNotEmpty) return nameInRoom;
    final name = brief?.name;
    if (name != null && name.isNotEmpty) return name;
    return '(닉네임 없음)';
  }

  static DateTime? _parse(dynamic v) =>
      v is String ? DateTime.tryParse(v)?.toLocal() : null;

  static AdminChatRoom fromMap(Map<String, dynamic> m) => AdminChatRoom(
    roomId: m['roomId'] as String? ?? '',
    kind: ChatKind.fromKey(m['kind'] as String?),
    relatedType: m['relatedType'] as String?,
    relatedId: m['relatedId'] as String?,
    relatedTitle: m['relatedTitle'] as String?,
    sourceExists: m['sourceExists'] == true,
    hostId: m['hostId'] as String?,
    hostNameInRoom: m['hostNameInRoom'] as String?,
    host: ChatUserBrief.fromMap(m['host']),
    guestId: m['guestId'] as String?,
    guestNameInRoom: m['guestNameInRoom'] as String?,
    guest: ChatUserBrief.fromMap(m['guest']),
    lastMessage: m['lastMessage'] as String? ?? '',
    lastMessageAt: _parse(m['lastMessageAt']),
    createdAt: _parse(m['createdAt']),
    messageCount: (m['messageCount'] as num?)?.toInt(),
    idScheme: m['idScheme'] as String? ?? 'legacy',
  );
}

class AdminChatMessage {
  const AdminChatMessage({
    required this.id,
    required this.senderId,
    required this.role,
    required this.senderNameInMessage,
    required this.senderNickname,
    required this.text,
    required this.isAuto,
    required this.isSystem,
    required this.createdAt,
    required this.extraFields,
  });

  final String id;
  final String? senderId;

  /// 'host' | 'guest' | 'participant' | 'unknown'
  final String role;
  final String? senderNameInMessage;
  final String? senderNickname;
  final String text;

  /// 서버가 호스트 이름으로 내보낸 자동 안내(chatAutoMessages.js).
  final bool isAuto;

  /// 방 참가자가 아닌 uid가 보낸 말. 지금 스키마에 시스템 메시지 개념은 없고,
  /// 이 조건이 그 자리를 대신한다.
  final bool isSystem;
  final DateTime? createdAt;

  /// senderId/senderName/text/isAuto/createdAt 다섯 개 외의 필드. 지금 스키마엔
  /// 첨부도 삭제 표시도 없지만(firestore.rules가 hasOnly로 못 박음), 나중에
  /// 생기면 관리자 화면이 조용히 버리지 않고 먼저 보여주도록 그대로 받아둔다.
  final Map<String, dynamic>? extraFields;

  // ── 사용자가 지운 말 ────────────────────────────────────────────────
  //
  // 앱의 '메시지 삭제'는 문서를 지우지 않는다. 원문(text)만 빈 문자열로 덮고
  // deletedAt/deletedBy를 남긴다(firestore.rules의 messages update). 그래서
  // **관리자에게도 원문은 오지 않는다** — 여기서 가리는 게 아니라 서버에
  // 남아 있지 않다. 대신 "있었다가 지워졌다"는 기록은 그대로다.
  //
  // 두 값은 adminChatViewer.js가 알 수 없는 키를 그대로 실어 보내는 통로
  // (extraFields)로 올라온다 — 그 통로를 만들어 둔 이유가 정확히 이 경우다.
  bool get isDeleted => extraFields?['deletedAt'] != null;

  /// 삭제 시각(서버가 ISO 문자열로 올려 준다) · 삭제한 사람의 uid.
  String? get deletedAtIso => extraFields?['deletedAt'] as String?;
  String? get deletedBy => extraFields?['deletedBy'] as String?;

  String get senderLabel {
    final n = senderNickname;
    if (n != null && n.isNotEmpty) return n;
    final s = senderNameInMessage;
    if (s != null && s.isNotEmpty) return s;
    return senderId ?? '알 수 없음';
  }

  String get roleLabel => switch (role) {
    'host' => '호스트',
    'guest' => '게스트',
    'participant' => '참여자',
    _ => '외부',
  };

  static AdminChatMessage fromMap(Map<String, dynamic> m) => AdminChatMessage(
    id: m['id'] as String? ?? '',
    senderId: m['senderId'] as String?,
    role: m['role'] as String? ?? 'unknown',
    senderNameInMessage: m['senderNameInMessage'] as String?,
    senderNickname: m['senderNickname'] as String?,
    text: m['text'] as String? ?? '',
    isAuto: m['isAuto'] == true,
    isSystem: m['isSystem'] == true,
    createdAt: m['createdAt'] is String
        ? DateTime.tryParse(m['createdAt'] as String)?.toLocal()
        : null,
    extraFields: m['extraFields'] is Map
        ? Map<String, dynamic>.from(m['extraFields'] as Map)
        : null,
  );
}

class AdminChatRoomPage {
  const AdminChatRoomPage({
    required this.rooms,
    required this.nextCursor,
    required this.truncated,
  });

  final List<AdminChatRoom> rooms;
  final String? nextCursor;

  /// 서버가 한 요청에서 훑을 수 있는 만큼을 다 훑고도 페이지를 못 채운 경우.
  /// "결과가 없다"와 구분해서 화면에 알린다 — 조용히 잘라내지 않기 위함.
  final bool truncated;
}

class AdminChatRoomDetail {
  const AdminChatRoomDetail({
    required this.room,
    required this.messages,
    required this.hasMore,
    required this.nextCursor,
  });

  final AdminChatRoom room;
  final List<AdminChatMessage> messages;
  final bool hasMore;
  final String? nextCursor;
}

/// 관리자 채팅 열람 — **읽기 전용**.
///
/// chatRooms/messages에는 관리자 규칙 예외가 없다. 이 두 함수(Admin SDK onCall)가
/// 유일한 통로이고, 어느 쪽도 방/메시지에 아무것도 쓰지 않는다. 상세를 열면
/// 서버가 userActivityLogs에 감사 로그(actorType:'admin')만 남긴다.
class AdminChatService {
  AdminChatService._();

  static FirebaseFunctions get _fn =>
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  static Future<AdminChatRoomPage> listRooms({
    ChatKind kind = ChatKind.all,
    ChatSearchField? searchField,
    String searchValue = '',
    int limit = 50,
    String? cursorId,
  }) async {
    final result = await _fn.httpsCallable('adminListChatRooms').call({
      'kind': kind.key,
      'searchField': searchField?.key,
      'searchValue': searchValue,
      'limit': limit,
      'cursorId': cursorId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    final rooms = ((data['rooms'] as List?) ?? const [])
        .map((r) => AdminChatRoom.fromMap(Map<String, dynamic>.from(r as Map)))
        .toList();
    return AdminChatRoomPage(
      rooms: rooms,
      nextCursor: data['nextCursor'] as String?,
      truncated: data['truncated'] == true,
    );
  }

  static Future<AdminChatRoomDetail> getRoom(
    String roomId, {
    String? cursorId,
  }) async {
    final result = await _fn.httpsCallable('adminGetChatRoom').call({
      'roomId': roomId,
      'cursorId': cursorId,
    });
    final data = Map<String, dynamic>.from(result.data as Map);
    return AdminChatRoomDetail(
      room: AdminChatRoom.fromMap(
        Map<String, dynamic>.from(data['room'] as Map),
      ),
      messages: ((data['messages'] as List?) ?? const [])
          .map(
            (m) => AdminChatMessage.fromMap(Map<String, dynamic>.from(m as Map)),
          )
          .toList(),
      hasMore: data['hasMore'] == true,
      nextCursor: data['nextCursor'] as String?,
    );
  }
}
