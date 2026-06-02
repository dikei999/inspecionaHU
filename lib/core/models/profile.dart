class Profile {
  final String id;
  final String? hospitalId;
  final String fullName;
  final String email;
  final String cpf;
  final String? role; // null | super_admin | director | supervisor | inspector
  final String? photoUrl;
  final String status;
  final DateTime? lastAccess;
  final DateTime createdAt;

  const Profile({
    required this.id,
    this.hospitalId,
    required this.fullName,
    required this.email,
    required this.cpf,
    this.role,
    this.photoUrl,
    required this.status,
    this.lastAccess,
    required this.createdAt,
  });

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
        id: json['id'] as String,
        hospitalId: json['hospital_id'] as String?,
        fullName: json['full_name'] as String,
        email: json['email'] as String,
        cpf: json['cpf'] as String,
        role: json['role'] as String?,
        photoUrl: json['photo_url'] as String?,
        status: json['status'] as String,
        lastAccess: json['last_access'] != null
            ? DateTime.parse(json['last_access'] as String)
            : null,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'hospital_id': hospitalId,
        'full_name': fullName,
        'email': email,
        'cpf': cpf,
        'role': role,
        'photo_url': photoUrl,
        'status': status,
        'last_access': lastAccess?.toIso8601String(),
        'created_at': createdAt.toIso8601String(),
      };

  bool get isActive => status == 'active';
  // super_admin has no hospital_id by design — only role matters for them
  bool get isLinked =>
      role == 'super_admin' || (role != null && hospitalId != null);
  bool get isSuperAdmin => role == 'super_admin';
  bool get isDirector => role == 'director';
  bool get isSupervisor => role == 'supervisor';
  bool get isInspector => role == 'inspector';

  Profile copyWith({
    String? hospitalId,
    String? fullName,
    String? email,
    String? cpf,
    String? role,
    String? photoUrl,
    String? status,
    DateTime? lastAccess,
  }) =>
      Profile(
        id: id,
        hospitalId: hospitalId ?? this.hospitalId,
        fullName: fullName ?? this.fullName,
        email: email ?? this.email,
        cpf: cpf ?? this.cpf,
        role: role ?? this.role,
        photoUrl: photoUrl ?? this.photoUrl,
        status: status ?? this.status,
        lastAccess: lastAccess ?? this.lastAccess,
        createdAt: createdAt,
      );
}
