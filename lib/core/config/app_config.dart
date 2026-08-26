/// Flags de configuração compile-time do app.
class AppConfig {
  AppConfig._();

  /// Mostra o card "Modo Demo" no login e o "Painel Demo" no Super Admin.
  /// Ferramenta de desenvolvimento — mudar para false antes de gerar o
  /// APK final de produção.
  static const bool showDemoLogin = true;
}
