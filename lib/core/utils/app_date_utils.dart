import 'package:intl/intl.dart';

class AppDateUtils {
  AppDateUtils._();

  static final _dateFormatter = DateFormat('dd/MM/yyyy', 'pt_BR');
  static final _dateTimeFormatter = DateFormat('dd/MM/yyyy HH:mm', 'pt_BR');
  static final _timeFormatter = DateFormat('HH:mm', 'pt_BR');
  static final _monthYearFormatter = DateFormat('MMMM yyyy', 'pt_BR');

  static String formatDate(DateTime date) => _dateFormatter.format(date);

  static String formatDateTime(DateTime dateTime) =>
      _dateTimeFormatter.format(dateTime);

  static String formatTime(DateTime dateTime) => _timeFormatter.format(dateTime);

  static String formatMonthYear(DateTime date) =>
      _monthYearFormatter.format(date);

  /// Verifica se uma tarefa está atrasada.
  /// Regra: due_date < HOJE AND status NOT IN ('submitted', 'validated',
  /// 'cancelled').
  ///
  /// A comparação é por DIA: uma tarefa com prazo hoje só fica atrasada
  /// amanhã. Comparar com now() a marcava como atrasada à meia-noite do
  /// próprio dia do prazo.
  static bool isOverdue(DateTime dueDate, String status) {
    if (status == 'submitted' ||
        status == 'validated' ||
        status == 'cancelled') {
      return false;
    }
    final agora = DateTime.now();
    final hoje = DateTime(agora.year, agora.month, agora.day);
    final prazo = DateTime(dueDate.year, dueDate.month, dueDate.day);
    return prazo.isBefore(hoje);
  }

  /// Verifica se o prazo está chegando (< 24h).
  static bool isDueSoon(DateTime dueDate) {
    final diff = dueDate.difference(DateTime.now());
    return diff.isNegative == false && diff.inHours < 24;
  }

  static DateTime? parseDate(String? value) {
    if (value == null) return null;
    return DateTime.tryParse(value);
  }
}
