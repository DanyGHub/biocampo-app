import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';

/// Estado de autorización y disponibilidad de ubicación para habilitar el mapa real.
enum LocationAccessState {
  granted,
  denied,
  deniedForever,
  serviceDisabled,
  unavailable,
}

/// Datos del sensor satelital GNSS capturados
class GpsTelemetry {
  final double latitude;
  final double longitude;
  final double altitude;
  final double accuracy;
  final bool isSimulated;
  final String statusMessage;
  final DateTime? timestamp;
  final LocationAccessState accessState;
  final bool isPermissionGranted;
  final bool isServiceEnabled;

  const GpsTelemetry({
    required this.latitude,
    required this.longitude,
    required this.altitude,
    required this.accuracy,
    this.isSimulated = false,
    required this.statusMessage,
    this.timestamp,
    this.accessState = LocationAccessState.granted,
    this.isPermissionGranted = true,
    this.isServiceEnabled = true,
  });

  /// Cumple con el requerimiento de calidad RNF-05 (Error radial <= 5m)
  bool get isHighPrecision => accuracy <= 5.0;

  /// Determina si existe permiso autorizado y servicio activo para renderizar el mapa real.
  bool get hasMapAuthorization =>
      isPermissionGranted &&
      isServiceEnabled &&
      accessState == LocationAccessState.granted;

  /// Fecha y hora de captura de la telemetría
  DateTime get recordedAt => timestamp ?? DateTime.now();

  /// Conversión de grados decimales a formato cartográfico Grados, Minutos y Segundos (DMS)
  static String toDms(double decimalDegree, {required bool isLatitude}) {
    final direction = isLatitude
        ? (decimalDegree >= 0 ? 'N' : 'S')
        : (decimalDegree >= 0 ? 'E' : 'W');
    final absVal = decimalDegree.abs();
    final degrees = absVal.floor();
    final minutesNotTruncated = (absVal - degrees) * 60;
    final minutes = minutesNotTruncated.floor();
    final seconds = ((minutesNotTruncated - minutes) * 60).toStringAsFixed(1);
    return "$degrees° $minutes' $seconds\" $direction";
  }

  String get dmsLatitude => toDms(latitude, isLatitude: true);
  String get dmsLongitude => toDms(longitude, isLatitude: false);
  String get dmsString => '$dmsLatitude, $dmsLongitude';

  @override
  String toString() {
    return 'GpsTelemetry(lat: $latitude, lon: $longitude, acc: ±${accuracy}m, sim: $isSimulated, auth: $accessState)';
  }
}

/// Servicio de Geolocalización Satelital (GNSS) y Permisos de BioCampo (Web y Móvil).
/// Cumple con RF-03, RNF-05 y control estricto de permisos antes de mostrar cartografía en línea.
class LocationService {
  static const double _fallbackLat = 22.1524;
  static const double _fallbackLon = -102.6142;
  static const double _fallbackAlt = 2450.0;

  /// Abre los ajustes de aplicación en dispositivos móviles para otorgar permisos bloqueados.
  /// En Web retorna false de forma segura sin lanzar excepciones.
  static Future<bool> openDeviceAppSettings() async {
    if (kIsWeb) return false;
    try {
      return await Geolocator.openAppSettings();
    } catch (_) {
      return false;
    }
  }

  /// Abre los ajustes de ubicación/GPS en dispositivos móviles.
  /// En Web retorna false de forma segura sin lanzar excepciones.
  static Future<bool> openDeviceLocationSettings() async {
    if (kIsWeb) return false;
    try {
      return await Geolocator.openLocationSettings();
    } catch (_) {
      return false;
    }
  }

  /// Adquiere las coordenadas geográficas actuales del dispositivo mediante GNSS/Navegador.
  /// Si [requestPermissionIfDenied] es true, solicita al usuario el permiso en Android o Web.
  static Future<GpsTelemetry> getCurrentLocation({
    bool requestPermissionIfDenied = true,
  }) async {
    try {
      final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        return const GpsTelemetry(
          latitude: _fallbackLat,
          longitude: _fallbackLon,
          altitude: _fallbackAlt,
          accuracy: 3.5,
          isSimulated: true,
          accessState: LocationAccessState.serviceDisabled,
          isPermissionGranted: false,
          isServiceEnabled: false,
          statusMessage:
              'Servicios de ubicación (GPS) desactivados. Activa la ubicación para ver el mapa.',
        );
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.unableToDetermine) {
        if (!requestPermissionIfDenied) {
          return const GpsTelemetry(
            latitude: _fallbackLat,
            longitude: _fallbackLon,
            altitude: _fallbackAlt,
            accuracy: 4.2,
            isSimulated: true,
            accessState: LocationAccessState.denied,
            isPermissionGranted: false,
            isServiceEnabled: true,
            statusMessage:
                'Faltan permisos de ubicación. Autoriza el acceso para visualizar el mapa.',
          );
        }

        permission = await Geolocator.requestPermission();
        // En Web geolocator_web envuelve errores transitorios como deniedForever;
        // reconsultamos checkPermission() para conocer el estado real del navegador.
        if (kIsWeb && permission == LocationPermission.deniedForever) {
          final verified = await Geolocator.checkPermission();
          if (verified != LocationPermission.unableToDetermine) {
            permission = verified;
          }
        }

        if (permission == LocationPermission.denied ||
            permission == LocationPermission.unableToDetermine) {
          return const GpsTelemetry(
            latitude: _fallbackLat,
            longitude: _fallbackLon,
            altitude: _fallbackAlt,
            accuracy: 4.2,
            isSimulated: true,
            accessState: LocationAccessState.denied,
            isPermissionGranted: false,
            isServiceEnabled: true,
            statusMessage:
                'Faltan permisos de ubicación. Se requiere autorización del usuario.',
          );
        }
      }

      if (permission == LocationPermission.deniedForever) {
        return const GpsTelemetry(
          latitude: _fallbackLat,
          longitude: _fallbackLon,
          altitude: _fallbackAlt,
          accuracy: 4.0,
          isSimulated: true,
          accessState: LocationAccessState.deniedForever,
          isPermissionGranted: false,
          isServiceEnabled: true,
          statusMessage: kIsWeb
              ? 'Permiso de ubicación bloqueado en el navegador. Habilítalo en los ajustes del sitio.'
              : 'Permisos de ubicación denegados permanentemente. Habilítalos en los ajustes del dispositivo.',
        );
      }

      // Permiso otorgado: intentar adquisición de alta precisión GNSS con respaldo de precisión media
      Position? position;
      try {
        position = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: const Duration(seconds: 10),
        );
      } catch (e) {
        debugPrint('[LocationService] Alta precisión no disponible ($e). Reintentando con precisión estándar...');
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: const Duration(seconds: 8),
          );
        } catch (e2) {
          debugPrint('[LocationService] Precisión estándar falló ($e2).');
          if (!kIsWeb) {
            position = await Geolocator.getLastKnownPosition();
          }
        }
      }

      if (position == null) {
        return const GpsTelemetry(
          latitude: _fallbackLat,
          longitude: _fallbackLon,
          altitude: _fallbackAlt,
          accuracy: 4.5,
          isSimulated: true,
          accessState: LocationAccessState.unavailable,
          isPermissionGranted: true,
          isServiceEnabled: true,
          statusMessage:
              'Permiso autorizado, pero no se pudo fijar la señal de ubicación del equipo. Intenta nuevamente.',
        );
      }

      return GpsTelemetry(
        latitude: position.latitude,
        longitude: position.longitude,
        altitude: position.altitude,
        accuracy: position.accuracy,
        isSimulated: false,
        timestamp: position.timestamp,
        accessState: LocationAccessState.granted,
        isPermissionGranted: true,
        isServiceEnabled: true,
        statusMessage:
            'Ubicación Real Activa (±${position.accuracy.toStringAsFixed(1)} m)',
      );
    } on MissingPluginException {
      debugPrint('[LocationService] Plugin GNSS no registrado en entorno de prueba. Usando telemetría de respaldo.');
      return const GpsTelemetry(
        latitude: _fallbackLat,
        longitude: _fallbackLon,
        altitude: _fallbackAlt,
        accuracy: 3.8,
        isSimulated: true,
        accessState: LocationAccessState.denied,
        isPermissionGranted: false,
        isServiceEnabled: false,
        statusMessage:
            'Faltan permisos o hardware GNSS disponible en este entorno.',
      );
    } catch (e) {
      debugPrint('[LocationService] Excepción de geolocalización: $e');
      return const GpsTelemetry(
        latitude: _fallbackLat,
        longitude: _fallbackLon,
        altitude: _fallbackAlt,
        accuracy: 3.8,
        isSimulated: true,
        accessState: LocationAccessState.unavailable,
        isPermissionGranted: false,
        isServiceEnabled: true,
        statusMessage:
            'No fue posible obtener la ubicación del dispositivo. Revisa los permisos e intenta nuevamente.',
      );
    }
  }
}
