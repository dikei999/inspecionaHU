class NotificationModel {
  final String id;
  final String userId;
  final String? hospitalId;
  final String type;
  // Tipos: task_due_soon | task_overdue | draft_reminder | report_validated |
  //        access_request | access_approved | access_denied
  final String title;
  final String? body;
  final String? referenceId; // id da entidade relacionada (task, inspection...)
  final bool read;
  final DateTime createdAt;

  const NotificationModel({
    required this.id,
    required this.userId,
    this.hospitalId,
    required this.type,
    required this.title,
    this.body,
    this.referenceId,
    required this.read,
    required this.createdAt,
  });

  factory NotificationModel.fromJson(Map<String, dynamic> json) =>
      NotificationModel(
        id: json['id'] as String,
        userId: json['user_id'] as String,
        hospitalId: json['hospital_id'] as String?,
        type: json['type'] as String,
        title: json['title'] as String,
        body: json['body'] as String?,
        referenceId: json['reference_id'] as String?,
        read: json['read'] as bool,
        createdAt: DateTime.parse(json['created_at'] as String),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'user_id': userId,
        'hospital_id': hospitalId,
        'type': type,
        'title': title,
        'body': body,
        'reference_id': referenceId,
        'read': read,
        'created_at': createdAt.toIso8601String(),
      };

  NotificationModel copyWith({bool? read}) => NotificationModel(
        id: id,
        userId: userId,
        hospitalId: hospitalId,
        type: type,
        title: title,
        body: body,
        referenceId: referenceId,
        read: read ?? this.read,
        createdAt: createdAt,
      );
}
