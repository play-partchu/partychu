const admin = require('firebase-admin');

// ── FCM 발송 공용 창구 ───────────────────────────────────────────────────────
//
// 토큰을 읽어 보내고, **죽은 토큰을 그 자리에서 지우는** 일까지 여기서만 한다.
// 발송하는 곳마다 토큰 조회를 따로 짜면 정리 로직이 한쪽에만 붙어서, 정리하지
// 않는 경로로 보낼 때마다 지워졌어야 할 토큰이 되살아난 것처럼 남는다.
//
// ── 죽은 토큰을 반드시 지워야 하는 이유 ──────────────────────────────────────
// 앱을 지운 기기의 토큰은 영원히 실패한다. 그냥 두면 한 사람의 devices에
// 재설치할 때마다 문서가 쌓여서, 알림 한 건에 실패 요청만 수십 개를 보내게
// 된다. FCM은 이 실패를 'registration-token-not-registered'로 분명히
// 알려주므로, 그 응답을 받은 문서만 골라 지운다.
//
// 반대로 일시적 오류(unavailable, internal)는 **절대 지우지 않는다** — 지우면
// 멀쩡한 기기가 다음 알림부터 조용히 대상에서 빠진다.

const admin_messaging = () => admin.messaging();

/** 매니페스트(AndroidManifest.xml)와 앱(PushNotificationService)이 같이 쓰는 채널. */
const ANDROID_CHANNEL_ID = 'partychu_default';

/** sendEachForMulticast 한 번에 넣을 수 있는 토큰 수. */
const MULTICAST_LIMIT = 500;

/** 이 코드로 실패한 토큰은 되살아날 수 없다 — 문서를 지운다. */
const DEAD_TOKEN_CODES = new Set([
  'messaging/registration-token-not-registered',
  'messaging/invalid-registration-token',
  'messaging/invalid-argument',
]);

/** FCM data는 값이 전부 문자열이어야 한다. null/undefined는 키째 뺀다. */
function stringifyData(data) {
  const out = {};
  for (const [k, v] of Object.entries(data || {})) {
    if (v === null || v === undefined || v === '') continue;
    out[k] = typeof v === 'string' ? v : String(v);
  }
  return out;
}

/** 알림 본문이 너무 길면 기기에서 잘린다 — 보내기 전에 우리가 자른다. */
function clip(text, max) {
  const s = (text || '').toString().replace(/\s+/g, ' ').trim();
  return s.length <= max ? s : `${s.slice(0, max - 1)}…`;
}

/** uid들의 devices 문서를 모아 [{ token, ref }]로 돌려준다. */
async function collectDevices(db, uids) {
  const unique = [...new Set((uids || []).filter(Boolean))];
  if (unique.length === 0) return [];

  const snaps = await Promise.all(
    unique.map((uid) =>
      db.collection('users').doc(uid).collection('devices').get(),
    ),
  );

  // 같은 토큰이 여러 uid 밑에 남아 있을 수 있다(계정 전환 직후 등). 토큰 기준
  // 으로 접어서 **한 기기에 같은 알림이 두 번 뜨는 것**을 막는다.
  const byToken = new Map();
  for (const snap of snaps) {
    for (const doc of snap.docs) {
      const token = doc.get('token') || doc.id;
      if (typeof token !== 'string' || token.length < 20) continue;
      if (!byToken.has(token)) byToken.set(token, { token, ref: doc.ref });
    }
  }
  return [...byToken.values()];
}

/**
 * 여러 사용자에게 같은 알림을 보낸다.
 *
 * @param {string|string[]} uids 받는 사람(들).
 * @param {{title: string, body: string, data?: object}} message
 * @returns {Promise<{sent: number, failed: number, pruned: number}>}
 *   발송을 못 해도 **예외를 던지지 않는다** — 푸시 실패가 알림 문서 생성이나
 *   예약 처리 같은 본래 작업을 되돌리면 안 되기 때문이다.
 */
async function sendPushToUsers(uids, { title, body, data } = {}) {
  const list = Array.isArray(uids) ? uids : [uids];
  const result = { sent: 0, failed: 0, pruned: 0 };
  if (!title && !body) return result;

  const db = admin.firestore();
  let devices;
  try {
    devices = await collectDevices(db, list);
  } catch (e) {
    console.error('[push] 기기 조회 실패:', e.message);
    return result;
  }
  if (devices.length === 0) return result;

  const payloadData = stringifyData(data);
  const dead = [];

  for (let i = 0; i < devices.length; i += MULTICAST_LIMIT) {
    const chunk = devices.slice(i, i + MULTICAST_LIMIT);
    try {
      const res = await admin_messaging().sendEachForMulticast({
        tokens: chunk.map((d) => d.token),
        notification: {
          title: clip(title, 60),
          body: clip(body, 160),
        },
        data: payloadData,
        android: {
          // 알림이 곧 소식의 전부인 앱이라 지연 배달은 의미가 없다.
          priority: 'high',
          notification: {
            channelId: ANDROID_CHANNEL_ID,
            sound: 'default',
          },
        },
        apns: {
          // content-available(무음 백그라운드 푸시)는 일부러 넣지 않는다.
          // 그걸 켜려면 앱에 remote-notification 백그라운드 모드가 있어야 하고,
          // 없는 채로 보내면 APNs가 우선순위를 낮춰 **알림 자체가 늦거나 묶여서
          // 도착한다.** 우리는 백그라운드에서 할 일이 없고 알림만 보여주면 된다.
          payload: { aps: { sound: 'default' } },
        },
      });

      res.responses.forEach((r, idx) => {
        if (r.success) {
          result.sent += 1;
          return;
        }
        result.failed += 1;
        const code = r.error && r.error.code;
        if (DEAD_TOKEN_CODES.has(code)) dead.push(chunk[idx].ref);
        else console.warn('[push] 발송 실패:', code);
      });
    } catch (e) {
      // 청크 하나가 통째로 실패해도 남은 청크는 계속 보낸다.
      result.failed += chunk.length;
      console.error('[push] 멀티캐스트 실패:', e.message);
    }
  }

  if (dead.length > 0) {
    try {
      // 배치 한도(500)를 넘지 않게 나눠서 지운다.
      for (let i = 0; i < dead.length; i += MULTICAST_LIMIT) {
        const batch = db.batch();
        for (const ref of dead.slice(i, i + MULTICAST_LIMIT)) batch.delete(ref);
        await batch.commit();
      }
      result.pruned = dead.length;
    } catch (e) {
      // 못 지워도 다음 발송 때 다시 시도된다.
      console.error('[push] 죽은 토큰 정리 실패:', e.message);
    }
  }

  return result;
}

module.exports = {
  sendPushToUsers,
  ANDROID_CHANNEL_ID,
  __helpers: { stringifyData, clip, collectDevices, DEAD_TOKEN_CODES },
};
