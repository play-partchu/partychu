class PetPolicy {
  PetPolicy({
    this.status,
    Set<String>? allowedAnimals,
    this.sizeLimit,
    this.maxCount,
    this.extraFeeEnabled = false,
    this.extraFeeAmount,
    Set<String>? requiredConditions,
    this.notes,
  }) : allowedAnimals = allowedAnimals ?? {},
       requiredConditions = requiredConditions ?? {};

  final PetPolicyStatus? status;
  final Set<String> allowedAnimals;
  final String? sizeLimit;
  final int? maxCount;
  final bool extraFeeEnabled;
  final int? extraFeeAmount;
  final Set<String> requiredConditions;
  final String? notes;

  factory PetPolicy.empty() => PetPolicy();

  factory PetPolicy.fromMap(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return PetPolicy.empty();

    final rawStatus = map['status'];
    PetPolicyStatus? parsedStatus;
    if (rawStatus is String) {
      final match = PetPolicyStatus.values.firstWhere(
        (value) => value.name == rawStatus,
        orElse: () => PetPolicyStatus.notAllowed,
      );
      if (PetPolicyStatus.values.any((value) => value.name == rawStatus)) {
        parsedStatus = match;
      }
    }

    return PetPolicy(
      status: parsedStatus,
      allowedAnimals: ((map['allowedAnimals'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      sizeLimit: map['sizeLimit'] as String?,
      maxCount: (map['maxCount'] as num?)?.toInt(),
      extraFeeEnabled: map['extraFeeEnabled'] as bool? ?? false,
      extraFeeAmount: (map['extraFeeAmount'] as num?)?.toInt(),
      requiredConditions: ((map['requiredConditions'] as List?) ?? const [])
          .cast<String>()
          .toSet(),
      notes: map['notes'] as String?,
    );
  }

  Map<String, dynamic> toMap() => {
    'status': status?.name,
    'allowedAnimals': allowedAnimals.toList(),
    'sizeLimit': sizeLimit,
    'maxCount': maxCount,
    'extraFeeEnabled': extraFeeEnabled,
    'extraFeeAmount': extraFeeAmount,
    'requiredConditions': requiredConditions.toList(),
    'notes': notes,
  };

  bool get isAllowed =>
      status == PetPolicyStatus.possible ||
      status == PetPolicyStatus.conditional;

  bool get isUnspecified => status == null;

  PetPolicy copyWith({
    PetPolicyStatus? status,
    Set<String>? allowedAnimals,
    String? sizeLimit,
    int? maxCount,
    bool? extraFeeEnabled,
    int? extraFeeAmount,
    Set<String>? requiredConditions,
    String? notes,
  }) {
    return PetPolicy(
      status: status ?? this.status,
      allowedAnimals: allowedAnimals ?? this.allowedAnimals,
      sizeLimit: sizeLimit ?? this.sizeLimit,
      maxCount: maxCount ?? this.maxCount,
      extraFeeEnabled: extraFeeEnabled ?? this.extraFeeEnabled,
      extraFeeAmount: extraFeeAmount ?? this.extraFeeAmount,
      requiredConditions: requiredConditions ?? this.requiredConditions,
      notes: notes ?? this.notes,
    );
  }
}

enum PetPolicyStatus { notAllowed, possible, conditional }
