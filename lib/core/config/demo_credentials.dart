/// Credenciais fixas de contas demo, usadas só em desenvolvimento
/// (ver [AppConfig.showDemoLogin] e migration_demo_rpcs.sql).
class DemoCredentials {
  DemoCredentials._();

  static const superAdmin = ('superadmin@demo.com', 'demo1234');
  static const director = ('diretor@demo.com', 'demo1234');
  static const supervisor = ('supervisor@demo.com', 'demo1234');
  static const inspector = ('inspetor@demo.com', 'demo1234');
  static const demoHospitalSigla = 'HU-DEMO';
}
