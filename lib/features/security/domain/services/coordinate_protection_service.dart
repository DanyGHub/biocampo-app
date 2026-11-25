/// HU-07: contrato inicial S06. No implementa ni certifica AES-256.
class CoordinateProtectionService {
  String protect(String coordinate) {
    throw UnimplementedError('HU-07: proteccion de coordenadas pendiente');
  }

  String? reveal(String encrypted, {required bool authorized}) {
    throw UnimplementedError('HU-07: politica de acceso pendiente');
  }
}
