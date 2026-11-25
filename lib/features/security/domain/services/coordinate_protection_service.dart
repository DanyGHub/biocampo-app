import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// HU-07: AES-256-GCM con acceso condicionado por el contrato inicial.
/// Sin una clave externa, la clave vive solamente durante esta instancia.
/// La persistencia segura de claves y la identidad real aun no estan integradas.
class CoordinateProtectionService {
  final Random _random = Random.secure();
  late final Uint8List _key;

  CoordinateProtectionService({Uint8List? key}) {
    if (key != null && key.length != 32) {
      throw ArgumentError('AES-256 requiere una clave de 32 bytes');
    }
    _key = key == null
        ? Uint8List.fromList(List.generate(32, (_) => _random.nextInt(256)))
        : Uint8List.fromList(key);
  }

  String protect(String coordinate) {
    final nonce =
        Uint8List.fromList(List.generate(12, (_) => _random.nextInt(256)));
    // TODO(refactor): extraer la configuracion comun de AES-GCM de ambos metodos.
    final cipher = GCMBlockCipher(AESEngine());
    cipher.init(
        true, AEADParameters(KeyParameter(_key), 128, nonce, Uint8List(0)));
    final encrypted =
        cipher.process(Uint8List.fromList(utf8.encode(coordinate)));
    // Formato inicial: nonce (12 bytes) + texto cifrado + etiqueta (16 bytes).
    return base64Encode(Uint8List.fromList([...nonce, ...encrypted]));
  }

  String? reveal(String encrypted, {required bool authorized}) {
    if (!authorized) return null;

    try {
      final payload = base64Decode(encrypted);
      if (payload.length < 28) return null;
      final nonce = Uint8List.fromList(payload.sublist(0, 12));
      final cipher = GCMBlockCipher(AESEngine());
      cipher.init(
          false, AEADParameters(KeyParameter(_key), 128, nonce, Uint8List(0)));
      final plainText = cipher.process(Uint8List.fromList(payload.sublist(12)));
      return utf8.decode(plainText);
    } on FormatException {
      return null;
    } on InvalidCipherTextException {
      return null;
    }
  }
}
