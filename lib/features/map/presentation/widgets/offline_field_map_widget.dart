import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:biocampo_app/features/location/domain/services/location_service.dart';
import 'package:biocampo_app/features/map/domain/services/offline_map_service.dart';

/// Visor Cartográfico Georreferenciado en Tiempo Real (HU-05 · BIOC-6).
/// Utiliza cartografía real (CartoDB Voyager / OpenStreetMap / Esri Topo / Satelital)
/// mediante `flutter_map` con control estricto de permisos de ubicación y conectividad a internet.
class OfflineFieldMapWidget extends StatefulWidget {
  final double centerLat;
  final double centerLon;
  final double accuracyMeters;
  final List<OfflineMapMarker> markers;
  final double height;
  final bool compact;
  final VoidCallback? onRecenter;

  /// Controles de autorización de acceso al mapa real (Permisos + Internet).
  final LocationAccessState locationAccessState;
  final bool hasInternet;
  final bool isCheckingAccess;
  final VoidCallback? onRequestLocationPermission;
  final VoidCallback? onOpenLocationSettings;
  final VoidCallback? onRetryConnection;
  final VoidCallback? onTileNetworkError;
  final TileProvider? customTileProvider;

  const OfflineFieldMapWidget({
    super.key,
    required this.centerLat,
    required this.centerLon,
    required this.accuracyMeters,
    required this.markers,
    this.height = 410,
    this.compact = false,
    this.onRecenter,
    this.locationAccessState = LocationAccessState.granted,
    this.hasInternet = true,
    this.isCheckingAccess = false,
    this.onRequestLocationPermission,
    this.onOpenLocationSettings,
    this.onRetryConnection,
    this.onTileNetworkError,
    this.customTileProvider,
  });

  @override
  State<OfflineFieldMapWidget> createState() => _OfflineFieldMapWidgetState();
}

class _OfflineFieldMapWidgetState extends State<OfflineFieldMapWidget> {
  final MapController _mapController = MapController();

  MapLayerType _activeLayer = MapLayerType.estandar;
  bool _showMarkersLayer = true;
  bool _showProtectedZoneLayer = true;
  bool _showWgs84Grid = false;
  bool _showLayerMenu = false;

  bool _isMapReady = false;
  double _displayedZoom = 15.5;
  OfflineMapMarker? _selectedMarker;

  bool get _hasLocationPermission =>
      widget.locationAccessState == LocationAccessState.granted;

  bool get _canShowRealMap => _hasLocationPermission && widget.hasInternet;

  @override
  void didUpdateWidget(covariant OfflineFieldMapWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    final coordsChanged = oldWidget.centerLat != widget.centerLat ||
        oldWidget.centerLon != widget.centerLon;
    final becameUnlocked =
        (!oldWidget.hasInternet || oldWidget.locationAccessState != LocationAccessState.granted) &&
            _canShowRealMap;

    if (coordsChanged && _canShowRealMap && _isMapReady && !becameUnlocked) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isMapReady) {
          _mapController.move(
            LatLng(widget.centerLat, widget.centerLon),
            _displayedZoom,
          );
        }
      });
    }
    if (!_canShowRealMap) {
      _isMapReady = false;
      _selectedMarker = null;
      _showLayerMenu = false;
    }
  }

  void _zoomBy(double delta) {
    if (!_isMapReady) return;
    final nextZoom = (_displayedZoom + delta).clamp(3.0, 18.5);
    _mapController.move(_mapController.camera.center, nextZoom);
    setState(() => _displayedZoom = nextZoom);
  }

  void _recenterMap() {
    if (_isMapReady) {
      _mapController.move(LatLng(widget.centerLat, widget.centerLon), 15.5);
      setState(() => _displayedZoom = 15.5);
    }
    widget.onRecenter?.call();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: widget.height,
      decoration: BoxDecoration(
        color: const Color(0xFFE5ECEE),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _canShowRealMap ? const Color(0xFFCBD5E1) : const Color(0xFFFCA5A5),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x120F172A),
            blurRadius: 14,
            offset: Offset(0, 5),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16.5),
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    if (widget.isCheckingAccess && !_canShowRealMap) {
      return _buildCheckingAccessCard();
    }
    if (!_hasLocationPermission) {
      return _buildPermissionDeniedCard();
    }
    if (!widget.hasInternet) {
      return _buildNoInternetCard();
    }
    return _buildRealInteractiveMap();
  }

  Widget _buildCheckingAccessCard() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFF8FAFC),
      padding: const EdgeInsets.all(20),
      child: const Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CircularProgressIndicator(color: Color(0xFF00796B), strokeWidth: 2.8),
          SizedBox(height: 14),
          Text(
            'Verificando permisos de ubicación y conexión a internet...',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 13.5,
              fontWeight: FontWeight.w600,
              color: Color(0xFF334155),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionDeniedCard() {
    final state = widget.locationAccessState;
    final String headline;
    final String description;
    final String primaryButtonLabel;
    final IconData primaryButtonIcon;
    final VoidCallback? primaryAction;

    switch (state) {
      case LocationAccessState.serviceDisabled:
        headline = 'GPS del dispositivo desactivado';
        description =
            'Activa los servicios de ubicación (GPS) del dispositivo para cargar el mapa en tu posición actual.';
        primaryButtonLabel =
            kIsWeb ? 'Otorgar permisos de ubicación' : 'Activar ubicación / GPS';
        primaryButtonIcon = Icons.gps_fixed_rounded;
        primaryAction = widget.onOpenLocationSettings ?? widget.onRequestLocationPermission;
      case LocationAccessState.deniedForever:
        headline = 'Faltan permisos de ubicación (denegados)';
        description = kIsWeb
            ? 'El permiso de ubicación está bloqueado en el navegador. Habilítalo en el ícono de ajustes/candado junto a la barra de direcciones (Ubicación → Permitir) y presiona el botón.'
            : 'Los permisos de ubicación fueron denegados permanentemente. Habilita el permiso de Ubicación para BioCampo en los ajustes de tu teléfono.';
        primaryButtonLabel = kIsWeb
            ? 'Otorgar permisos de ubicación'
            : 'Abrir ajustes y otorgar permisos';
        primaryButtonIcon = kIsWeb ? Icons.my_location_rounded : Icons.settings_rounded;
        primaryAction = widget.onRequestLocationPermission;
      case LocationAccessState.unavailable:
        headline = 'Ubicación actual no disponible';
        description =
            'El permiso está autorizado, pero no se recibió respuesta de coordenadas. Verifica la ubicación del equipo y vuelve a intentar.';
        primaryButtonLabel = 'Reintentar ubicación GPS';
        primaryButtonIcon = Icons.refresh_rounded;
        primaryAction = widget.onRequestLocationPermission;
      case LocationAccessState.denied:
      case LocationAccessState.granted:
        headline = 'Faltan permisos de ubicación';
        description =
            'Vista de mapa bloqueada: debes autorizar el acceso a la ubicación del dispositivo para mostrar el mapa real en tu zona.';
        primaryButtonLabel = 'Otorgar permisos de ubicación';
        primaryButtonIcon = Icons.my_location_rounded;
        primaryAction = widget.onRequestLocationPermission;
    }

    return Container(
      width: double.infinity,
      color: const Color(0xFFFEF2F2),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: widget.compact ? 14 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.compact ? 44 : 56,
                height: widget.compact ? 44 : 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEE2E2),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFCA5A5), width: 1.5),
                ),
                child: Icon(
                  state == LocationAccessState.serviceDisabled
                      ? Icons.location_disabled_rounded
                      : Icons.wrong_location_rounded,
                  color: const Color(0xFFC62828),
                  size: widget.compact ? 24 : 30,
                ),
              ),
              SizedBox(height: widget.compact ? 8 : 12),
              Text(
                headline,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: widget.compact ? 14.5 : 16.5,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF7F1D1D),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                description,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: widget.compact ? 12 : 13,
                  color: const Color(0xFF475569),
                  height: 1.35,
                ),
              ),
              if (!widget.hasInternet) ...[
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFEF3C7),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFCD34D)),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.wifi_off_rounded, size: 14, color: Color(0xFFB45309)),
                      SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          'También falta conexión a internet para cargar el mapa.',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w600,
                            color: Color(0xFF92400E),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              SizedBox(height: widget.compact ? 10 : 16),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(64, 42),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    icon: Icon(primaryButtonIcon, size: 18),
                    label: Text(
                      primaryButtonLabel,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                    ),
                    onPressed: primaryAction,
                  ),
                  if (!kIsWeb &&
                      (state == LocationAccessState.deniedForever ||
                          state == LocationAccessState.serviceDisabled))
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFF0F2F38),
                        minimumSize: const Size(64, 42),
                        side: const BorderSide(color: Color(0xFF94A3B8)),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.refresh_rounded, size: 17),
                      label: const Text('Verificar permiso', style: TextStyle(fontSize: 12.5)),
                      onPressed: widget.onRetryConnection,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildNoInternetCard() {
    return Container(
      width: double.infinity,
      color: const Color(0xFFFFFBEB),
      child: Center(
        child: SingleChildScrollView(
          padding: EdgeInsets.symmetric(
            horizontal: 20,
            vertical: widget.compact ? 14 : 24,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: widget.compact ? 44 : 56,
                height: widget.compact ? 44 : 56,
                decoration: BoxDecoration(
                  color: const Color(0xFFFEF3C7),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFFFCD34D), width: 1.5),
                ),
                child: Icon(
                  Icons.wifi_off_rounded,
                  color: const Color(0xFFD97706),
                  size: widget.compact ? 24 : 30,
                ),
              ),
              SizedBox(height: widget.compact ? 8 : 12),
              Text(
                'Sin conexión a internet',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: widget.compact ? 14.5 : 16.5,
                  fontWeight: FontWeight.bold,
                  color: const Color(0xFF92400E),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Vista de mapa bloqueada: se requiere conexión Wi-Fi o datos móviles activos para mostrar el mapa real de tu ubicación.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: widget.compact ? 12 : 13,
                  color: const Color(0xFF475569),
                  height: 1.35,
                ),
              ),
              SizedBox(height: widget.compact ? 10 : 16),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFD97706),
                  foregroundColor: Colors.white,
                  minimumSize: const Size(64, 42),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: const Text(
                  'Reintentar conexión',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                onPressed: widget.onRetryConnection,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildRealInteractiveMap() {
    final centerPoint = LatLng(widget.centerLat, widget.centerLon);
    final TileProvider effectiveTileProvider = widget.customTileProvider ??
        NetworkTileProvider(
          silenceExceptions: true,
          cachingProvider: const DisabledMapCachingProvider(),
        );

    final circles = <CircleMarker>[
      // Halo de precisión GNSS alrededor del usuario (estilo Google Maps)
      CircleMarker(
        point: centerPoint,
        radius: widget.accuracyMeters.clamp(8.0, 200.0),
        useRadiusInMeter: true,
        color: const Color(0x2E1A73E8),
        borderColor: const Color(0x881A73E8),
        borderStrokeWidth: 1.3,
      ),
      if (_showProtectedZoneLayer)
        CircleMarker(
          point: centerPoint,
          radius: 320.0,
          useRadiusInMeter: true,
          color: const Color(0x1400796B),
          borderColor: const Color(0x7700796B),
          borderStrokeWidth: 1.5,
        ),
      if (_showMarkersLayer)
        for (final m in widget.markers.where((mk) => mk.isProtected))
          CircleMarker(
            point: LatLng(m.latitude, m.longitude),
            radius: 5000.0, // Radio protector real ±5 km (HU-07)
            useRadiusInMeter: true,
            color: const Color(0x1EF59E0B),
            borderColor: const Color(0x99D97706),
            borderStrokeWidth: 1.4,
          ),
    ];

    final mapMarkers = <Marker>[
      // Marcador azul de ubicación real actual del usuario
      Marker(
        point: centerPoint,
        width: 28,
        height: 28,
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF1A73E8),
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 3),
            boxShadow: const [
              BoxShadow(
                color: Color(0x55000000),
                blurRadius: 6,
                offset: Offset(0, 2),
              ),
            ],
          ),
        ),
      ),
      if (_showMarkersLayer)
        for (final marker in widget.markers) _buildFlutterMapMarker(marker),
    ];

    return Stack(
      children: [
        // 1. Mapa Real Interactivo con Tiles Cartográficos en Línea
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: centerPoint,
            initialZoom: _displayedZoom,
            minZoom: 3.0,
            maxZoom: 18.5,
            backgroundColor: const Color(0xFFE5ECEE),
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onMapReady: () {
              if (mounted) {
                setState(() => _isMapReady = true);
              }
            },
            onTap: (_, __) {
              if (_showLayerMenu || _selectedMarker != null) {
                setState(() {
                  _showLayerMenu = false;
                  _selectedMarker = null;
                });
              }
            },
            onPositionChanged: (camera, _) {
              if ((camera.zoom - _displayedZoom).abs() >= 0.25 && mounted) {
                setState(() => _displayedZoom = camera.zoom);
              } else {
                _displayedZoom = camera.zoom;
              }
            },
          ),
          children: [
            TileLayer(
              key: ValueKey<MapLayerType>(_activeLayer),
              urlTemplate: _activeLayer.tileUrlTemplate,
              fallbackUrl: _activeLayer.fallbackUrlTemplate,
              userAgentPackageName: 'com.example.biocampo_app',
              maxNativeZoom: 18,
              tileProvider: effectiveTileProvider,
              errorTileCallback: (tile, error, stackTrace) {
                widget.onTileNetworkError?.call();
              },
            ),
            CircleLayer(circles: circles),
            MarkerLayer(markers: mapMarkers),
          ],
        ),

        // 2. Cuadrícula WGS84 opcional superpuesta
        if (_showWgs84Grid)
          const Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _Wgs84GridOverlayPainter()),
            ),
          ),

        // 3. Cabecera flotante estilo Google Maps
        Positioned(
          top: 10,
          left: 10,
          right: widget.compact ? 10 : 58,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.95),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: const Color(0xFFE2E8F0)),
              boxShadow: const [
                BoxShadow(color: Color(0x1A0F172A), blurRadius: 8, offset: Offset(0, 2)),
              ],
            ),
            child: Row(
              children: [
                const Icon(Icons.map_rounded, size: 17, color: Color(0xFF00796B)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.compact
                        ? '${widget.centerLat.toStringAsFixed(4)}, ${widget.centerLon.toStringAsFixed(4)} · Mapa Real'
                        : '${_activeLayer.label} · ${widget.centerLat.toStringAsFixed(4)}, ${widget.centerLon.toStringAsFixed(4)}',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Text(
                    'EN LÍNEA',
                    style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                  ),
                ),
              ],
            ),
          ),
        ),

        // 4. Botón flotante de Capas (Top-Right)
        if (!widget.compact)
          Positioned(
            top: 10,
            right: 10,
            child: Material(
              color: Colors.white.withValues(alpha: 0.95),
              shape: const CircleBorder(),
              elevation: 3,
              child: IconButton(
                icon: Icon(
                  Icons.layers_rounded,
                  color: _showLayerMenu ? const Color(0xFF00796B) : const Color(0xFF334155),
                  size: 20,
                ),
                tooltip: 'Capas del mapa',
                constraints: const BoxConstraints.tightFor(width: 40, height: 40),
                padding: EdgeInsets.zero,
                onPressed: () => setState(() => _showLayerMenu = !_showLayerMenu),
              ),
            ),
          ),

        // 5. Menú flotante de Capas Cartográficas
        if (_showLayerMenu && !widget.compact)
          Positioned(
            top: 56,
            right: 10,
            width: 245,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFCBD5E1)),
                boxShadow: const [
                  BoxShadow(color: Color(0x260F172A), blurRadius: 12, offset: Offset(0, 4)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Tipo de Mapa Base',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: MapLayerType.values.map((layer) {
                      final selected = layer == _activeLayer;
                      return ChoiceChip(
                        label: Text(
                          layer.label.split(' ').first,
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: selected ? Colors.white : const Color(0xFF334155),
                          ),
                        ),
                        selected: selected,
                        selectedColor: const Color(0xFF00796B),
                        backgroundColor: const Color(0xFFF1F5F9),
                        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        visualDensity: VisualDensity.compact,
                        onSelected: (_) => setState(() => _activeLayer = layer),
                      );
                    }).toList(),
                  ),
                  const Divider(height: 14),
                  const Text(
                    'Capas Superpuestas',
                    style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                  ),
                  _buildLayerToggle('Avistamientos', _showMarkersLayer, (v) => setState(() => _showMarkersLayer = v)),
                  _buildLayerToggle('Área Protegida', _showProtectedZoneLayer, (v) => setState(() => _showProtectedZoneLayer = v)),
                  _buildLayerToggle('Cuadrícula WGS84', _showWgs84Grid, (v) => setState(() => _showWgs84Grid = v)),
                ],
              ),
            ),
          ),

        // 6. Controles flotantes de Zoom (+ / -) y Centrar (Bottom-Right)
        Positioned(
          bottom: _selectedMarker != null ? 105 : 12,
          right: 10,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.95),
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: const [
                    BoxShadow(color: Color(0x1F0F172A), blurRadius: 6, offset: Offset(0, 2)),
                  ],
                ),
                child: Column(
                  children: [
                    _mapControlButton(Icons.add_rounded, 'Acercar', () => _zoomBy(1.0)),
                    const SizedBox(width: 28, child: Divider(height: 1, color: Color(0xFFE2E8F0))),
                    _mapControlButton(Icons.remove_rounded, 'Alejar', () => _zoomBy(-1.0)),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Material(
                color: Colors.white.withValues(alpha: 0.95),
                shape: const CircleBorder(),
                elevation: 3,
                child: IconButton(
                  icon: const Icon(Icons.my_location_rounded, size: 19, color: Color(0xFF1A73E8)),
                  tooltip: 'Centrar en mi ubicación',
                  constraints: const BoxConstraints.tightFor(width: 38, height: 38),
                  padding: EdgeInsets.zero,
                  onPressed: _recenterMap,
                ),
              ),
            ],
          ),
        ),

        // 7. Barra de Zoom, Pines y Atribución Cartográfica (Bottom-Left)
        if (_selectedMarker == null)
          Positioned(
            bottom: 10,
            left: 10,
            right: 64,
            child: Align(
              alignment: Alignment.bottomLeft,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.explore_outlined, size: 14, color: Color(0xFF00796B)),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.compact
                              ? 'Z${_displayedZoom.toStringAsFixed(0)} · ${widget.markers.length} pines'
                              : 'N | Z${_displayedZoom.toStringAsFixed(1)} · ${widget.markers.length} pines · ${_activeLayer.attributionText}',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF334155),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),

        // 8. Tarjeta inferior de detalle al tocar un marcador
        if (_selectedMarker != null)
          Positioned(
            left: 10,
            right: 10,
            bottom: 10,
            child: _buildMarkerDetailCard(_selectedMarker!),
          ),
      ],
    );
  }

  Marker _buildFlutterMapMarker(OfflineMapMarker marker) {
    final isSelected = _selectedMarker?.id == marker.id;
    final Color pinColor = marker.isProtected
        ? const Color(0xFFD97706)
        : (marker.isReferencePoint ? const Color(0xFF334155) : const Color(0xFF00796B));
    final IconData pinIcon = marker.isProtected
        ? Icons.lock_rounded
        : (marker.isReferencePoint ? Icons.flag_rounded : Icons.eco_rounded);

    return Marker(
      point: LatLng(marker.latitude, marker.longitude),
      width: 118,
      height: 52,
      alignment: Alignment.topCenter,
      child: GestureDetector(
        onTap: () => setState(() {
          _showLayerMenu = false;
          _selectedMarker = marker;
        }),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected ? pinColor : Colors.white.withValues(alpha: 0.94),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: pinColor, width: 1),
                boxShadow: const [
                  BoxShadow(color: Color(0x22000000), blurRadius: 4, offset: Offset(0, 1)),
                ],
              ),
              child: Text(
                marker.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 9.5,
                  fontWeight: FontWeight.bold,
                  color: isSelected ? Colors.white : const Color(0xFF0F2F38),
                ),
              ),
            ),
            const SizedBox(height: 2),
            Container(
              width: isSelected ? 28 : 24,
              height: isSelected ? 28 : 24,
              decoration: BoxDecoration(
                color: pinColor,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white, width: 2),
                boxShadow: const [
                  BoxShadow(color: Color(0x3D000000), blurRadius: 4, offset: Offset(0, 2)),
                ],
              ),
              child: Icon(pinIcon, color: Colors.white, size: isSelected ? 15 : 13),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLayerToggle(String label, bool value, ValueChanged<bool> onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, color: Color(0xFF334155)),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              value ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              size: 18,
              color: value ? const Color(0xFF00796B) : const Color(0xFF94A3B8),
            ),
          ],
        ),
      ),
    );
  }

  Widget _mapControlButton(IconData icon, String tooltip, VoidCallback onPressed) {
    return IconButton(
      icon: Icon(icon, size: 19, color: const Color(0xFF334155)),
      tooltip: tooltip,
      constraints: const BoxConstraints.tightFor(width: 36, height: 34),
      padding: EdgeInsets.zero,
      onPressed: onPressed,
    );
  }

  Widget _buildMarkerDetailCard(OfflineMapMarker marker) {
    final report = marker.report;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: marker.isProtected ? const Color(0xFFF59E0B) : const Color(0xFFCBD5E1)),
        boxShadow: const [
          BoxShadow(color: Color(0x290F172A), blurRadius: 10, offset: Offset(0, 3)),
        ],
      ),
      child: Row(
        children: [
          if (report?.fotoBytesBase64 != null && report!.fotoBytesBase64!.isNotEmpty)
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.memory(
                base64Decode(report.fotoBytesBase64!),
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _markerIconBadge(marker),
              ),
            )
          else
            _markerIconBadge(marker),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  marker.title,
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  marker.subtitle,
                  style: TextStyle(
                    fontSize: 11,
                    color: marker.isProtected ? const Color(0xFFB45309) : const Color(0xFF475569),
                    fontWeight: marker.isProtected ? FontWeight.w600 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  '${marker.latitude.toStringAsFixed(4)}, ${marker.longitude.toStringAsFixed(4)}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF64748B)),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 18, color: Color(0xFF64748B)),
            onPressed: () => setState(() => _selectedMarker = null),
          ),
        ],
      ),
    );
  }

  Widget _markerIconBadge(OfflineMapMarker marker) {
    return Container(
      width: 44,
      height: 44,
      decoration: BoxDecoration(
        color: marker.isProtected ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2F1),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Icon(
        marker.isProtected
            ? Icons.shield_rounded
            : (marker.isReferencePoint ? Icons.flag_rounded : Icons.eco_rounded),
        color: marker.isProtected ? const Color(0xFFD97706) : const Color(0xFF00796B),
      ),
    );
  }
}

class _Wgs84GridOverlayPainter extends CustomPainter {
  const _Wgs84GridOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final gridPaint = Paint()
      ..color = const Color(0x280F2F38)
      ..strokeWidth = 0.8;
    const step = 64.0;
    for (double x = step; x < size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), gridPaint);
    }
    for (double y = step; y < size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), gridPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _Wgs84GridOverlayPainter oldDelegate) => false;
}
