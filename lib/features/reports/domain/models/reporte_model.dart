/// Modelo de Dominio: Reporte de Avistamiento de Biodiversidad
/// Representa el registro de campo generado por un biólogo en una expedición.
/// Posee una relación relacional N:1 con la entidad Usuario (usuario_id).
/// Incluye campos del Incremento del Sprint 1 (HU-01 a HU-04) y Sprint 2 (HU-07 cifrado).
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

  // Incremento Sprint 1: HU-01 (Foto), HU-02 (Darwin Core) y HU-04 (Hábitat)
  final String? fotoPath; // Ruta de persistencia relativa Zero-Cloud (HU-01)
  final String? fotoBytesBase64; // Serialización de imagen para visualización Web/Móvil
  final String? nombreCientifico; // Estándar Darwin Core (HU-02)
  final String sustrato; // Variable ecológica de microhábitat (HU-04)
  final String estrato; // Variable ecológica de microhábitat (HU-04)
  final String condicion; // Variable ecológica de microhábitat (HU-04)

  // Incremento Sprint 2: HU-07 (Seguridad y cifrado de especies protegidas)
  final bool esProtegida;
  final String? coordenadasCifradas;

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
    this.fotoPath,
    this.fotoBytesBase64,
    this.nombreCientifico,
    this.sustrato = 'No determinado',
    this.estrato = 'No determinado',
    this.condicion = 'No determinado',
    this.esProtegida = false,
    this.coordenadasCifradas,
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
      fotoPath: map['foto_path'] as String?,
      fotoBytesBase64: map['foto_bytes_base64'] as String?,
      nombreCientifico: map['nombre_cientifico'] as String?,
      sustrato: (map['sustrato'] as String?) ?? 'No determinado',
      estrato: (map['estrato'] as String?) ?? 'No determinado',
      condicion: (map['condicion'] as String?) ?? 'No determinado',
      esProtegida: map['es_protegida'] == true || map['es_protegida'] == 1,
      coordenadasCifradas: map['coordenadas_cifradas'] as String?,
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
      'foto_path': fotoPath,
      'foto_bytes_base64': fotoBytesBase64,
      'nombre_cientifico': nombreCientifico,
      'sustrato': sustrato,
      'estrato': estrato,
      'condicion': condicion,
      'es_protegida': esProtegida ? 1 : 0,
      'coordenadas_cifradas': coordenadasCifradas,
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
    String? fotoPath,
    String? fotoBytesBase64,
    String? nombreCientifico,
    String? sustrato,
    String? estrato,
    String? condicion,
    bool? esProtegida,
    String? coordenadasCifradas,
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
      fotoPath: fotoPath ?? this.fotoPath,
      fotoBytesBase64: fotoBytesBase64 ?? this.fotoBytesBase64,
      nombreCientifico: nombreCientifico ?? this.nombreCientifico,
      sustrato: sustrato ?? this.sustrato,
      estrato: estrato ?? this.estrato,
      condicion: condicion ?? this.condicion,
      esProtegida: esProtegida ?? this.esProtegida,
      coordenadasCifradas: coordenadasCifradas ?? this.coordenadasCifradas,
    );
  }

  @override
  String toString() {
    return 'ReporteModel(id: $id, usuarioId: $usuarioId, especie: $nombreComun, sci: $nombreCientifico, protegida: $esProtegida, lat: $latitud, lon: $longitud, sync: $estadoSync)';
  }
}
