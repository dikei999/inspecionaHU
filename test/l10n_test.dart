import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';

void main() {
  setUpAll(() async => initializeDateFormatting('pt_BR'));

  test('intl formata mes e dia em portugues', () {
    final d = DateTime(2026, 3, 9); // segunda-feira
    expect(DateFormat('MMMM yyyy', 'pt_BR').format(d), contains('março'));
    expect(DateFormat('EEEE', 'pt_BR').format(d), contains('segunda'));
  });

  testWidgets('date picker do Material sai em pt_BR', (tester) async {
    await tester.pumpWidget(MaterialApp(
      locale: const Locale('pt', 'BR'),
      supportedLocales: const [Locale('pt', 'BR')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Builder(
        builder: (ctx) => TextButton(
          onPressed: () => showDatePicker(
            context: ctx,
            initialDate: DateTime(2026, 3, 9),
            firstDate: DateTime(2026, 1, 1),
            lastDate: DateTime(2026, 12, 31),
          ),
          child: const Text('abrir'),
        ),
      ),
    ));
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();

    // Rótulos do date picker em português, não em inglês.
    expect(find.text('Cancelar'), findsOneWidget);
    expect(find.text('CANCEL'), findsNothing);
    expect(find.text('OK'), findsOneWidget);
  });
}
