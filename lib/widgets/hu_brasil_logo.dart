import 'package:flutter/material.dart';

/// Logo institucional "HU Brasil", exibida ao lado da identidade do
/// InspecionaHU no rodapé do login e no cabeçalho do PDF (bloco 5).
///
/// O arquivo é opcional: se `assets/branding/logo_hu_brasil.png` não estiver
/// presente, o widget simplesmente não ocupa espaço em vez de estourar a
/// tela com o retângulo de erro do Flutter. Assim a tela de login continua
/// funcionando em qualquer build, com ou sem o arquivo.
///
/// SOBRE O TAMANHO — o arquivo é um quadrado de 500×500 com o desenho
/// centralizado numa faixa de 424×124, ou seja, a arte ocupa só ~25% da
/// altura da imagem; o resto é margem transparente. Dimensionar por altura
/// (`height: 30`) renderizava a marca com ~7px reais e ela sumia. Por isso
/// o widget é medido por LARGURA, que é a dimensão que a arte de fato
/// preenche, e a altura da caixa é derivada da proporção do arquivo.
class HuBrasilLogo extends StatelessWidget {
  static const assetPath = 'assets/branding/logo_hu_brasil.png';

  /// Proporção do quadro do arquivo (500×500 = 1.0). A arte interna é bem
  /// mais larga que alta, então a caixa reserva a altura do quadro inteiro.
  static const _aspectRatio = 1.0;

  /// Fração da altura da caixa realmente ocupada pelo desenho (~25%).
  /// Serve para o chamador saber a altura ÓPTICA e alinhar direito.
  static const alturaUtilFracao = 0.248;

  /// Largura da caixa. A altura sai daqui pela proporção do arquivo.
  final double width;

  const HuBrasilLogo({super.key, this.width = 132});

  /// Altura visível aproximada da arte, para alinhar com elementos vizinhos.
  double get alturaOptica => width * _aspectRatio * alturaUtilFracao;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      assetPath,
      width: width,
      fit: BoxFit.contain,
      // Ausência do arquivo não pode quebrar a tela.
      errorBuilder: (_, _, _) => const SizedBox.shrink(),
    );
  }
}
