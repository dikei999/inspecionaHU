import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../features/auth/providers/auth_provider.dart';
import '../features/auth/screens/login_screen.dart';
import '../features/auth/screens/cadastro_screen.dart';
import '../features/auth/screens/aguardo_screen.dart';
import '../features/auth/screens/forgot_password_screen.dart';
import '../features/shared/screens/perfil_screen.dart';
import '../features/shared/screens/notificacoes_screen.dart';
// Super Admin
import '../features/super_admin/screens/super_admin_dashboard_screen.dart';
import '../features/super_admin/screens/hospitais_screen.dart';
import '../features/super_admin/screens/criar_hospital_screen.dart';
import '../features/super_admin/screens/vincular_director_screen.dart';
import '../features/super_admin/screens/gestao_usuarios_screen.dart';
import '../features/super_admin/screens/templates_globais_screen.dart';
import '../features/super_admin/screens/form_template_screen.dart';
// Director
import '../features/director/screens/director_dashboard_screen.dart';
import '../features/director/screens/gestao_setores_screen.dart';
import '../features/director/screens/form_setor_screen.dart';
import '../features/director/screens/gestao_equipe_screen.dart';
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
import '../features/inspector/screens/calendario_screen.dart';
import '../features/inspector/screens/resposta_checklist_screen.dart';
import 'routes.dart';
import 'theme.dart';

class App extends StatefulWidget {
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  late final AuthProvider _authProvider;
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _authProvider = AuthProvider();
    _router = GoRouter(
      refreshListenable: _authProvider,
      initialLocation: AppRoutes.login,
      redirect: _redirect,
      routes: _buildRoutes(),
    );
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
        path: AppRoutes.gestaoEquipe,
        builder: (context, state) => const GestaoEquipeScreen(),
      ),
      GoRoute(
        path: AppRoutes.novoChecklist,
        builder: (context, state) => const FormChecklistScreen(),
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
        builder: (context, state) => const AtribuirTarefaScreen(),
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

      // ── Supervisor (Fase 5) ───────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.supervisorDashboard,
        builder: (context, state) => const SupervisorDashboardScreen(),
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
    _authProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<AuthProvider>.value(
      value: _authProvider,
      child: MaterialApp.router(
        title: 'InspecionaHU',
        theme: AppTheme.lightTheme,
        routerConfig: _router,
        debugShowCheckedModeBanner: false,
      ),
    );
  }
}
