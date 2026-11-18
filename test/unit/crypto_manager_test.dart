import 'package:flutter_test/flutter_test.dart';
import 'package:crypto/crypto.dart';
import 'dart:convert';

void main() {
  group('CP-07: Pruebas Unitarias de Criptografía e Integridad SHA-256', () {
    test('Debe generar un hash SHA-256 determinista de 64 caracteres hexadecimales', () {
      // Simulación de bytes de fotografía JPEG
      final sampleBytes = utf8.encode('BioCampo_Fotografia_Prueba_Muestra_01');
      final digest = sha256.convert(sampleBytes);
      final hashString = digest.toString();

      expect(hashString.length, equals(64));
      expect(hashString, isA<String>());
      // Verificación de determinismo
      final digestSecond = sha256.convert(sampleBytes);
      expect(hashString, equals(digestSecond.toString()));
    });

    test('Debe detectar cualquier alteración en los bytes de la muestra (Inmutabilidad)', () {
      final originalBytes = utf8.encode('Muestra_Original_Quercus');
      final alteredBytes = utf8.encode('Muestra_Alterada_Quercus');

      final hashOriginal = sha256.convert(originalBytes).toString();
      final hashAltered = sha256.convert(alteredBytes).toString();

      expect(hashOriginal, isNot(equals(hashAltered)));
    });
  });
}
