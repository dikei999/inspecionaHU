/// Constantes de domínio do sistema (categorias NR-32, estados BR, etc.)
class AppConstants {
  AppConstants._();

  /// Seções da NR-32 usadas como categoria (fonte: docs/BIBLIOTECA_NR32.md).
  static const List<String> nr32Categories = [
    '32.2 Riscos Biológicos',
    '32.3 Riscos Químicos',
    '32.4 Radiações Ionizantes',
    '32.5 Resíduos',
    '32.6 Conforto por Ocasião das Refeições',
    '32.7 Lavanderias',
    '32.8 Limpeza e Conservação',
    '32.9 Manutenção de Máquinas e Equipamentos',
    '32.10 Disposições Gerais',
    'Anexo III — Perfurocortantes',
  ];

  /// Itens de dropdown de categoria: inclui [current] como opção extra
  /// quando é um valor legado que não está mais em [nr32Categories],
  /// evitando assertion error do DropdownButtonFormField.
  static List<String> nr32CategoryOptions(String? current) {
    if (current == null ||
        current.isEmpty ||
        nr32Categories.contains(current)) {
      return nr32Categories;
    }
    return [current, ...nr32Categories];
  }

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
