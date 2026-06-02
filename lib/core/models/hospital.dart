class Hospital {
  final String id;
  final String name;
  final String sigla;
  final String city;
  final String state;
  final String status;
  final DateTime createdAt;

  const Hospital({
    required this.id,
    required this.name,
    required this.sigla,
    required this.city,
    required this.state,
    required this.status,
    required this.createdAt,
  });

  factory Hospital.fromJson(Map<String, dynamic> json) => Hospital(
        id: json['id'] as String,
        name: json['name'] as String,
        sigla: json['sigla'] as String,
        city: json['city'] as String,
        state: json['state'] as String,
        status: json['status'] as String,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sigla': sigla,
        'city': city,
        'state': state,
        'status': status,
        'created_at': createdAt.toIso8601String(),
      };

  bool get isActive => status == 'active';

  Hospital copyWith({
    String? name,
    String? sigla,
    String? city,
    String? state,
    String? status,
  }) =>
      Hospital(
        id: id,
        name: name ?? this.name,
        sigla: sigla ?? this.sigla,
        city: city ?? this.city,
        state: state ?? this.state,
        status: status ?? this.status,
        createdAt: createdAt,
      );
}
