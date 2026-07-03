import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/notification_model.dart';

/// Recepção de notificações no app:
/// 1. Assina Supabase Realtime na tabela `notifications` filtrada pelo
///    user_id logado.
/// 2. Ao receber um INSERT, exibe notificação local (flutter_local_notifications)
///    e atualiza o contador reativo de não-lidas (badge no sino do AppBar).
///
/// O push FCM real (app fechado) é entregue pela camada 3c — ver
/// lib/core/services/firebase_config.dart e docs/FIREBASE_SETUP.md.
class NotificationProvider extends ChangeNotifier {
  final SupabaseClient _db = Supabase.instance.client;
  static final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();
  static bool _localPluginReady = false;

  RealtimeChannel? _channel;
  String? _userId;

  List<NotificationModel> _notifications = [];
  int _unreadCount = 0;
  bool _loading = false;

  List<NotificationModel> get notifications => _notifications;
  int get unreadCount => _unreadCount;
  bool get loading => _loading;
  bool get isActive => _userId != null;

  // ── Inicialização do plugin de notificações locais ─────────────────────────

  /// Canal Android dedicado, em pt-BR. Chamado uma única vez por sessão.
  static Future<void> _ensureLocalPlugin() async {
    if (_localPluginReady) return;
    try {
      const androidInit =
          AndroidInitializationSettings('@mipmap/ic_launcher');
      const iosInit = DarwinInitializationSettings();
      await _localPlugin.initialize(
        const InitializationSettings(android: androidInit, iOS: iosInit),
      );

      final androidImpl =
          _localPlugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (androidImpl != null) {
        await androidImpl.createNotificationChannel(
          const AndroidNotificationChannel(
            'inspecionahu_notifications',
            'Notificações InspecionaHU',
            description:
                'Prazos de tarefas, relatórios validados e pedidos de acesso',
            importance: Importance.high,
          ),
        );
        // Android 13+ exige permissão de runtime para exibir notificações
        await androidImpl.requestNotificationsPermission();
      }
      _localPluginReady = true;
    } catch (e) {
      // Sem notificação local o app continua funcional (badge segue ativo)
      debugPrint('[NotificationProvider] init local plugin falhou: $e');
    }
  }

  // ── Ciclo de vida (chamar após login / no logout) ───────────────────────────

  /// Inicia o serviço para o usuário logado: carrega a lista e assina Realtime.
  Future<void> start(String userId) async {
    if (_userId == userId) return; // já ativo para este usuário
    await stop();
    _userId = userId;

    await _ensureLocalPlugin();
    await refresh();

    try {
      _channel = _db
          .channel('notifications-$userId')
          .onPostgresChanges(
            event: PostgresChangeEvent.insert,
            schema: 'public',
            table: 'notifications',
            filter: PostgresChangeFilter(
              type: PostgresChangeFilterType.eq,
              column: 'user_id',
              value: userId,
            ),
            callback: _onInsert,
          )
          .subscribe();
    } catch (e) {
      debugPrint('[NotificationProvider] realtime subscribe falhou: $e');
    }
  }

  /// Encerra a assinatura e limpa o estado (logout).
  Future<void> stop() async {
    if (_channel != null) {
      try {
        await _db.removeChannel(_channel!);
      } catch (_) {}
      _channel = null;
    }
    _userId = null;
    _notifications = [];
    _unreadCount = 0;
    notifyListeners();
  }

  void _onInsert(PostgresChangePayload payload) {
    try {
      final model = NotificationModel.fromJson(payload.newRecord);
      _notifications.insert(0, model);
      if (!model.read) _unreadCount++;
      notifyListeners();
      _showLocal(model);
    } catch (e) {
      debugPrint('[NotificationProvider] payload inválido: $e');
    }
  }

  Future<void> _showLocal(NotificationModel n) async {
    if (!_localPluginReady) return;
    try {
      await _localPlugin.show(
        n.id.hashCode,
        n.title,
        n.body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'inspecionahu_notifications',
            'Notificações InspecionaHU',
            channelDescription:
                'Prazos de tarefas, relatórios validados e pedidos de acesso',
            importance: Importance.high,
            priority: Priority.high,
            icon: '@mipmap/ic_launcher',
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
    } catch (e) {
      debugPrint('[NotificationProvider] show local falhou: $e');
    }
  }

  // ── Operações sobre a lista ─────────────────────────────────────────────────

  /// Recarrega as notificações do usuário (mais recentes primeiro).
  Future<void> refresh() async {
    final uid = _userId;
    if (uid == null) return;
    _loading = true;
    notifyListeners();
    try {
      final data = await _db
          .from('notifications')
          .select()
          .eq('user_id', uid)
          .order('created_at', ascending: false)
          .limit(100);
      _notifications = (data as List)
          .map((e) => NotificationModel.fromJson(e as Map<String, dynamic>))
          .toList();
      _unreadCount = _notifications.where((n) => !n.read).length;
    } catch (e) {
      debugPrint('[NotificationProvider] refresh falhou: $e');
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  /// Marca uma notificação como lida (update read=true).
  Future<void> markAsRead(String notificationId) async {
    final uid = _userId;
    if (uid == null) return;
    final idx = _notifications.indexWhere((n) => n.id == notificationId);
    if (idx == -1 || _notifications[idx].read) return;

    // Atualização otimista do badge
    _notifications[idx] = _notifications[idx].copyWith(read: true);
    _unreadCount = _notifications.where((n) => !n.read).length;
    notifyListeners();

    try {
      await _db
          .from('notifications')
          .update({'read': true})
          .eq('id', notificationId)
          .eq('user_id', uid);
    } catch (e) {
      debugPrint('[NotificationProvider] markAsRead falhou: $e');
    }
  }

  /// Marca todas as notificações do usuário como lidas.
  Future<void> markAllAsRead() async {
    final uid = _userId;
    if (uid == null) return;
    _notifications =
        _notifications.map((n) => n.copyWith(read: true)).toList();
    _unreadCount = 0;
    notifyListeners();

    try {
      await _db
          .from('notifications')
          .update({'read': true})
          .eq('user_id', uid)
          .eq('read', false);
    } catch (e) {
      debugPrint('[NotificationProvider] markAllAsRead falhou: $e');
    }
  }
}
