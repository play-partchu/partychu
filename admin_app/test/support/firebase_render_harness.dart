// 관리자 화면을 **실제로 렌더링**하기 위한 Firebase 대역.
//
// 목적은 하나다 — 화면 레이아웃을 진짜 데이터가 들어간 상태로 그려보고,
// 좁은 폭에서 넘침(overflow)이 나는지 확인하는 것. 그래서 이 파일은 데이터를
// 흉내만 내고, 앱 코드는 손대지 않은 그대로(FirebaseFirestore.instance /
// FirebaseFunctions.instanceFor) 쓴다.
//
// ⚠ 테스트 전용이다. 운영 코드·규칙·데이터와는 아무 관계가 없다.
//
// 플랫폼 인터페이스 패키지들은 cloud_firestore/cloud_functions가 이미 끌고
// 오는 것이라, 테스트 대역을 만들려고 pubspec에 따로 올리지는 않는다.
// ignore_for_file: depend_on_referenced_packages
import 'dart:async';

import 'package:cloud_firestore_platform_interface/cloud_firestore_platform_interface.dart';
import 'package:cloud_functions_platform_interface/cloud_functions_platform_interface.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/firebase_core_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

// ── firebase_core ───────────────────────────────────────────────────────────

const _options = FirebaseOptions(
  apiKey: 'k',
  appId: 'a',
  messagingSenderId: 's',
  projectId: 'partychu-test',
);

class _FakeApp extends FirebaseAppPlatform {
  _FakeApp(super.name, super.options);
}

class _MockCore extends FirebasePlatform with MockPlatformInterfaceMixin {
  @override
  FirebaseAppPlatform app([String name = defaultFirebaseAppName]) =>
      _FakeApp(name, _options);

  @override
  Future<FirebaseAppPlatform> initializeApp({
    String? name,
    FirebaseOptions? options,
  }) async =>
      _FakeApp(name ?? defaultFirebaseAppName, options ?? _options);

  @override
  List<FirebaseAppPlatform> get apps => [app()];
}

// ── Firestore ───────────────────────────────────────────────────────────────

/// 컬렉션 경로 → 문서(id, 데이터) 목록. 테스트가 채운다.
typedef FakeCollections = Map<String, List<(String, Map<String, dynamic>)>>;

/// 테스트가 붙잡고 쓰는 가짜 저장소.
///
/// 읽기 전용 대역으로 시작했지만, 읽음 처리처럼 **쓰고 나서 화면이 다시
/// 그려지는 것**까지 봐야 해서 쓰기와 재방출을 붙였다. Firestore를 흉내 내는
/// 것이 목적이 아니라, 앱이 보내는 쓰기를 **그대로 기록해 확인**하고 목록
/// 스트림을 다시 흘려보내는 것이 목적이다.
class FakeFirestoreStore {
  FakeFirestoreStore(this.collections);

  final FakeCollections collections;

  /// 앱이 보낸 쓰기 기록 — `(컬렉션/문서, 데이터)`.
  final List<(String, Map<String, dynamic>)> writes = [];

  /// 등호(`==`) 조건을 **실제로 걸러서** 돌려줄 컬렉션.
  ///
  /// 기본은 비어 있다 — 레이아웃 테스트는 조건과 상관없이 같은 문서를 받는
  /// 편이 편해서, 예전부터 where를 무시해 왔다. 개수 집계처럼 조건이 결과를
  /// 바꾸는 화면을 볼 때만 테스트가 여기에 컬렉션을 넣는다. [reset]이 비운다.
  final Set<String> equalityFiltered = {};

  final Map<String, List<void Function()>> _listeners = {};

  void _notify(String collection) {
    for (final fn in List.of(_listeners[collection] ?? const [])) {
      fn();
    }
  }

  void _addListener(String collection, void Function() fn) {
    _listeners.putIfAbsent(collection, () => []).add(fn);
  }

  void _removeListener(String collection, void Function() fn) {
    _listeners[collection]?.remove(fn);
  }

  /// 다음 테스트를 위해 내용을 통째로 갈아끼운다.
  ///
  /// 테스트마다 새 store를 만들 수 없다 — `FirebaseFirestore.instance`가
  /// **한 번 만들어지면 캐시되어**, 나중에 플랫폼을 바꿔 끼워도 앱은 처음
  /// 것을 계속 쓴다. 그래서 store는 하나로 두고 내용만 새로 채운다.
  void reset(FakeCollections next) {
    final touched = {...collections.keys, ...next.keys};
    collections.clear();
    for (final e in next.entries) {
      collections[e.key] = [
        for (final (id, data) in e.value) (id, Map<String, dynamic>.of(data)),
      ];
    }
    writes.clear();
    equalityFiltered.clear();
    for (final c in touched) {
      _notify(c);
    }
  }

  /// 서버가 `readBy`에 uid를 더한 것과 같은 상태로 만든다.
  ///
  /// 앱은 `FieldValue.arrayUnion`을 보내는데, 그 값은 플랫폼 경계를 넘기 전의
  /// 불투명한 표식이라 대역이 해석할 수 없다. 그래서 **쓰기가 왔다는 사실**은
  /// writes로 확인하고, 그 결과 상태는 테스트가 이 함수로 만든다.
  void markReadBy(String collection, String docId, String uid) {
    final docs = collections[collection];
    if (docs == null) return;
    for (var i = 0; i < docs.length; i++) {
      if (docs[i].$1 != docId) continue;
      final data = Map<String, dynamic>.of(docs[i].$2);
      final readBy = [...(data['readBy'] as List? ?? const []), uid];
      data['readBy'] = readBy.toSet().toList();
      docs[i] = (docs[i].$1, data);
    }
    _notify(collection);
  }
}

class _MockFirestore extends FirebaseFirestorePlatform
    with MockPlatformInterfaceMixin {
  _MockFirestore(this.store);

  final FakeFirestoreStore store;

  FakeCollections get collections => store.collections;

  @override
  FirebaseFirestorePlatform delegateFor({
    FirebaseApp? app,
    String databaseId = 'default',
  }) =>
      this;

  @override
  CollectionReferencePlatform collection(String collectionPath) =>
      _MockCollection(this, collectionPath);

  @override
  DocumentReferencePlatform doc(String documentPath) =>
      _MockDoc(this, documentPath);

  @override
  WriteBatchPlatform batch() => _MockWriteBatch(store);
}

/// '모두 읽음'이 쓰는 배치. 개별 쓰기와 같은 곳에 기록해 테스트가 한 눈으로
/// 본다 — 커밋한 뒤에야 기록된다(실제 배치처럼 커밋 전에는 아무 일도 없다).
class _MockWriteBatch extends WriteBatchPlatform with MockPlatformInterfaceMixin {
  _MockWriteBatch(this._store);

  final FakeFirestoreStore _store;
  final List<(String, Map<String, dynamic>)> _pending = [];

  @override
  void update(String documentPath, Map<String, dynamic> data) {
    _pending.add((documentPath, data));
  }

  @override
  void set(String documentPath, Map<String, dynamic> data, [SetOptions? options]) {
    _pending.add((documentPath, data));
  }

  @override
  void delete(String documentPath) {
    _pending.add((documentPath, const {'__delete': true}));
  }

  @override
  Future<void> commit() async {
    _store.writes.addAll(_pending);
    _pending.clear();
  }
}

SnapshotMetadataPlatform get _queryMeta => SnapshotMetadataPlatform(false, false);
PigeonSnapshotMetadata get _docMeta =>
    PigeonSnapshotMetadata(hasPendingWrites: false, isFromCache: false);

class _MockQuery extends QueryPlatform with MockPlatformInterfaceMixin {
  // params에 null을 넘겨야 where/orderBy 같은 기본 파라미터가 채워진다
  // (실제 MethodChannelQuery와 같은 방식).
  _MockQuery(this.db, this.path, [this.conditions = const []]) : super(db, null);

  /// 상위 [QueryPlatform.firestore]와 이름이 겹치지 않게 따로 들고 있는다.
  final _MockFirestore db;
  final String path;

  /// 걸러 낼 등호 조건 — [FakeFirestoreStore.equalityFiltered]에 든 컬렉션만.
  final List<List<dynamic>> conditions;

  List<(String, Map<String, dynamic>)> get _rows {
    final all = db.collections[path] ?? const [];
    if (conditions.isEmpty) return all;
    return [
      for (final row in all)
        if (conditions.every((c) => _matches(row, c))) row,
    ];
  }

  static bool _matches((String, Map<String, dynamic>) row, List<dynamic> c) {
    if (c.length < 3 || c[1] != '==') return true; // 등호 외 조건은 거르지 않는다.
    final field = c[0];
    final components = field is FieldPath ? field.components : ['$field'];
    if (components.length == 1 && components.single == '__name__') {
      return row.$1 == c[2];
    }
    Object? v = row.$2;
    for (final k in components) {
      v = v is Map ? v[k] : null;
    }
    return v == c[2];
  }

  // 정렬·제한은 레이아웃과 무관하므로 같은 결과를 그대로 돌려준다.
  @override
  QueryPlatform orderBy(Iterable<List<dynamic>> orders) => this;

  @override
  QueryPlatform limit(int limit) => this;

  @override
  QueryPlatform limitToLast(int limit) => this;

  @override
  QueryPlatform where(Object filter) {
    if (filter is List && db.store.equalityFiltered.contains(path)) {
      return _MockQuery(db, path, [
        ...conditions,
        for (final c in filter)
          if (c is List) c,
      ]);
    }
    return this;
  }

  // Filter.or/and 같은 복합 조건은 거르지 않는다(레이아웃·개수 테스트 범위 밖).
  @override
  QueryPlatform whereFilter(FilterPlatformInterface filter) => this;

  @override
  Future<QuerySnapshotPlatform> get([GetOptions options = const GetOptions()]) async =>
      _snapshot();

  @override
  AggregateQueryPlatform count() => _MockCount(this);

  QuerySnapshotPlatform _snapshot() => QuerySnapshotPlatform(
        [
          for (final (id, data) in _rows)
            DocumentSnapshotPlatform(db, '$path/$id', data, _docMeta),
        ],
        const [],
        _queryMeta,
      );

  @override
  Stream<QuerySnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    ListenSource listenSource = ListenSource.defaultSource,
  }) {
    // 한 번 흘리고 끝나면 읽음 처리 뒤 목록이 다시 그려지는지 볼 수 없다.
    // 저장소가 바뀔 때마다 현재 상태를 다시 내보낸다.
    late StreamController<QuerySnapshotPlatform> controller;
    void push() {
      if (!controller.isClosed) controller.add(_snapshot());
    }

    controller = StreamController<QuerySnapshotPlatform>(
      onListen: () {
        push();
        db.store._addListener(path, push);
      },
      onCancel: () => db.store._removeListener(path, push),
    );
    return controller.stream;
  }
}

class _MockCount extends AggregateQueryPlatform with MockPlatformInterfaceMixin {
  _MockCount(_MockQuery super.query);

  @override
  Future<AggregateQuerySnapshotPlatform> get({required AggregateSource source}) async =>
      AggregateQuerySnapshotPlatform(
        count: (query as _MockQuery)._rows.length,
        sum: const [],
        average: const [],
      );
}

/// 실제 구현(MethodChannelCollectionReference)과 같은 모양 — 컬렉션은
/// CollectionReferencePlatform을 상속하지 않고 Query를 상속한 뒤 인터페이스만
/// 구현한다. 그래야 기본 파라미터가 제대로 채워진다.
class _MockCollection extends _MockQuery
    implements
        // ignore: avoid_implementing_value_types
        CollectionReferencePlatform {
  _MockCollection(super.db, super.path);

  @override
  String get id => path.split('/').last;

  @override
  DocumentReferencePlatform? get parent => null;

  @override
  DocumentReferencePlatform doc([String? path]) =>
      _MockDoc(db, '${this.path}/$path');

  Future<DocumentReferencePlatform> add(Map<String, dynamic> data) async =>
      throw UnimplementedError('테스트 대역은 읽기만 흉내 낸다');
}

class _MockDoc extends DocumentReferencePlatform with MockPlatformInterfaceMixin {
  _MockDoc(this._firestore, this.path) : super(_firestore, path);

  final _MockFirestore _firestore;
  @override
  final String path;

  Map<String, dynamic>? get _data {
    final i = path.lastIndexOf('/');
    final collection = path.substring(0, i);
    final id = path.substring(i + 1);
    final docs = _firestore.collections[collection];
    if (docs == null) return null;
    for (final entry in docs) {
      if (entry.$1 == id) return entry.$2;
    }
    return null;
  }

  @override
  Stream<DocumentSnapshotPlatform> snapshots({
    bool includeMetadataChanges = false,
    ListenSource listenSource = ListenSource.defaultSource,
  }) =>
      Stream.value(DocumentSnapshotPlatform(_firestore, path, _data, _docMeta));

  @override
  Future<DocumentSnapshotPlatform> get([GetOptions options = const GetOptions()]) async =>
      DocumentSnapshotPlatform(_firestore, path, _data, _docMeta);

  /// 앱이 보낸 쓰기를 **기록만** 한다. 성공으로 돌려주므로 화면 쪽 흐름은
  /// 그대로 이어지고, 무엇을 보냈는지는 [FakeFirestoreStore.writes]로 본다.
  @override
  Future<void> update(Map<FieldPath, dynamic> data) async {
    _firestore.store.writes.add((
      path,
      {for (final e in data.entries) e.key.toString(): e.value},
    ));
  }

  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    _firestore.store.writes.add((path, data));
  }
}

// ── Cloud Functions ─────────────────────────────────────────────────────────

/// 콜러블 이름 → 반환값.
typedef FakeCallables = Map<String, Object? Function(Object? params)>;

class _MockFunctions extends FirebaseFunctionsPlatform
    with MockPlatformInterfaceMixin {
  _MockFunctions(this.callables, {FirebaseApp? app, String region = 'us-central1'})
      : super(app, region);

  final FakeCallables callables;

  @override
  FirebaseFunctionsPlatform delegateFor({FirebaseApp? app, required String region}) =>
      _MockFunctions(callables, app: app, region: region);

  @override
  HttpsCallablePlatform httpsCallable(
    String? origin,
    String name,
    HttpsCallableOptions options,
  ) =>
      _MockCallable(this, origin, name, options);
}

class _MockCallable extends HttpsCallablePlatform with MockPlatformInterfaceMixin {
  _MockCallable(this._functions, String? origin, String name, HttpsCallableOptions options)
      : super(_functions, origin, name, options, null);

  final _MockFunctions _functions;

  @override
  Future<dynamic> call([dynamic parameters]) async {
    final fn = _functions.callables[name];
    if (fn == null) {
      throw StateError('테스트에 등록되지 않은 콜러블: $name');
    }
    return fn(parameters);
  }
}

// ── 설치 ────────────────────────────────────────────────────────────────────

/// 프로세스당 하나 — 아래 주석 참고.
FakeFirestoreStore? _store;
_MockFunctions? _functions;

/// 앱 코드를 그대로 둔 채 Firebase만 대역으로 바꿔 끼운다.
///
/// 돌려주는 [FakeFirestoreStore]로 테스트가 저장소를 읽고(앱이 보낸 쓰기)
/// 바꿀 수 있다(읽음 처리 결과를 만들어 화면이 다시 그려지는지 확인).
///
/// ⚠️ **플랫폼은 한 번만 갈아끼운다.** 앱의 서비스들이 `FirebaseFirestore.
/// instance`를 `static final`로 들고 있어서, 테스트마다 새 플랫폼을 꽂아도
/// 두 번째부터는 무시되고 첫 store를 계속 쓴다(그래서 setUp마다 새로 만들면
/// 앞 테스트의 상태가 그대로 새어 나온다). 대신 같은 store의 내용만 갈아끼운다.
Future<FakeFirestoreStore> installFakeFirebase({
  FakeCollections collections = const {},
  FakeCallables callables = const {},
}) async {
  if (_store == null) {
    FirebasePlatform.instance = _MockCore();
    await Firebase.initializeApp();
    _store = FakeFirestoreStore({});
    _functions = _MockFunctions({});
    FirebaseFirestorePlatform.instance = _MockFirestore(_store!);
    FirebaseFunctionsPlatform.instance = _functions!;
  }
  _store!.reset(collections);
  _functions!.callables
    ..clear()
    ..addAll(callables);
  return _store!;
}
