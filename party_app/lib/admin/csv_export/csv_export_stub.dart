/// 비-웹 플랫폼용 스텁 (관리자 화면은 웹 전용이라 실제로 호출되지 않음).
void downloadCsv(String filename, String csvContent) {
  throw UnsupportedError('CSV 다운로드는 웹에서만 지원됩니다.');
}
