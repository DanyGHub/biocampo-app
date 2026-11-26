import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:biocampo_app/features/security/domain/services/coordinate_protection_service.dart';

void main() {
  group('HU-07: comprobaciones adicionales de proteccion', () {
    const coordinate = '0.12345,0.54321';

    test('Cifrar dos veces usa nonces diferentes y permite recuperar el dato',
        () {
      final service = CoordinateProtectionService();
      final first = service.protect(coordinate);
      final second = service.protect(coordinate);
      expect(base64Decode(first).sublist(0, 12),
          isNot(orderedEquals(base64Decode(second).sublist(0, 12))));
      expect(service.reveal(first, authorized: true), coordinate);
      expect(service.reveal(second, authorized: true), coordinate);
    });

    test('Rechaza un mensaje cuya etiqueta fue alterada', () {
      final service = CoordinateProtectionService();
      final payload = base64Decode(service.protect(coordinate));
      payload[payload.length - 1] ^= 1;
      expect(service.reveal(base64Encode(payload), authorized: true), isNull);
    });

    test('Solo otra instancia con la misma clave puede recuperar el dato', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      final writer = CoordinateProtectionService(key: key);
      final reader = CoordinateProtectionService(key: key);
      final wrongReader = CoordinateProtectionService(key: Uint8List(32));
      final encrypted = writer.protect(coordinate);
      expect(reader.reveal(encrypted, authorized: true), coordinate);
      expect(wrongReader.reveal(encrypted, authorized: true), isNull);
      expect(reader.reveal(encrypted, authorized: false), isNull);
    });

    test('Rechaza datos incompletos o con formato invalido', () {
      final service = CoordinateProtectionService();
      expect(service.reveal('%%%', authorized: true), isNull);
      expect(service.reveal(base64Encode([1, 2, 3]), authorized: true), isNull);
      expect(service.reveal('%%%', authorized: false), isNull);
    });

    test('Rechaza claves que no tengan 256 bits', () {
      expect(() => CoordinateProtectionService(key: Uint8List(16)),
          throwsArgumentError);
    });
  });
}
