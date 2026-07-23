const sharp = require('C:/Users/야옹/AppData/Local/Temp/node_modules/sharp');

const input  = 'C:/partymap/party_app/assets/icon/app_icon.png';
const output = 'C:/partymap/party_app/assets/icon/app_icon_large.png';

const TARGET   = 1024;   // 최종 출력 크기 (정사각형)
const ZOOM     = 1.75;   // 토끼 확대 배율 (1.75배 → 80~90% 채움)

async function run() {
  const { width, height } = await sharp(input).metadata();
  console.log(`원본 크기: ${width}x${height}`);

  // 1) 중앙에서 정사각형 크롭
  const sq   = Math.min(width, height);
  const left = Math.floor((width  - sq) / 2);
  const top  = Math.floor((height - sq) / 2);

  // 2) 확대 후 중앙 재크롭 (줌 효과)
  const scaled   = Math.round(TARGET * ZOOM);
  const cropLeft = Math.floor((scaled - TARGET) / 2);
  const cropTop  = Math.floor((scaled - TARGET) / 2);

  await sharp(input)
    .extract({ left, top, width: sq, height: sq })
    .resize(scaled, scaled, { kernel: sharp.kernel.lanczos3 })
    .extract({ left: cropLeft, top: cropTop, width: TARGET, height: TARGET })
    .png({ compressionLevel: 9 })
    .toFile(output);

  console.log(`완료: ${output} (${TARGET}x${TARGET})`);
}

run().catch(err => { console.error(err); process.exit(1); });
