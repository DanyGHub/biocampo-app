/// Servicio de Búsqueda y Validación Taxonómica Darwin Core (HU-02 · BIOC-3)
class CatalogoTaxonomicoService {
  /// Base de datos de taxonomía precargada localmente bajo estándar Darwin Core
  static final List<Map<String, String>> _catalogoDarwinCore = [
    {
      'scientificName': 'Pinus cembroides',
      'vernacularName': 'Pino piñonero',
      'kingdom': 'Plantae',
      'family': 'Pinaceae',
      'taxonRank': 'Species',
    },
    {
      'scientificName': 'Pinus leiophylla',
      'vernacularName': 'Pino chino',
      'kingdom': 'Plantae',
      'family': 'Pinaceae',
      'taxonRank': 'Species',
    },
    {
      'scientificName': 'Quercus potosina',
      'vernacularName': 'Roble / Encino',
      'kingdom': 'Plantae',
      'family': 'Fagaceae',
      'taxonRank': 'Species',
    },
    {
      'scientificName': 'Panthera onca',
      'vernacularName': 'Jaguar',
      'kingdom': 'Animalia',
      'family': 'Felidae',
      'taxonRank': 'Species',
      'protectedStatus': 'Peligro de Extinción (NOM-059-SEMARNAT)',
    },
    {
      'scientificName': 'Aquila chrysaetos',
      'vernacularName': 'Águila real',
      'kingdom': 'Animalia',
      'family': 'Accipitridae',
      'taxonRank': 'Species',
      'protectedStatus': 'Amenazada (NOM-059-SEMARNAT)',
    },
    {
      'scientificName': 'Mammillaria marksiana',
      'vernacularName': 'Biznaguita',
      'kingdom': 'Plantae',
      'family': 'Cactaceae',
      'taxonRank': 'Species',
      'protectedStatus': 'Protección Especial (NOM-059-SEMARNAT)',
    },
    {
      'scientificName': 'Ambystoma mexicanum',
      'vernacularName': 'Ajolote mexicano',
      'kingdom': 'Animalia',
      'family': 'Ambystomatidae',
      'taxonRank': 'Species',
      'protectedStatus': 'Peligro de Extinción (NOM-059-SEMARNAT)',
    },
    {
      'scientificName': 'Odocoileus virginianus',
      'vernacularName': 'Venado cola blanca',
      'kingdom': 'Animalia',
      'family': 'Cervidae',
      'taxonRank': 'Species',
    },
    {
      'scientificName': 'Sylvilagus floridanus',
      'vernacularName': 'Conejo serrano',
      'kingdom': 'Animalia',
      'family': 'Leporidae',
      'taxonRank': 'Species',
    },
  ];

  static Future<List<Map<String, String>>> buscarEspecieDarwinCore({
    required String query,
  }) async {
    final queryNorm = query.trim().toLowerCase();
    if (queryNorm.length < 2) {
      return [];
    }

    return _catalogoDarwinCore.where((item) {
      final sci = item['scientificName']?.toLowerCase() ?? '';
      final vern = item['vernacularName']?.toLowerCase() ?? '';
      return sci.startsWith(queryNorm) ||
             sci.contains(queryNorm) ||
             vern.contains(queryNorm);
    }).toList();
  }

  /// Determina el estatus NOM-059/UICN de una especie para activar protección HU-07
  static String? getProtectionStatus(String nombreComun, [String? nombreCientifico]) {
    final comun = nombreComun.trim().toLowerCase();
    final cien = (nombreCientifico ?? '').trim().toLowerCase();

    for (final item in _catalogoDarwinCore) {
      final status = item['protectedStatus'];
      if (status == null) continue;
      final itemSci = item['scientificName']!.toLowerCase();
      final itemVern = item['vernacularName']!.toLowerCase();
      if ((cien.isNotEmpty && (cien == itemSci || cien.contains(itemSci))) ||
          comun.contains(itemVern) ||
          comun.contains(itemSci)) {
        return status;
      }
    }

    if (comun.contains('proteg') ||
        comun.contains('peligro') ||
        comun.contains('jaguar') ||
        comun.contains('águila') ||
        comun.contains('aguila') ||
        comun.contains('ajolote') ||
        comun.contains('biznaga')) {
      return 'Especie Sensible Protegida (NOM-059)';
    }
    return null;
  }

  static bool isProtectedSpecies(String nombreComun, [String? nombreCientifico]) =>
      getProtectionStatus(nombreComun, nombreCientifico) != null;
}
