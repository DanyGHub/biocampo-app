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
    },
    {
      'scientificName': 'Aquila chrysaetos',
      'vernacularName': 'Águila real',
      'kingdom': 'Animalia',
      'family': 'Accipitridae',
      'taxonRank': 'Species',
    },
    {
      'scientificName': 'Mammillaria marksiana',
      'vernacularName': 'Biznaguita',
      'kingdom': 'Plantae',
      'family': 'Cactaceae',
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
}
