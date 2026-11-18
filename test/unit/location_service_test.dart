import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import 'package:biocampo_app/features/location/domain/services/location_service.dart';
import 'package:biocampo_app/features/reports/domain/models/reporte_model.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Paso 3: Pruebas Unitarias de Geolocalización GNSS y Operación Verificable', () {
    late AppDatabase db;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      db = AppDatabase.instance;
      db.clearForTesting();
      await db.initialize();
    });

    test('CP-04.1: Adquisición de Telemetría GNSS y Estructura de Datos', () async {
      final telemetry = await LocationService.getCurrentLocation();

      expect(telemetry.latitude, isNotNull);
      expect(telemetry.longitude, isNotNull);
      expect(telemetry.altitude, isPositive);
      expect(telemetry.accuracy, isPositive);
      expect(telemetry.statusMessage, isNotEmpty);
    });

    test('CP-04.2: Verificación de Criterio de Calidad RNF-05 (Error radial <= 5m)', () {
      const highPrec = GpsTelemetry(
        latitude: 22.1524,
        longitude: -102.6142,
        altitude: 2450.0,
        accuracy: 3.5,
        statusMessage: 'Fijación Satelital Exitosa',
      );
      expect(highPrec.isHighPrecision, isTrue);

      const lowPrec = GpsTelemetry(
        latitude: 22.1524,
        longitude: -102.6142,
        altitude: 2450.0,
        accuracy: 8.2,
        statusMessage: 'Señal Degenerada por Dosel',
      );
      expect(lowPrec.isHighPrecision, isFalse);
    });

    test('CP-04.3: Conversión Cartográfica a Grados, Minutos y Segundos (DMS)', () {
      const lat = 22.1524;
      const lon = -102.6142;

      final dmsLat = GpsTelemetry.toDms(lat, isLatitude: true);
      final dmsLon = GpsTelemetry.toDms(lon, isLatitude: false);

      expect(dmsLat, contains('22°'));
      expect(dmsLat, contains('N'));
      expect(dmsLon, contains('102°'));
      expect(dmsLon, contains('W'));
    });

    test('CP-05: Operación Verificable - Inserción Relacional con Telemetría GPS en SQLite', () async {
      final biologo = (await db.getUsuarioByMatricula('biologo1'))!;

      final telemetry = await LocationService.getCurrentLocation();

      final reporteVerificable = ReporteModel(
        usuarioId: biologo.id!,
        fechaHora: DateTime.now().toIso8601String(),
        latitud: telemetry.latitude,
        longitud: telemetry.longitude,
        altitud: telemetry.altitude,
        precisionGps: telemetry.accuracy,
        nombreComun: 'Águila Real (Aquila chrysaetos)',
        notas: 'Avistamiento verificado con sensor satelital GNSS.',
      );

      final insertId = await db.insertReporte(reporteVerificable);
      expect(insertId, isPositive);

      final reportes = await db.getReportes(usuarioId: biologo.id);
      expect(reportes.length, equals(1));

      final guardado = reportes.first;
      expect(guardado.usuarioId, equals(biologo.id));
      expect(guardado.nombreComun, equals('Águila Real (Aquila chrysaetos)'));
      expect(guardado.latitud, equals(telemetry.latitude));
      expect(guardado.longitud, equals(telemetry.longitude));
      expect(guardado.precisionGps, equals(telemetry.accuracy));
      expect(guardado.precisionGps, lessThanOrEqualTo(5.0)); // Valida RNF-05
    });
  });
}
