import 'package:flutter_test/flutter_test.dart';
import 'package:biocampo_app/features/reports/domain/services/catalogo_taxonomico_service.dart';

void main() {
  group('HU-02: Catálogo taxonómico offline con búsqueda predictiva (BIOC-3)', () {
    test('CP-HU02.1: Autocompletado Darwin Core en < 200 ms con prefijo >= 2 caracteres', () async {
      // Conductor XP: Ángel Daniel López Rodríguez
      // Copiloto XP: Cindy Fabiola Hernández Muñoz
      const query = 'Pin';

      final stopwatch = Stopwatch()..start();
      final sugerencias = await CatalogoTaxonomicoService.buscarEspecieDarwinCore(query: query);
      stopwatch.stop();

      // Criterios de Aceptación:
      expect(stopwatch.elapsedMilliseconds, lessThan(200),
          reason: 'La consulta local en SQLite debe responder en menos de 200 ms');
      expect(sugerencias, isNotEmpty,
          reason: 'Debe encontrar coincidencias taxonómicas en el catálogo precargado');
      expect(sugerencias.first['scientificName'], equals('Pinus cembroides'),
          reason: 'Debe autollenar nombre científico bajo estándar Darwin Core');
    });
  });
}
