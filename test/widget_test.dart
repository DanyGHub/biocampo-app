import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import 'package:biocampo_app/core/network/network_status_service.dart';
import 'package:biocampo_app/features/auth/domain/services/auth_service.dart';
import 'package:biocampo_app/features/auth/presentation/screens/login_screen.dart';

void main() {
  testWidgets('CP-Widget: Flujo Limpio de Login y Acceso al Dashboard', (WidgetTester tester) async {
    // 1. Inicializar base de datos y mocks de almacenamiento/sensores
    SharedPreferences.setMockInitialValues({});
    const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      geolocatorChannel,
      (MethodCall call) async {
        if (call.method == 'isLocationServiceEnabled') return false;
        return null;
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geolocatorChannel, null));

    final networkService = NetworkStatusService(
      checkConnectivityFn: () async => [ConnectivityResult.none],
      reachabilityFn: () async => false,
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
    );

    final db = AppDatabase.instance;
    db.clearForTesting();
    await db.initialize();
    final authService = AuthService(database: db);

    // 2. Renderizar pantalla de Login
    await tester.pumpWidget(
      MaterialApp(
        home: LoginScreen(
          authService: authService,
          networkStatusService: networkService,
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3. Verificar elementos limpios de la pantalla de login
    expect(find.text('Iniciar Sesión'), findsNWidgets(2)); // Título y Botón
    expect(find.text('Usuario'), findsOneWidget);
    expect(find.text('Contraseña'), findsOneWidget);

    // 4. Ingresar credenciales
    await tester.enterText(find.byType(TextField).first, 'biologo1');
    await tester.enterText(find.byType(TextField).last, 'BioCampo2026!');
    await tester.pump();

    // 5. Presionar botón Iniciar Sesión
    await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar Sesión'));
    await tester.pumpAndSettle();

    // 6. Verificar acceso exitoso
    expect(authService.isAuthenticated, isTrue);
  });
}
