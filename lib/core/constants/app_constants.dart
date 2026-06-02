/// Constantes de domínio do sistema (categorias NR-32, estados BR, etc.)
class AppConstants {
  AppConstants._();

  static const List<String> nr32Categories = [
    'Gerenciamento de Resíduos (RSS)',
    'Produtos Químicos',
    'Radiações Ionizantes',
    'Radiações Não Ionizantes',
    'Ergonomia',
    'Segurança Biológica',
    'EPIs e EPC',
    'Instalações Físicas',
    'Esterilização e Desinfecção',
    'Lavanderia',
    'Preparo e Distribuição de Alimentos',
    'Manutenção Predial',
    'Geral / Outros',
  ];

  static const List<String> brazilianStates = [
    'AC', 'AL', 'AP', 'AM', 'BA', 'CE', 'DF', 'ES', 'GO',
    'MA', 'MT', 'MS', 'MG', 'PA', 'PB', 'PR', 'PE', 'PI',
    'RJ', 'RN', 'RS', 'RO', 'RR', 'SC', 'SP', 'SE', 'TO',
  ];

  static const List<Map<String, String>> checklistFrequencies = [
    {'value': 'daily', 'label': 'Diária'},
    {'value': 'weekly', 'label': 'Semanal'},
    {'value': 'biweekly', 'label': 'Quinzenal'},
    {'value': 'monthly', 'label': 'Mensal'},
    {'value': 'custom', 'label': 'Personalizada'},
  ];

  static const List<Map<String, String>> weekDays = [
    {'value': 'mon', 'label': 'Seg'},
    {'value': 'tue', 'label': 'Ter'},
    {'value': 'wed', 'label': 'Qua'},
    {'value': 'thu', 'label': 'Qui'},
    {'value': 'fri', 'label': 'Sex'},
    {'value': 'sat', 'label': 'Sáb'},
    {'value': 'sun', 'label': 'Dom'},
  ];

  static String roleLabel(String? role) {
    switch (role) {
      case 'super_admin':
        return 'Super Admin';
      case 'director':
        return 'Diretor';
      case 'supervisor':
        return 'Supervisor';
      case 'inspector':
        return 'Inspetor';
      default:
        return 'Sem vínculo';
    }
  }

  static String statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'Pendente';
      case 'in_progress':
        return 'Em andamento';
      case 'submitted':
        return 'Enviado';
      case 'validated':
        return 'Validado';
      case 'active':
        return 'Ativo';
      case 'inactive':
        return 'Inativo';
      default:
        return status;
    }
  }

  static String frequencyLabel(String freq) {
    switch (freq) {
      case 'daily':
        return 'Diária';
      case 'weekly':
        return 'Semanal';
      case 'biweekly':
        return 'Quinzenal';
      case 'monthly':
        return 'Mensal';
      case 'custom':
        return 'Personalizada';
      default:
        return freq;
    }
  }
}
