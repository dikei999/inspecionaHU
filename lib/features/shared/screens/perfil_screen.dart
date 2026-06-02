import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart'
    show FileOptions, PostgrestException, Supabase, UserAttributes;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_constants.dart';
import '../../../core/services/audit_service.dart';
import '../../../core/utils/cpf_utils.dart';
import '../../auth/providers/auth_provider.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  final _db = Supabase.instance.client;
  final _nomeCtrl = TextEditingController();
  final _senhaAtualCtrl = TextEditingController();
  final _novaSenhaCtrl = TextEditingController();
  final _confirmSenhaCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  final _senhaFormKey = GlobalKey<FormState>();

  bool _saving = false;
  bool _savingPassword = false;
  bool _uploadingPhoto = false;
  bool _obscureSenhaAtual = true;
  bool _obscureNova = true;
  bool _obscureConfirm = true;

  @override
  void initState() {
    super.initState();
    final profile = context.read<AuthProvider>().profile;
    if (profile != null) {
      _nomeCtrl.text = profile.fullName;
    }
  }

  @override
  void dispose() {
    _nomeCtrl.dispose();
    _senhaAtualCtrl.dispose();
    _novaSenhaCtrl.dispose();
    _confirmSenhaCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickPhoto() async {
    setState(() => _uploadingPhoto = true);
    try {
      final picker = ImagePicker();
      final picked =
          await picker.pickImage(source: ImageSource.camera, imageQuality: 80);
      if (picked == null || !mounted) {
        setState(() => _uploadingPhoto = false);
        return;
      }

      final auth = context.read<AuthProvider>();
      final uid = auth.profile!.id;

      final compressed = await FlutterImageCompress.compressWithFile(
        picked.path,
        minWidth: 1280,
        minHeight: 1280,
        quality: 75,
        keepExif: false,
      );
      if (compressed == null || !mounted) {
        setState(() => _uploadingPhoto = false);
        return;
      }

      final path = 'avatars/$uid.jpg';
      await _db.storage.from('avatars').uploadBinary(
            path,
            compressed,
            fileOptions: FileOptions(contentType: 'image/jpeg', upsert: true),
          );

      final publicUrl = _db.storage.from('avatars').getPublicUrl(path);
      final error = await auth.updateProfile(photoUrl: publicUrl);

      if (!mounted) return;
      if (error != null) {
        _snack(error, error: true);
      } else {
        await AuditService.log(
          userId: uid,
          action: 'atualizar_foto_perfil',
          entityType: 'profile',
          entityId: uid,
        );
        _snack('Foto atualizada.');
      }
    } catch (_) {
      if (mounted) _snack('Erro ao atualizar foto.', error: true);
    } finally {
      if (mounted) setState(() => _uploadingPhoto = false);
    }
  }

  Future<void> _salvarNome() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      final auth = context.read<AuthProvider>();
      final uid = auth.profile!.id;
      final novoNome = _nomeCtrl.text.trim();
      final error = await auth.updateProfile(fullName: novoNome);
      if (!mounted) return;
      if (error != null) {
        _snack(error, error: true);
      } else {
        await AuditService.log(
          userId: uid,
          action: 'atualizar_perfil',
          entityType: 'profile',
          entityId: uid,
          details: {'full_name': novoNome},
        );
        _snack('Nome atualizado.');
      }
    } catch (_) {
      if (mounted) _snack('Erro ao salvar nome.', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _alterarSenha() async {
    if (!_senhaFormKey.currentState!.validate()) return;
    setState(() => _savingPassword = true);
    try {
      await _db.auth.updateUser(
        UserAttributes(password: _novaSenhaCtrl.text),
      );
      if (!mounted) return;
      final uid = _db.auth.currentUser!.id;
      await AuditService.log(
        userId: uid,
        action: 'alterar_senha',
        entityType: 'profile',
        entityId: uid,
      );
      _senhaAtualCtrl.clear();
      _novaSenhaCtrl.clear();
      _confirmSenhaCtrl.clear();
      _snack('Senha alterada com sucesso.');
    } on PostgrestException catch (e) {
      if (mounted) _snack('Erro: ${e.message}', error: true);
    } catch (_) {
      if (mounted) _snack('Erro ao alterar senha.', error: true);
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  void _snack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final profile = context.watch<AuthProvider>().profile;
    if (profile == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    final initials = profile.fullName
        .split(' ')
        .where((w) => w.isNotEmpty)
        .take(2)
        .map((w) => w[0].toUpperCase())
        .join();

    return Scaffold(
      appBar: AppBar(title: const Text('Meu Perfil')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // ── Avatar ──────────────────────────────────────────────────
            Center(
              child: GestureDetector(
                onTap: _uploadingPhoto ? null : _pickPhoto,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CircleAvatar(
                      radius: 44,
                      backgroundColor: AppColors.primary,
                      backgroundImage: profile.photoUrl != null
                          ? NetworkImage(profile.photoUrl!)
                          : null,
                      child: profile.photoUrl == null
                          ? Text(
                              initials,
                              style: const TextStyle(
                                  fontSize: 24, color: Colors.white),
                            )
                          : null,
                    ),
                    Positioned(
                      bottom: 0,
                      right: -4,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 2),
                        ),
                        child: _uploadingPhoto
                            ? const Padding(
                                padding: EdgeInsets.all(7),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.camera_alt,
                                size: 16, color: Colors.white),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                AppConstants.roleLabel(profile.role),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: AppColors.primary),
              ),
            ),
            const SizedBox(height: 28),

            // ── Seção: Dados pessoais ──────────────────────────────────
            _SectionHeader(title: 'Dados pessoais'),
            const SizedBox(height: 16),
            Form(
              key: _formKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _nomeCtrl,
                    maxLength: 200,
                    textCapitalization: TextCapitalization.words,
                    decoration: const InputDecoration(
                      labelText: 'Nome completo',
                      prefixIcon: Icon(Icons.person_outline),
                    ),
                    validator: (v) => (v == null || v.trim().isEmpty)
                        ? 'Campo obrigatório'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  _ReadOnlyField(
                    label: 'E-mail',
                    value: profile.email,
                    icon: Icons.email_outlined,
                  ),
                  const SizedBox(height: 12),
                  _ReadOnlyField(
                    label: 'CPF',
                    value: CpfUtils.mask(profile.cpf),
                    icon: Icons.badge_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _salvarNome,
                child: _saving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Salvar nome'),
              ),
            ),

            const SizedBox(height: 32),

            // ── Seção: Alterar senha ───────────────────────────────────
            _SectionHeader(title: 'Alterar senha'),
            const SizedBox(height: 16),
            Form(
              key: _senhaFormKey,
              child: Column(
                children: [
                  TextFormField(
                    controller: _senhaAtualCtrl,
                    obscureText: _obscureSenhaAtual,
                    decoration: InputDecoration(
                      labelText: 'Senha atual',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureSenhaAtual
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () => setState(
                            () => _obscureSenhaAtual = !_obscureSenhaAtual),
                      ),
                    ),
                    validator: (v) => (v == null || v.isEmpty)
                        ? 'Campo obrigatório'
                        : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _novaSenhaCtrl,
                    obscureText: _obscureNova,
                    decoration: InputDecoration(
                      labelText: 'Nova senha',
                      prefixIcon: const Icon(Icons.lock_reset_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureNova
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _obscureNova = !_obscureNova),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.length < 6) ? 'Mínimo 6 caracteres' : null,
                  ),
                  const SizedBox(height: 12),
                  TextFormField(
                    controller: _confirmSenhaCtrl,
                    obscureText: _obscureConfirm,
                    decoration: InputDecoration(
                      labelText: 'Confirmar nova senha',
                      prefixIcon: const Icon(Icons.lock_outlined),
                      suffixIcon: IconButton(
                        icon: Icon(_obscureConfirm
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined),
                        onPressed: () =>
                            setState(() => _obscureConfirm = !_obscureConfirm),
                      ),
                    ),
                    validator: (v) => v != _novaSenhaCtrl.text
                        ? 'As senhas não coincidem'
                        : null,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 48,
              child: ElevatedButton(
                onPressed: _savingPassword ? null : _alterarSenha,
                child: _savingPassword
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Alterar senha'),
              ),
            ),

            const SizedBox(height: 32),

            // ── Sair ────────────────────────────────────────────────────
            OutlinedButton.icon(
              onPressed: () => context.read<AuthProvider>().signOut(),
              icon: const Icon(Icons.logout, color: AppColors.nonCompliant),
              label: const Text('Sair da conta'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.nonCompliant,
                side: const BorderSide(color: AppColors.nonCompliant),
                minimumSize: const Size(double.infinity, 48),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(width: 12),
        const Expanded(child: Divider()),
      ],
    );
  }
}

class _ReadOnlyField extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  const _ReadOnlyField({required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon),
        filled: true,
        fillColor: AppColors.background,
        enabled: false,
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.border, width: 0.5),
        ),
      ),
      child: Text(
        value,
        style: Theme.of(context)
            .textTheme
            .bodyMedium
            ?.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}
