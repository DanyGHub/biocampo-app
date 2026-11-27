import 'package:biocampo_app/features/reports/domain/models/reporte_model.dart';
import 'package:biocampo_app/features/security/domain/services/coordinate_protection_service.dart';

/// Capas cartográficas reales soportadas por el visor georreferenciado (HU-05)
enum MapLayerType {
  estandar(
    'Estándar (Calles)',
    'Cartografía vial detallada estilo Google Maps (Esri World Street)',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
    null,
    '© Esri · World Street Map',
  ),
  topografico(
    'Topográfico',
    'Relieve geográfico, ríos y senderos topográficos (Esri World Topo)',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Topo_Map/MapServer/tile/{z}/{y}/{x}',
    null,
    '© Esri · World Topo Map',
  ),
  ecologico(
    'Satelital (Reserva)',
    'Imagen satelital real de cobertura vegetal y terreno (Esri World Imagery)',
    'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
    null,
    '© Esri · World Imagery',
  );

  final String label;
  final String description;
  final String tileUrlTemplate;
  final String? fallbackUrlTemplate;
  final String attributionText;

  const MapLayerType(
    this.label,
    this.description,
    this.tileUrlTemplate,
    this.fallbackUrlTemplate,
    this.attributionText,
  );
}

/// Marcador georreferenciado renderizable en el mapa offline
class OfflineMapMarker {
  final String id;
  final String title;
  final String subtitle;
  final double latitude;
  final double longitude;
  final bool isProtected;
  final bool isReferencePoint;
  final ReporteModel? report;

  const OfflineMapMarker({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.latitude,
    required this.longitude,
    this.isProtected = false,
    this.isReferencePoint = false,
    this.report,
  });
}

/// HU-05: carga inicial de marcadores desde los datos locales.
class OfflineMapService {
  Future<List<String>> loadMarkers(
      {required bool online, required List<String> localMarkers}) async {
    // En esta fase se usa la fuente local con o sin conexion.
    return List<String>.from(localMarkers);
  }

  /// Construye la lista enriquecida de marcadores offline a partir de reportes locales
  /// aplicando ofuscación radial para especies protegidas (HU-07) si no están reveladas.
  Future<List<OfflineMapMarker>> buildMapMarkers({
    required double centerLat,
    required double centerLon,
    required List<ReporteModel> reportes,
    Set<int> revealedReportIds = const {},
    bool isOnline = false,
  }) async {
    final ids = reportes.map((r) => 'avistamiento-${r.id ?? r.fechaHora}').toList();
    await loadMarkers(online: isOnline, localMarkers: ids);

    final markers = <OfflineMapMarker>[];

    for (final r in reportes) {
      final isRevealed = r.id != null && revealedReportIds.contains(r.id);
      final shouldObfuscate = r.esProtegida && !isRevealed;
      final coords = shouldObfuscate
          ? CoordinateProtectionService.obfuscateCoordinate(
              r.latitud,
              r.longitud,
              seed: r.id ?? r.nombreComun.hashCode,
            )
          : (lat: r.latitud, lon: r.longitud);

      markers.add(
        OfflineMapMarker(
          id: 'report-${r.id ?? r.fechaHora}',
          title: r.nombreComun,
          subtitle: shouldObfuscate
              ? 'Especie protegida · Ubicación ofuscada (±5 km)'
              : (r.nombreCientifico ?? 'Sustrato: ${r.sustrato}'),
          latitude: coords.lat,
          longitude: coords.lon,
          isProtected: r.esProtegida,
          report: r,
        ),
      );
    }

    return markers;
  }
}
