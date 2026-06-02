class AccessRequest {
  final String id;
  final String sectorId;
  final String requesterId;
  final String ownerId;
  final bool canView;
  final bool canEdit;
  final String status; // pending | approved | denied
  final DateTime requestedAt;
  final DateTime? resolvedAt;
  final String? resolvedBy; // owner OU director

  const AccessRequest({
    required this.id,
    required this.sectorId,
    required this.requesterId,
    required this.ownerId,
    required this.canView,
    required this.canEdit,
    required this.status,
    required this.requestedAt,
    this.resolvedAt,
    this.resolvedBy,
  });

  factory AccessRequest.fromJson(Map<String, dynamic> json) => AccessRequest(
        id: json['id'] as String,
        sectorId: json['sector_id'] as String,
        requesterId: json['requester_id'] as String,
        ownerId: json['owner_id'] as String,
        canView: json['can_view'] as bool,
        canEdit: json['can_edit'] as bool,
        status: json['status'] as String,
        requestedAt: DateTime.parse(json['requested_at'] as String),
        resolvedAt: json['resolved_at'] != null
            ? DateTime.parse(json['resolved_at'] as String)
            : null,
        resolvedBy: json['resolved_by'] as String?,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'sector_id': sectorId,
        'requester_id': requesterId,
        'owner_id': ownerId,
        'can_view': canView,
        'can_edit': canEdit,
        'status': status,
        'requested_at': requestedAt.toIso8601String(),
        'resolved_at': resolvedAt?.toIso8601String(),
        'resolved_by': resolvedBy,
      };

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isDenied => status == 'denied';
}
