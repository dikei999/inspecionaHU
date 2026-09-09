class AppRoutes {
  AppRoutes._();

  // ── Auth ─────────────────────────────────────────────────────────────────
  static const login = '/login';
  static const cadastro = '/cadastro';
  static const aguardo = '/aguardo';
  static const forgotPassword = '/forgot-password';

  // ── Compartilhado ────────────────────────────────────────────────────────
  static const perfil = '/perfil';
  /// Detalhes do setor — hub central (Diretor e Supervisor).
  static String detalhesSetor(String sectorId) => '/setor/$sectorId';

  /// Detalhes de UMA tarefa, somente leitura — Diretor e Supervisor.
  /// Item 2 (revisão): antes tocar numa tarefa levava para a tela de
  /// resposta (do Inspetor), que dava "erro ao responder checklist".
  static String tarefaDetalhes(String taskId) => '/tarefa/$taskId';
  static const notificacoes = '/notificacoes';
  static const convidarUsuario = '/convidar-usuario';

  /// Convite ja vinculado a um setor — usado pela aba Equipe do setor.
  static String convidarUsuarioNoSetor(String sectorId) =>
      '$convidarUsuario?sectorId=$sectorId';
  static const convitesEnviados = '/convites-enviados';

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
  static const painelDemo = '/super-admin/painel-demo';

  // ── Director ─────────────────────────────────────────────────────────────
  static const directorDashboard = '/director';
  static const gestaoSetores = '/director/setores';
  static const novoSetor = '/director/setores/novo';
  static String editarSetor(String id) => '/director/setores/$id/editar';
  /// Gestão de Usuários do hospital: membros + pedidos de acesso.
  /// O que é de setor vive na aba Equipe do próprio setor.
  static const gestaoUsuariosHospital = '/director/usuarios';
  static const novoChecklist = '/director/checklists/novo';
  /// Novo checklist com setor pré-selecionado (aba Checklists do setor).
  static String novoChecklistNoSetor(String sectorId) =>
      '$novoChecklist?sectorId=$sectorId';
  static String editarChecklist(String id) => '/director/checklists/$id/editar';
  static const templatesLocais = '/director/templates-locais';
  static const novoTemplateLocal = '/director/templates-locais/novo';
  static String editarTemplateLocal(String id) =>
      '/director/templates-locais/$id/editar';
  static const atribuirTarefa = '/director/tarefas/nova';
  /// Atribuir tarefa com setor pré-selecionado (aba Tarefas do setor).
  static String atribuirTarefaNoSetor(String sectorId) =>
      '$atribuirTarefa?sectorId=$sectorId';
  static const quadroTarefasGestao = '/director/tarefas';
  static const calendarioInstitucional = '/director/calendario';
  static String relatorioIndividual(String id) => '/director/relatorios/$id';
  static const acessoCompartilhado = '/director/acesso-compartilhado';
  static const pedidosAcesso = '/director/pedidos-acesso';
  static const relatoriosAnalises = '/director/analises';
  static const configuracoes = '/director/configuracoes';

  // ── Supervisor ───────────────────────────────────────────────────────────
  static const supervisorDashboard = '/supervisor';
  static const supervisorRelatorios = '/supervisor/analises';
  static const supervisorConfiguracoes = '/supervisor/configuracoes';

  // ── Inspetor ─────────────────────────────────────────────────────────────
  static const inspectorDashboard = '/inspector';
  static const inspectorCalendario = '/inspector/calendario';
  /// Ocorrencias de uma serie recorrente.
  static String serieTarefas(String seriesId) =>
      '/inspector/serie/$seriesId';

  static const inspectorHistorico = '/inspector/historico';
  static String responderChecklist(String taskId) =>
      '/inspector/tarefas/$taskId/responder';

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
