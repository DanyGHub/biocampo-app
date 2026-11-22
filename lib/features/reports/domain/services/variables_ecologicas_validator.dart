/// Validador de Variables de Microhábitat y Entorno Ecológico (HU-04 · BIOC-5)
class VariablesEcologicasValidator {
  static const String fallbackDefault = 'No determinado';

  /// Valida y normaliza variables de microhábitat con fallback seguro para captura rápida
  static Map<String, dynamic> validarYNormalizar({
    String? sustrato,
    String? estrato,
    String? condicion,
  }) {
    return {
      'sustrato': _saneado(sustrato),
      'estrato': _saneado(estrato),
      'condicion': _saneado(condicion),
      'timestamp_validacion': DateTime.now().toIso8601String(),
    };
  }

  static String _saneado(String? valor) {
    if (valor == null || valor.trim().isEmpty) {
      return fallbackDefault;
    }
    return valor.trim();
  }
}
