/// Representa la estructura de un JSON Web Token (JWT) decodificado
/// conforme al estándar RFC 7519.
class JwtTokenModel {
  final String rawToken;
  final String algorithm;
  final String type;
  final int usuarioId;
  final String matricula;
  final String nombre;
  final String rol;
  final DateTime issuedAt;
  final DateTime expiresAt;

  const JwtTokenModel({
    required this.rawToken,
    required this.algorithm,
    required this.type,
    required this.usuarioId,
    required this.matricula,
    required this.nombre,
    required this.rol,
    required this.issuedAt,
    required this.expiresAt,
  });

  /// Indica si el token ha expirado
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Tiempo restante de vigencia
  Duration get remainingTime => expiresAt.difference(DateTime.now());

  @override
  String toString() {
    return 'JwtTokenModel(usuarioId: $usuarioId, matricula: $matricula, expira: $expiresAt, valido: ${!isExpired})';
  }
}
