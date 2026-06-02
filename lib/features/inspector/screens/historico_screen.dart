import 'package:flutter/material.dart';

class HistoricoScreen extends StatelessWidget {
  const HistoricoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Meu Histórico')),
      body: const Center(child: Text('Histórico de inspeções — em desenvolvimento')),
    );
  }
}
