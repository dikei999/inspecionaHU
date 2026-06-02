import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseService {
  SupabaseService._();

  static const String supabaseUrl = 'https://xccmdnwexdkevrlpynio.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9'
      '.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhjY21kbndleGRrZXZybHB5bmlvIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzMTYwODUsImV4cCI6MjA4OTg5MjA4NX0'
      '._YNgH7mzjCUQ20LHDBgT-l4i1Y65a_zYBPH5-omt8R0';

  /// Cliente principal — use em toda chamada ao banco/auth/storage.
  /// NUNCA exponha a service_role_key no código Flutter.
  static SupabaseClient get client => Supabase.instance.client;

  static GoTrueClient get auth => client.auth;

  static SupabaseStorageClient get storage => client.storage;
}
