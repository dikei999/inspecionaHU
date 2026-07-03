import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;

/// Scaffold do Firebase Cloud Messaging (push com app fechado).
///
/// O Firebase AINDA NÃO está configurado neste projeto:
///   - não existe android/app/google-services.json
///   - o plugin com.google.gms.google-services NÃO está aplicado no Gradle
///
/// Por isso todo o código de FCM fica isolado atrás de [enabled]:
/// [tryInitialize] tenta inicializar o Firebase e, se falhar (situação
/// atual), o app segue normalmente — as notificações em tempo real
/// continuam funcionando via Supabase Realtime (notification_service.dart).
///
/// Passo a passo para ativar o FCM de verdade: docs/FIREBASE_SETUP.md
class FirebaseConfig {
  FirebaseConfig._();

  /// true somente quando o Firebase inicializou com sucesso
  /// (ou seja, google-services.json presente e plugin aplicado).
  static bool enabled = false;

  /// Tenta inicializar o Firebase sem quebrar o app na ausência
  /// da configuração. Chamar no main() antes do runApp.
  static Future<void> tryInitialize() async {
    try {
      await Firebase.initializeApp();
      enabled = true;
      debugPrint('[FirebaseConfig] Firebase inicializado — FCM disponível');
    } catch (e) {
      enabled = false;
      debugPrint(
          '[FirebaseConfig] Firebase não configurado (esperado): $e');
    }
  }

  /// Registra o dispositivo para push: pede permissão, obtém o token
  /// FCM e o salva no perfil do usuário logado.
  /// No-op enquanto [enabled] for false.
  ///
  /// Requer a coluna profiles.fcm_token (SQL em docs/FIREBASE_SETUP.md).
  static Future<void> registerDevice(String userId) async {
    if (!enabled) return;
    try {
      final messaging = FirebaseMessaging.instance;

      final settings = await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      if (settings.authorizationStatus == AuthorizationStatus.denied) {
        return;
      }

      final token = await messaging.getToken();
      if (token == null) return;

      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': token}).eq('id', userId);

      // Mantém o token atualizado quando o FCM o renovar
      messaging.onTokenRefresh.listen((newToken) async {
        try {
          await Supabase.instance.client
              .from('profiles')
              .update({'fcm_token': newToken}).eq('id', userId);
        } catch (e) {
          debugPrint('[FirebaseConfig] refresh token falhou: $e');
        }
      });
    } catch (e) {
      debugPrint('[FirebaseConfig] registerDevice falhou: $e');
    }
  }

  /// Remove o token do perfil no logout (para o push parar de chegar).
  static Future<void> unregisterDevice(String userId) async {
    if (!enabled) return;
    try {
      await Supabase.instance.client
          .from('profiles')
          .update({'fcm_token': null}).eq('id', userId);
      await FirebaseMessaging.instance.deleteToken();
    } catch (e) {
      debugPrint('[FirebaseConfig] unregisterDevice falhou: $e');
    }
  }
}
