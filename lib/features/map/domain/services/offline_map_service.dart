/// HU-05: carga inicial de marcadores desde los datos locales.
class OfflineMapService {
  Future<List<String>> loadMarkers(
      {required bool online, required List<String> localMarkers}) async {
    // En esta fase se usa la fuente local con o sin conexion.
    return List<String>.from(localMarkers);
  }
}
