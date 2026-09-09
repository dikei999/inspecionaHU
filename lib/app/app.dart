import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../core/services/notification_service.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/cadastro_screen.dart';
import '../features/auth/screens/aguardo_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/shared/screens/perfil_screen.dart';
import '../features/shared/screens/notificacoes_screen.dart';
import '../features/shared/screens/convidar_usuario_screen.dart';
import '../features/shared/screens/convites_enviados_screen.dart';
import '../features/shared/screens/detalhes_setor_screen.dart';
import '../features/shared/screens/tarefa_detalhes_screen.dart';
import '../features/shared/screens/relatorios_analises_screen.dart';
import '../features/shared/screens/configuracoes_screen.dart';
// Super Admin
import '../features/super_admin/screens/super_admin_dashboard_screen.dart';
import '../features/super_admin/screens/hospitais_screen.dart';
import '../features/super_admin/screens/criar_hospital_screen.dart';
import '../features/super_admin/screens/vincular_director_screen.dart';
import '../features/super_admin/screens/gestao_usuarios_screen.dart';
import '../features/super_admin/screens/templates_globais_screen.dart';
import '../features/super_admin/screens/form_template_screen.dart';
import '../features/super_admin/screens/painel_demo_screen.dart';
// Director
import '../features/director/screens/director_dashboard_screen.dart';
import '../features/director/screens/gestao_setores_screen.dart';
import '../features/director/screens/form_setor_screen.dart';
import '../features/director/screens/gestao_usuarios_hospital_screen.dart';
import '../features/director/screens/form_checklist_screen.dart';
import '../features/director/screens/templates_locais_screen.dart';
import '../features/director/screens/atribuir_tarefa_screen.dart';
import '../features/director/screens/quadro_tarefas_gestao_screen.dart';
import '../features/director/screens/calendario_institucional_screen.dart';
import '../features/director/screens/relatorio_individual_screen.dart';
import '../features/director/screens/acesso_compartilhado_screen.dart';
import '../features/director/screens/pedidos_acesso_screen.dart';
// Supervisor
import '../features/supervisor/screens/supervisor_dashboard_screen.dart';
// Inspetor
import '../features/inspector/screens/quadro_tarefas_screen.dart';
import '../features/inspector/screens/historico_screen.dart';
import '../features/inspector/screens/serie_tarefas_screen.dart';
import '../features/inspector/screens/calendario_screen.dart';
import '../features/inspector/screens/resposta_checklist_screen.dart';
import '../core/services/offline_sync_service.dart';
import '../widgets/connection_banner.dart';
import 'routes.dart';
import 'theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthProvider _authProvider;
  late final NotificationProvider _notificationProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _notificationProvider = NotificationProvider();
    _authProvider.addListener(_syncNotificationService);
    _syncNotificationService();
    // Monitor de conexao + fila de envio offline (6.4/6.5).
    OfflineSyncService.start();
    // Voltou a rede depois de entrar com perfil em cache: troca pelo
    // perfil do servidor, silenciosamente (6.1).
    OfflineSyncService.online.addListener(_revalidarPerfilOffline);
    _router = GoRouter(
      refreshListenable: _authProvider,
      initialLocation: AppRoutes.login,
      redirect: _redirect,
      routes: _buildRoutes(),
    );
  }

  /// Inicia o serviço de notificações após o login e encerra no logout.
  void _syncNotificationService() {
    final profile = _authProvider.profile;
    if (_authProvider.status == AuthStatus.authenticated && profile != null) {
      _notificationProvider.start(profile.id);
    } else if (_authProvider.status == AuthStatus.unauthenticated &&
        _notificationProvider.isActive) {
      _notificationProvider.stop();
    }
  }

  String? _redirect(BuildContext context, GoRouterState state) {
    final status = _authProvider.status;
    final location = state.uri.path;

    // Aguarda carregamento inicial
    if (status == AuthStatus.loading) return null;

    // Não autenticado → apenas login e cadastro são acessíveis
    if (status == AuthStatus.unauthenticated) {
      if (location == AppRoutes.cadastro) return null;
      if (location == AppRoutes.login) return null;
      if (location == AppRoutes.forgotPassword) return null;
      return AppRoutes.login;
    }

    // Autenticado — verifica se tem role
    final profile = _authProvider.profile;
    final role = profile?.role;
    final hasRole = role == 'super_admin' ||
        (role != null && profile?.hospitalId != null);

    // Sem role → tela de aguardo
    if (!hasRole) {
      if (location == AppRoutes.aguardo) return null;
      return AppRoutes.aguardo;
    }

    // Tem role — não pode ficar em telas de auth/aguardo
    final authScreens = {
      AppRoutes.login,
      AppRoutes.cadastro,
      AppRoutes.aguardo,
    };
    if (authScreens.contains(location)) {
      return AppRoutes.dashboardForRole(role);
    }

    // Proteção de rota por role: super_admin não acessa /director, etc.
    if (role == 'super_admin' && location.startsWith('/director')) {
      return AppRoutes.superAdminDashboard;
    }
    if (role == 'director' && location.startsWith('/super-admin')) {
      return AppRoutes.directorDashboard;
    }

    // /setor/:id é o hub de gestão — só Diretor e Supervisor entram.
    // A permissão fina (owner / sector_access) é resolvida na própria tela.
    if (location.startsWith('/setor/') &&
        role != 'director' &&
        role != 'supervisor') {
      return AppRoutes.dashboardForRole(role);
    }

    // Inspetor só acessa as próprias rotas.
    if (role == 'inspector' &&
        (location.startsWith('/director') ||
            location.startsWith('/supervisor') ||
            location.startsWith('/super-admin'))) {
      return AppRoutes.inspectorDashboard;
    }

    // Diretor não usa os aliases /supervisor/*.
    if (role == 'director' && location.startsWith('/supervisor')) {
      return AppRoutes.directorDashboard;
    }
    // Supervisor pode acessar rotas /director/* compartilhadas (setores, checklists,
    // tarefas, equipe, relatórios, calendário, acesso) — exceto apenas
    // templates-locais (exclusivo do Director).
    if (role == 'supervisor' && location.startsWith('/director')) {
      if (location.startsWith('/director/templates-locais')) {
        return AppRoutes.supervisorDashboard;
      }
      // Permite as demais rotas /director/*
    }

    return null;
  }

  List<RouteBase> _buildRoutes() {
    return [
      // ── Auth ──────────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.cadastro,
        builder: (context, state) => const CadastroScreen(),
      ),
      GoRoute(
        path: AppRoutes.aguardo,
        builder: (context, state) => const AguardoScreen(),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        builder: (context, state) => const ForgotPasswordScreen(),
      ),

      // ── Compartilhado ─────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.perfil,
        builder: (context, state) => const PerfilScreen(),
      ),
      GoRoute(
        path: AppRoutes.notificacoes,
        builder: (context, state) => const NotificacoesScreen(),
      ),
      GoRoute(
        path: AppRoutes.convidarUsuario,
        builder: (context, state) => ConvidarUsuarioScreen(
          initialSectorId: state.uri.queryParameters['sectorId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.convitesEnviados,
        builder: (context, state) => const ConvitesEnviadosScreen(),
      ),
      // Hub central do setor — Diretor e Supervisor (permissões resolvidas
      // dentro da tela; Supervisor sem acesso vê mensagem e volta).
      GoRoute(
        path: '/setor/:sectorId',
        builder: (context, state) => DetalhesSetorScreen(
          sectorId: state.pathParameters['sectorId']!,
        ),
      ),
      // Detalhes de UMA tarefa, somente leitura — Diretor e Supervisor
      // (item 2 da revisão: substitui o destino que antes era a tela de
      // resposta do Inspetor).
      GoRoute(
        path: '/tarefa/:taskId',
        builder: (context, state) => TarefaDetalhesScreen(
          taskId: state.pathParameters['taskId']!,
        ),
      ),

      // ── Super Admin ───────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.superAdminDashboard,
        builder: (context, state) => const SuperAdminDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.hospitais,
        builder: (context, state) => const HospitaisScreen(),
      ),
      GoRoute(
        path: AppRoutes.criarHospital,
        builder: (context, state) => const CriarHospitalScreen(),
      ),
      GoRoute(
        path: AppRoutes.vincularDirector,
        builder: (context, state) => const VincularDirectorScreen(),
      ),
      GoRoute(
        path: AppRoutes.gestaoUsuarios,
        builder: (context, state) => const GestaoUsuariosScreen(),
      ),
      GoRoute(
        path: AppRoutes.templatesGlobais,
        builder: (context, state) => const TemplatesGlobaisScreen(),
      ),
      GoRoute(
        path: AppRoutes.novoTemplateGlobal,
        builder: (context, state) => const FormTemplateScreen(scope: 'global'),
      ),
      GoRoute(
        path: '/super-admin/templates-globais/:id/editar',
        builder: (context, state) => FormTemplateScreen(
          scope: 'global',
          templateId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: AppRoutes.painelDemo,
        builder: (context, state) => const PainelDemoScreen(),
      ),

      // ── Director ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.directorDashboard,
        builder: (context, state) => const DirectorDashboardScreen(),
      ),
      GoRoute(
        path: AppRoutes.gestaoSetores,
        builder: (context, state) => const GestaoSetoresScreen(),
      ),
      GoRoute(
        path: AppRoutes.novoSetor,
        builder: (context, state) => const FormSetorScreen(),
      ),
      GoRoute(
        path: '/director/setores/:id/editar',
        builder: (context, state) =>
            FormSetorScreen(sectorId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.gestaoUsuariosHospital,
        builder: (context, state) => const GestaoUsuariosHospitalScreen(),
      ),
      GoRoute(
        path: AppRoutes.novoChecklist,
        builder: (context, state) => FormChecklistScreen(
          initialSectorId: state.uri.queryParameters['sectorId'],
        ),
      ),
      GoRoute(
        path: '/director/checklists/:id/editar',
        builder: (context, state) =>
            FormChecklistScreen(checklistId: state.pathParameters['id']),
      ),
      GoRoute(
        path: AppRoutes.templatesLocais,
        builder: (context, state) => const TemplatesLocaisScreen(),
      ),
      GoRoute(
        path: AppRoutes.novoTemplateLocal,
        builder: (context, state) => const FormTemplateScreen(scope: 'local'),
      ),
      GoRoute(
        path: '/director/templates-locais/:id/editar',
        builder: (context, state) => FormTemplateScreen(
          scope: 'local',
          templateId: state.pathParameters['id'],
        ),
      ),
      GoRoute(
        path: AppRoutes.atribuirTarefa,
        builder: (context, state) => AtribuirTarefaScreen(
          initialSectorId: state.uri.queryParameters['sectorId'],
        ),
      ),
      GoRoute(
        path: AppRoutes.quadroTarefasGestao,
        builder: (context, state) => const QuadroTarefasGestaoScreen(),
      ),
      GoRoute(
        path: AppRoutes.calendarioInstitucional,
        builder: (context, state) => const CalendarioInstitucionalScreen(),
      ),
      GoRoute(
        path: '/director/relatorios/:id',
        builder: (context, state) =>
            RelatorioIndividualScreen(inspectionId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.acessoCompartilhado,
        builder: (context, state) => const AcessoCompartilhadoScreen(),
      ),
      GoRoute(
        path: AppRoutes.pedidosAcesso,
        builder: (context, state) => const PedidosAcessoScreen(),
      ),
      GoRoute(
        path: AppRoutes.relatoriosAnalises,
        builder: (context, state) => const RelatoriosAnalisesScreen(),
      ),
      GoRoute(
        path: AppRoutes.configuracoes,
        builder: (context, state) => const ConfiguracoesScreen(),
      ),

      // ── Supervisor (Fase 5) ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.supervisorDashboard,
        builder: (context, state) => const SupervisorDashboardScreen(),
      ),
      // Aliases do Supervisor para as telas compartilhadas — o conteúdo é
      // filtrado por role dentro de cada tela.
      GoRoute(
        path: AppRoutes.supervisorRelatorios,
        builder: (context, state) => const RelatoriosAnalisesScreen(),
      ),
      GoRoute(
        path: AppRoutes.supervisorConfiguracoes,
        builder: (context, state) => const ConfiguracoesScreen(),
      ),

      // ── Inspetor ──────────────────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.inspectorDashboard,
        builder: (context, state) => const QuadroTarefasScreen(),
      ),
      GoRoute(
        path: AppRoutes.inspectorCalendario,
        builder: (context, state) => const CalendarioScreen(),
      ),
      GoRoute(
        path: '/inspector/serie/:id',
        builder: (context, state) =>
            SerieTarefasScreen(seriesId: state.pathParameters['id']!),
      ),
      GoRoute(
        path: AppRoutes.inspectorHistorico,
        builder: (context, state) => const HistoricoScreen(),
      ),
      GoRoute(
        path: '/inspector/tarefas/:taskId/responder',
        builder: (context, state) => RespostaChecklistScreen(
          taskId: state.pathParameters['taskId']!,
        ),
      ),
    ];
  }

  @override
  void dispose() {
    _authProvider.removeListener(_syncNotificationService);
    OfflineSyncService.online.removeListener(_revalidarPerfilOffline);
    _notificationProvider.dispose();
    _authProvider.dispose();
    super.dispose();
  }

  void _revalidarPerfilOffline() {
    if (!OfflineSyncService.online.value) return;
    _authProvider.revalidateProfileIfOffline();
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AuthProvider>.value(value: _authProvider),
        ChangeNotifierProvider<NotificationProvider>.value(
            value: _notificationProvider),
      ],
      child: MaterialApp.router(
        title: 'InspecionaHU',
        theme: AppTheme.lightTheme,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
        // Interface em portugues do Brasil: sem isso os widgets do Material
        // (date picker, cabecalho de calendario, tooltips) saem em ingles,
        // mesmo com o intl ja formatando as datas em pt_BR.
        locale: const Locale('pt', 'BR'),
        supportedLocales: const [Locale('pt', 'BR')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        // Faixa global de status de conexao (6.5): some por completo
        // quando esta online e sem pendencia, deixando o fluxo online
        // exatamente como era.
        builder: (context, child) =>
            ConnectionBanner(child: child ?? const SizedBox.shrink()),
      ),
    );
  }
}
