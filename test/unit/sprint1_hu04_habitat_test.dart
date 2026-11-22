import 'package:flutter_test/flutter_test.dart';
import 'package:biocampo_app/features/reports/domain/services/variables_ecologicas_validator.dart';

void main() {
  group('HU-04: Formulario de hábitat y variables ecológicas (BIOC-5)', () {
    test('CP-HU04.1: Validación de microhábitat con selectores One-Hand y fallback seguro', () {
      // Conductor XP: Cindy Fabiola Hernández Muñoz
      // Copiloto XP: Ángel Daniel López Rodríguez
      
      final resultadoNormal = VariablesEcologicasValidator.validarYNormalizar(
        sustrato: 'Hojarasca húmeda',
        estrato: 'Arbustivo',
        condicion: 'Vivo',
      );

      // Criterios de Aceptación:
      expect(resultadoNormal['sustrato'], equals('Hojarasca húmeda'));
      expect(resultadoNormal['estrato'], equals('Arbustivo'));
      expect(resultadoNormal['condicion'], equals('Vivo'));

      // Validación de fallback ante captura apresurada (clima adverso)
      final resultadoFallback = VariablesEcologicasValidator.validarYNormalizar();
      expect(resultadoFallback['sustrato'], equals('No determinado'));
      expect(resultadoFallback['estrato'], equals('No determinado'));
      expect(resultadoFallback['condicion'], equals('No determinado'));
    });
  });
}
