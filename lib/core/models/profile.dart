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
  final String profileCode; // código público para convites (6 chars)

  /// Telefone e cargo — opcionais, informados pelo próprio usuário.
  /// `jobTitle` é texto livre e NÃO se confunde com [role], que define a
  /// permissão no sistema.
  final String? phone;
  final String? jobTitle;

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
    this.profileCode = '',
    this.phone,
    this.jobTitle,
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
        profileCode: (json['profile_code'] as String?) ?? '',
        phone: json['phone'] as String?,
        jobTitle: json['job_title'] as String?,
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
        'profile_code': profileCode,
        'phone': phone,
        'job_title': jobTitle,
      };

  /// Código formatado com prefixo # para exibição.
  String get displayCode => profileCode.isEmpty ? '' : '#$profileCode';

  // ── Nome e sobrenome ────────────────────────────────────────────────────
  // Derivados de full_name, que continua sendo a fonte única no banco.
  // Separar em duas colunas exigiria migrar todos os registros e manteria
  // dois lugares para a mesma informação; aqui a divisão é só de interface
  // e a recomposição é sempre "nome + sobrenome".

  /// Primeiro nome. É o que a saudação usa.
  String get firstName {
    final t = fullName.trim();
    if (t.isEmpty) return '';
    final i = t.indexOf(' ');
    return i == -1 ? t : t.substring(0, i);
  }

  /// Tudo depois do primeiro nome. Vazio quando só há um nome.
  String get lastName {
    final t = fullName.trim();
    final i = t.indexOf(' ');
    return i == -1 ? '' : t.substring(i + 1).trim();
  }

  /// Junta nome e sobrenome de volta em full_name, sem espaço sobrando.
  static String joinName(String first, String last) =>
      [first.trim(), last.trim()].where((p) => p.isNotEmpty).join(' ');

  /// Saudação do cabeçalho: cargo + primeiro nome, ex.: "Diretor João".
  ///
  /// Usa o CARGO DO SISTEMA (role), não job_title: é o papel que define o
  /// que a pessoa vê no app. Sem role definido, devolve só o nome.
  String get saudacao {
    final nome = firstName;
    final cargo = switch (role) {
      'super_admin' => 'Admin',
      'director' => 'Diretor',
      'supervisor' => 'Supervisor',
      'inspector' => 'Inspetor',
      _ => null,
    };
    if (nome.isEmpty) return cargo ?? '';
    return cargo == null ? nome : '$cargo $nome';
  }

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
