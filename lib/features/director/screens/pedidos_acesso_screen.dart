import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show Supabase;
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_dimensions.dart';
import '../../../core/models/access_request.dart';
import '../../../core/models/profile.dart';
import '../../../core/models/sector.dart';
import '../../../core/services/audit_service.dart';
import '../../auth/providers/auth_provider.dart';

class PedidosAcessoScreen extends StatefulWidget {
  /// Quando true a tela é renderizada como aba dentro de outra Scaffold
  /// (Equipe) — sem AppBar própria. A lógica de negócio é a mesma.
  final bool embedded;

  const PedidosAcessoScreen({super.key, this.embedded = false});

  @override
  State<PedidosAcessoScreen> createState() => _PedidosAcessoScreenState();
}

class _PedidosAcessoScreenState extends State<PedidosAcessoScreen> {
  final _db = Supabase.instance.client;

  bool _loading = true;
  List<_RequestView> _requests = [];
  String? _hospitalId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final profile = context.read<AuthProvider>().profile;
    _hospitalId = profile?.hospitalId;
    if (_hospitalId == null) {
      // Perfil ainda nao carregado: encerra o loading para
      // a tela nao ficar presa no skeleton indefinidamente.
      if (mounted) setState(() => _loading = false);
      return;
    }

    try {
      // Busca setores do hospital para filtrar pedidos relevantes
      final setoresData = await _db
          .from('sectors')
          .select('id')
          .eq('hospital_id', _hospitalId!);

      final sectorIds =
          setoresData.map((s) => s['id'] as String).toList();

      if (sectorIds.isEmpty) {
        if (mounted) setState(() => _loading = false);
        return;
      }

      final reqData = await _db
          .from('access_requests')
          .select()
          .inFilter('sector_id', sectorIds)
          .eq('status', 'pending')
          .order('requested_at', ascending: false);

      // Enriquece com nomes de setor e solicitante
      final requesterIds =
          reqData.map((r) => r['requester_id'] as String).toSet().toList();
      final reqSectorIds =
          reqData.map((r) => r['sector_id'] as String).toSet().toList();

      Map<String, Profile> profiles = {};
      if (requesterIds.isNotEmpty) {
        final profilesData = await _db
            .from('profiles')
            .select('id, full_name, cpf, email')
            .inFilter('id', requesterIds);
        for (final p in profilesData) {
          profiles[p['id'] as String] = Profile.fromJson({
            ...p,
            'status': 'active',
            'created_at': DateTime.now().toIso8601String(),
          });
        }
      }

      Map<String, Sector> sectors = {};
      if (reqSectorIds.isNotEmpty) {
        final sectorsData = await _db
            .from('sectors')
            .select()
            .inFilter('id', reqSectorIds);
        for (final s in sectorsData) {
          final sec = Sector.fromJson(s);
          sectors[sec.id] = sec;
        }
      }

      if (mounted) {
        setState(() {
          _requests = reqData.map((r) {
            final req = AccessRequest.fromJson(r);
            return _RequestView(
              request: req,
              requester: profiles[req.requesterId],
              sector: sectors[req.sectorId],
            );
          }).toList();
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _resolve(
      _RequestView item, bool approve) async {
    final auth = context.read<AuthProvider>();
    final profile = auth.profile!;
    final now = DateTime.now().toIso8601String();

    try {
      await _db.from('access_requests').update({
        'status': approve ? 'approved' : 'denied',
        'resolved_at': now,
        'resolved_by': profile.id,
      }).eq('id', item.request.id);

      if (approve) {
        // Cria ou atualiza entrada em sector_access
        await _db.from('sector_access').upsert({
          'sector_id': item.request.sectorId,
          'supervisor_id': item.request.requesterId,
          'can_view': item.request.canView,
          'can_edit': item.request.canEdit,
          'granted_by': profile.id,
        }, onConflict: 'sector_id,supervisor_id');
      }

      // Notifica o solicitante
      await _db.from('notifications').insert({
        'user_id': item.request.requesterId,
        'hospital_id': _hospitalId,
        'type': approve ? 'access_approved' : 'access_denied',
        'title':
            approve ? 'Acesso aprovado' : 'Acesso negado',
        'body':
            '${approve ? 'Seu pedido de acesso' : 'Seu pedido de acesso'} ao setor "${item.sector?.name}" foi ${approve ? 'aprovado' : 'negado'}.',
        'read': false,
      });

      await AuditService.log(
        userId: profile.id,
        hospitalId: _hospitalId,
        action:
            '${approve ? 'aprovar' : 'negar'}_pedido_acesso',
        entityType: 'access_request',
        entityId: item.request.id,
        details: {
          'sector_id': item.request.sectorId,
          'requester_id': item.request.requesterId,
        },
      );

      if (mounted) {
        _showSnack(approve ? 'Acesso aprovado.' : 'Pedido negado.');
        _load();
      }
    } catch (_) {
      if (mounted) _showSnack('Erro ao processar pedido.', error: true);
    }
  }

  void _showSnack(String msg, {bool error = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: error ? AppColors.nonCompliant : AppColors.compliant,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final fmt = DateFormat('dd/MM/yyyy HH:mm');

    return Scaffold(
      backgroundColor: widget.embedded ? Colors.transparent : null,
      appBar:
          widget.embedded ? null : AppBar(title: const Text('Pedidos de Acesso')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _requests.isEmpty
                  ? const Center(
                      child: Text('Nenhum pedido de acesso pendente.'))
                  : ListView.builder(
                      padding: const EdgeInsets.all(
                          AppDimensions.screenPadding),
                      itemCount: _requests.length,
                      itemBuilder: (ctx, i) {
                        final item = _requests[i];
                        return Card(
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.requester?.fullName ?? '—',
                                  style: Theme.of(context)
                                      .textTheme
                                      .titleMedium,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Solicitou acesso ao setor: ${item.sector?.name ?? '—'}',
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall,
                                ),
                                const SizedBox(height: 4),
                                Row(
                                  children: [
                                    if (item.request.canView)
                                      const Padding(
                                        padding: EdgeInsets.only(right: 6),
                                        child: _PermLabel(
                                            label: 'Visualização',
                                            color: AppColors.primary),
                                      ),
                                    if (item.request.canEdit)
                                      const _PermLabel(
                                          label: 'Modificação',
                                          color: AppColors.compliant),
                                  ],
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  fmt.format(item.request.requestedAt),
                                  style: Theme.of(context)
                                      .textTheme
                                      .bodySmall
                                      ?.copyWith(
                                          color: AppColors.textSecondary),
                                ),
                                const SizedBox(height: 12),
                                Row(
                                  children: [
                                    Expanded(
                                      child: OutlinedButton(
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor:
                                              AppColors.nonCompliant,
                                          side: const BorderSide(
                                              color: AppColors.nonCompliant),
                                        ),
                                        onPressed: () =>
                                            _resolve(item, false),
                                        child: const Text('Negar'),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: ElevatedButton(
                                        onPressed: () =>
                                            _resolve(item, true),
                                        child: const Text('Aprovar'),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
            ),
    );
  }
}

class _RequestView {
  final AccessRequest request;
  final Profile? requester;
  final Sector? sector;
  _RequestView({required this.request, this.requester, this.sector});
}

class _PermLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _PermLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(label,
          style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600)),
    );
  }
}
