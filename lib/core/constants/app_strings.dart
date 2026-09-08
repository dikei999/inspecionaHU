class AppStrings {
  AppStrings._();

  // App
  static const String appName = 'InspecionaHU';
  static const String appSlogan = 'Seu hospital mais seguro.';

  /// Assinatura institucional — fonte UNICA. Aparece na tela de login, no
  /// painel do Super Admin e no rodape do PDF. Trocar aqui muda em todos.
  static const String assinaturaInstitucional =
      'HU Brasil · Hospitais Universitários Federais';

  // Auth
  static const String login = 'Entrar';
  static const String logout = 'Sair';
  static const String register = 'Cadastrar';
  static const String email = 'E-mail';
  static const String password = 'Senha';
  static const String fullName = 'Nome completo';
  static const String cpf = 'CPF';
  static const String confirmPassword = 'Confirmar senha';

  // Tela de aguardo
  static const String waitingTitle = 'Aguardando vinculação';
  static const String waitingMessage =
      'Informe seu e-mail ao seu Diretor ou Supervisor para ser vinculado ao hospital.';
  static const String yourEmail = 'Seu e-mail';

  // Perfis
  static const String superAdmin = 'Super Admin';
  static const String director = 'Diretor';
  static const String supervisor = 'Supervisor';
  static const String inspector = 'Inspetor';

  // Status de inspeção
  static const String statusDraft = 'Rascunho';
  static const String statusSubmitted = 'Enviado';
  static const String statusValidated = 'Validado';
  static const String statusPending = 'Pendente';
  static const String statusInProgress = 'Em andamento';
  static const String statusOverdue = 'Atrasado';

  // Respostas do checklist
  static const String compliant = 'C';
  static const String nonCompliant = 'NC';
  static const String notApplicable = 'N/A';

  // Ações
  static const String save = 'Salvar';
  static const String saveAndExit = 'Salvar e sair';
  static const String finishAndSend = 'Finalizar e enviar';
  static const String validate = 'Validar';
  static const String cancel = 'Cancelar';
  static const String confirm = 'Confirmar';
  static const String edit = 'Editar';
  static const String deactivate = 'Desativar';
  static const String reactivate = 'Reativar';
  static const String link = 'Vincular';
  static const String unlink = 'Desvincular';
  static const String exportPdf = 'Exportar PDF';
  static const String exportExcel = 'Exportar Excel';

  // Erros comuns
  static const String errorGeneric = 'Algo deu errado. Tente novamente.';
  static const String errorRequired = 'Campo obrigatório';
  static const String errorInvalidEmail = 'E-mail inválido';
  static const String errorInvalidCpf = 'CPF inválido';
  static const String errorPasswordMismatch = 'As senhas não coincidem';
  static const String errorNcRequiresObservation =
      'Observação obrigatória para itens Não Conformes';
  static const String errorNcRequiresPhoto =
      'Foto obrigatória para este item Não Conforme';
  static const String errorOffline =
      'Sem conexão. Os dados serão sincronizados ao reconectar.';

  // Checklist
  static const String observation = 'Observação';
  static const String observationHint = 'Descreva o problema encontrado...';
  static const String photo = 'Foto';
  static const String takePhoto = 'Tirar foto';
  static const String nr32Reference = 'Referência NR-32';
  static const String critical = 'Crítico';

  // Notificações
  static const String notificationTaskDueSoon = 'Prazo chegando';
  static const String notificationTaskOverdue = 'Tarefa atrasada';
  static const String notificationReportValidated = 'Relatório validado';
  static const String notificationAccessRequest = 'Solicitação de acesso';
  static const String notificationAccessApproved = 'Acesso aprovado';
  static const String notificationAccessDenied = 'Acesso negado';

  // Mensagem de checklist alterado offline
  static const String checklistChangedOffline =
      'O checklist foi alterado desde que você iniciou esta inspeção.';

  // Confirmação de segunda inspeção
  static const String duplicateInspectionWarning =
      'Já existe uma inspeção enviada para este checklist neste período. Deseja criar uma nova?';
}
