import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/invitation.dart';
import '../models/profile.dart';

/// Serviço do sistema de convite via código de perfil.
///
/// Toda mutação passa pelas RPCs do banco (send_invitation,
/// send_director_invitation, accept/decline/cancel_invitation), que aplicam
/// as regras de negócio e lançam RAISE EXCEPTION com mensagens em português.
/// As RPCs propagam essas mensagens via [PostgrestException.message] — os
/// chamadores devem capturar e exibir `.message` diretamente.
class InvitationService {
  InvitationService._();

  static final _db = Supabase.instance.client;

  /// Envia convite de Supervisor/Inspetor. Retorna o id do convite criado.
  static Future<String> sendInvitation({
    required String inviteeCode,
    required String role,
    List<String> sectorIds = const [],
    String? message,
  }) async {
    final result = await _db.rpc('send_invitation', params: {
      '_invitee_code': _normalizeCode(inviteeCode),
      '_role': role,
      '_sector_ids': sectorIds,
      '_message': message,
    });
    return result.toString();
  }

  /// Envia convite de Diretor (Super Admin). Retorna o id do convite criado.
  static Future<String> sendDirectorInvitation({
    required String inviteeCode,
    required String hospitalId,
    String? message,
  }) async {
    final result = await _db.rpc('send_director_invitation', params: {
      '_invitee_code': _normalizeCode(inviteeCode),
      '_hospital_id': hospitalId,
      '_message': message,
    });
    return result.toString();
  }

  static Future<void> acceptInvitation(String invitationId) async {
    await _db.rpc('accept_invitation', params: {'_invitation_id': invitationId});
  }

  static Future<void> declineInvitation(String invitationId) async {
    await _db
        .rpc('decline_invitation', params: {'_invitation_id': invitationId});
  }

  static Future<void> cancelInvitation(String invitationId) async {
    await _db
        .rpc('cancel_invitation', params: {'_invitation_id': invitationId});
  }

  /// Convites pendentes recebidos pelo usuário logado, ainda válidos.
  static Future<List<Invitation>> getMyPendingInvitations() async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];

    final data = await _db
        .from('invitations')
        .select(
            '*, inviter:profiles!inviter_id(full_name), hospital:hospitals!hospital_id(name)')
        .eq('invitee_id', uid)
        .eq('status', 'pending')
        .gt('expires_at', DateTime.now().toUtc().toIso8601String())
        .order('created_at', ascending: false);

    return (data as List)
        .map((e) => Invitation.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Convites enviados pelo usuário logado, opcionalmente filtrados por status.
  static Future<List<Invitation>> getSentInvitations(
      {String? statusFilter}) async {
    final uid = _db.auth.currentUser?.id;
    if (uid == null) return [];

    var query = _db
        .from('invitations')
        .select(
            '*, invitee:profiles!invitee_id(full_name), hospital:hospitals!hospital_id(name)')
        .eq('inviter_id', uid);

    if (statusFilter != null && statusFilter != 'all') {
      query = query.eq('status', statusFilter);
    }

    final data = await query.order('created_at', ascending: false);

    return (data as List)
        .map((e) => Invitation.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  /// Busca um usuário elegível para convite pelo código de perfil.
  /// Retorna null se não encontrar ou se o usuário já estiver vinculado.
  static Future<Profile?> lookupUserByCode(String code) async {
    final normalized = _normalizeCode(code);
    if (normalized.isEmpty) return null;

    final data = await _db
        .from('profiles')
        .select()
        .eq('profile_code', normalized)
        .isFilter('role', null)
        .eq('status', 'active')
        .maybeSingle();

    return data != null ? Profile.fromJson(data) : null;
  }

  /// Remove o prefixo # e normaliza para maiúsculas.
  static String _normalizeCode(String code) =>
      code.replaceAll('#', '').trim().toUpperCase();
}
