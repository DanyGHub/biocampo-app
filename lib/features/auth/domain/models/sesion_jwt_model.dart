/// Modelo de Dominio: Sesión JWT Persistida en Base de Datos Relacional
/// Modela la entidad 'sesion_jwt' en SQLite relacionada con la tabla 'usuario' (1:1).
class SesionJwtModel {
  final int? id;
  final int usuarioId; // Clave Foránea (FK) hacia tabla 'usuario'
  final String jwtToken;
  final String algoritmo; // 'HS256'
  final String emitidoEn; // ISO 8601
  final String expiraEn; // ISO 8601
  final bool activo;

  const SesionJwtModel({
    this.id,
    required this.usuarioId,
    required this.jwtToken,
    this.algoritmo = 'HS256',
    required this.emitidoEn,
    required this.expiraEn,
    this.activo = true,
  });

  factory SesionJwtModel.fromMap(Map<String, dynamic> map) {
    return SesionJwtModel(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      jwtToken: map['jwt_token'] as String,
      algoritmo: (map['algoritmo'] as String?) ?? 'HS256',
      emitidoEn: map['emitido_en'] as String,
      expiraEn: map['expira_en'] as String,
      activo: (map['activo'] as int? ?? 1) == 1,
    );
  }

  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'usuario_id': usuarioId,
      'jwt_token': jwtToken,
      'algoritmo': algoritmo,
      'emitido_en': emitidoEn,
      'expira_en': expiraEn,
      'activo': activo ? 1 : 0,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }
}
