import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import 'package:biocampo_app/core/network/network_status_service.dart';
import 'package:biocampo_app/core/theme/app_theme.dart';
import 'package:biocampo_app/features/auth/domain/services/auth_service.dart';
import 'package:biocampo_app/features/auth/presentation/screens/login_screen.dart';
import 'package:biocampo_app/features/home/presentation/screens/home_screen.dart';

class _TestMemoryTileProvider extends TileProvider {
  _TestMemoryTileProvider();

  static final Uint8List _transparent1x1Png = Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
    0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
    0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
    0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
    0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
    0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
  ]);

  @override
  ImageProvider getImage(TileCoordinates coordinates, TileLayer options) {
    return MemoryImage(_transparent1x1Png);
  }
}

void main() {
  testWidgets(
      'Integración Visual Sprint 2 (HU-05 Mapa Real, HU-06 Cola FIFO, HU-07 Cifrado AES-256) con permisos e internet',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      geolocatorChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return 2; // whileInUse
          case 'requestPermission':
            return 2;
          case 'getCurrentPosition':
            return <String, dynamic>{
              'latitude': 21.8853,
              'longitude': -102.2916,
              'altitude': 1888.0,
              'accuracy': 3.2,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'heading': 0.0,
              'heading_accuracy': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
              'altitude_accuracy': 1.0,
              'vertical_speed': 0.0,
              'vertical_speed_accuracy': 0.0,
              'is_mocked': false,
            };
          default:
            return null;
        }
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geolocatorChannel, null));

    final networkService = NetworkStatusService(
      checkConnectivityFn: () async => [ConnectivityResult.wifi],
      reachabilityFn: () async => true,
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
    );

    final db = AppDatabase.instance;
    db.clearForTesting();
    await db.initialize();
    final authService = AuthService(database: db);

    // Simular ventana estrecha tipo pestaña VSCode / móvil (390x844)
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.solarLightTheme,
        home: LoginScreen(
          authService: authService,
          networkStatusService: networkService,
          mapTileProvider: _TestMemoryTileProvider(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 1. Iniciar sesión con cuenta de docente evaluadora
    await tester.enterText(find.byType(TextField).first, 'docente_eval');
    await tester.enterText(find.byType(TextField).last, 'BioCampo2026!');
    await tester.tap(find.widgetWithText(ElevatedButton, 'Iniciar Sesión'));
    await tester.pumpAndSettle();

    expect(find.text('Mapa y GPS'), findsOneWidget);
    expect(find.textContaining('Offline · 0 cola'), findsOneWidget);

    // 2. Probar eventos de ratón (MouseTracker) sobre la UI principal
    final mouseGesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouseGesture.addPointer(location: Offset.zero);
    addTearDown(mouseGesture.removePointer);
    await mouseGesture.moveTo(const Offset(200, 100));
    await tester.pump();
    await mouseGesture.moveTo(const Offset(250, 350));
    await tester.pump();

    // 3. Crear un reporte de especie protegida (HU-02 + HU-04 + HU-07 + HU-05 Mapa Real)
    await tester.tap(find.text('Iniciar Registro de Reporte'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Jaguar');
    await tester.pumpAndSettle();
    expect(find.textContaining('Jaguar (Panthera onca)'), findsOneWidget);
    await tester.tap(find.textContaining('Jaguar (Panthera onca)').first);
    await tester.pumpAndSettle();

    // Verificar detección automática de especie protegida HU-07
    expect(find.textContaining('Peligro de Extinción'), findsOneWidget);

    // Avanzar a Fase 2 (GPS + Vista previa de Mapa Real)
    await tester.ensureVisible(find.text('Siguiente: GPS ➔'));
    await tester.tap(find.text('Siguiente: GPS ➔'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('EN LÍNEA'), findsOneWidget);

    // Avanzar a Fase 3 (Fotos con botón "Capturar")
    await tester.ensureVisible(find.text('Siguiente: Fotos ➔'));
    await tester.tap(find.text('Siguiente: Fotos ➔'));
    await tester.pumpAndSettle();
    expect(find.text('Capturar'), findsOneWidget);

    // Avanzar a Fase 4 (Confirmación) y Guardar
    await tester.ensureVisible(find.text('Siguiente: Confirmar ➔'));
    await tester.tap(find.text('Siguiente: Confirmar ➔'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Cifrado AES-256-GCM'), findsOneWidget);

    await tester.ensureVisible(find.text('Guardar Reporte'));
    await tester.tap(find.text('Guardar Reporte'));
    await tester.pumpAndSettle();

    // 4. Verificar en Tab 2 (Reportes Guardados): Cola FIFO (HU-06) y Cifrado (HU-07)
    expect(find.textContaining('Offline · 1 cola'), findsOneWidget);
    expect(find.text('PENDIENTE · Cola FIFO'), findsOneWidget);
    expect(find.textContaining('Especie Protegida · Coordenadas Cifradas'), findsOneWidget);

    // Revelar coordenadas autorizadas
    await tester.ensureVisible(find.text('Revelar Exactas'));
    await tester.tap(find.text('Revelar Exactas'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Coordenadas Exactas Descifradas'), findsOneWidget);

    // Abrir Cola / Red y sincronizar FIFO a Online
    await tester.ensureVisible(find.text('Cola / Red'));
    await tester.tap(find.text('Cola / Red'));
    await tester.pumpAndSettle();
    expect(find.text('Cola de Sincronización (HU-06)'), findsOneWidget);

    await tester.tap(find.textContaining('Modo Campo Offline'));
    await tester.pumpAndSettle();
    expect(find.textContaining('todos los muestreos están sincronizados'), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded).last);
    await tester.pumpAndSettle();
    expect(find.text('SINCRONIZADO'), findsOneWidget);

    // 5. Navegar a Tab 3 (Mapa y GPS) y probar selector de capas en Mapa Real
    await tester.tap(find.text('Mapa y GPS'));
    await tester.pumpAndSettle();
    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.byTooltip('Capas del mapa'), findsOneWidget);

    await tester.tap(find.byTooltip('Capas del mapa'));
    await tester.pumpAndSettle();
    expect(find.text('Tipo de Mapa Base'), findsOneWidget);
    await tester.tap(find.text('Topográfico'));
    await tester.pumpAndSettle();
  });

  testWidgets('Denegación de mapa sin permisos de ubicación y desbloqueo mediante botón funcional',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    var currentPermission = 0; // denied inicialmente
    var requestCalls = 0;

    const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      geolocatorChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
            return currentPermission;
          case 'requestPermission':
            requestCalls++;
            // Primera llamada (carga inicial) simula denegación; segundo intento (botón) otorga permiso
            if (requestCalls >= 2) {
              currentPermission = 2; // whileInUse
            }
            return currentPermission;
          case 'getCurrentPosition':
            return <String, dynamic>{
              'latitude': 21.8853,
              'longitude': -102.2916,
              'altitude': 1888.0,
              'accuracy': 4.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'heading': 0.0,
              'heading_accuracy': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
              'altitude_accuracy': 1.0,
              'vertical_speed': 0.0,
              'vertical_speed_accuracy': 0.0,
              'is_mocked': false,
            };
          default:
            return null;
        }
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geolocatorChannel, null));

    final networkService = NetworkStatusService(
      checkConnectivityFn: () async => [ConnectivityResult.wifi],
      reachabilityFn: () async => true,
      connectivityStream: const Stream<List<ConnectivityResult>>.empty(),
    );

    final db = AppDatabase.instance;
    db.clearForTesting();
    await db.initialize();
    final authService = AuthService(database: db);
    await authService.login('biologo1', 'BioCampo2026!');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.solarLightTheme,
        home: HomeScreen(
          authService: authService,
          networkStatusService: networkService,
          mapTileProvider: _TestMemoryTileProvider(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mapa y GPS'));
    await tester.pumpAndSettle();

    // Vista al mapa debe estar bloqueada por falta de permisos
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Faltan permisos de ubicación'), findsOneWidget);
    expect(find.text('Otorgar permisos de ubicación'), findsOneWidget);

    // Al pulsar el botón funcional, otorga permisos y muestra el mapa real
    await tester.tap(find.text('Otorgar permisos de ubicación'));
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('EN LÍNEA'), findsOneWidget);
  });

  testWidgets('Denegación de mapa sin conexión a internet y recuperación al reintentar',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    var online = false;

    const geolocatorChannel = MethodChannel('flutter.baseflow.com/geolocator');
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      geolocatorChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'isLocationServiceEnabled':
            return true;
          case 'checkPermission':
          case 'requestPermission':
            return 2; // whileInUse
          case 'getCurrentPosition':
            return <String, dynamic>{
              'latitude': 21.8853,
              'longitude': -102.2916,
              'altitude': 1888.0,
              'accuracy': 4.0,
              'timestamp': DateTime.now().millisecondsSinceEpoch,
              'heading': 0.0,
              'heading_accuracy': 0.0,
              'speed': 0.0,
              'speed_accuracy': 0.0,
              'altitude_accuracy': 1.0,
              'vertical_speed': 0.0,
              'vertical_speed_accuracy': 0.0,
              'is_mocked': false,
            };
          default:
            return null;
        }
      },
    );
    addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(geolocatorChannel, null));

    final controller = StreamController<List<ConnectivityResult>>.broadcast();
    addTearDown(controller.close);

    final networkService = NetworkStatusService(
      checkConnectivityFn: () async =>
          online ? [ConnectivityResult.mobile] : [ConnectivityResult.none],
      reachabilityFn: () async => online,
      connectivityStream: controller.stream,
    );

    final db = AppDatabase.instance;
    db.clearForTesting();
    await db.initialize();
    final authService = AuthService(database: db);
    await authService.login('biologo1', 'BioCampo2026!');

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.solarLightTheme,
        home: HomeScreen(
          authService: authService,
          networkStatusService: networkService,
          mapTileProvider: _TestMemoryTileProvider(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Mapa y GPS'));
    await tester.pumpAndSettle();

    // Vista al mapa denegada por falta de internet
    expect(find.byType(FlutterMap), findsNothing);
    expect(find.text('Sin conexión a internet'), findsOneWidget);
    expect(find.text('Reintentar conexión'), findsOneWidget);

    // Simular activación de datos móviles y pulsar reintentar
    online = true;
    await tester.tap(find.text('Reintentar conexión'));
    await tester.pumpAndSettle();

    expect(find.byType(FlutterMap), findsOneWidget);
    expect(find.text('EN LÍNEA'), findsOneWidget);
  });
}
