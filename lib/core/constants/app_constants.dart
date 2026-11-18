/// Constantes Nucleares del Sistema BioCampo
/// Cumplimiento de requisitos de ergonomía táctil in-situ y persistencia
class AppConstants {
  // --- Requerimientos Ergonómicos One-Hand (RF-06, RNF-01) ---
  /// Altura mínima de controles interactivos para uso con guantes (dp)
  static const double minTouchTargetSize = 56.0;

  /// Margen inferior de seguridad para navegación con una sola mano
  static const double bottomActionPadding = 24.0;

  // --- Parámetros de Cámara y Multimedia (RF-04, RNF-01) ---
  /// Límite superior de compresión JPEG para optimizar almacenamiento local (Bytes)
  static const int maxPhotoSizeBytes = 800 * 1024; // 800 KB

  /// Target óptimo de compresión JPEG (Bytes)
  static const int targetPhotoSizeBytes = 600 * 1024; // 600 KB

  /// Calidad de compresión JPEG inicial (0-100)
  static const int jpegQualityInitial = 80;

  // --- Parámetros Satelitales GNSS (RF-03, RNF-05) ---
  /// Umbral máximo tolerable de error radial en metros (CEP)
  static const double maxGpsErrorRadiusMeters = 5.0;

  /// Timeout de adquisición de satélites antes de activar fallback manual (segundos)
  static const int gnssTimeoutSeconds = 10;

  // --- Persistencia Transaccional SQLite WAL (RF-02, RNF-02) ---
  static const String databaseName = 'biocampo_offline.db';
  static const int databaseVersion = 1;

  // --- Parámetros de Sincronización Diferida (RF-08, RF-09) ---
  /// Tamaño de bloque atómico para envío en campamento (chunks)
  static const int syncBatchSize = 5;

  /// Base de Exponential Backoff para reintentos en segundos
  static const int backoffBaseSeconds = 2;

  /// Máximo número de reintentos automáticos antes de suspender worker
  static const int maxSyncRetries = 5;

  // --- Nombre de Red de Campamento Autorizada ---
  static const String campWifiSsidPrefix = 'BioCamp-';
}
