import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../../../app/routes.dart';
import '../../../core/config/app_config.dart';
import '../../../core/config/demo_credentials.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/services/offline_sync_service.dart';
import '../../../core/constants/app_strings.dart';
import '../../../widgets/hu_brasil_logo.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  bool _obscure = true;
  bool _loading = false;
  String? _error;

  /// Rede de segurança (item 1): só aparece SEM conexão e COM perfil salvo
  /// neste aparelho. Nas duas outras combinações o botão seria ruído.
  bool _podeEntrarOffline = false;

  @override
  void initState() {
    super.initState();
    _checarEntradaOffline();
    // A faixa de conexão já observa o connectivity_plus; reaproveitar o
    // mesmo sinal evita um segundo monitor só para isto.
    OfflineSyncService.online.addListener(_checarEntradaOffline);
  }

  Future<void> _checarEntradaOffline() async {
    final temCache = await AuthProvider.temPerfilEmCache();
    final semRede = !OfflineSyncService.online.value;
    if (!mounted) return;
    setState(() => _podeEntrarOffline = temCache && semRede);
  }

  Future<void> _continuarOffline() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    final erro = await context.read<AuthProvider>().entrarOfflineManualmente();
    if (mounted) {
      setState(() {
        _loading = false;
        _error = erro;
      });
    }
  }

  @override
  void dispose() {
    OfflineSyncService.online.removeListener(_checarEntradaOffline);
    _emailCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await _doLogin(_emailCtrl.text.trim(), _passwordCtrl.text);
  }

  /// Login rápido com uma conta demo fixa (ver DemoCredentials).
  /// Ferramenta de desenvolvimento — atrás de AppConfig.showDemoLogin.
  Future<void> _demoLogin((String, String) credentials) async {
    _emailCtrl.text = credentials.$1;
    _passwordCtrl.text = credentials.$2;
    await _doLogin(credentials.$1, credentials.$2);
  }

  Future<void> _doLogin(String email, String password) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final error = await context.read<AuthProvider>().signIn(
      email: email,
      password: password,
    );

    if (mounted) {
      setState(() {
        _loading = false;
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        color: AppColors.background,
        child: CustomPaint(
          painter: _MedicalCrossPatternPainter(),
          child: SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // ── Identidade institucional ─────────────────────
                        Center(
                          child: Image.asset(
                            'assets/branding/logo_full.png',
                            height: 76,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Center(
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary50,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: AppColors.primary100,
                                width: 0.8,
                              ),
                            ),
                            child: const Text(
                              'GESTÃO DE CONFORMIDADE NR-32',
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                color: AppColors.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        Center(
                          child: Text(
                            AppStrings.assinaturaInstitucional,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 14,
                              color: AppColors.textSecondary,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // ── Card do formulário ───────────────────────────
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: AppColors.surface,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: AppColors.border,
                              width: 0.5,
                            ),
                            boxShadow: AppShadows.card,
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Text(
                                'Entrar na conta',
                                style: Theme.of(context).textTheme.titleLarge,
                              ),
                              // Estado offline evidente, antes dos campos.
                              if (_podeEntrarOffline) ...[
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.pending50,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                        color: AppColors.pending100),
                                  ),
                                  child: Row(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Icon(Icons.wifi_off,
                                          size: 18,
                                          color: AppColors.pending),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              'Sem conexão',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .titleSmall
                                                  ?.copyWith(
                                                    color: AppColors.pending,
                                                    fontWeight:
                                                        FontWeight.w700,
                                                  ),
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              'Há dados salvos neste '
                                              'aparelho. É possível entrar '
                                              'e trabalhar offline.',
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall
                                                  ?.copyWith(
                                                      color:
                                                          AppColors.pending),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 14),
                              ],

                              const SizedBox(height: 16),
                              TextFormField(
                                controller: _emailCtrl,
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: TextInputAction.next,
                                decoration: const InputDecoration(
                                  labelText: 'E-mail',
                                  prefixIcon: Icon(Icons.email_outlined),
                                ),
                                validator: (v) =>
                                    (v == null || v.trim().isEmpty)
                                    ? 'Campo obrigatório'
                                    : null,
                              ),
                              const SizedBox(height: 12),
                              TextFormField(
                                controller: _passwordCtrl,
                                obscureText: _obscure,
                                textInputAction: TextInputAction.done,
                                onFieldSubmitted: (_) => _submit(),
                                decoration: InputDecoration(
                                  labelText: 'Senha',
                                  prefixIcon: const Icon(Icons.lock_outlined),
                                  suffixIcon: IconButton(
                                    icon: Icon(
                                      _obscure
                                          ? Icons.visibility_off_outlined
                                          : Icons.visibility_outlined,
                                    ),
                                    onPressed: () =>
                                        setState(() => _obscure = !_obscure),
                                  ),
                                ),
                                validator: (v) => (v == null || v.isEmpty)
                                    ? 'Campo obrigatório'
                                    : null,
                              ),

                              // ── Esqueci a senha ──────────────────────────
                              Align(
                                alignment: Alignment.centerRight,
                                child: TextButton(
                                  onPressed: () =>
                                      context.push(AppRoutes.forgotPassword),
                                  style: TextButton.styleFrom(
                                    minimumSize: Size.zero,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4,
                                      vertical: 8,
                                    ),
                                  ),
                                  child: const Text('Esqueci minha senha'),
                                ),
                              ),

                              // ── Erro ─────────────────────────────────────
                              if (_error != null) ...[
                                const SizedBox(height: 4),
                                Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: AppColors.nonCompliant50,
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: AppColors.nonCompliant.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.error_outline,
                                        color: AppColors.nonCompliant,
                                        size: 18,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          _error!,
                                          style: const TextStyle(
                                            color: AppColors.nonCompliant,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 12),

                              // ── Botão entrar ──────────────────────────────
                              Container(
                                height: 48,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  boxShadow: _loading
                                      ? null
                                      : AppShadows.primaryGlow,
                                ),
                                child: _podeEntrarOffline
                                    // Sem rede e com perfil salvo, entrar
                                    // com senha vai falhar de qualquer
                                    // jeito. O botão principal passa a ser
                                    // o que funciona.
                                    ? ElevatedButton.icon(
                                        onPressed: _loading
                                            ? null
                                            : _continuarOffline,
                                        icon: const Icon(Icons.wifi_off,
                                            size: 18),
                                        label:
                                            const Text('Continuar offline'),
                                      )
                                    : ElevatedButton(
                                        onPressed: _loading ? null : _submit,
                                        child: _loading
                                            ? const SizedBox(
                                                width: 20,
                                                height: 20,
                                                child:
                                                    CircularProgressIndicator(
                                                  strokeWidth: 2,
                                                  color: Colors.white,
                                                ),
                                              )
                                            : const Text('Entrar'),
                                      ),
                              ),

                              // Com o offline em primeiro plano, entrar com
                              // senha continua acessível — só recua.
                              if (_podeEntrarOffline) ...[
                                const SizedBox(height: 8),
                                OutlinedButton(
                                  onPressed: _loading ? null : _submit,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.textSecondary,
                                    side: const BorderSide(
                                        color: AppColors.borderStrong),
                                    minimumSize:
                                        const Size(double.infinity, 44),
                                  ),
                                  child: const Text('Tentar entrar online'),
                                ),
                              ],
                            ],
                          ),
                        ),

                        const SizedBox(height: 14),

                        // ── Modo Demo (ferramenta de desenvolvimento) ────
                        // Recolhido por padrão: aberto, era ele que fazia a
                        // tela passar da altura do celular. O bloco continua
                        // aqui, a um toque de distância.
                        // Sem rede, o login demo nao funciona (ele autentica
                        // no servidor) e so ocuparia altura. Some junto com
                        // o link de criar conta, que tambem exige internet.
                        if (AppConfig.showDemoLogin && !_podeEntrarOffline) ...[
                          _DemoLoginCard(
                            loading: _loading,
                            onSelect: _demoLogin,
                          ),
                          const SizedBox(height: 10),
                        ],

                        // ── Link criar conta ─────────────────────────────
                        if (!_podeEntrarOffline)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              'Não tem conta?',
                              style: TextStyle(
                                fontSize: 14,
                                color: AppColors.textSecondary,
                              ),
                            ),
                            TextButton(
                              onPressed: () => context.push(AppRoutes.cadastro),
                              style: TextButton.styleFrom(
                                foregroundColor: AppColors.primary,
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 10,
                                ),
                              ),
                              child: const Text(
                                'Criar conta',
                                style: TextStyle(
                                  fontWeight: FontWeight.w700,
                                  decoration: TextDecoration.underline,
                                ),
                              ),
                            ),
                          ],
                        ),

                        // ── Rodapé institucional ─────────────────────────
                        // Identidade do InspecionaHU ao lado da logo HU
                        // Brasil (bloco 5). A logo some sozinha se o arquivo
                        // não estiver no bundle — a tela não quebra.
                        const SizedBox(height: 6),
                        // Só a HU Brasil: o ícone do HU ao lado repetia a
                        // identidade que já está na logo grande do topo.
                        // O arquivo é um quadrado com ~75% de margem
                        // transparente, então o ClipRect recorta a faixa útil.
                        Center(
                          child: ClipRect(
                            child: Align(
                              alignment: Alignment.center,
                              heightFactor: HuBrasilLogo.alturaUtilFracao * 1.3,
                              child: const HuBrasilLogo(width: 168),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Card discreto de login rápido com contas fixas — ferramenta de
/// desenvolvimento, some quando AppConfig.showDemoLogin = false.
class _DemoLoginCard extends StatefulWidget {
  final bool loading;
  final void Function((String, String) credentials) onSelect;

  const _DemoLoginCard({required this.loading, required this.onSelect});

  @override
  State<_DemoLoginCard> createState() => _DemoLoginCardState();
}

class _DemoLoginCardState extends State<_DemoLoginCard> {
  /// Recolhido por padrão. Aberto, os quatro botões de perfil somavam ~90px
  /// e eram a maior causa de a tela de login passar da altura do celular.
  /// O bloco continua aqui — a um toque de distância.
  bool _aberto = false;

  bool get loading => widget.loading;
  void Function((String, String)) get onSelect => widget.onSelect;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceSubtle,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _aberto = !_aberto),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade600,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: const Text(
                    'DEMO',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: Colors.white,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Login rápido para testes',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
                Icon(
                  _aberto ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
          if (_aberto) ...[
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _DemoButton(
                  label: 'Super Admin',
                  onPressed: loading
                      ? null
                      : () => onSelect(DemoCredentials.superAdmin),
                ),
                _DemoButton(
                  label: 'Diretor',
                  onPressed: loading
                      ? null
                      : () => onSelect(DemoCredentials.director),
                ),
                _DemoButton(
                  label: 'Supervisor',
                  onPressed: loading
                      ? null
                      : () => onSelect(DemoCredentials.supervisor),
                ),
                _DemoButton(
                  label: 'Inspetor',
                  onPressed: loading
                      ? null
                      : () => onSelect(DemoCredentials.inspector),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _DemoButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;

  const _DemoButton({required this.label, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: onPressed,
      style: OutlinedButton.styleFrom(
        foregroundColor: AppColors.primary,
        backgroundColor: Colors.white,
        side: const BorderSide(color: AppColors.primary200),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        textStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
      ),
      child: Text('Entrar como $label'),
    );
  }
}

/// Padrão sutil de cruzes (motivo hospitalar) sobre o fundo claro do login.
class _MedicalCrossPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.035)
      ..style = PaintingStyle.fill;

    const spacing = 72.0;
    const arm = 5.0; // meia-largura do braço da cruz
    const len = 14.0; // meio-comprimento da cruz

    for (double y = spacing / 2; y < size.height; y += spacing) {
      // desloca colunas alternadas para quebrar a grade
      final offsetX = ((y ~/ spacing) % 2 == 0) ? 0.0 : spacing / 2;
      for (double x = spacing / 2 + offsetX; x < size.width; x += spacing) {
        final path = Path()
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(x, y),
                width: arm * 2,
                height: len * 2,
              ),
              const Radius.circular(2),
            ),
          )
          ..addRRect(
            RRect.fromRectAndRadius(
              Rect.fromCenter(
                center: Offset(x, y),
                width: len * 2,
                height: arm * 2,
              ),
              const Radius.circular(2),
            ),
          );
        canvas.drawPath(path, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
