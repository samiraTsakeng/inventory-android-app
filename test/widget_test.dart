import 'package:flutter_test/flutter_test.dart';

import 'package:wise_inventory/main.dart';

void main() {
  test('MyApp démarre sur l\'écran de connexion par défaut', () {
    expect(const MyApp().initialRoute, '/');
  });

  test('MyApp accepte une route initiale', () {
    expect(const MyApp(initialRoute: '/adjustment-entry').initialRoute,
        '/adjustment-entry');
  });
}
