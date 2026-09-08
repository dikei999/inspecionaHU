import 'package:flutter/material.dart';

/// Logo institucional "HU Brasil", exibida ao lado da identidade do
/// InspecionaHU no rodapé do login e no cabeçalho do PDF (bloco 5).
///
/// O arquivo é opcional: se `assets/branding/logo_hu_brasil.png` não estiver
/// presente, o widget simplesmente não ocupa espaço em vez de estourar a
/// tela com o retângulo de erro do Flutter. Assim a tela de login continua
/// funcionando em qualquer build, com ou sem o arquivo.
class HuBrasilLogo extends StatelessWidget {
  static const assetPath = 'assets/branding/logo_hu_brasil.png';

  final double height;

  const HuBrasilLogo({super.key, this.height = 34});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      height: height,
      fit: BoxFit.contain,
      // Ausência do arquivo não pode quebrar a tela.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
