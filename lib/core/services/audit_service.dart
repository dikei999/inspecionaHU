import 'package:supabase_flutter/supabase_flutter.dart';

class AuditService {
  AuditService._();

  static final _db = Supabase.instance.client;

  /// Registra uma ação no audit_log (seção 16.10).
  /// Falha silenciosa — o audit_log não deve bloquear a operação principal.
  static Future<void> log({
    required String userId,
    String? hospitalId,
    required String action,
    required String entityType,
    required String entityId,
    Map<String, dynamic>? details,
  }) async {
    try {
      await _db.from('audit_log').insert({
        'user_id': userId,
        'hospital_id': hospitalId,
        'action': action,
        'entity_type': entityType,
        'entity_id': entityId,
        'details': details,
      });
    } catch (_) {
      // Falha no audit_log é não-fatal
    }
  }
}
