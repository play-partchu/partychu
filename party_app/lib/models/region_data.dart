/// 전국 시/도 → 구/시/군 2단계 지역 데이터 (중앙 관리).
/// 장소대여 지역 필터, 파티 등록 시 주소 자동 추출, 파티 상세검색 지역 필터가
/// 모두 이 데이터를 공유해 지역명이 어긋나지 않도록 한다.
class RegionData {
  RegionData._();

  static const Map<String, List<String>> regionDistricts = {
    '서울': ['강남구','강동구','강북구','강서구','관악구','광진구','구로구','금천구','노원구','도봉구','동대문구','동작구','마포구','서대문구','서초구','성동구','성북구','송파구','양천구','영등포구','용산구','은평구','종로구','중구','중랑구'],
    '경기': ['가평군','고양시','과천시','광명시','광주시','구리시','군포시','김포시','남양주시','동두천시','부천시','성남시','수원시','시흥시','안산시','안성시','안양시','양주시','양평군','여주시','연천군','오산시','용인시','의왕시','의정부시','이천시','파주시','평택시','포천시','하남시','화성시'],
    '인천': ['강화군','계양구','남동구','동구','미추홀구','부평구','서구','연수구','옹진군','중구'],
    '부산': ['강서구','금정구','기장군','남구','동구','동래구','부산진구','북구','사상구','사하구','서구','수영구','연제구','영도구','중구','해운대구'],
    '대구': ['군위군','달서구','달성군','동구','북구','서구','수성구','중구'],
    '광주': ['광산구','남구','동구','북구','서구'],
    '대전': ['대덕구','동구','서구','유성구','중구'],
    '울산': ['남구','동구','북구','울주군','중구'],
    '세종': ['세종시'],
    '강원': ['강릉시','고성군','동해시','삼척시','속초시','양구군','양양군','영월군','원주시','인제군','정선군','철원군','춘천시','태백시','평창군','홍천군','화천군','횡성군'],
    '충북': ['괴산군','단양군','보은군','영동군','옥천군','음성군','제천시','증평군','진천군','청주시','충주시'],
    '충남': ['계룡시','공주시','금산군','논산시','당진시','보령시','부여군','서산시','서천군','아산시','예산군','천안시','청양군','태안군','홍성군'],
    '전북': ['고창군','군산시','김제시','남원시','무주군','부안군','순창군','완주군','익산시','임실군','장수군','전주시','정읍시','진안군'],
    '전남': ['강진군','고흥군','곡성군','광양시','구례군','나주시','담양군','목포시','무안군','보성군','순천시','신안군','여수시','영광군','영암군','완도군','장성군','장흥군','진도군','함평군','해남군','화순군'],
    '경북': ['경산시','경주시','고령군','구미시','김천시','문경시','봉화군','상주시','성주군','안동시','영덕군','영양군','영주시','영천시','예천군','울릉군','울진군','의성군','청도군','청송군','칠곡군','포항시'],
    '경남': ['거제시','거창군','고성군','김해시','남해군','밀양시','사천시','산청군','양산시','의령군','진주시','창녕군','창원시','통영시','하동군','함안군','함양군','합천군'],
    '제주': ['서귀포시','제주시'],
  };

  static List<String> get regions => regionDistricts.keys.toList();

  /// 주소 문자열 앞부분에서 시/도 코드를 추출 (예: "서울특별시 강남구 ..." → "서울").
  static String extractRegion(String address) {
    if (address.startsWith('서울')) return '서울';
    if (address.startsWith('경기')) return '경기';
    if (address.startsWith('인천')) return '인천';
    if (address.startsWith('강원')) return '강원';
    if (address.startsWith('충청북도') || address.startsWith('충북')) return '충북';
    if (address.startsWith('충청남도') || address.startsWith('충남')) return '충남';
    if (address.startsWith('대전')) return '대전';
    if (address.startsWith('세종')) return '세종';
    if (address.startsWith('전라북도') || address.startsWith('전북')) return '전북';
    if (address.startsWith('전라남도') || address.startsWith('전남')) return '전남';
    if (address.startsWith('광주')) return '광주';
    if (address.startsWith('경상북도') || address.startsWith('경북')) return '경북';
    if (address.startsWith('경상남도') || address.startsWith('경남')) return '경남';
    if (address.startsWith('대구')) return '대구';
    if (address.startsWith('울산')) return '울산';
    if (address.startsWith('부산')) return '부산';
    if (address.startsWith('제주')) return '제주';
    return '서울'; // fallback
  }

  /// 주소 문자열에서 구/시/군을 추출. [region]을 알고 있으면 해당 지역의
  /// 구/시/군 목록 안에서만 탐색해 정확도를 높인다 (예: "중구"는 여러 지역에 존재).
  static String? extractDistrict(String address, {String? region}) {
    final candidates = region != null
        ? (regionDistricts[region] ?? const [])
        : regionDistricts.values.expand((d) => d);
    for (final district in candidates) {
      if (address.contains(district)) return district;
    }
    return null;
  }

  /// 해당 구/시/군이 속한 시/도 목록 (동명 구가 여러 지역에 존재할 수 있어 List로 반환).
  /// 주로 district 필드가 없는 기존 데이터에 대한 region 기준 하위호환 매칭에 사용.
  static List<String> regionsOfDistrict(String district) {
    final result = <String>[];
    regionDistricts.forEach((region, districts) {
      if (districts.contains(district)) result.add(region);
    });
    return result;
  }

  /// 주소 문자열 앞부분의 시/도 정식 명칭을 흔히 쓰는 축약형으로 바꾼다
  /// ("서울특별시 강남구" → "서울 강남구"). 매칭되는 접두어가 없으면
  /// 원본 그대로 돌려준다.
  static const Map<String, String> regionLongToShort = {
    '서울특별시': '서울',
    '부산광역시': '부산',
    '대구광역시': '대구',
    '인천광역시': '인천',
    '광주광역시': '광주',
    '대전광역시': '대전',
    '울산광역시': '울산',
    '세종특별자치시': '세종',
    '경기도': '경기',
    '강원특별자치도': '강원',
    '강원도': '강원',
    '충청북도': '충북',
    '충청남도': '충남',
    '전북특별자치도': '전북',
    '전라북도': '전북',
    '전라남도': '전남',
    '경상북도': '경북',
    '경상남도': '경남',
    '제주특별자치도': '제주',
  };

  static String shortenRegionPrefix(String address) {
    for (final entry in regionLongToShort.entries) {
      if (address.startsWith(entry.key)) {
        return entry.value + address.substring(entry.key.length);
      }
    }
    return address;
  }

  /// 주소(도로명·지번 어느 쪽이든) 안에서 동/읍/면/리/가 토큰 하나만 뽑아낸다.
  /// 도로명주소는 대부분 동 정보를 포함하지 않으므로, 지번주소처럼 동이
  /// 실제로 들어있는 문자열을 넘겨야 값을 얻을 수 있다. 못 찾으면 null.
  static String? _extractDongToken(String address) {
    final tokens = address
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty);
    for (final t in tokens) {
      if (t.endsWith('동') ||
          t.endsWith('읍') ||
          t.endsWith('면') ||
          t.endsWith('리') ||
          t.endsWith('가')) {
        return t;
      }
    }
    return null;
  }

  /// 주소 안에서 도로명(~로/~길) 토큰 하나만 뽑아낸다. 건물번호(숫자, "12-3"
  /// 등)는 절대 포함하지 않는다 — 동을 못 찾았을 때만 쓰는 최후의 대체용.
  static String? _extractRoadNameToken(String address) {
    final tokens = address
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty);
    for (final t in tokens) {
      if (t.endsWith('로') || t.endsWith('길')) return t;
    }
    return null;
  }

  /// 메인 파티 목록의 모든 카드(작은/기본/큰 카드, 지도 안 "이 근처 파티")가
  /// 공통으로 쓰는 장소 포맷터. 시/도·도로명 번지·상세주소는 절대 표시하지
  /// 않고, 항상 "구+동" 한 줄만 반환한다(상세페이지는 이 함수를 쓰지 않음).
  ///
  /// 우선순위:
  /// 1) Firestore에 저장된 district 필드(등록 시 이미 계산해둔 값).
  /// 2) (좌표 기반 역지오코딩 — 현재 API 키/백엔드가 없어 아직 미구현.
  ///    나중에 준비되면 이 자리에 캐시된 조회 한 단계만 끼워 넣으면 된다.
  ///    이 함수는 동기 함수이고 순수 문자열 파싱뿐이라 별도 캐싱은
  ///    필요 없다 — 실제 네트워크 호출이 생기는 시점에 캐싱을 추가할 것.)
  /// 3) 지번주소(그다음 도로명주소/기타 주소)에서 구·동 토큰을 직접 추출.
  /// 4) 동을 끝내 못 찾으면(도로명주소뿐이라 동 정보가 없는 경우) 임의로
  ///    잘못된 동을 지어내지 않고, "구 + 도로명"(번지 제외)으로 대체하고,
  ///    그마저 없으면 구까지만 표시한다.
  static String formatCardLocation(Map<String, dynamic> data) {
    final jibun = (data['jibunAddress'] as String?)?.trim() ?? '';
    final road = (data['roadAddress'] as String?)?.trim() ?? '';
    final rawAddress = (data['address'] as String?)?.trim() ?? '';
    final location = (data['location'] as String?)?.trim() ?? '';
    final bestAddress = jibun.isNotEmpty
        ? jibun
        : road.isNotEmpty
        ? road
        : rawAddress.isNotEmpty
        ? rawAddress
        : location;
    if (bestAddress.isEmpty) return '';

    final storedDistrict = (data['district'] as String?)?.trim() ?? '';
    final region = storedDistrict.isNotEmpty
        ? null
        : extractRegion(shortenRegionPrefix(bestAddress));
    final district = storedDistrict.isNotEmpty
        ? storedDistrict
        : extractDistrict(bestAddress, region: region);

    final dong =
        _extractDongToken(jibun) ??
        _extractDongToken(road) ??
        _extractDongToken(rawAddress) ??
        _extractDongToken(location);
    if (dong != null) {
      return (district != null && district.isNotEmpty) ? '$district $dong' : dong;
    }

    final roadName = _extractRoadNameToken(road.isNotEmpty ? road : bestAddress);
    if (roadName != null) {
      return (district != null && district.isNotEmpty)
          ? '$district $roadName'
          : roadName;
    }

    return district ?? '';
  }

  /// 모임 카드/상세 화면에서 "동 이름"(굵게, 큰 글씨)과 "시 구"(연하게,
  /// 작은 글씨) 두 줄로 장소를 표시하기 위한 값을 만든다.
  ///
  /// - 시/구는 등록 시 이미 저장해둔 region/district 필드를 우선 쓰고,
  ///   없으면 저장된 주소 문자열에서 다시 추출한다.
  /// - 동은 도로명주소에는 보통 없으므로 지번주소(jibunAddress)를 우선
  ///   사용하고, 그래도 못 찾으면 도로명주소/기타 주소 문자열 순으로
  ///   시도한다. 어디서도 동을 못 찾으면(정말 오래된 데이터 등) 구/시로
  ///   대체한다 — 절대 도로명·번지 전체를 반환하지 않는다.
  static ({String dong, String cityDistrict}) partyLocationLines(
    Map<String, dynamic> data,
  ) {
    final jibun = (data['jibunAddress'] as String?)?.trim() ?? '';
    final road = (data['roadAddress'] as String?)?.trim() ?? '';
    final rawAddress = (data['address'] as String?)?.trim() ?? '';
    final location = (data['location'] as String?)?.trim() ?? '';
    final bestAddress = jibun.isNotEmpty
        ? jibun
        : road.isNotEmpty
        ? road
        : rawAddress.isNotEmpty
        ? rawAddress
        : location;

    final storedRegion = (data['region'] as String?)?.trim() ?? '';
    final storedDistrict = (data['district'] as String?)?.trim() ?? '';

    final region = storedRegion.isNotEmpty
        ? storedRegion
        : (bestAddress.isEmpty ? '' : extractRegion(shortenRegionPrefix(bestAddress)));
    final district = storedDistrict.isNotEmpty
        ? storedDistrict
        : (bestAddress.isEmpty ? null : extractDistrict(bestAddress, region: region));

    final dong =
        _extractDongToken(jibun) ??
        _extractDongToken(road) ??
        _extractDongToken(rawAddress) ??
        _extractDongToken(location);

    final cityDistrict = [
      region,
      district ?? '',
    ].where((s) => s.isNotEmpty).join(' ');

    return (
      dong: dong ?? (district ?? (region.isEmpty ? '장소 미정' : region)),
      cityDistrict: cityDistrict,
    );
  }

  /// 주소에서 "구(또는 군) + 동(읍/면/리)"만 뽑아낸다.
  /// 예) "경기도 성남시 중원구 성남동" → "중원구 성남동"
  ///     "서울특별시 강남구 역삼동"   → "강남구 역삼동"
  /// 글자 수로 잘라내는 방식이 아니라, 주소를 공백 기준으로 나눠 행정구역
  /// 단위(구/군 → 동/읍/면/리) 토큰을 그대로 찾아 조합한다 — 임의 절삭이 아님.
  /// 매칭되는 단위를 못 찾으면(도로명 주소 등 동 단위가 없는 경우) 찾은 만큼만
  /// 반환하고, 아예 못 찾으면 원본 주소를 그대로 반환한다(이 함수는 절대
  /// "..."을 붙이거나 글자 수로 자르지 않는다).
  static String shortDistrictDong(String address) {
    final tokens = address
        .trim()
        .split(RegExp(r'\s+'))
        .where((t) => t.isNotEmpty)
        .toList();
    if (tokens.isEmpty) return address;

    var guIdx = tokens.indexWhere((t) => t.endsWith('구'));
    if (guIdx == -1) guIdx = tokens.indexWhere((t) => t.endsWith('군'));
    if (guIdx == -1) return address;

    for (var i = guIdx + 1; i < tokens.length; i++) {
      final t = tokens[i];
      if (t.endsWith('동') || t.endsWith('읍') || t.endsWith('면') || t.endsWith('리') || t.endsWith('가')) {
        return '${tokens[guIdx]} $t';
      }
    }
    return tokens[guIdx];
  }
}
