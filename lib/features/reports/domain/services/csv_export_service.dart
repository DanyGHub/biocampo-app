/// Servicio de Exportación Tabular RFC 4180 de Muestreos Biológicos (HU-03 · BIOC-4)
class CsvExportService {
  /// Genera cadena serializada en formato CSV conforme a la especificación RFC 4180
  static Future<String> generarArchivoCsvLocal({
    required List<Map<String, dynamic>> registros,
    required String nombreArchivo,
  }) async {
    final buffer = StringBuffer();

    final headers = ['id', 'fecha', 'especie', 'latitud', 'longitud', 'sustrato', 'foto_path'];
    buffer.writeln(headers.join(','));

    for (final reg in registros) {
      final fila = headers.map((key) {
        final val = reg[key]?.toString() ?? '';
        // Si contiene coma, comillas dobles o salto de línea, se envuelve en comillas dobles y se escapan comillas
        if (val.contains(',') || val.contains('"') || val.contains('\n')) {
          return '"${val.replaceAll('"', '""')}"';
        }
        return val;
      }).join(',');
      buffer.writeln(fila);
    }

    return buffer.toString().trimRight();
  }
}
