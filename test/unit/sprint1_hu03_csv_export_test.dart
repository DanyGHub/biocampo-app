import 'package:flutter_test/flutter_test.dart';

// Interfaz preliminar para fase RED de TDD
abstract class CsvExportService {
  static Future<String> generarArchivoCsvLocal({
    required List<Map<String, dynamic>> registros,
    required String nombreArchivo,
  }) async {
    // Fase ROJO de TDD: La funcionalidad aún no está codificada
    throw UnimplementedError(
      'TDD Rojo: CsvExportService.generarArchivoCsvLocal() no está implementado aún.',
    );
  }
}

void main() {
  group('HU-03: Exportación local de muestreos a formato CSV (BIOC-4)', () {
    test('CP-HU03.1: Generación tabular RFC 4180 en UTF-8 y guardado mediante SAF', () async {
      // Autor Conductor: Ángel Daniel López Rodríguez
      // Autor Copiloto: Reyli Uvaldo Martínez Hernández
      final muestraReportes = [
        {
          'id': 1,
          'fecha': '2026-11-18 10:30:00',
          'especie': 'Pinus cembroides',
          'latitud': 21.8853,
          'longitud': -102.2916,
          'sustrato': 'Suelo orgánico',
          'foto_path': '/storage/evidencia_1.jpg'
        }
      ];

      final csvContent = await CsvExportService.generarArchivoCsvLocal(
        registros: muestraReportes,
        nombreArchivo: 'expedicion_sierra_fria_20261118.csv',
      );

      // Criterios de Aceptación:
      expect(csvContent, contains('id,fecha,especie,latitud,longitud,sustrato,foto_path'),
          reason: 'Debe contener encabezados tabulares normalizados RFC 4180');
      expect(csvContent, contains('Pinus cembroides'),
          reason: 'Debe serializar los datos correctamente con comas como delimitador');
    });
  });
}
