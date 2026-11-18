import 'dart:convert';
import 'package:crypto/crypto.dart';
import '../models/jwt_token_model.dart';
import '../models/usuario_model.dart';

/// Servicio de generación, firma criptográfica y validación de JSON Web Tokens (JWT)
/// Implementa HMAC-SHA256 (HS256) bajo la especificación RFC 7519.
class JwtService {
  /// Clave secreta simétrica del sistema BioCampo para firma de tokens offline
  static const String _defaultSecretKey = 'BioCampo_SecretKey_UAA_Ingenieria_2026_Offline_JWT';

  final String _secretKey;

  JwtService({String secretKey = _defaultSecretKey}) : _secretKey = secretKey;

  /// Codifica una cadena a Base64Url sin padding ('=')
  static String _base64UrlEncode(String input) {
    return base64Url.encode(utf8.encode(input)).replaceAll('=', '');
  }

  /// Decodifica una cadena Base64Url agregando padding si es necesario
  static String _base64UrlDecode(String input) {
    var normalized = input;
    final remainder = normalized.length % 4;
    if (remainder > 0) {
      normalized = normalized.padRight(normalized.length + (4 - remainder), '=');
    }
    return utf8.decode(base64Url.decode(normalized));
  }

  /// Genera y firma criptográficamente un JWT a partir de un usuario autenticado
  String generateToken(UsuarioModel usuario, {Duration duration = const Duration(hours: 24)}) {
    final now = DateTime.now();
    final expiration = now.add(duration);

    // 1. Header RFC 7519
    final header = {
      'alg': 'HS256',
      'typ': 'JWT',
    };

    // 2. Payload con Claims estándar y de dominio
    final payload = {
      'sub': usuario.id.toString(),
      'matricula': usuario.matricula,
      'nombre': usuario.nombreCompleto,
      'rol': usuario.rol,
      'iat': (now.millisecondsSinceEpoch ~/ 1000),
      'exp': (expiration.millisecondsSinceEpoch ~/ 1000),
    };

    final headerEncoded = _base64UrlEncode(jsonEncode(header));
    final payloadEncoded = _base64UrlEncode(jsonEncode(payload));
    final unsignedToken = '$headerEncoded.$payloadEncoded';

    // 3. Firma HMAC-SHA256
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    final digest = hmac.convert(utf8.encode(unsignedToken));
    final signatureEncoded = base64Url.encode(digest.bytes).replaceAll('=', '');

    return '$unsignedToken.$signatureEncoded';
  }

  /// Valida la firma y vigencia temporal de un JWT
  bool verifyToken(String token) {
    final parts = token.split('.');
    if (parts.length != 3) {
      return false;
    }

    final headerEncoded = parts[0];
    final payloadEncoded = parts[1];
    final signatureEncoded = parts[2];

    // Verificar firma criptográfica
    final unsignedToken = '$headerEncoded.$payloadEncoded';
    final hmac = Hmac(sha256, utf8.encode(_secretKey));
    final expectedDigest = hmac.convert(utf8.encode(unsignedToken));
    final expectedSignature = base64Url.encode(expectedDigest.bytes).replaceAll('=', '');

    if (signatureEncoded != expectedSignature) {
      return false; // Firma inválida / Token adulterado
    }

    // Verificar expiración
    try {
      final payloadJson = jsonDecode(_base64UrlDecode(payloadEncoded)) as Map<String, dynamic>;
      final expSeconds = payloadJson['exp'] as int?;
      if (expSeconds != null) {
        final expDate = DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000);
        if (DateTime.now().isAfter(expDate)) {
          return false; // Token expirado
        }
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Decodifica un JWT y extrae sus Claims en un modelo tipado
  JwtTokenModel? decodeToken(String token) {
    if (!verifyToken(token)) {
      return null;
    }

    final parts = token.split('.');
    try {
      final headerJson = jsonDecode(_base64UrlDecode(parts[0])) as Map<String, dynamic>;
      final payloadJson = jsonDecode(_base64UrlDecode(parts[1])) as Map<String, dynamic>;

      final iatSeconds = payloadJson['iat'] as int? ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000);
      final expSeconds = payloadJson['exp'] as int? ?? (DateTime.now().millisecondsSinceEpoch ~/ 1000 + 86400);

      return JwtTokenModel(
        rawToken: token,
        algorithm: headerJson['alg'] as String? ?? 'HS256',
        type: headerJson['typ'] as String? ?? 'JWT',
        usuarioId: int.tryParse(payloadJson['sub'].toString()) ?? 0,
        matricula: payloadJson['matricula'] as String? ?? '',
        nombre: payloadJson['nombre'] as String? ?? '',
        rol: payloadJson['rol'] as String? ?? 'Investigador',
        issuedAt: DateTime.fromMillisecondsSinceEpoch(iatSeconds * 1000),
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expSeconds * 1000),
      );
    } catch (_) {
      return null;
    }
  }
}
