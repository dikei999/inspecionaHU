class AppRoutes {
  AppRoutes._();

  // ── Auth ─────────────────────────────────────────────────────────────────
  static const login = '/login';
  static const cadastro = '/cadastro';
  static const aguardo = '/aguardo';
  static const forgotPassword = '/forgot-password';

  // ── Compartilhado ────────────────────────────────────────────────────────
  static const perfil = '/perfil';
  static const notificacoes = '/notificacoes';

  // ── Super Admin ──────────────────────────────────────────────────────────
  static const superAdminDashboard = '/super-admin';
  static const hospitais = '/super-admin/hospitais';
  static const criarHospital = '/super-admin/hospitais/novo';
  static const vincularDirector = '/super-admin/vincular-director';
  static const gestaoUsuarios = '/super-admin/usuarios';
  static const templatesGlobais = '/super-admin/templates-globais';
  static const novoTemplateGlobal = '/super-admin/templates-globais/novo';
  static String editarTemplateGlobal(String id) =>
      '/super-admin/templates-globais/$id/editar';

  // ── Director ─────────────────────────────────────────────────────────────
  static const directorDashboard = '/director';
  static const gestaoSetores = '/director/setores';
  static const novoSetor = '/director/setores/novo';
  static String editarSetor(String id) => '/director/setores/$id/editar';
  static const gestaoEquipe = '/director/equipe';
  static const novoChecklist = '/director/checklists/novo';
  static String editarChecklist(String id) => '/director/checklists/$id/editar';
  static const templatesLocais = '/director/templates-locais';
  static const novoTemplateLocal = '/director/templates-locais/novo';
  static String editarTemplateLocal(String id) =>
      '/director/templates-locais/$id/editar';
  static const atribuirTarefa = '/director/tarefas/nova';
  static const quadroTarefasGestao = '/director/tarefas';
  static const calendarioInstitucional = '/director/calendario';
  static String relatorioIndividual(String id) => '/director/relatorios/$id';
  static const acessoCompartilhado = '/director/acesso-compartilhado';
  static const pedidosAcesso = '/director/pedidos-acesso';

  // ── Supervisor ───────────────────────────────────────────────────────────
  static const supervisorDashboard = '/supervisor';

  // ── Inspetor ─────────────────────────────────────────────────────────────
  static const inspectorDashboard = '/inspector';
  static const inspectorCalendario = '/inspector/calendario';
  static const inspectorHistorico = '/inspector/historico';

  // Helper: retorna rota de dashboard para cada role
  static String dashboardForRole(String? role) {
    switch (role) {
      case 'super_admin':
        return superAdminDashboard;
      case 'director':
        return directorDashboard;
      case 'supervisor':
        return supervisorDashboard;
      case 'inspector':
        return inspectorDashboard;
      default:
        return aguardo;
    }
  }
}
