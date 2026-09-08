import 'package:flutter_test/flutter_test.dart';
import 'package:inspecionahu/core/constants/app_strings.dart';

/// Item 3 — a tela de login não deve rolar em celular comum.
///
/// O teste não monta a LoginScreen real (ela depende de Supabase
/// inicializado e de Provider). Ele guarda o ORÇAMENTO VERTICAL do layout:
/// se alguém acrescentar um bloco à tela sem compensar em outro lugar, a
/// soma passa do limite e o teste quebra, apontando o que aconteceu.
void main() {
  group('assinatura institucional', () {
    test('é a string padronizada, sem menção a EBSERH', () {
      expect(AppStrings.assinaturaInstitucional,
          'HU Brasil · Hospitais Universitários Federais');
      expect(AppStrings.assinaturaInstitucional.contains('EBSERH'), isFalse);
    });
  });

  group('orçamento vertical do login', () {
    // Alturas dos blocos após a reorganização, com o bloco demo recolhido.
    const blocos = <String, double>{
      'padding vertical (14*2)': 28,
      'logo_full': 76,
      'gap': 10,
      'chip NR-32': 27,
      'gap ': 8,
      'assinatura institucional': 20,
      'gap  ': 16,
      'card do formulário': 270,
      'gap   ': 14,
      'card demo (recolhido)': 44,
      'gap    ': 10,
      'linha criar conta': 40,
      'gap     ': 6,
      'rodapé HU Brasil': 54,
    };

    final total = blocos.values.reduce((a, b) => a + b);

    // Altura útil = altura da tela menos status bar e navigation bar (~90px).
    const telasComuns = <String, double>{
      'Pixel 5': 851,
      'Galaxy S21': 800,
      'Pixel 4a': 780,
    };

    for (final tela in telasComuns.entries) {
      test('cabe sem rolagem no ${tela.key}', () {
        final util = tela.value - 90;
        expect(total, lessThanOrEqualTo(util),
            reason: 'conteúdo ${total.toStringAsFixed(0)}px não cabe em '
                '${util.toStringAsFixed(0)}px de área útil');
      });
    }

    // Estado offline: entram o aviso "Sem conexão" (86) + gap (14) + o
    // botão secundário (44+8); saem o bloco demo (44+10) e o link de criar
    // conta (40+6), que exigem internet e não funcionariam ali.
    final totalOffline = total + 86 + 14 + 44 + 8 - 54 - 46;

    for (final tela in telasComuns.entries) {
      test('estado offline cabe sem rolagem no ${tela.key}', () {
        final util = tela.value - 90;
        expect(totalOffline, lessThanOrEqualTo(util),
            reason: 'com o aviso de sem conexão o conteúdo passou de '
                '${util.toStringAsFixed(0)}px');
      });
    }

    test('mesmo com o bloco demo aberto continua cabendo no Pixel 5', () {
      // Aberto, o bloco cresce ~90px (rótulo + 4 botões em duas linhas).
      // Depois da reorganização isso ainda cabe num celular comum; o
      // recolhimento existe como folga para telas menores, não como
      // condição para a tela não rolar.
      const acrescimoAberto = 90.0;
      final utilPixel5 = 851 - 90;
      expect(total + acrescimoAberto, lessThanOrEqualTo(utilPixel5));
    });
  });
}
