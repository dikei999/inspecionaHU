import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../../../app/routes.dart';
import '../../auth/providers/auth_provider.dart';
import 'membros_hospital_tab.dart';
import 'pedidos_acesso_screen.dart';

/// Gestão de Usuários do hospital.
///
/// Reúne o que NÃO pertence a setor nenhum. Tudo que é de setor — vincular
/// Inspetor, acesso compartilhado, convite já vinculado, convites daquele
/// setor — vive na aba Equipe do próprio setor, que é o único lugar para
/// gerir as pessoas de um setor.
///
/// Aqui ficam só as duas coisas de alcance hospitalar:
///   • Membros  — listar Supervisores e Inspetores, desativar/reativar e
///                convidar alguém sem vínculo prévio com um setor.
///   • Pedidos  — solicitações de acesso pendentes de aprovação.
///
/// Um Supervisor recém-convidado, ainda sem setor, não apareceria em
/// nenhuma aba de setor — é por isso que esta tela existe.
class GestaoUsuariosHospitalScreen extends StatefulWidget {
  const GestaoUsuariosHospitalScreen({super.key});

  @override
  State<GestaoUsuariosHospitalScreen> createState() =>
      _GestaoUsuariosHospitalScreenState();
}

class _GestaoUsuariosHospitalScreenState
    extends State<GestaoUsuariosHospitalScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tab;
  bool _isDirector = false;

  @override
  void initState() {
    super.initState();
    _isDirector = context.read<AuthProvider>().profile?.role == 'director';
    // Só o Diretor resolve pedidos de acesso; o Supervisor vê apenas membros.
    _tab = TabController(length: _isDirector ? 2 : 1, vsync: this);
    _tab.addListener(_onTabChanged);
  }

  @override
  void dispose() {
    _tab.removeListener(_onTabChanged);
    _tab.dispose();
    super.dispose();
  }

  void _onTabChanged() {
    if (_tab.indexIsChanging) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Gestão de Usuários'),
        bottom: TabBar(
          controller: _tab,
          tabs: [
            const Tab(text: 'Membros'),
            if (_isDirector) const Tab(text: 'Pedidos de acesso'),
          ],
        ),
      ),
      // Convidar só faz sentido na aba de membros.
      floatingActionButton: _tab.index == 0
          ? FloatingActionButton.extended(
              onPressed: () => context.push(AppRoutes.convidarUsuario),
              icon: const Icon(Icons.person_add_alt_1),
              label: const Text('Convidar usuário'),
            )
          : null,
      body: TabBarView(
        controller: _tab,
        children: [
          const MembrosHospitalTab(),
          if (_isDirector) const PedidosAcessoScreen(embedded: true),
        ],
      ),
    );
  }
}
