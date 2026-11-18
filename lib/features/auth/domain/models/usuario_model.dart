/// Modelo de Dominio: Usuario (Biólogo / Investigador)
/// Representa a los usuarios del sistema BioCampo conforme a la especificación
/// de la Base de Datos Relacional de Fase II y la entrega de Fase III.
class UsuarioModel {
  final int? id;
  final String matricula; // Identificador/Username (ej. 'biologo1', 'BIO-001')
  final String nombreCompleto;
  final String passwordHash;
  final String salt;
  final String rol; // 'Investigador', 'Coordinador', 'Administrador'
  final String? ultimoLogin;

  const UsuarioModel({
    this.id,
    required this.matricula,
    required this.nombreCompleto,
    required this.passwordHash,
    required this.salt,
    this.rol = 'Investigador',
    this.ultimoLogin,
  });

  /// Crea una copia del modelo con campos modificados
  UsuarioModel copyWith({
    int? id,
    String? matricula,
    String? nombreCompleto,
    String? passwordHash,
    String? salt,
    String? rol,
    String? ultimoLogin,
  }) {
    return UsuarioModel(
      id: id ?? this.id,
      matricula: matricula ?? this.matricula,
      nombreCompleto: nombreCompleto ?? this.nombreCompleto,
      passwordHash: passwordHash ?? this.passwordHash,
      salt: salt ?? this.salt,
      rol: rol ?? this.rol,
      ultimoLogin: ultimoLogin ?? this.ultimoLogin,
    );
  }

  /// Mapeo desde registro de SQLite / JSON
  factory UsuarioModel.fromMap(Map<String, dynamic> map) {
    return UsuarioModel(
      id: map['id'] as int?,
      matricula: map['matricula'] as String,
      nombreCompleto: map['nombre_completo'] as String,
      passwordHash: map['password_hash'] as String,
      salt: map['salt'] as String,
      rol: (map['rol'] as String?) ?? 'Investigador',
      ultimoLogin: map['ultimo_login'] as String?,
    );
  }

  /// Mapeo hacia registro de SQLite / JSON
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'matricula': matricula,
      'nombre_completo': nombreCompleto,
      'password_hash': passwordHash,
      'salt': salt,
      'rol': rol,
      'ultimo_login': ultimoLogin,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  @override
  String toString() {
    return 'UsuarioModel(id: $id, matricula: $matricula, nombre: $nombreCompleto, rol: $rol)';
  }
}
