class CpfUtils {
  CpfUtils._();

  /// Valida um CPF (11 dígitos sem formatação).
  static bool isValid(String cpf) {
    final digits = cpf.replaceAll(RegExp(r'\D'), '');
    if (digits.length != 11) return false;
    if (RegExp(r'^(\d)\1{10}$').hasMatch(digits)) return false;

    int sum = 0;
    for (int i = 0; i < 9; i++) {
      sum += int.parse(digits[i]) * (10 - i);
    }
    int remainder = (sum * 10) % 11;
    if (remainder == 10 || remainder == 11) remainder = 0;
    if (remainder != int.parse(digits[9])) return false;

    sum = 0;
    for (int i = 0; i < 10; i++) {
      sum += int.parse(digits[i]) * (11 - i);
    }
    remainder = (sum * 10) % 11;
    if (remainder == 10 || remainder == 11) remainder = 0;
    return remainder == int.parse(digits[10]);
  }

  /// Remove formatação, mantém apenas os 11 dígitos.
  static String strip(String cpf) => cpf.replaceAll(RegExp(r'\D'), '');

  /// Formata para exibição: ***.***.*XX-XX
  /// Exibe apenas os últimos 4 dígitos (regra seção 15.3).
  static String mask(String cpf) {
    final d = strip(cpf);
    if (d.length != 11) return cpf;
    return '***.***.${d.substring(6, 9)}-${d.substring(9)}';
  }
}
