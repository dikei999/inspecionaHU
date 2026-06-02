class InspectionResponse {
  final String id;
  final String inspectionId;
  final String checklistItemId;
  final String? status; // C | NC | NA | null (não respondido)
  final String? observation; // obrigatório se status = 'NC'
  final String? photoUrl;
  final DateTime? photoCapturedAt;
  final int? photoSizeKb;
  final DateTime? answeredAt;

  const InspectionResponse({
    required this.id,
    required this.inspectionId,
    required this.checklistItemId,
    this.status,
    this.observation,
    this.photoUrl,
    this.photoCapturedAt,
    this.photoSizeKb,
    this.answeredAt,
  });

  factory InspectionResponse.fromJson(Map<String, dynamic> json) =>
      InspectionResponse(
        id: json['id'] as String,
        inspectionId: json['inspection_id'] as String,
        checklistItemId: json['checklist_item_id'] as String,
        status: json['status'] as String?,
        observation: json['observation'] as String?,
        photoUrl: json['photo_url'] as String?,
        photoCapturedAt: json['photo_captured_at'] != null
            ? DateTime.parse(json['photo_captured_at'] as String)
            : null,
        photoSizeKb: json['photo_size_kb'] as int?,
        answeredAt: json['answered_at'] != null
            ? DateTime.parse(json['answered_at'] as String)
            : null,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'inspection_id': inspectionId,
        'checklist_item_id': checklistItemId,
        'status': status,
        'observation': observation,
        'photo_url': photoUrl,
        'photo_captured_at': photoCapturedAt?.toIso8601String(),
        'photo_size_kb': photoSizeKb,
        'answered_at': answeredAt?.toIso8601String(),
      };

  bool get isAnswered => status != null;
  bool get isNonCompliant => status == 'NC';
  bool get isCompliant => status == 'C';
  bool get isNotApplicable => status == 'NA';
}
