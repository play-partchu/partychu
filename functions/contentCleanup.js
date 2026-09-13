// ══════════════════════════════════════════════════════════════════════════
// 콘텐츠 정리 — 삭제할 때 실제로 무엇을 지우고 무엇을 남길지 정하는 공용 모듈.
//
// 두 경로가 이 파일을 함께 쓴다:
//   1. 사용자가 삭제 버튼을 누를 때 (contentDelete.js의 deleteContent 콜러블)
//   2. 만료 콘텐츠 자동 삭제 (index.js의 deleteExpiredParties 등)
//
// 둘이 갈라지면 "손으로 지운 파티"와 "30일 지나 자동 삭제된 파티"가 서로 다른
// 쓰레기를 남긴다. 그래서 정리 규칙은 여기 한 곳에만 있다.
//
// ⚠ 이 파일은 Cloud Function을 export 하지 않는 **순수 헬퍼 모듈**이다.
//   index.js에서 Object.assign(exports, ...)로 가져오면 안 되고, 반드시
//   구조분해로만 참조한다(partyCapacity.js·memberActivityHelpers.js와 동일).
//
// ── 지우는 것 / 남기는 것 ────────────────────────────────────────────────
//
// 지운다: 콘텐츠 본체, 하위 구성물(룸·예약 슬롯·상품·프로모션), 채팅방과
//         메시지, 찜, Cloudflare 사진·동영상, 결제가 없던 신청서.
//
// 남긴다: **거래기록** — 주문·이용권·예약·결제된 신청서. 전자상거래법상
//         거래기록 보존 의무가 걸리는 자료라 콘텐츠가 사라져도 지우지
//         않는다. 대신 contentDeleted/deletedAt과 콘텐츠 스냅샷(이름·유형·
//         금액·결제상태)을 붙여, 원본 콘텐츠 문서가 없어도 거래내역만으로
//         내용을 알아볼 수 있게 한다.
//
//         판매 이력이 있는 상품(soldCount > 0)도 남긴다 — 보존한 주문·
//         이용권이 가리키는 대상이라, 지우면 그 기록을 검증할 수 없다.
// ══════════════════════════════════════════════════════════════════════════

const admin = require('firebase-admin');
const { deleteDocMedia } = require('./cloudflareCleanup');

// ── 콘텐츠 유형 ─────────────────────────────────────────────────────────
// 클라이언트(content_delete_service.dart의 DeletableContent)와 key가 1:1로
// 맞는다. 유형을 추가할 때는 양쪽에 함께 넣어야 한다.
const TYPES = {
  party: {
    collection: 'parties',
    label: '파티',
    // detailImageUrl — 상세 본문 전용 세로형 이미지 1장. 대표 사진과 다른
    // 필드에 살지만 같은 R2 버킷에 있으므로, 여기서 빠지면 파티를 지워도
    // 그 이미지만 영영 남는다(models/party_detail_image.dart 참고).
    imageFields: [
      'images', 'imageUrls', 'mainImageUrl', 'coverImageUrl', 'detailImageUrl',
    ],
  },
  place: {
    collection: 'places',
    label: '장소',
    imageFields: ['imageUrls', 'coverImageUrl'],
  },
  event: {
    collection: 'events',
    label: '플레이스',
    imageFields: ['imageUrls', 'introImageUrls', 'coverImageUrl'],
  },
  // 🎪 이벤트 한 건(매장 이벤트 · 공간 이벤트). 플레이스/장소대여를 지울 때
  // 딸려 지워지는 경로는 예전부터 있었지만(collectLinkedRefs), 원본은 그대로
  // 두고 **이벤트만** 지우는 경로가 없었다 — 종료 14일 뒤 자동 삭제
  // (deleteExpiredPromotions)와 한도 초과 정리(registrationLimitGuard)가 이
  // 유형을 쓴다.
  //
  // imageUrl(단수)이 함께 들어간 이유: 이벤트는 옛 단일 사진 필드를 아직 쓰는
  // 문서가 있다(place_promotion.dart의 allImageUrls가 둘을 합쳐 읽는다).
  promotion: {
    collection: 'placePromotions',
    label: '이벤트',
    imageFields: ['imageUrl', 'imageUrls', 'coverImageUrl'],
  },
  partyShop: {
    collection: 'partyShops',
    label: '파티샵',
    imageFields: ['imageUrls', 'introImageUrls', 'coverImageUrl'],
  },
  crew: {
    collection: 'crews',
    label: '파트너',
    imageFields: ['imageUrls'],
  },
};

// 아직 정리되지 않은 = 삭제를 막아야 하는 신청/예약/주문 상태.
// 'pending'은 승인제 파티에서 호스트 결정을 기다리는 구간이다 — 아직 살아 있는
// 신청이므로 이 목록에 든다. accountWithdrawal.js와 **같은 값**이어야 한다
// (한쪽만 바뀌면 탈퇴는 막히는데 파티는 지워지는 식으로 어긋난다).
const LIVE_APPLICATION_STATUSES = ['applied', 'pending', 'approved'];
const LIVE_RESERVATION_STATUSES = ['pending', 'confirmed', 'paid', 'reserved'];
const LIVE_ORDER_STATUSES = ['pending', 'paid', 'confirmed', 'issued'];
// 방문예약(placeVisitReservations)은 상태 어휘가 위 예약들과 다르다 —
// placeVisitReservations.js의 LIVE_STATUSES와 **같은 값**이어야 한다(그쪽이
// 정원 계산에 세는 기준이다). 한쪽만 바뀌면 "정원은 차 있는데 장소는 지워지는"
// 식으로 어긋난다.
const LIVE_VISIT_STATUSES = ['requested', 'approved'];

// 스냅샷에 담을 금액·결제상태를 뽑을 후보 필드. 컬렉션마다 이름이 달라서
// 먼저 발견되는 값을 쓴다.
const AMOUNT_FIELDS = [
  'totalPrice', 'totalAmount', 'paidAmount', 'payAmount', 'amount',
  'appliedFee', 'price',
];
const PAYMENT_STATUS_FIELDS = ['paymentStatus', 'refundStatus', 'status'];

function pickFirst(data, fields) {
  for (const field of fields) {
    const value = data[field];
    if (value !== undefined && value !== null && value !== '') return value;
  }
  return null;
}

// ── 삭제해도 되는지 판정 ────────────────────────────────────────────────
//
// 막아야 하면 사용자에게 그대로 보여줄 문구를, 괜찮으면 null을 돌려준다.
// 자동 삭제 경로는 이 판정을 쓰지 않는다(만료된 콘텐츠는 이미 정산이 끝난
// 상태이고, 예약 작업이 사용자에게 안내할 방법도 없다).

async function blockingReasonForParty(db, docRef) {
  const snap = await docRef
    .collection('applications')
    .where('status', 'in', LIVE_APPLICATION_STATUSES)
    .get();
  const paid = snap.docs.filter((d) => Number(d.data().appliedFee || 0) > 0);
  if (paid.length > 0) {
    return `결제한 신청자 ${paid.length}명이 남아 있어 삭제할 수 없습니다. `
      + '파티 상태를 \'취소\'로 바꿔 환불을 진행한 뒤 삭제해주세요.';
  }
  if (snap.size > 0) {
    return `신청자 ${snap.size}명이 남아 있어 삭제할 수 없습니다. `
      + '파티 상태를 \'취소\'로 바꿔 신청을 정리한 뒤 삭제해주세요.';
  }

  const bookings = await db
    .collection('packageBookings')
    .where('partyId', '==', docRef.id)
    .where('status', 'in', LIVE_RESERVATION_STATUSES)
    .get();
  if (!bookings.empty) {
    return `진행 중인 패키지 예약 ${bookings.size}건이 있어 삭제할 수 없습니다. `
      + '예약을 먼저 취소·환불해주세요.';
  }
  return null;
}

async function blockingReasonForPlaceLike(db, docId) {
  const groups = await db
    .collection('placeReservationGroups')
    .where('placeId', '==', docId)
    .where('status', 'in', LIVE_RESERVATION_STATUSES)
    .get();
  if (!groups.empty) {
    return `진행 중인 예약 ${groups.size}건이 있어 삭제할 수 없습니다. `
      + '예약을 먼저 취소·환불해주세요.';
  }

  const packages = await db
    .collection('packageBookings')
    .where('placeId', '==', docId)
    .where('status', 'in', LIVE_RESERVATION_STATUSES)
    .get();
  if (!packages.empty) {
    return `진행 중인 패키지 예약 ${packages.size}건이 있어 삭제할 수 없습니다. `
      + '예약을 먼저 취소·환불해주세요.';
  }

  const orders = await db
    .collection('placeProductOrders')
    .where('placeId', '==', docId)
    .where('status', 'in', LIVE_ORDER_STATUSES)
    .get();
  if (!orders.empty) {
    return `사용되지 않은 이용권 ${orders.size}건이 남아 있어 삭제할 수 없습니다. `
      + '이용권을 먼저 취소·환불해주세요.';
  }

  // 방문예약도 다른 예약과 똑같이 살아 있으면 삭제를 막는다 — 예전에는 이
  // 검사가 빠져 있어, 방문예약만 걸린 장소가 아무 경고 없이 지워지고 예약이
  // 사라진 장소를 가리키게 됐다.
  const visits = await db
    .collection('placeVisitReservations')
    .where('placeId', '==', docId)
    .where('status', 'in', LIVE_VISIT_STATUSES)
    .get();
  if (!visits.empty) {
    return `진행 중인 방문예약 ${visits.size}건이 있어 삭제할 수 없습니다. `
      + '예약을 먼저 취소·거절해주세요.';
  }
  return null;
}

async function blockingReasonForShop(db, docId) {
  const orders = await db
    .collection('orders')
    .where('shopId', '==', docId)
    .where('status', 'in', LIVE_ORDER_STATUSES)
    .get();
  if (!orders.empty) {
    return `처리 중인 주문 ${orders.size}건이 있어 삭제할 수 없습니다. `
      + '주문을 먼저 완료하거나 취소·환불해주세요.';
  }
  return null;
}

async function blockingReason(db, type, docRef) {
  switch (type) {
    case 'party':
      return blockingReasonForParty(db, docRef);
    case 'place':
    case 'event':
      return blockingReasonForPlaceLike(db, docRef.id);
    case 'partyShop':
      return blockingReasonForShop(db, docRef.id);
    default:
      return null;
  }
}

// ── 수집 ────────────────────────────────────────────────────────────────

async function refsWhere(db, collection, field, value) {
  const snap = await db.collection(collection).where(field, '==', value).get();
  return snap.docs;
}

async function subDocs(docRef, name) {
  const snap = await docRef.collection(name).get();
  return snap.docs;
}

/// 삭제 대상(refs)과 보존 대상(preserve)을 한 번에 모은다.
///
/// 룸·상품처럼 자기 사진을 들고 있는 하위 문서는 여기서 사진까지 정리한다
/// (지우기로 결정된 것만 — 보존 대상의 사진은 남긴다).
async function collectLinkedRefs(db, type, docRef, creds) {
  const id = docRef.id;
  const refs = [];      // 완전히 삭제할 문서
  const preserve = [];  // 거래기록 — 스냅샷만 붙이고 남길 문서

  if (type === 'party') {
    // 신청서 — 결제가 있었던 건은 거래기록이라 남긴다. collectionGroup
    // 쿼리로 읽히므로 부모 파티가 사라져도 마이페이지에서 계속 보인다.
    for (const app of await subDocs(docRef, 'applications')) {
      if (Number(app.data().appliedFee || 0) > 0) preserve.push(app);
      else refs.push(app.ref);
    }
    preserve.push(...(await refsWhere(db, 'packageBookings', 'partyId', id)));
  }

  if (type === 'place' || type === 'event') {
    for (const room of await refsWhere(db, 'placeRooms', 'placeId', id)) {
      await deleteDocMedia(creds, room.data(), 'contentCleanup', ['roomImages']);
      refs.push(room.ref);
    }
    refs.push(...(await subDocs(docRef, 'reservationSlots')).map((d) => d.ref));
    // 방문예약이 잡아 둔 시간 슬롯. placeVisitReservations.js가
    // `events/{placeId}/visitSlots`에 쓰므로 플레이스(event) 삭제에서만 실제로
    // 나오지만, 장소(place)에서 돌려도 빈 결과라 분기 없이 같이 둔다
    // (reservationSlots와 정확히 같은 취급 — 예약 정원 카운터라 거래기록이 아니다).
    refs.push(...(await subDocs(docRef, 'visitSlots')).map((d) => d.ref));

    // 상품 — 판매 이력이 있으면 보존한 이용권이 가리키는 대상이라 남긴다.
    for (const product of await refsWhere(db, 'placeProducts', 'placeId', id)) {
      if (Number(product.data().soldCount || 0) > 0) {
        preserve.push(product);
      } else {
        await deleteDocMedia(creds, product.data(), 'contentCleanup',
          ['imageUrl', 'imageUrls']);
        refs.push(product.ref);
      }
    }
    for (const promo of await refsWhere(db, 'placePromotions', 'placeId', id)) {
      await deleteDocMedia(creds, promo.data(), 'contentCleanup',
        ['imageUrl', 'imageUrls']);
      refs.push(promo.ref);
    }

    // 매장 이벤트 신청 — 프로모션과 **함께** 지운다. 이벤트가 사라지면 그
    // 신청서가 가리킬 대상이 없고, 규칙상 게스트도 호스트도 지울 수 없어
    // (취소는 상태 전환이다) 여기서 정리하지 않으면 영영 고아로 남는다.
    // 결제가 걸리지 않아 거래기록이 아니므로 보존 대상이 아니다.
    refs.push(
      ...(await refsWhere(db, 'placeEventApplications', 'placeId', id))
        .map((d) => d.ref),
    );

    // 메뉴는 프로모션과 완전히 같은 성격이다 — 결제·재고·주문이 없는 순수
    // 콘텐츠라 거래기록이 아니고, 자기 사진을 들고 있어 사진까지 정리한다.
    // (place_menu_service.dart가 "프로모션과 같은 구조"라고 못박아 둔 그대로.)
    for (const menu of await refsWhere(db, 'placeMenus', 'placeId', id)) {
      await deleteDocMedia(creds, menu.data(), 'contentCleanup',
        ['imageUrl', 'imageUrls']);
      refs.push(menu.ref);
    }

    // 예약·이용권은 전부 거래기록.
    preserve.push(...(await refsWhere(db, 'placeReservationGroups', 'placeId', id)));
    preserve.push(...(await refsWhere(db, 'packageBookings', 'placeId', id)));
    preserve.push(...(await refsWhere(db, 'placeBookings', 'placeId', id)));
    preserve.push(...(await refsWhere(db, 'reservations', 'placeId', id)));
    preserve.push(...(await refsWhere(db, 'placeProductOrders', 'placeId', id)));
    // 방문예약도 예약이라 지우지 않고 스냅샷만 붙인다(위 예약들과 동일).
    preserve.push(...(await refsWhere(db, 'placeVisitReservations', 'placeId', id)));
  }

  // 🎪 이벤트 한 건만 지울 때 — 딸린 것은 그 이벤트의 신청서뿐이다.
  //
  // 이벤트에는 결제가 걸리지 않아 거래기록이 없다(신청은 '가겠다'는 표시다).
  // 규칙상 게스트도 호스트도 신청서를 지울 수 없으므로(취소는 상태 전환이다)
  // 여기서 정리하지 않으면 가리킬 이벤트가 없는 채로 영영 남는다 — 플레이스를
  // 통째로 지울 때와 **같은 취급**이다(위 place/event 분기의 같은 컬렉션).
  //
  // 부모 플레이스의 🎪 미러(themeTags·갈래·종료일)는 다시 계산하지 않는다.
  // 미러는 **지금 보이는 이벤트**만 반영하는데(place_event_taxonomy.dart의
  // mirrorFrom), 이 경로로 지워지는 이벤트는 이미 종료·숨김이라 미러에 들어
  // 있지 않다. 즉 지워도 미러 값이 달라지지 않는다.
  if (type === 'promotion') {
    refs.push(
      ...(await refsWhere(db, 'placeEventApplications', 'eventId', id))
        .map((d) => d.ref),
    );
  }

  if (type === 'partyShop') {
    for (const product of await subDocs(docRef, 'products')) {
      if (Number(product.data().soldCount || 0) > 0) {
        preserve.push(product);
      } else {
        await deleteDocMedia(creds, product.data(), 'contentCleanup',
          ['imageUrl', 'imageUrls']);
        refs.push(product.ref);
      }
    }
    preserve.push(...(await refsWhere(db, 'orders', 'shopId', id)));
  }

  // 채팅방 — 거래기록이 아니므로 메시지까지 함께 지운다.
  // (chat_service.dart가 relatedId로 콘텐츠와 묶는다.)
  for (const room of await refsWhere(db, 'chatRooms', 'relatedId', id)) {
    refs.push(...(await subDocs(room.ref, 'messages')).map((d) => d.ref));
    refs.push(room.ref);
  }

  // 찜 — 문서 id가 "{userId}_{type}_{itemId}"라 id로는 못 찾는다. 함께
  // 저장되는 itemId 필드로 건다(favorites_service.dart 참고).
  refs.push(...(await refsWhere(db, 'favorites', 'itemId', id)).map((d) => d.ref));

  return { refs, preserve };
}

// ── 실행 ────────────────────────────────────────────────────────────────

/// 400건씩 나눠 지운다(Firestore batch 상한 500).
async function deleteRefs(db, refs) {
  const CHUNK = 400;
  for (let i = 0; i < refs.length; i += CHUNK) {
    const batch = db.batch();
    refs.slice(i, i + CHUNK).forEach((ref) => batch.delete(ref));
    await batch.commit();
  }
}

/// 거래기록에 "원본 콘텐츠가 삭제됐다"는 표시와 스냅샷을 붙인다.
///
/// 금액·결제상태는 기록 자신에서 뽑아 스냅샷 안에 복사해 둔다 — 나중에
/// 필드 이름이 바뀌거나 상태가 갱신돼도, 삭제 시점의 거래내역을 그대로
/// 확인할 수 있어야 하기 때문이다.
async function preserveRecords(db, docs, contentSnapshot) {
  const CHUNK = 400;
  for (let i = 0; i < docs.length; i += CHUNK) {
    const batch = db.batch();
    for (const doc of docs.slice(i, i + CHUNK)) {
      const data = doc.data();
      batch.set(doc.ref, {
        contentDeleted: true,
        deletedAt: admin.firestore.FieldValue.serverTimestamp(),
        deletedContent: {
          ...contentSnapshot,
          amount: pickFirst(data, AMOUNT_FIELDS),
          paymentStatus: pickFirst(data, PAYMENT_STATUS_FIELDS),
        },
      }, { merge: true });
    }
    await batch.commit();
  }
}

/// 삭제된 콘텐츠를 나중에 알아보기 위한 최소 정보.
function contentSnapshotOf(type, docRef, data) {
  const meta = TYPES[type];
  return {
    type,
    collection: meta.collection,
    id: docRef.id,
    title: data.title || data.name || '',
    hostId: data.hostId || data.hostUid || '',
  };
}

/// 콘텐츠 문서 하나를 정리한다 — 연결 데이터 삭제 + 거래기록 보존 + 미디어
/// 삭제 + 본체 삭제. 사용자 삭제와 자동 삭제가 모두 이 함수를 부른다.
///
/// 삭제 가능 여부([blockingReason])는 여기서 확인하지 않는다 — 자동 삭제는
/// 그 판정을 쓰지 않기 때문에, 판정은 호출부가 필요할 때만 한다.
async function cleanupContentDoc(db, type, docRef, data, creds, logTag = 'contentCleanup') {
  const meta = TYPES[type];
  const { refs, preserve } = await collectLinkedRefs(db, type, docRef, creds);

  if (preserve.length > 0) {
    await preserveRecords(db, preserve, contentSnapshotOf(type, docRef, data));
  }
  await deleteRefs(db, refs);
  await deleteDocMedia(creds, data, logTag, meta.imageFields);
  await docRef.delete();

  console.log(
    `[${logTag}] ${meta.collection}/${docRef.id} 삭제 — `
    + `연결 문서 ${refs.length}건 삭제, 거래기록 ${preserve.length}건 보존`,
  );
  return { deleted: refs.length, preserved: preserve.length };
}

module.exports = {
  TYPES,
  blockingReason,
  collectLinkedRefs,
  cleanupContentDoc,
};
