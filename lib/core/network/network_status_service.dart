import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Resultado detallado de la verificación de conectividad real a internet.
class NetworkStatusResult {
  final bool hasInternet;
  final List<ConnectivityResult> transportTypes;
  final String message;

  const NetworkStatusResult({
    required this.hasInternet,
    required this.transportTypes,
    required this.message,
  });

  String get transportLabel {
    if (!hasInternet) return 'Sin conexión';
    if (transportTypes.contains(ConnectivityResult.wifi)) return 'Wi-Fi';
    if (transportTypes.contains(ConnectivityResult.mobile)) return 'Datos móviles';
    if (transportTypes.contains(ConnectivityResult.ethernet)) return 'Ethernet';
    if (transportTypes.contains(ConnectivityResult.vpn)) return 'VPN';
    return 'En línea';
  }
}

/// Servicio encargado de validar la conectividad real de red (Wi-Fi / Datos móviles / Web)
/// antes de autorizar la renderización del mapa cartográfico en línea.
class NetworkStatusService {
  final Future<List<ConnectivityResult>> Function()? _checkConnectivityFn;
  final Future<bool> Function()? _reachabilityFn;
  final Stream<List<ConnectivityResult>>? _connectivityStream;

  NetworkStatusService({
    Future<List<ConnectivityResult>> Function()? checkConnectivityFn,
    Future<bool> Function()? reachabilityFn,
    Stream<List<ConnectivityResult>>? connectivityStream,
  })  : _checkConnectivityFn = checkConnectivityFn,
        _reachabilityFn = reachabilityFn,
        _connectivityStream = connectivityStream;

  /// Stream reactivo de cambios de interfaz de red (Wi-Fi, datos, offline).
  Stream<List<ConnectivityResult>> get onConnectivityChanged {
    final streamOverride = _connectivityStream;
    if (streamOverride != null) {
      return streamOverride;
    }
    try {
      return Connectivity().onConnectivityChanged;
    } catch (_) {
      return const Stream<List<ConnectivityResult>>.empty();
    }
  }

  /// Verifica primero la interfaz activa del dispositivo y después confirma alcance real HTTP
  /// hacia los servidores de mapas para evitar falsos positivos (Wi-Fi sin salida a internet).
  Future<NetworkStatusResult> checkInternetStatus() async {
    final checkConnectivityOverride = _checkConnectivityFn;
    final reachabilityOverride = _reachabilityFn;

    List<ConnectivityResult> results;
    try {
      results = checkConnectivityOverride != null
          ? await checkConnectivityOverride()
          : await Connectivity().checkConnectivity().timeout(
                const Duration(seconds: 3),
                onTimeout: () => const [ConnectivityResult.none],
              );
    } on MissingPluginException {
      // Entorno de pruebas unitarias sin canal nativo conectado
      if (reachabilityOverride == null) {
        return const NetworkStatusResult(
          hasInternet: false,
          transportTypes: [ConnectivityResult.none],
          message: 'Sin conexión a internet verificada.',
        );
      }
      results = const [ConnectivityResult.wifi];
    } catch (e) {
      debugPrint('[NetworkStatusService] Error consultando interfaz de red: $e');
      return const NetworkStatusResult(
        hasInternet: false,
        transportTypes: [ConnectivityResult.none],
        message: 'No fue posible verificar la conectividad de red.',
      );
    }

    final hasRadioOrAdapter = results.isNotEmpty &&
        results.any((r) => r != ConnectivityResult.none);

    if (!hasRadioOrAdapter) {
      return NetworkStatusResult(
        hasInternet: false,
        transportTypes: results,
        message: 'Sin conexión a internet. Activa Wi-Fi o datos móviles para cargar el mapa.',
      );
    }

    final reachable = reachabilityOverride != null
        ? await reachabilityOverride()
        : await _probeMapTileServers();

    if (!reachable) {
      return NetworkStatusResult(
        hasInternet: false,
        transportTypes: results,
        message: 'Sin conexión a internet. Hay señal de red, pero no hay salida a servidores de mapas.',
      );
    }

    return NetworkStatusResult(
      hasInternet: true,
      transportTypes: results,
      message: _buildOnlineMessage(results),
    );
  }

  static String _buildOnlineMessage(List<ConnectivityResult> results) {
    if (results.contains(ConnectivityResult.wifi)) {
      return 'Conectado vía Wi-Fi.';
    }
    if (results.contains(ConnectivityResult.mobile)) {
      return 'Conectado vía datos móviles.';
    }
    if (results.contains(ConnectivityResult.ethernet)) {
      return 'Conectado vía red Ethernet.';
    }
    return 'Conexión a internet activa.';
  }

  /// Sonda ligera con parámetro anti-caché para validar respuesta real del servicio de mapas.
  Future<bool> _probeMapTileServers() async {
    final ts = DateTime.now().millisecondsSinceEpoch;
    final probeUris = [
      Uri.parse('https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/0/0/0?t=$ts'),
      Uri.parse('https://tile.openstreetmap.org/0/0/0.png?t=$ts'),
    ];

    final client = http.Client();
    try {
      for (final uri in probeUris) {
        try {
          final response = await client.head(uri).timeout(const Duration(seconds: 4));
          if (response.statusCode >= 200 && response.statusCode < 400) {
            return true;
          }
        } catch (_) {
          // Intentar siguiente servidor espejo antes de declarar sin conexión
        }
      }
      return false;
    } finally {
      client.close();
    }
  }
}
