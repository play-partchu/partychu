// demoContentRewrite.js 로 바꾼 콘텐츠를 **원래대로 되돌리는** 1회성 스크립트.
//
// 배포되는 Cloud Function이 아니고 앱 진입점도 없다. 로컬 실행 전용이다.
// Firestore 접근 계층(REST + gcloud 토큰)은 demoContentRewrite.js 의 것을
// 그대로 재사용한다 — 코덱이 어긋나면 복원이 조용히 망가지기 때문이다.
//
// ── 무엇을 하나 ───────────────────────────────────────────────────────────
// .demo-out/ 에 남은 기록을 읽어 PATCH로 옛 값을 다시 써 넣는다.
//
//   applied-<ts>.json  … 실제로 바꾼 필드와 그 직전 값(before)만 담겨 있다.
//                        **가장 정확한 복원 원본**이라 기본으로 이걸 쓴다.
//   backup-<ts>.json   … 대상 문서 원문 전체. applied 기록이 없을 때(적용
//                        도중 죽어 기록이 안 남았을 때) --from-backup 으로
//                        쓴다. 이때는 --fields 로 되돌릴 필드를 명시해야 한다.
//
// ── 무엇을 하지 않나 ──────────────────────────────────────────────────────
//   · 문서를 만들거나 지우지 않는다. PATCH만 쓰고, 없는 문서에는
//     `currentDocument.exists=true` 때문에 서버가 거부한다.
//   · hostId가 --uid 와 다른 문서를 만나면 **그 자리에서 전체 중단**한다.
//     남의 문서에 옛 값을 쓰는 것은 되돌리기가 아니라 새로운 사고다.
//   · R2에 올린 데모 이미지를 지우지 않는다(옛 이미지를 아직 지우지 않았다면
//     URL만 되돌아가도 화면은 원래대로 돌아온다).
//   · firestore.rules · 인증 · 앱 로직을 건드리지 않는다.
//
// ── 실행 ─────────────────────────────────────────────────────────────────
//   드라이런(기본):
//     node scripts/demoContentRestore.js --uid <UID>
//   실제 복원:
//     node scripts/demoContentRestore.js --uid <UID> --apply
//   특정 기록에서:
//     node scripts/demoContentRestore.js --uid <UID> --applied .demo-out/applied-....json --apply
//   백업 원문에서(applied 기록이 없을 때):
//     node scripts/demoContentRestore.js --uid <UID> --apply --from-backup \
//       --backup .demo-out/backup-....json \
//       --fields title,description,placeName,address,roadAddress,jibunAddress,detailAddress,location,latitude,longitude,region,district
//
//   DEBUG=1 을 붙이면 문서마다 되돌리는 필드 목록까지 찍는다.

'use strict';

const fs = require('fs');
const path = require('path');

const R = require('./demoContentRewrite');

const OUT_DIR = R.OUT_DIR;
const ABSENT = R.ABSENT;

// ── 인자 ───────────────────────────────────────────────────────────────────

function parseArgs(argv) {
  const out = { flags: new Set(), opts: {} };
  for (let i = 0; i < argv.length; i += 1) {
    const a = argv[i];
    if (!a.startsWith('--')) continue;
    const eq = a.indexOf('=');
    if (eq > 0) out.opts[a.slice(2, eq)] = a.slice(eq + 1);
    else if (argv[i + 1] && !argv[i + 1].startsWith('--')) { out.opts[a.slice(2)] = argv[i + 1]; i += 1; }
    else out.flags.add(a.slice(2));
  }
  return out;
}

const args = parseArgs(process.argv.slice(2));
const FLAG = (n) => args.flags.has(n);
const OPT = (n) => (args.opts[n] || '').trim();
const APPLY = FLAG('apply');

// ── 기록 파일 찾기 ─────────────────────────────────────────────────────────

function newestIn(prefix) {
  if (!fs.existsSync(OUT_DIR)) return null;
  const files = fs
    .readdirSync(OUT_DIR)
    .filter((n) => n.startsWith(prefix) && n.endsWith('.json'))
    .sort();
  return files.length === 0 ? null : path.join(OUT_DIR, files[files.length - 1]);
}

function fromApplied(file) {
  const j = JSON.parse(fs.readFileSync(file, 'utf8'));
  return {
    uid: j.uid,
    source: file,
    items: (j.applied || []).map((a) => ({
      collection: a.collection,
      docId: a.docId,
      slug: a.slug,
      before: a.before,
    })),
  };
}

function fromBackup(file, fields) {
  const j = JSON.parse(fs.readFileSync(file, 'utf8'));
  return {
    uid: j.uid,
    source: file,
    items: (j.docs || []).map((d) => {
      const before = {};
      for (const f of fields) {
        before[f] = Object.prototype.hasOwnProperty.call(d.data, f) ? d.data[f] : ABSENT;
      }
      return { collection: d.collection, docId: d.docId, slug: d.slug, before };
    }),
  };
}

/// 이름 필드는 컬렉션마다 다르다 — 표에 뭘 보여줄지 고른다.
function nameOf(data) {
  if (!data) return '';
  for (const k of ['title', 'name', 'roomName']) {
    if (typeof data[k] === 'string' && data[k]) return data[k];
  }
  return '';
}

// ── main ───────────────────────────────────────────────────────────────────

async function main() {
  const uid = OPT('uid');
  if (!uid) {
    console.error('');
    console.error('[중단] --uid 가 없다. 복원도 uid를 명시했을 때만 한다.');
    console.error('');
    process.exit(1);
  }

  let plan;
  if (FLAG('from-backup')) {
    const file = OPT('backup') || newestIn('backup-');
    if (!file || !fs.existsSync(file)) {
      console.error('[중단] 백업 파일을 찾지 못했다 (--backup <경로>).');
      process.exit(1);
    }
    const fieldsRaw = OPT('fields');
    if (!fieldsRaw) {
      console.error('[중단] --from-backup 에는 --fields 가 필요하다.');
      console.error('        원문 전체를 되돌리면 그 사이 정상적으로 바뀐 값까지 되감긴다.');
      process.exit(1);
    }
    plan = fromBackup(file, fieldsRaw.split(',').map((s) => s.trim()).filter(Boolean));
  } else {
    const file = OPT('applied') || newestIn('applied-');
    if (!file || !fs.existsSync(file)) {
      console.error('[중단] applied 기록을 찾지 못했다.');
      console.error('        아직 --apply 를 하지 않았거나, 기록이 남기 전에 죽었을 수 있다.');
      console.error('        후자라면 --from-backup --fields ... 로 되돌릴 것.');
      process.exit(1);
    }
    plan = fromApplied(file);
  }

  if (plan.uid && plan.uid !== uid) {
    console.error(`[중단] 기록(${plan.source})의 uid가 --uid 와 다르다: ${plan.uid}`);
    process.exit(1);
  }

  console.log('');
  console.log(APPLY ? '════════ 복원 ════════' : '════════ 복원 DRY RUN — 아무것도 쓰지 않는다 ════════');
  console.log(`uid  : ${uid}`);
  console.log(`원본 : ${plan.source}`);
  console.log(`대상 : ${plan.items.length}건`);
  console.log('');

  let done = 0;
  let skipped = 0;

  for (const it of plan.items) {
    const current = await R.restGet(it.collection, it.docId);
    if (!current) {
      console.log(`  SKIP    ${it.collection}/${it.docId} — 문서 없음`);
      skipped += 1;
      continue;
    }

    if (current.hostId !== uid) {
      console.error('');
      console.error(`[전체 중단] ${it.collection}/${it.docId} 의 hostId(${current.hostId})가 --uid 와 다르다.`);
      console.error(`            여기까지 ${done}건 처리됨. 기록을 확인할 것.`);
      process.exit(1);
    }

    const patch = {};
    const changed = [];
    for (const [k, v] of Object.entries(it.before || {})) {
      if (k === 'updatedAt') continue; // 되감지 않는다 — 지금 시각으로 다시 찍는다.
      if (v === ABSENT) {
        patch[k] = R.DELETE;
        changed.push(`${k}=(삭제)`);
      } else {
        patch[k] = v;
        changed.push(k);
      }
    }
    if (Object.keys(patch).length === 0) { skipped += 1; continue; }
    patch.updatedAt = R.nowTs();

    const back = nameOf(it.before);
    console.log(
      `  ${APPLY ? 'RESTORE' : 'WOULD  '} ${R.w(it.collection, 18)}${R.w(it.docId, 23)}` +
        `${R.clip(nameOf(current) || '(없음)', 22)} → ${back || '(이름 필드 없음)'}`,
    );
    if (process.env.DEBUG) console.log(`            필드: ${changed.join(', ')}`);

    if (APPLY) await R.restPatch(it.collection, it.docId, patch);
    done += 1;
  }

  console.log('');
  console.log(`${APPLY ? '복원' : '복원 예정'} ${done}건 / 건너뜀 ${skipped}건`);
  if (!APPLY) {
    console.log('');
    console.log('실제로 되돌리려면 --apply 를 붙일 것.');
  }
  console.log('');
}

main()
  .then(() => process.exit(0))
  .catch((e) => {
    console.error('');
    console.error('실패:', e.message);
    if (process.env.DEBUG) console.error(e.stack);
    process.exit(1);
  });
