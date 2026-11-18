/// Modelo de Dominio: Reporte de Avistamiento de Biodiversidad
/// Representa el registro de campo generado por un biólogo en una expedición.
/// Posee una relación relacional N:1 con la entidad Usuario (usuario_id).
class ReporteModel {
  final int? id;
  final int usuarioId; // Clave foránea (FK) hacia tabla 'usuario'
  final String fechaHora; // Timestamp ISO 8601
  final double latitud; // Coordenada WGS84 del API de Geolocalización
  final double longitud; // Coordenada WGS84 del API de Geolocalización
  final double altitud; // Altura en metros sobre nivel del mar
  final double precisionGps; // Error radial en metros reportado por sensor GNSS
  final String nombreComun; // Especie o taxón identificado (ej. 'Jaguar', 'Orquídea')
  final String notas; // Observaciones de campo
  final String estadoSync; // 'PENDIENTE', 'SINCRONIZADO'

  const ReporteModel({
    this.id,
    required this.usuarioId,
    required this.fechaHora,
    required this.latitud,
    required this.longitud,
    this.altitud = 0.0,
    this.precisionGps = 0.0,
    required this.nombreComun,
    this.notas = '',
    this.estadoSync = 'PENDIENTE',
  });

  /// Mapeo desde registro de SQLite / JSON
  factory ReporteModel.fromMap(Map<String, dynamic> map) {
    return ReporteModel(
      id: map['id'] as int?,
      usuarioId: map['usuario_id'] as int,
      fechaHora: map['fecha_hora'] as String,
      latitud: (map['latitud'] as num).toDouble(),
      longitud: (map['longitud'] as num).toDouble(),
      altitud: (map['altitud'] as num?)?.toDouble() ?? 0.0,
      precisionGps: (map['precision_gps'] as num?)?.toDouble() ?? 0.0,
      nombreComun: map['nombre_comun'] as String,
      notas: (map['notas'] as String?) ?? '',
      estadoSync: (map['estado_sync'] as String?) ?? 'PENDIENTE',
    );
  }

  /// Mapeo hacia registro de SQLite / JSON
  Map<String, dynamic> toMap() {
    final map = <String, dynamic>{
      'usuario_id': usuarioId,
      'fecha_hora': fechaHora,
      'latitud': latitud,
      'longitud': longitud,
      'altitud': altitud,
      'precision_gps': precisionGps,
      'nombre_comun': nombreComun,
      'notas': notas,
      'estado_sync': estadoSync,
    };
    if (id != null) {
      map['id'] = id;
    }
    return map;
  }

  ReporteModel copyWith({
    int? id,
    int? usuarioId,
    String? fechaHora,
    double? latitud,
    double? longitud,
    double? altitud,
    double? precisionGps,
    String? nombreComun,
    String? notas,
    String? estadoSync,
  }) {
    return ReporteModel(
      id: id ?? this.id,
      usuarioId: usuarioId ?? this.usuarioId,
      fechaHora: fechaHora ?? this.fechaHora,
      latitud: latitud ?? this.latitud,
      longitud: longitud ?? this.longitud,
      altitud: altitud ?? this.altitud,
      precisionGps: precisionGps ?? this.precisionGps,
      nombreComun: nombreComun ?? this.nombreComun,
      notas: notas ?? this.notas,
      estadoSync: estadoSync ?? this.estadoSync,
    );
  }

  @override
  String toString() {
    return 'ReporteModel(id: $id, usuarioId: $usuarioId, especie: $nombreComun, lat: $latitud, lon: $longitud, sync: $estadoSync)';
  }
}
