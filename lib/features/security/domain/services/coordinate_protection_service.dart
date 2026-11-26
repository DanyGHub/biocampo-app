import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:pointycastle/export.dart';

/// HU-07: AES-256-GCM con acceso condicionado por el contrato inicial.
/// Sin una clave externa, la clave vive solamente durante esta instancia.
/// La persistencia segura de claves y la identidad real aun no estan integradas.
class CoordinateProtectionService {
  static const int _keyLengthBytes = 32;
  static const int _nonceLengthBytes = 12;
  static const int _tagLengthBits = 128;
  static const int _minimumPayloadLength =
      _nonceLengthBytes + _tagLengthBits ~/ 8;

  final Random _random = Random.secure();
  late final Uint8List _key;

  CoordinateProtectionService({Uint8List? key}) {
    if (key != null && key.length != _keyLengthBytes) {
      throw ArgumentError('AES-256 requiere una clave de 32 bytes');
    }
    _key =
        key == null ? _randomBytes(_keyLengthBytes) : Uint8List.fromList(key);
  }

  String protect(String coordinate) {
    final nonce = _randomBytes(_nonceLengthBytes);
    final cipher = _createCipher(encrypting: true, nonce: nonce);
    final encrypted =
        cipher.process(Uint8List.fromList(utf8.encode(coordinate)));
    // Formato conservado: nonce + texto cifrado + etiqueta de autenticacion.
    return base64Encode(Uint8List.fromList([...nonce, ...encrypted]));
  }

  String? reveal(String encrypted, {required bool authorized}) {
    if (!authorized) return null;

    try {
      final payload = base64Decode(encrypted);
      if (payload.length < _minimumPayloadLength) return null;
      final nonce = Uint8List.fromList(payload.sublist(0, _nonceLengthBytes));
      final cipher = _createCipher(encrypting: false, nonce: nonce);
      final plainText = cipher
          .process(Uint8List.fromList(payload.sublist(_nonceLengthBytes)));
      return utf8.decode(plainText);
    } on FormatException {
      return null;
    } on InvalidCipherTextException {
      return null;
    }
  }

  Uint8List _randomBytes(int length) =>
      Uint8List.fromList(List.generate(length, (_) => _random.nextInt(256)));

  GCMBlockCipher _createCipher({
    required bool encrypting,
    required Uint8List nonce,
  }) {
    return GCMBlockCipher(AESEngine())
      ..init(
          encrypting,
          AEADParameters(
              KeyParameter(_key), _tagLengthBits, nonce, Uint8List(0)));
  }
}
