import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/profile.dart';
import 'supabase_service.dart';

class AuthService {
  AuthService._();

  static User? get currentUser => SupabaseService.auth.currentUser;

  static bool get isLoggedIn => currentUser != null;

  static Future<AuthResponse> signUp({
    required String email,
    required String password,
  }) async {
    return SupabaseService.auth.signUp(email: email, password: password);
  }

  static Future<AuthResponse> signIn({
    required String email,
    required String password,
  }) async {
    return SupabaseService.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await SupabaseService.auth.signOut();
  }

  /// Busca o perfil do usuário autenticado.
  /// Retorna null se ainda não vinculado (role = null).
  static Future<Profile?> fetchProfile() async {
    final uid = currentUser?.id;
    if (uid == null) return null;

    final data = await SupabaseService.client
        .from('profiles')
        .select()
        .eq('id', uid)
        .maybeSingle();

    if (data == null) return null;
    return Profile.fromJson(data);
  }

  /// Stream de mudanças de estado de autenticação.
  static Stream<AuthState> get authStateChanges =>
      SupabaseService.auth.onAuthStateChange;
}
