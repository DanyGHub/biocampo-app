import 'package:flutter_test/flutter_test.dart';

// Definición preliminar de interfaz para fase RED de TDD
abstract class FotoEvidenciaService {
  static Future<Map<String, dynamic>> comprimirYVincular({
    required String rutaTemporal,
    required int reporteId,
    required double latitud,
    required double longitud,
  }) async {
    // Fase ROJO de TDD: La funcionalidad aún no está codificada
    throw UnimplementedError(
      'TDD Rojo: FotoEvidenciaService.comprimirYVincular() no está implementado aún.',
    );
  }
}

void main() {
  group('HU-01: Captura fotográfica rápida y asociación atómica (BIOC-1)', () {
    test('CP-HU01.1: Compresión adaptativa JPEG < 350 KB y persistencia de ruta relativa', () async {
      // Autor Conductor: Cindy Fabiola Hernández Muñoz
      // Autor Copiloto: Ángel Daniel López Rodríguez
      const int reporteId = 101;
      const String dummyPath = '/cache/raw_cam_20261118.jpg';
      const double lat = 21.8853;
      const double lon = -102.2916;

      final resultado = await FotoEvidenciaService.comprimirYVincular(
        rutaTemporal: dummyPath,
        reporteId: reporteId,
        latitud: lat,
        longitud: lon,
      );

      // Criterios de Aceptación:
      expect(resultado['size_bytes'], lessThanOrEqualTo(358400),
          reason: 'El peso de la foto debe ser estrictamente menor o igual a 350 KB');
      expect(resultado['ruta_relativa'], contains('evidencia_101_'),
          reason: 'La ruta debe asociar el ID de reporte');
      expect(resultado['zero_cloud'], isTrue,
          reason: 'Debe operar 100% en almacenamiento local');
    });
  });
}
