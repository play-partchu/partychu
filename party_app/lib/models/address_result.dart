class AddressResult {
  final String placeName;
  final String address;
  final String roadAddress;
  final String jibunAddress;
  final double latitude;
  final double longitude;

  const AddressResult({
    required this.placeName,
    required this.address,
    required this.roadAddress,
    required this.jibunAddress,
    required this.latitude,
    required this.longitude,
  });

  String get displayName =>
      placeName.isNotEmpty ? placeName : roadAddress.isNotEmpty ? roadAddress : address;

  String get displayAddress =>
      roadAddress.isNotEmpty ? roadAddress : address;
}
