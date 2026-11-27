import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:biocampo_app/core/network/network_status_service.dart';
import 'package:biocampo_app/features/location/domain/services/location_service.dart';
import 'package:biocampo_app/features/map/domain/services/offline_map_service.dart';
import 'package:biocampo_app/features/map/presentation/widgets/offline_field_map_widget.dart';
import 'package:biocampo_app/features/reports/domain/models/reporte_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NetworkStatusService y Control de Acceso al Mapa', () {
    test('Sin mock nativo checkInternetStatus retorna rápido en unit test', () async {
      final res = await NetworkStatusService().checkInternetStatus();
      expect(res.hasInternet, isFalse);
    });

    testWidgets('Sin mock nativo dentro de testWidgets avanza con pump', (tester) async {
      NetworkStatusResult? res;
      await tester.runAsync(() async {
        res = await NetworkStatusService().checkInternetStatus();
      });
      expect(res?.hasInternet, isFalse);
    });

    test('Sin adaptador de red (ConnectivityResult.none) deniega conectividad', () async {
      final service = NetworkStatusService(
        checkConnectivityFn: () async => [ConnectivityResult.none],
        reachabilityFn: () async => true,
      );

      final res = await service.checkInternetStatus();
      expect(res.hasInternet, isFalse);
      expect(res.message, contains('Sin conexión'));
    });

    test('Con Wi-Fi sin salida real a internet (reachability=false) deniega conectividad', () async {
      final service = NetworkStatusService(
        checkConnectivityFn: () async => [ConnectivityResult.wifi],
        reachabilityFn: () async => false,
      );

      final res = await service.checkInternetStatus();
      expect(res.hasInternet, isFalse);
      expect(res.message, contains('Sin conexión'));
    });

    test('Con Wi-Fi o datos móviles activos y alcance real habilita conectividad', () async {
      final service = NetworkStatusService(
        checkConnectivityFn: () async => [ConnectivityResult.mobile],
        reachabilityFn: () async => true,
      );

      final res = await service.checkInternetStatus();
      expect(res.hasInternet, isTrue);
      expect(res.transportLabel, 'Datos móviles');
    });

    testWidgets('Deniega mapa con botón funcional cuando faltan permisos de ubicación', (tester) async {
      var permissionRequested = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineFieldMapWidget(
              centerLat: 21.885,
              centerLon: -102.291,
              accuracyMeters: 4.0,
              markers: const [],
              locationAccessState: LocationAccessState.denied,
              hasInternet: true,
              onRequestLocationPermission: () => permissionRequested = true,
            ),
          ),
        ),
      );

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('Faltan permisos de ubicación'), findsOneWidget);
      expect(find.text('Otorgar permisos de ubicación'), findsOneWidget);

      await tester.tap(find.text('Otorgar permisos de ubicación'));
      await tester.pump();
      expect(permissionRequested, isTrue);
    });

    testWidgets('Deniega mapa mostrando razón cuando no hay conexión a internet', (tester) async {
      var retried = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineFieldMapWidget(
              centerLat: 21.885,
              centerLon: -102.291,
              accuracyMeters: 4.0,
              markers: const [],
              locationAccessState: LocationAccessState.granted,
              hasInternet: false,
              onRetryConnection: () => retried = true,
            ),
          ),
        ),
      );

      expect(find.byType(FlutterMap), findsNothing);
      expect(find.text('Sin conexión a internet'), findsOneWidget);
      expect(find.text('Reintentar conexión'), findsOneWidget);

      await tester.tap(find.text('Reintentar conexión'));
      await tester.pump();
      expect(retried, isTrue);
    });

    testWidgets('Muestra mapa real interactivo y capas cuando hay permiso e internet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: OfflineFieldMapWidget(
              centerLat: 21.8853,
              centerLon: -102.2916,
              accuracyMeters: 4.0,
              markers: const [
                OfflineMapMarker(
                  id: 'm1',
                  title: 'Jaguar (Panthera onca)',
                  subtitle: 'Especie protegida',
                  latitude: 21.89,
                  longitude: -102.29,
                  isProtected: true,
                ),
              ],
              locationAccessState: LocationAccessState.granted,
              hasInternet: true,
              customTileProvider: _EmptyMemoryTileProvider(),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FlutterMap), findsOneWidget);
      expect(find.text('EN LÍNEA'), findsOneWidget);
      expect(find.byTooltip('Capas del mapa'), findsOneWidget);

      await tester.tap(find.byTooltip('Capas del mapa'));
      await tester.pumpAndSettle();
      expect(find.text('Tipo de Mapa Base'), findsOneWidget);
      expect(find.text('Topográfico'), findsOneWidget);
      expect(find.text('Satelital'), findsOneWidget);
    });

    test('Capa Estándar usa Esri World Street Map sin CartoDB y buildMapMarkers omite banderas', () async {
      expect(MapLayerType.estandar.tileUrlTemplate, contains('arcgisonline.com'));
      expect(MapLayerType.estandar.tileUrlTemplate, contains('World_Street_Map'));
      expect(MapLayerType.estandar.tileUrlTemplate, isNot(contains('cartocdn.com')));

      final service = OfflineMapService();
      final emptyMarkers = await service.buildMapMarkers(
        centerLat: 21.8853,
        centerLon: -102.2916,
        reportes: const [],
        isOnline: true,
      );
      expect(emptyMarkers, isEmpty);

      final withReport = await service.buildMapMarkers(
        centerLat: 21.8853,
        centerLon: -102.2916,
        reportes: const [
          ReporteModel(
            id: 10,
            usuarioId: 1,
            fechaHora: '2026-11-27T17:30:00',
            latitud: 21.8853,
            longitud: -102.2916,
            altitud: 1888.0,
            precisionGps: 3.5,
            nombreComun: 'Pino piñonero',
            notas: 'Avistamiento real en campo',
          ),
        ],
        isOnline: true,
      );
      expect(withReport.length, 1);
      expect(withReport.first.isReferencePoint, isFalse);
      expect(withReport.first.title, 'Pino piñonero');
    });
  });
}

class _EmptyMemoryTileProvider extends TileProvider {
  _EmptyMemoryTileProvider();

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
