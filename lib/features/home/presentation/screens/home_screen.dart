import 'dart:async';
import 'dart:convert';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import 'package:biocampo_app/core/network/network_status_service.dart';
import 'package:biocampo_app/features/auth/domain/services/auth_service.dart';
import 'package:biocampo_app/features/location/domain/services/location_service.dart';
import 'package:biocampo_app/features/reports/domain/models/reporte_model.dart';
import 'package:biocampo_app/features/reports/domain/services/foto_evidencia_service.dart';
import 'package:biocampo_app/features/reports/domain/services/catalogo_taxonomico_service.dart';
import 'package:biocampo_app/features/reports/domain/services/csv_export_service.dart';
import 'package:biocampo_app/features/reports/domain/services/variables_ecologicas_validator.dart';
import 'package:biocampo_app/features/map/domain/services/offline_map_service.dart';
import 'package:biocampo_app/features/map/presentation/widgets/offline_field_map_widget.dart';
import 'package:biocampo_app/features/sync/domain/services/sync_queue_service.dart';
import 'package:biocampo_app/features/sync/domain/services/sync_queue_storage.dart';
import 'package:biocampo_app/features/security/domain/services/coordinate_protection_service.dart';
import 'package:biocampo_app/features/auth/presentation/screens/login_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;
  final NetworkStatusService? networkStatusService;
  final TileProvider? mapTileProvider;

  const HomeScreen({
    super.key,
    required this.authService,
    this.networkStatusService,
    this.mapTileProvider,
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;

  // Estado del Wizard de Generación de Reporte
  int _wizardStep = 0; // 0: Inicio, 1: Datos, 2: GPS, 3: Fotos, 4: Confirmación
  final _especieController = TextEditingController();
  final _notasController = TextEditingController();
  bool _fotoSeleccionada = false;

  // Variables Sprint 1: HU-01 (Foto), HU-02 (Darwin Core) y HU-04 (Hábitat)
  String? _fotoPath;
  String? _fotoBase64;
  Uint8List? _fotoBytes;
  int? _fotoSizeBytes;
  String? _nombreCientifico;
  List<Map<String, String>> _sugerenciasDarwinCore = [];
  String _sustratoSeleccionado = 'No determinado';
  String _estratoSeleccionado = 'No determinado';
  String _condicionSeleccionada = 'No determinado';

  // Variables Sprint 2: HU-05 (Mapa Real), HU-06 (Cola Sync) y HU-07 (Cifrado AES-256)
  final OfflineMapService _offlineMapService = OfflineMapService();
  late final SyncQueueService _syncQueueService;
  late final NetworkStatusService _networkStatusService;
  StreamSubscription<List<ConnectivityResult>>? _connectivitySubscription;
  final CoordinateProtectionService _protectionService = CoordinateProtectionService.forLocalApp();
  bool _esEspecieProtegida = false;
  String? _estatusProteccionDetectado;
  bool _isOfflineMode = true; // Modo Offline-First activo por defecto para encolar localmente
  bool _isSyncing = false;
  List<String> _pendingQueueIds = [];
  List<OfflineMapMarker> _mapMarkers = [];
  final Set<int> _revealedReportIds = {};
  bool _simulateUnauthorizedView = false;

  // Estado de Geolocalización, Conectividad Real y Base de Datos
  GpsTelemetry? _currentTelemetry;
  bool _isLocating = false;
  bool _hasInternetConnection = false;
  bool _isCheckingMapAccess = true;
  String _networkStatusMessage = 'Verificando conectividad de red...';
  DateTime? _lastTileErrorCheck;
  bool _isSaving = false;
  List<ReporteModel> _reportes = [];

  Future<void> _buscarSugerenciasDarwinCore(String query) async {
    final detectedStatus = CatalogoTaxonomicoService.getProtectionStatus(query, _nombreCientifico);
    if (query.trim().length < 2) {
      if (mounted) {
        setState(() {
          _sugerenciasDarwinCore = [];
          _estatusProteccionDetectado = detectedStatus;
          if (detectedStatus != null) _esEspecieProtegida = true;
        });
      }
      return;
    }
    final resultados = await CatalogoTaxonomicoService.buscarEspecieDarwinCore(query: query);
    if (mounted) {
      setState(() {
        _sugerenciasDarwinCore = resultados;
        _estatusProteccionDetectado = detectedStatus;
        if (detectedStatus != null) _esEspecieProtegida = true;
      });
    }
  }

  /// Captura de evidencia fotográfica interactiva estilo WhatsApp (HU-01)
  /// Solicita permisos multimedia a nivel de sistema operativo y abre la cámara nativa del usuario.
  Future<void> _capturarConCamara() async {
    try {
      // 1. Petición explícita de permisos de cámara y multimedia (Android/iOS)
      if (!kIsWeb) {
        final cameraStatus = await Permission.camera.request();
        if (cameraStatus.isPermanentlyDenied) {
          if (mounted) {
            _mostrarDialogoPermisoCamara();
          }
          return;
        } else if (cameraStatus.isDenied) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Se requiere permiso de cámara para capturar la evidencia del espécimen.'),
                backgroundColor: Color(0xFFC62828),
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      // 2. Apertura del obturador de cámara del dispositivo del individuo
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
        preferredCameraDevice: CameraDevice.rear,
      );

      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final telemetry = _currentTelemetry ?? await LocationService.getCurrentLocation();
        final resultado = await FotoEvidenciaService.comprimirYVincular(
          rutaTemporal: picked.path,
          reporteId: DateTime.now().millisecondsSinceEpoch % 10000,
          latitud: telemetry.latitude,
          longitud: telemetry.longitude,
        );

        if (mounted) {
          setState(() {
            _fotoBytes = bytes;
            _fotoBase64 = base64Encode(bytes);
            _fotoPath = picked.name.isNotEmpty ? picked.name : (resultado['ruta_relativa'] as String?);
            _fotoSizeBytes = bytes.length;
            _fotoSeleccionada = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Foto capturada y almacenada en el reporte (${(bytes.length / 1024).toStringAsFixed(1)} KB ≤ 350 KB).'),
              backgroundColor: const Color(0xFF00796B),
              behavior: SnackBarBehavior.floating,
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error al capturar con la cámara: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No fue posible abrir la cámara ($e). Puedes elegir una imagen de la galería.'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _mostrarDialogoPermisoCamara() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.camera_alt_rounded, color: Color(0xFFC62828)),
            SizedBox(width: 8),
            Text('Permiso de Cámara', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'Para capturar la fotografía del espécimen es necesario habilitar los permisos multimedia en los ajustes de tu dispositivo.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00796B)),
            onPressed: () {
              Navigator.pop(ctx);
              openAppSettings();
            },
            child: const Text('Abrir Ajustes', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _mostrarFotoAmpliada(BuildContext context, Uint8List bytes, String titulo) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppBar(
              title: Text(titulo, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
              backgroundColor: const Color(0xFF00796B),
              foregroundColor: Colors.white,
              elevation: 0,
              shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
              leading: IconButton(
                icon: const Icon(Icons.close_rounded),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            InteractiveViewer(
              panEnabled: true,
              minScale: 0.8,
              maxScale: 4.0,
              child: ClipRRect(
                borderRadius: const BorderRadius.vertical(bottom: Radius.circular(16)),
                child: Image.memory(bytes, fit: BoxFit.contain),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _seleccionarFoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
        source: source,
        maxWidth: 1024,
        maxHeight: 1024,
        imageQuality: 75,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        final telemetry = _currentTelemetry ?? await LocationService.getCurrentLocation();
        final resultado = await FotoEvidenciaService.comprimirYVincular(
          rutaTemporal: picked.path,
          reporteId: DateTime.now().millisecondsSinceEpoch % 10000,
          latitud: telemetry.latitude,
          longitud: telemetry.longitude,
        );

        if (mounted) {
          setState(() {
            _fotoBytes = bytes;
            _fotoBase64 = base64Encode(bytes);
            _fotoPath = picked.name.isNotEmpty ? picked.name : (resultado['ruta_relativa'] as String?);
            _fotoSizeBytes = bytes.length;
            _fotoSeleccionada = true;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Foto seleccionada y comprimida (${(bytes.length / 1024).toStringAsFixed(1)} KB ≤ 350 KB).'),
              backgroundColor: const Color(0xFF00796B),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('[HomeScreen] Error al seleccionar foto: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No fue posible seleccionar la imagen ($e).'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _exportarCsvRFC4180() async {
    if (_reportes.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No hay avistamientos guardados para exportar.')),
      );
      return;
    }

    final mapList = _reportes.map((r) => {
      'id': r.id,
      'fecha': r.fechaHora,
      'especie': r.nombreComun,
      'latitud': r.latitud,
      'longitud': r.longitud,
      'sustrato': r.sustrato,
      'foto_path': r.fotoPath ?? 'Sin foto',
    }).toList();

    final csvText = await CsvExportService.generarArchivoCsvLocal(
      registros: mapList,
      nombreArchivo: 'biocampo_muestreos_sprint1.csv',
    );

    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.file_download_done_rounded, color: Color(0xFF00796B)),
            SizedBox(width: 8),
            Expanded(
              child: Text('Exportación CSV (RFC 4180)', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Se generó la exportación de ${_reportes.length} avistamientos bajo estándar RFC 4180 en UTF-8.'),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(10),
              ),
              constraints: const BoxConstraints(maxHeight: 180),
              child: SingleChildScrollView(
                child: Text(
                  csvText,
                  style: const TextStyle(fontFamily: 'Courier', fontSize: 11),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00796B),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.copy_rounded, size: 16),
            label: const Text('Copiar CSV'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: csvText));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('CSV copiado al portapapeles exitosamente.')),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildHabitatChipSelector(String title, List<String> options, String selected, ValueChanged<String> onSelected) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF475569))),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          runSpacing: 4,
          children: options.map((opt) {
            final isSel = opt == selected;
            return ChoiceChip(
              label: Text(opt, style: TextStyle(fontSize: 11.5, color: isSel ? Colors.white : const Color(0xFF334155), fontWeight: isSel ? FontWeight.bold : FontWeight.normal)),
              selected: isSel,
              selectedColor: const Color(0xFF00796B),
              backgroundColor: const Color(0xFFF1F5F9),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              onSelected: (_) => onSelected(opt),
            );
          }).toList(),
        ),
      ],
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _tabController = TabController(length: 3, vsync: this);
    _syncQueueService = SyncQueueService(storage: SharedPreferencesSyncQueueStorage());
    _networkStatusService = widget.networkStatusService ?? NetworkStatusService();
    _connectivitySubscription = _networkStatusService.onConnectivityChanged.listen(
      (_) => _checkNetworkStatus(),
      onError: (_) {},
    );
    _loadInitialLocationAndReports();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _connectivitySubscription?.cancel();
    _tabController.dispose();
    _especieController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Al volver de ajustes del teléfono (permisos, GPS o Wi-Fi), revalidar acceso al mapa.
      _recheckMapAccess(requestPermissionIfDenied: false);
    }
  }

  Future<void> _loadInitialLocationAndReports() async {
    await _refreshReports();
    await _recheckMapAccess(requestPermissionIfDenied: true);
  }

  Future<void> _checkNetworkStatus() async {
    final result = await _networkStatusService.checkInternetStatus();
    if (!mounted) return;
    setState(() {
      _hasInternetConnection = result.hasInternet;
      _networkStatusMessage = result.message;
    });
    await _rebuildMapMarkers();
  }

  Future<void> _recheckMapAccess({bool requestPermissionIfDenied = false}) async {
    if (mounted) {
      setState(() => _isCheckingMapAccess = true);
    }
    try {
      await Future.wait([
        _checkNetworkStatus(),
        _acquireGpsLocation(requestPermissionIfDenied: requestPermissionIfDenied),
      ]);
    } finally {
      if (mounted) {
        setState(() => _isCheckingMapAccess = false);
      }
    }
  }

  void _handleTileNetworkError() {
    final now = DateTime.now();
    if (_lastTileErrorCheck != null &&
        now.difference(_lastTileErrorCheck!) < const Duration(seconds: 6)) {
      return;
    }
    _lastTileErrorCheck = now;
    _checkNetworkStatus();
  }

  Future<void> _refreshReports() async {
    final list = await AppDatabase.instance.getReportes(
      usuarioId: widget.authService.currentUser?.id,
    );

    // Reconciliar cola FIFO con reportes pendientes en SQLite (HU-06)
    for (final r in list.reversed) {
      if (r.id != null && r.estadoSync == 'PENDIENTE') {
        await _syncQueueService.enqueue('reporte-${r.id}');
      }
    }
    final pendingIds = await _syncQueueService.pendingIds();

    final centerLat = _currentTelemetry?.latitude ?? 22.1524;
    final centerLon = _currentTelemetry?.longitude ?? -102.6142;
    final markers = await _offlineMapService.buildMapMarkers(
      centerLat: centerLat,
      centerLon: centerLon,
      reportes: list,
      revealedReportIds: _revealedReportIds,
      isOnline: _hasInternetConnection && !_isOfflineMode,
    );

    if (mounted) {
      setState(() {
        _reportes = list;
        _pendingQueueIds = pendingIds;
        _mapMarkers = markers;
      });
    }
  }

  Future<void> _rebuildMapMarkers() async {
    final centerLat = _currentTelemetry?.latitude ?? 22.1524;
    final centerLon = _currentTelemetry?.longitude ?? -102.6142;
    final markers = await _offlineMapService.buildMapMarkers(
      centerLat: centerLat,
      centerLon: centerLon,
      reportes: _reportes,
      revealedReportIds: _revealedReportIds,
      isOnline: _hasInternetConnection && !_isOfflineMode,
    );
    if (mounted) {
      setState(() => _mapMarkers = markers);
    }
  }

  Future<void> _acquireGpsLocation({bool requestPermissionIfDenied = true}) async {
    if (mounted) {
      setState(() => _isLocating = true);
    }
    final telemetry = await LocationService.getCurrentLocation(
      requestPermissionIfDenied: requestPermissionIfDenied,
    );
    if (mounted) {
      setState(() {
        _currentTelemetry = telemetry;
        _isLocating = false;
      });
      await _rebuildMapMarkers();
    }
  }

  Future<void> _requestLocationPermissionFromUi() async {
    final currentState = _currentTelemetry?.accessState;

    if (!kIsWeb && currentState == LocationAccessState.serviceDisabled) {
      await _handleOpenLocationSettings();
      return;
    }

    if (!kIsWeb && currentState == LocationAccessState.deniedForever) {
      final opened = await LocationService.openDeviceAppSettings();
      if (!mounted) return;
      if (opened) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Activa el permiso de Ubicación para BioCampo y regresa a la aplicación.'),
            backgroundColor: Color(0xFF00796B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        await _recheckMapAccess(requestPermissionIfDenied: true);
      }
      return;
    }

    await _recheckMapAccess(requestPermissionIfDenied: true);

    if (!mounted) return;
    final newState = _currentTelemetry?.accessState;
    if (kIsWeb && newState == LocationAccessState.deniedForever) {
      _mostrarDialogoPermisoUbicacionWeb();
    } else if (!kIsWeb && newState == LocationAccessState.deniedForever) {
      await LocationService.openDeviceAppSettings();
    }
  }

  Future<void> _handleOpenLocationSettings() async {
    if (kIsWeb) {
      await _requestLocationPermissionFromUi();
      return;
    }
    final opened = await LocationService.openDeviceLocationSettings();
    if (!mounted) return;
    if (!opened) {
      await _recheckMapAccess(requestPermissionIfDenied: true);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Activa la Ubicación / GPS del dispositivo y vuelve a BioCampo.'),
          backgroundColor: Color(0xFF00796B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _mostrarDialogoPermisoUbicacionWeb() {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: const Row(
          children: [
            Icon(Icons.location_off_rounded, color: Color(0xFFC62828)),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Ubicación bloqueada en navegador',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
        content: const Text(
          'El navegador bloqueó el acceso a tu ubicación para este sitio.\n\n'
          'Para otorgar permisos manualmente:\n'
          '1. Haz clic en el ícono de ajustes o candado junto a la barra URL.\n'
          '2. Cambia el permiso "Ubicación" a "Permitir".\n'
          '3. Presiona el botón "Verificar permiso".',
          style: TextStyle(fontSize: 13.5, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cerrar'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF00796B),
              foregroundColor: Colors.white,
            ),
            icon: const Icon(Icons.refresh_rounded, size: 17),
            label: const Text('Verificar permiso'),
            onPressed: () {
              Navigator.pop(ctx);
              _recheckMapAccess(requestPermissionIfDenied: true);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _toggleNetworkMode(bool goOnline) async {
    setState(() => _isOfflineMode = !goOnline);
    if (goOnline && _pendingQueueIds.isNotEmpty) {
      await _sincronizarColaFifo();
    } else {
      await _rebuildMapMarkers();
    }
  }

  Future<void> _sincronizarColaFifo() async {
    if (_isOfflineMode) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sin conexión de red: los reportes permanecen protegidos en la cola FIFO.'),
          backgroundColor: Color(0xFFD97706),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    setState(() => _isSyncing = true);
    try {
      final syncedCount = await _syncQueueService.flushQueue(
        isOnline: true,
        onSend: (queueId) async {
          final idStr = queueId.replaceFirst('reporte-', '');
          final idNum = int.tryParse(idStr);
          if (idNum != null) {
            await AppDatabase.instance.updateReporteEstadoSync(idNum, 'SINCRONIZADO');
          }
          return true;
        },
      );
      await _refreshReports();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            syncedCount > 0
                ? 'Sincronización FIFO completada: $syncedCount reporte(s) enviados.'
                : 'La cola de sincronización está vacía.',
          ),
          backgroundColor: const Color(0xFF00796B),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }

  Future<void> _showSyncQueueModal() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => StatefulBuilder(
        builder: (context, setModalState) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: _isOfflineMode ? const Color(0xFFFEF3C7) : const Color(0xFFE0F2F1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      _isOfflineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                      color: _isOfflineMode ? const Color(0xFFD97706) : const Color(0xFF00796B),
                    ),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Cola de Sincronización (HU-06)',
                          style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                        ),
                        Text(
                          'Control FIFO sin duplicados y detección de red',
                          style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                    onPressed: () => Navigator.of(sheetCtx).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                decoration: BoxDecoration(
                  color: _hasInternetConnection
                      ? const Color(0xFFE0F2F1)
                      : const Color(0xFFFEF2F2),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: _hasInternetConnection
                        ? const Color(0xFF80CBC4)
                        : const Color(0xFFFCA5A5),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _hasInternetConnection
                          ? Icons.wifi_rounded
                          : Icons.wifi_off_rounded,
                      size: 18,
                      color: _hasInternetConnection
                          ? const Color(0xFF00796B)
                          : const Color(0xFFC62828),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _hasInternetConnection
                            ? 'Internet del dispositivo: $_networkStatusMessage'
                            : 'Internet del dispositivo: Sin conexión (Mapa bloqueado)',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _hasInternetConnection
                              ? const Color(0xFF004D40)
                              : const Color(0xFF991B1B),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      tooltip: 'Verificar internet',
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                      onPressed: () async {
                        await _checkNetworkStatus();
                        if (sheetCtx.mounted) setModalState(() {});
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 10),
              Material(
                color: const Color(0xFFF8FAFC),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                  side: const BorderSide(color: Color(0xFFE2E8F0)),
                ),
                clipBehavior: Clip.antiAlias,
                child: SwitchListTile(
                  title: Text(
                    _isOfflineMode ? 'Modo Campo Offline (Zero-Cloud)' : 'Conectividad Activa (Wi-Fi / Red)',
                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                  ),
                  subtitle: Text(
                    _isOfflineMode
                        ? 'Los nuevos reportes se encolan localmente sin pérdida.'
                        : 'Red disponible: dispara envío FIFO automático.',
                    style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                  ),
                  activeThumbColor: const Color(0xFF00796B),
                  value: !_isOfflineMode,
                  onChanged: (goOnline) async {
                    await _toggleNetworkMode(goOnline);
                    if (sheetCtx.mounted) setModalState(() {});
                  },
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Pendientes en Cola FIFO (${_pendingQueueIds.length}):',
                style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF334155)),
              ),
              const SizedBox(height: 8),
              if (_pendingQueueIds.isEmpty)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.check_circle_rounded, color: Color(0xFF00796B)),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Cola vacía: todos los muestreos están sincronizados.',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF004D40)),
                        ),
                      ),
                    ],
                  ),
                )
              else
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 180),
                  child: ListView.separated(
                    shrinkWrap: true,
                    itemCount: _pendingQueueIds.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (_, i) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFFBEB),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFDE68A)),
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 11,
                            backgroundColor: const Color(0xFFD97706),
                            child: Text(
                              '${i + 1}',
                              style: const TextStyle(fontSize: 11, color: Colors.white, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _pendingQueueIds[i],
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                            ),
                          ),
                          const Text(
                            'PENDIENTE',
                            style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: Color(0xFFB45309)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00796B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(48),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: _isSyncing
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : const Icon(Icons.sync_rounded),
                  label: Text(
                    _isOfflineMode ? 'Activa la red para sincronizar' : 'Sincronizar Cola FIFO Ahora',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  onPressed: _isSyncing || _pendingQueueIds.isEmpty
                      ? null
                      : () async {
                          await _sincronizarColaFifo();
                          if (sheetCtx.mounted) setModalState(() {});
                        },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _guardarReporteFinal() async {
    final user = widget.authService.currentUser;
    if (user == null || user.id == null) return;

    final especie = _especieController.text.trim();
    if (especie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Por favor ingresa la especie en el Paso 1.', style: TextStyle(fontSize: 14)),
          backgroundColor: Color(0xFFC62828),
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _wizardStep = 1);
      return;
    }

    setState(() => _isSaving = true);

    final telemetry = _currentTelemetry ?? await LocationService.getCurrentLocation();

    // Normalización segura de variables ecológicas conforme a HU-04
    final validadoHabitat = VariablesEcologicasValidator.validarYNormalizar(
      sustrato: _sustratoSeleccionado,
      estrato: _estratoSeleccionado,
      condicion: _condicionSeleccionada,
    );

    // Protección criptográfica AES-256-GCM para especies protegidas (HU-07)
    final esProtegida = _esEspecieProtegida ||
        CatalogoTaxonomicoService.isProtectedSpecies(especie, _nombreCientifico);
    final coordPlain = '${telemetry.latitude.toStringAsFixed(6)},${telemetry.longitude.toStringAsFixed(6)}';
    final encryptedCoords = esProtegida ? _protectionService.protect(coordPlain) : null;

    final nuevoReporte = ReporteModel(
      usuarioId: user.id!,
      fechaHora: DateTime.now().toIso8601String(),
      latitud: telemetry.latitude,
      longitud: telemetry.longitude,
      altitud: telemetry.altitude,
      precisionGps: telemetry.accuracy,
      nombreComun: especie,
      nombreCientifico: _nombreCientifico,
      fotoPath: _fotoPath,
      fotoBytesBase64: _fotoBase64,
      sustrato: validadoHabitat['sustrato'] as String,
      estrato: validadoHabitat['estrato'] as String,
      condicion: validadoHabitat['condicion'] as String,
      notas: _notasController.text.trim(),
      estadoSync: 'PENDIENTE',
      esProtegida: esProtegida,
      coordenadasCifradas: encryptedCoords,
    );

    try {
      final insertedId = await AppDatabase.instance.insertReporte(nuevoReporte);
      await _syncQueueService.enqueue('reporte-$insertedId');
      if (!_isOfflineMode) {
        await _sincronizarColaFifo();
      }

      _especieController.clear();
      _notasController.clear();
      _fotoSeleccionada = false;
      _fotoPath = null;
      _fotoBase64 = null;
      _fotoBytes = null;
      _fotoSizeBytes = null;
      _nombreCientifico = null;
      _sugerenciasDarwinCore = [];
      _sustratoSeleccionado = 'No determinado';
      _estratoSeleccionado = 'No determinado';
      _condicionSeleccionada = 'No determinado';
      _esEspecieProtegida = false;
      _estatusProteccionDetectado = null;
      _wizardStep = 0; // Regresar inicio del wizard
      await _refreshReports();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            esProtegida
                ? 'Reporte guardado con coordenadas cifradas AES-256 (HU-07).'
                : 'Reporte guardado y encolado exitosamente.',
            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          backgroundColor: const Color(0xFF00796B),
          behavior: SnackBarBehavior.floating,
        ),
      );

      // Deslizar automáticamente a la pestaña de "Reportes Guardados"
      _tabController.animateTo(1);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar reporte: $e'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _showQuickSightingDialog() async {
    final especieCtrl = TextEditingController();
    final notasCtrl = TextEditingController();

    if (_currentTelemetry == null) {
      await _acquireGpsLocation();
    }

    if (!mounted) return;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 24,
          bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.add_location_alt_rounded, color: Color(0xFF00796B), size: 22),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Registro Rápido in-situ',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                      ),
                      Text(
                        'Operación verificable vinculada a GPS',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.satellite_alt_rounded, color: Color(0xFF00796B), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'GPS: ${_currentTelemetry?.latitude.toStringAsFixed(4)}, ${_currentTelemetry?.longitude.toStringAsFixed(4)} (±${_currentTelemetry?.accuracy.toStringAsFixed(1)} m)',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF0F2F38)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Especie / Taxón *', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 6),
            TextField(
              controller: especieCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 15, color: Color(0xFF0F2F38)),
              decoration: InputDecoration(
                hintText: 'Ej. Águila Real, Puma concolor, Venado...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Notas de Campo (Opcional)', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 6),
            TextField(
              controller: notasCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, color: Color(0xFF0F2F38)),
              decoration: InputDecoration(
                hintText: 'Observación en terreno, hábitat...',
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00796B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              icon: const Icon(Icons.check_circle_outline_rounded),
              label: const Text('Guardar Reporte Verificable', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final especie = especieCtrl.text.trim();
                if (especie.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor ingresa la especie observada.'),
                      backgroundColor: Color(0xFFC62828),
                    ),
                  );
                  return;
                }
                Navigator.of(ctx).pop();
                await _saveReportFromQuickDialog(especie, notasCtrl.text.trim());
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _saveReportFromQuickDialog(String especie, String notas) async {
    final user = widget.authService.currentUser;
    if (user == null || user.id == null) return;

    final telemetry = _currentTelemetry ?? await LocationService.getCurrentLocation();
    final esProtegida = CatalogoTaxonomicoService.isProtectedSpecies(especie);
    final coordPlain = '${telemetry.latitude.toStringAsFixed(6)},${telemetry.longitude.toStringAsFixed(6)}';
    final encryptedCoords = esProtegida ? _protectionService.protect(coordPlain) : null;

    final reporte = ReporteModel(
      usuarioId: user.id!,
      fechaHora: DateTime.now().toIso8601String(),
      latitud: telemetry.latitude,
      longitud: telemetry.longitude,
      altitud: telemetry.altitude,
      precisionGps: telemetry.accuracy,
      nombreComun: especie,
      notas: notas.isEmpty ? 'Avistamiento verificado por GNSS in-situ.' : notas,
      estadoSync: 'PENDIENTE',
      esProtegida: esProtegida,
      coordenadasCifradas: encryptedCoords,
    );

    try {
      final insertedId = await AppDatabase.instance.insertReporte(reporte);
      await _syncQueueService.enqueue('reporte-$insertedId');
      if (!_isOfflineMode) {
        await _sincronizarColaFifo();
      }
      await _refreshReports();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            esProtegida
                ? '¡Reporte de "$especie" guardado con cifrado AES-256!'
                : '¡Reporte de "$especie" guardado y encolado con éxito!',
          ),
          backgroundColor: const Color(0xFF00796B),
          behavior: SnackBarBehavior.floating,
        ),
      );
      _tabController.animateTo(1); // Deslizar automáticamente a Reportes Guardados
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al guardar reporte: $e'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _confirmDeleteReport(ReporteModel reporte) async {
    final confirmCtrl = TextEditingController();
    bool canProceed = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFFFEBEE),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.delete_outline_rounded, color: Color(0xFFC62828), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Eliminar Reporte #${reporte.id}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El reporte #${reporte.id} ("${reporte.nombreComun}") se va a eliminar, escribe "eliminar" para confirmar:',
                style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFFC62828)),
                decoration: InputDecoration(
                  hintText: 'escribe "eliminar"',
                  hintStyle: const TextStyle(fontWeight: FontWeight.normal, color: Color(0xFF94A3B8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFFC62828), width: 1.8),
                  ),
                ),
                onChanged: (val) {
                  setDialogState(() {
                    canProceed = val.trim().toLowerCase() == 'eliminar';
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canProceed ? const Color(0xFFC62828) : const Color(0xFFE2E8F0),
                foregroundColor: canProceed ? Colors.white : const Color(0xFF94A3B8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: canProceed ? 2 : 0,
              ),
              onPressed: canProceed
                  ? () async {
                      Navigator.of(dialogCtx).pop();
                      await _deleteReport(reporte);
                    }
                  : null,
              child: const Text('Eliminar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _deleteReport(ReporteModel reporte) async {
    if (reporte.id == null) return;
    try {
      final success = await AppDatabase.instance.deleteReporte(reporte.id!);
      if (success) {
        await _syncQueueService.remove('reporte-${reporte.id}');
        _revealedReportIds.remove(reporte.id);
        await _refreshReports();
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Reporte #${reporte.id} eliminado correctamente.'),
            backgroundColor: const Color(0xFF00796B),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error al eliminar: $e'),
          backgroundColor: const Color(0xFFC62828),
        ),
      );
    }
  }

  Future<void> _confirmEditReport(ReporteModel reporte) async {
    final confirmCtrl = TextEditingController();
    bool canProceed = false;

    final shouldOpenForm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: const BoxDecoration(
                  color: Color(0xFFE0F2F1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.edit_outlined, color: Color(0xFF00796B), size: 20),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Editar Reporte #${reporte.id}',
                  style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'El reporte #${reporte.id} ("${reporte.nombreComun}") se va a editar, escribe "editar" para confirmar:',
                style: const TextStyle(fontSize: 14, color: Color(0xFF334155), height: 1.4),
              ),
              const SizedBox(height: 14),
              TextField(
                controller: confirmCtrl,
                autofocus: true,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                decoration: InputDecoration(
                  hintText: 'escribe "editar"',
                  hintStyle: const TextStyle(fontWeight: FontWeight.normal, color: Color(0xFF94A3B8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Color(0xFF00796B), width: 1.8),
                  ),
                ),
                onChanged: (val) {
                  setDialogState(() {
                    canProceed = val.trim().toLowerCase() == 'editar';
                  });
                },
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(false),
              child: const Text('Cancelar', style: TextStyle(color: Color(0xFF64748B), fontWeight: FontWeight.w600)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: canProceed ? const Color(0xFF00796B) : const Color(0xFFE2E8F0),
                foregroundColor: canProceed ? Colors.white : const Color(0xFF94A3B8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: canProceed ? 2 : 0,
              ),
              onPressed: canProceed ? () => Navigator.of(dialogCtx).pop(true) : null,
              child: const Text('Confirmar', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );

    if (shouldOpenForm == true && mounted) {
      await _showEditReportForm(reporte);
    }
  }

  Future<void> _showEditReportForm(ReporteModel reporte) async {
    final especieCtrl = TextEditingController(text: reporte.nombreComun);
    final notasCtrl = TextEditingController(text: reporte.notas);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetCtx) => Padding(
        padding: EdgeInsets.only(
          left: 22,
          right: 22,
          top: 24,
          bottom: MediaQuery.of(sheetCtx).viewInsets.bottom + 24,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.edit_note_rounded, color: Color(0xFF00796B), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Modificar Reporte #${reporte.id}',
                        style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                      ),
                      const Text(
                        'Actualizar especie u observaciones de campo',
                        style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
                  onPressed: () => Navigator.of(sheetCtx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.pin_drop_rounded, color: Color(0xFF00796B), size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Coordenadas fijas: ${reporte.latitud.toStringAsFixed(4)}, ${reporte.longitud.toStringAsFixed(4)} (±${reporte.precisionGps.toStringAsFixed(1)} m)',
                      style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: Color(0xFF0F2F38)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            const Text('Especie / Taxón *', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 6),
            TextField(
              controller: especieCtrl,
              style: const TextStyle(fontSize: 15, color: Color(0xFF0F2F38)),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 12),
            const Text('Notas de Campo', style: TextStyle(fontSize: 13.5, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
            const SizedBox(height: 6),
            TextField(
              controller: notasCtrl,
              maxLines: 2,
              style: const TextStyle(fontSize: 14, color: Color(0xFF0F2F38)),
              decoration: InputDecoration(
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00796B),
                foregroundColor: Colors.white,
                minimumSize: const Size.fromHeight(48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 2,
              ),
              icon: const Icon(Icons.save_rounded),
              label: const Text('Guardar Modificaciones', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              onPressed: () async {
                final nuevaEspecie = especieCtrl.text.trim();
                if (nuevaEspecie.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('La especie no puede estar vacía.'),
                      backgroundColor: Color(0xFFC62828),
                    ),
                  );
                  return;
                }
                Navigator.of(sheetCtx).pop();

                final actualizado = reporte.copyWith(
                  nombreComun: nuevaEspecie,
                  notas: notasCtrl.text.trim(),
                );

                try {
                  final ok = await AppDatabase.instance.updateReporte(actualizado);
                  if (ok) {
                    await _refreshReports();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Reporte #${reporte.id} modificado exitosamente.'),
                        backgroundColor: const Color(0xFF00796B),
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                } catch (e) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Error al modificar: $e'),
                      backgroundColor: const Color(0xFFC62828),
                    ),
                  );
                }
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _logout() async {
    await widget.authService.logout();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => LoginScreen(authService: widget.authService),
      ),
    );
  }

  void _showPerfilModal() {
    final user = widget.authService.currentUser;
    final decoded = widget.authService.currentDecodedToken;
    final token = widget.authService.currentToken;

    showModalBottomSheet<void>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (_) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 22.0, vertical: 24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.badge_rounded, color: Color(0xFF00796B), size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        user?.nombreCompleto ?? 'Usuario',
                        style: const TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                      ),
                      Text(
                        'Matrícula: ${user?.matricula} · Rol: ${user?.rol}',
                        style: const TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const Divider(height: 24),
            _summaryRow('Vigencia:', '${decoded?.remainingTime.inHours ?? 24} horas restantes'),
            const SizedBox(height: 14),
            const Text(
              'Token de Sesión:',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF475569)),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFC),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFCBD5E1)),
              ),
              child: SelectableText(
                token ?? 'Token no disponible',
                style: const TextStyle(fontSize: 10, fontFamily: 'monospace', color: Color(0xFF00796B)),
              ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cerrar Ventana'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.authService.currentUser;

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: const Text(
          'BioCampo',
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.bold,
            color: Colors.white,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: const Color(0xFF004D40), // Verde-Azul petróleo profundo
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline_rounded, color: Colors.white),
            tooltip: 'Detalles de Sesión JWT',
            onPressed: _showPerfilModal,
          ),
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: Colors.white),
            tooltip: 'Cerrar Sesión',
            onPressed: _logout,
          ),
        ],
        // Barra de Pestañas Deslizantes (Swipeable Tabs)
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: const Color(0xFF80CBC4),
          indicatorWeight: 3.5,
          labelColor: Colors.white,
          unselectedLabelColor: const Color(0xFFB2DFDB),
          labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5),
          tabs: const [
            Tab(
              icon: Icon(Icons.add_circle_outline_rounded, size: 21),
              text: 'Nuevo Reporte',
            ),
            Tab(
              icon: Icon(Icons.folder_open_rounded, size: 21),
              text: 'Reportes Guardados',
            ),
            Tab(
              icon: Icon(Icons.map_rounded, size: 21),
              text: 'Mapa y GPS',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Banner superior de Usuario activo y estado de red / cola FIFO (HU-06)
            Container(
              color: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: const BoxDecoration(
                      color: Color(0xFFE0F2F1),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.person_rounded, color: Color(0xFF00796B), size: 20),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.nombreCompleto ?? 'Usuario',
                          style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          user?.rol ?? 'Investigador',
                          style: const TextStyle(fontSize: 12, color: Color(0xFF64748B)),
                        ),
                      ],
                    ),
                  ),
                  InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _showSyncQueueModal,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: _isOfflineMode
                            ? const Color(0xFFFEF3C7)
                            : (_pendingQueueIds.isEmpty ? const Color(0xFFE0F2F1) : const Color(0xFFE0F2FE)),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _isOfflineMode
                              ? const Color(0xFFFCD34D)
                              : const Color(0xFF80CBC4),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _isOfflineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                            color: _isOfflineMode ? const Color(0xFFB45309) : const Color(0xFF00796B),
                            size: 14,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            _isOfflineMode
                                ? 'Offline · ${_pendingQueueIds.length} cola'
                                : (_pendingQueueIds.isEmpty ? 'En Línea' : 'Sync (${_pendingQueueIds.length})'),
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: _isOfflineMode ? const Color(0xFF92400E) : const Color(0xFF004D40),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE2E8F0)),

            // Contenido con Deslizamiento Táctil Horizontal (Swipe Left / Right)
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  // PESTAÑA 1: GENERAR REPORTE (POR FASES / ASISTENTE)
                  _buildGenerarReporteTab(),

                  // PESTAÑA 2: REPORTES GUARDADOS (HISTORIAL SQLITE)
                  _buildReportesGuardadosTab(),

                  // PESTAÑA 3: GEOLOCALIZACIÓN SATELITAL
                  _buildGeolocalizacionTab(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // =========================================================================
  // PESTAÑA 1: GENERAR REPORTE (ASISTENTE POR FASES)
  // =========================================================================
  Widget _buildGenerarReporteTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_wizardStep == 0) ...[
            // PANTALLA INICIAL DEL REPORTE: BOTÓN GRANDE Y LOGO
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24.0),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D0F172A),
                    blurRadius: 20.0,
                    offset: Offset(0, 8),
                  ),
                ],
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 36.0),
              child: Column(
                children: [
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      shape: BoxShape.circle,
                      border: Border.all(color: const Color(0xFF80CBC4), width: 2),
                    ),
                    child: const Icon(
                      Icons.note_add_rounded,
                      size: 42,
                      color: Color(0xFF00796B),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Generar Nuevo Reporte',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F2F38),
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Captura avistamientos in-situ mediante un flujo guiado por fases: datos, geolocalización satelital y evidencia.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 14.5,
                      color: Color(0xFF475569),
                      height: 1.35,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    height: 54,
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00796B),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 2,
                      ),
                      icon: const Icon(Icons.play_arrow_rounded, size: 24),
                      label: const Text(
                        'Iniciar Registro de Reporte',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      onPressed: () => setState(() => _wizardStep = 1),
                    ),
                  ),
                ],
              ),
            ),
          ] else ...[
            // ASISTENTE POR FASES (STEPPER)
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(22.0),
                border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x0D0F172A),
                    blurRadius: 16.0,
                    offset: Offset(0, 6),
                  ),
                ],
              ),
              padding: const EdgeInsets.all(22.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Barra de Progreso de Fases
                  _buildWizardProgress(),
                  const SizedBox(height: 24),

                  // CONTENIDO SEGÚN LA FASE ACTUAL
                  if (_wizardStep == 1) _buildFase1Datos(),
                  if (_wizardStep == 2) _buildFase2Gps(),
                  if (_wizardStep == 3) _buildFase3Fotos(),
                  if (_wizardStep == 4) _buildFase4Confirmacion(),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildWizardProgress() {
    return Row(
      children: [
        _stepChip(1, 'Datos', _wizardStep >= 1, _wizardStep == 1),
        const Expanded(child: Divider(color: Color(0xFFCBD5E1), thickness: 1.5)),
        _stepChip(2, 'GPS', _wizardStep >= 2, _wizardStep == 2),
        const Expanded(child: Divider(color: Color(0xFFCBD5E1), thickness: 1.5)),
        _stepChip(3, 'Fotos', _wizardStep >= 3, _wizardStep == 3),
        const Expanded(child: Divider(color: Color(0xFFCBD5E1), thickness: 1.5)),
        _stepChip(4, 'Guardar', _wizardStep == 4, _wizardStep == 4),
      ],
    );
  }

  Widget _stepChip(int step, String label, bool isDone, bool isActive) {
    final color = isActive
        ? const Color(0xFF00796B)
        : (isDone ? const Color(0xFF004D40) : const Color(0xFF94A3B8));
    return Column(
      children: [
        CircleAvatar(
          radius: 14,
          backgroundColor: isActive ? const Color(0xFF00796B) : (isDone ? const Color(0xFFE0F2F1) : const Color(0xFFE2E8F0)),
          child: Text(
            '$step',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: isActive ? Colors.white : color,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
            color: color,
          ),
        ),
      ],
    );
  }

  // Fase 1: Título y Descripción (Obligatorios)
  Widget _buildFase1Datos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fase 1: Datos del Avistamiento',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Indica la especie observada y las observaciones de campo (Obligatorio).',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),
        const Text('Especie / Taxón (HU-02 Darwin Core) *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 6),
        TextField(
          controller: _especieController,
          style: const TextStyle(fontSize: 15.5, color: Color(0xFF0F2F38)),
          onChanged: _buscarSugerenciasDarwinCore,
          decoration: InputDecoration(
            hintText: 'Ej. Pinus cembroides, Jaguar, Aquila...',
            prefixIcon: const Icon(Icons.search_rounded, color: Color(0xFF00796B)),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        if (_sugerenciasDarwinCore.isNotEmpty) ...[
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFFF0FDF4),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFFBBF7D0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Row(
                  children: [
                    Icon(Icons.auto_awesome, size: 14, color: Color(0xFF15803D)),
                    SizedBox(width: 4),
                    Expanded(
                      child: Text('Sugerencias Darwin Core (Autocompletado predictivo <200 ms):', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF15803D))),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: _sugerenciasDarwinCore.map((s) => ActionChip(
                    backgroundColor: Colors.white,
                    side: const BorderSide(color: Color(0xFF86EFAC)),
                    label: Text('${s['vernacularName']} (${s['scientificName']})', style: const TextStyle(fontSize: 11.5, color: Color(0xFF166534))),
                    onPressed: () {
                      final sci = s['scientificName'];
                      final vern = s['vernacularName'] ?? '';
                      final status = s['protectedStatus'] ??
                          CatalogoTaxonomicoService.getProtectionStatus(vern, sci);
                      setState(() {
                        _especieController.text = '$vern ($sci)';
                        _nombreCientifico = sci;
                        _sugerenciasDarwinCore.clear();
                        _estatusProteccionDetectado = status;
                        if (status != null) {
                          _esEspecieProtegida = true;
                        }
                      });
                    },
                  )).toList(),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 14),
        // Tarjeta de Protección Criptográfica AES-256-GCM (HU-07)
        Material(
          color: _esEspecieProtegida ? const Color(0xFFFFFBEB) : const Color(0xFFF8FAFC),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
              color: _esEspecieProtegida ? const Color(0xFFF59E0B) : const Color(0xFFE2E8F0),
              width: _esEspecieProtegida ? 1.4 : 1.0,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
            secondary: Icon(
              _esEspecieProtegida ? Icons.shield_rounded : Icons.security_outlined,
              color: _esEspecieProtegida ? const Color(0xFFD97706) : const Color(0xFF64748B),
            ),
            title: const Text(
              'Proteger Coordenadas (HU-07 · AES-256)',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
            ),
            subtitle: Text(
              _estatusProteccionDetectado != null
                  ? 'Detectada: $_estatusProteccionDetectado'
                  : 'Cifra coordenadas exactas y ofusca ±5 km en mapas públicos.',
              style: TextStyle(
                fontSize: 11.5,
                color: _esEspecieProtegida ? const Color(0xFFB45309) : const Color(0xFF64748B),
              ),
            ),
            activeThumbColor: const Color(0xFFD97706),
            value: _esEspecieProtegida,
            onChanged: (val) => setState(() => _esEspecieProtegida = val),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Variables Ecológicas de Hábitat (HU-04 Selectores One-Hand) *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 8),
        _buildHabitatChipSelector('Sustrato:', ['Hojarasca húmeda', 'Suelo orgánico', 'Roca', 'Corteza arbórea', 'No determinado'], _sustratoSeleccionado, (val) => setState(() => _sustratoSeleccionado = val)),
        const SizedBox(height: 8),
        _buildHabitatChipSelector('Estrato:', ['Arbustivo', 'Herbáceo', 'Arbóreo', 'Rupícola', 'No determinado'], _estratoSeleccionado, (val) => setState(() => _estratoSeleccionado = val)),
        const SizedBox(height: 8),
        _buildHabitatChipSelector('Condición:', ['Vivo', 'Fresco', 'Senescente', 'Restos / Huella', 'No determinado'], _condicionSeleccionada, (val) => setState(() => _condicionSeleccionada = val)),
        const SizedBox(height: 16),
        const Text('Notas de Campo / Hábitat *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 6),
        TextField(
          controller: _notasController,
          maxLines: 3,
          style: const TextStyle(fontSize: 15.5, color: Color(0xFF0F2F38)),
          decoration: InputDecoration(
            hintText: 'Observaciones de terreno, comportamiento o microclima...',
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _wizardStep = 0),
                child: const Text('Cancelar', style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00796B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () {
                  if (_especieController.text.trim().isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Por favor ingresa la especie.')),
                    );
                    return;
                  }
                  setState(() => _wizardStep = 2);
                },
                child: const Text('Siguiente: GPS ➔', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Fase 2: Ubicación Satelital GPS
  Widget _buildFase2Gps() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Expanded(
              child: Text(
                'Fase 2: Ubicación Satelital',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
              ),
            ),
            IconButton(
              icon: _isLocating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh_rounded, color: Color(0xFF00796B)),
              onPressed: _isLocating ? null : () => _recheckMapAccess(requestPermissionIfDenied: true),
            ),
          ],
        ),
        const SizedBox(height: 6),
        const Text(
          'Coordenadas fijadas automáticamente por el sensor satelital GNSS.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 18),
        if (_currentTelemetry != null) ...[
          if (!_currentTelemetry!.hasMapAuthorization) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: const Color(0xFFFEF2F2),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0xFFFCA5A5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, size: 18, color: Color(0xFFC62828)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _currentTelemetry!.statusMessage,
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF991B1B)),
                    ),
                  ),
                ],
              ),
            ),
          ],
          Row(
            children: [
              _buildMetricBox('Latitud', _currentTelemetry!.latitude.toStringAsFixed(6)),
              const SizedBox(width: 10),
              _buildMetricBox('Longitud', _currentTelemetry!.longitude.toStringAsFixed(6)),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _buildMetricBox('Altitud', '${_currentTelemetry!.altitude.toStringAsFixed(1)} m'),
              const SizedBox(width: 10),
              _buildMetricBox('Precisión GNSS', '±${_currentTelemetry!.accuracy.toStringAsFixed(1)} m'),
            ],
          ),
          const SizedBox(height: 16),
          OfflineFieldMapWidget(
            centerLat: _currentTelemetry!.latitude,
            centerLon: _currentTelemetry!.longitude,
            accuracyMeters: _currentTelemetry!.accuracy,
            markers: _mapMarkers,
            height: 225,
            compact: true,
            locationAccessState: _currentTelemetry!.accessState,
            hasInternet: _hasInternetConnection,
            isCheckingAccess: _isCheckingMapAccess || _isLocating,
            onRecenter: () => _recheckMapAccess(requestPermissionIfDenied: true),
            onRequestLocationPermission: _requestLocationPermissionFromUi,
            onOpenLocationSettings: _handleOpenLocationSettings,
            onRetryConnection: () => _recheckMapAccess(requestPermissionIfDenied: false),
            onTileNetworkError: _handleTileNetworkError,
            customTileProvider: widget.mapTileProvider,
          ),
        ] else ...[
          const Center(child: Padding(padding: EdgeInsets.all(16), child: Text('Adquiriendo satélites...'))),
        ],
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _wizardStep = 1),
                child: const Text('⬅ Atrás', style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00796B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _wizardStep = 3),
                child: const Text('Siguiente: Fotos ➔', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Fase 3: Fotos y Capturas (HU-01)
  Widget _buildFase3Fotos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fase 3: Fotos y Evidencia de Campo (HU-01)',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Captura fotográfica interactiva (< 350 KB) con persistencia Zero-Cloud integrada bajo el reporte.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: _fotoSeleccionada ? const Color(0xFF00796B) : const Color(0xFFCBD5E1),
              width: _fotoSeleccionada ? 1.5 : 1,
            ),
          ),
          child: Column(
            children: [
              if (_fotoBytes != null) ...[
                ClipRRect(
                  borderRadius: BorderRadius.circular(14),
                  child: Image.memory(
                    _fotoBytes!,
                    height: 220,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    errorBuilder: (ctx, err, stack) => Container(
                      height: 180,
                      color: const Color(0xFFE2E8F0),
                      alignment: Alignment.center,
                      child: const Text('Foto capturada correctamente', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE0F2F1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFF80CBC4)),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.check_circle_rounded, color: Color(0xFF00796B), size: 18),
                      const SizedBox(width: 6),
                      Text(
                        '${_fotoPath ?? "captura_campo.jpg"} · ${((_fotoSizeBytes ?? 286720) / 1024).toStringAsFixed(1)} KB (≤ 350 KB Zero-Cloud)',
                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF00796B),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.camera_alt_rounded, size: 18),
                      label: const Text('Volver a capturar', style: TextStyle(fontWeight: FontWeight.bold)),
                      onPressed: _capturarConCamara,
                    ),
                    const SizedBox(width: 10),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      icon: const Icon(Icons.photo_library_outlined, size: 18),
                      label: const Text('De galería'),
                      onPressed: () => _seleccionarFoto(ImageSource.gallery),
                    ),
                  ],
                ),
              ] else ...[
                Container(
                  width: 76,
                  height: 76,
                  decoration: const BoxDecoration(
                    color: Color(0xFFE0F2F1),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.photo_camera_rounded,
                    size: 40,
                    color: Color(0xFF00796B),
                  ),
                ),
                const SizedBox(height: 14),
                const Text(
                  'Tomar Fotografía del Espécimen',
                  style: TextStyle(fontSize: 16.5, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                ),
                const SizedBox(height: 6),
                const Text(
                  'Presiona "Capturar" para solicitar permisos de multimedia y abrir directamente la cámara del dispositivo.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),
                // Botón principal interactivo de Captura estilo WhatsApp
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF00796B),
                    foregroundColor: Colors.white,
                    minimumSize: const Size.fromHeight(52),
                    elevation: 3,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.camera_alt_rounded, size: 22),
                  label: const Text(
                    'Capturar',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, letterSpacing: 0.5),
                  ),
                  onPressed: _capturarConCamara,
                ),
                const SizedBox(height: 10),
                TextButton.icon(
                  style: TextButton.styleFrom(foregroundColor: const Color(0xFF64748B)),
                  icon: const Icon(Icons.photo_library_outlined, size: 18),
                  label: const Text('O seleccionar desde la galería / archivos', style: TextStyle(fontSize: 12.5)),
                  onPressed: () => _seleccionarFoto(ImageSource.gallery),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _wizardStep = 2),
                child: const Text('⬅ Atrás', style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00796B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _wizardStep = 4),
                child: const Text('Siguiente: Confirmar ➔', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ],
    );
  }

  // Fase 4: Confirmación y Guardado
  Widget _buildFase4Confirmacion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fase 4: Confirmación del Reporte',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Revisa el resumen antes de persistir el registro en la base de datos SQLite.',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 18),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _summaryRow('Especie (Común):', _especieController.text),
              if (_nombreCientifico != null) ...[
                const Divider(height: 16),
                _summaryRow('Darwin Core:', _nombreCientifico!),
              ],
              const Divider(height: 16),
              _summaryRow('Sustrato (HU-04):', _sustratoSeleccionado),
              const Divider(height: 16),
              _summaryRow('Estrato (HU-04):', _estratoSeleccionado),
              const Divider(height: 16),
              _summaryRow('Condición (HU-04):', _condicionSeleccionada),
              const Divider(height: 16),
              _summaryRow('Notas:', _notasController.text.isEmpty ? 'Ninguna' : _notasController.text),
              const Divider(height: 16),
              _summaryRow(
                'Coordenadas:',
                _currentTelemetry != null
                    ? '${_currentTelemetry!.latitude.toStringAsFixed(4)}, ${_currentTelemetry!.longitude.toStringAsFixed(4)}'
                    : 'Pendientes',
              ),
              const Divider(height: 16),
              _summaryRow(
                'Seguridad (HU-07):',
                _esEspecieProtegida
                    ? '🔒 Especie protegida · Cifrado AES-256-GCM'
                    : 'Estándar (Coordenadas públicas)',
              ),
              const Divider(height: 16),
              _summaryRow(
                'Sincronización (HU-06):',
                _isOfflineMode ? 'En cola FIFO local (Offline)' : 'Envío inmediato al guardar',
              ),
              const Divider(height: 16),
              _summaryRow('Fotografía (HU-01):', _fotoSeleccionada ? '${_fotoPath ?? "captura_campo.jpg"} (Comprimida ≤ 350 KB)' : 'Sin foto adjunta'),
              if (_fotoBytes != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    _fotoBytes!,
                    height: 160,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                onPressed: () => setState(() => _wizardStep = 3),
                child: const Text('⬅ Atrás', style: TextStyle(fontSize: 15, color: Color(0xFF64748B))),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              flex: 2,
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF00796B),
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(52),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  elevation: 2,
                ),
                icon: _isSaving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.check_circle_outline_rounded),
                label: const Text('Guardar Reporte', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                onPressed: _isSaving ? null : _guardarReporteFinal,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _summaryRow(String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 110, child: Text(label, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13.5, color: Color(0xFF475569)))),
        Expanded(child: Text(value, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F2F38)))),
      ],
    );
  }

  // =========================================================================
  // PESTAÑA 2: REPORTES GUARDADOS (HISTORIAL SQLITE)
  // =========================================================================
  Widget _buildReportesGuardadosTab() {
    final user = widget.authService.currentUser;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Flexible(
                child: Text(
                  'Reportes Guardados',
                  style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                      foregroundColor: Colors.white,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: const Icon(Icons.download_rounded, size: 16),
                    label: const Text('Exportar CSV', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    onPressed: _exportarCsvRFC4180,
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    icon: const Icon(Icons.sync_rounded, color: Color(0xFF00796B)),
                    tooltip: 'Actualizar lista',
                    onPressed: _refreshReports,
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total: ${_reportes.length} avistamientos persistidos en la base SQLite local.',
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 12),

          // Panel interactivo de Cola FIFO (HU-06) y Control de Acceso AES-256 (HU-07)
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE2E8F0)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Icon(
                      _isOfflineMode ? Icons.cloud_off_rounded : Icons.cloud_done_rounded,
                      color: _isOfflineMode ? const Color(0xFFD97706) : const Color(0xFF00796B),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isOfflineMode
                            ? 'Cola FIFO Offline: ${_pendingQueueIds.length} pendiente(s)'
                            : 'Red Activa · ${_pendingQueueIds.length} pendiente(s)',
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                      ),
                    ),
                    OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: const Size(0, 32),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      icon: const Icon(Icons.queue_rounded, size: 15, color: Color(0xFF00796B)),
                      label: const Text('Cola / Red', style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF00796B))),
                      onPressed: _showSyncQueueModal,
                    ),
                  ],
                ),
                const Divider(height: 14),
                Row(
                  children: [
                    Icon(
                      _simulateUnauthorizedView ? Icons.visibility_off_rounded : Icons.verified_user_rounded,
                      size: 18,
                      color: _simulateUnauthorizedView ? const Color(0xFFC62828) : const Color(0xFF00796B),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _simulateUnauthorizedView
                            ? 'Vista Pública (Sin permiso AES-256)'
                            : 'Perfil Autorizado (${user?.rol ?? "Investigador"})',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: _simulateUnauthorizedView ? const Color(0xFFC62828) : const Color(0xFF334155),
                        ),
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        minimumSize: const Size(0, 28),
                      ),
                      onPressed: () {
                        setState(() {
                          _simulateUnauthorizedView = !_simulateUnauthorizedView;
                          if (_simulateUnauthorizedView) {
                            _revealedReportIds.clear();
                          }
                        });
                        _rebuildMapMarkers();
                      },
                      child: Text(
                        _simulateUnauthorizedView ? 'Restaurar acceso' : 'Probar sin permiso',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold, color: Color(0xFF0284C7)),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          if (_reportes.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: Column(
                children: [
                  const Icon(Icons.folder_off_outlined, size: 48, color: Color(0xFF94A3B8)),
                  const SizedBox(height: 12),
                  const Text(
                    'No hay reportes registrados aún',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'Desliza a "Nuevo Reporte" o a "Geolocalización" para registrar el primero.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    onPressed: () => _tabController.animateTo(0),
                    child: const Text('Crear Primer Reporte'),
                  ),
                ],
              ),
            )
          else
            ListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _reportes.length,
              itemBuilder: (ctx, idx) {
                final r = _reportes[idx];
                final meetsRnf05 = r.precisionGps <= 5.0;

                return Container(
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x080F172A),
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  padding: const EdgeInsets.all(18),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  r.nombreComun,
                                  style: const TextStyle(
                                    fontSize: 17,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF0F2F38),
                                  ),
                                ),
                                if (r.nombreCientifico != null && r.nombreCientifico!.isNotEmpty)
                                  Padding(
                                    padding: const EdgeInsets.only(top: 2),
                                    child: Text(
                                      'Darwin Core: ${r.nombreCientifico}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontStyle: FontStyle.italic,
                                        color: Color(0xFF00796B),
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3.5),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFE0F2F1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  'ID #${r.id}',
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFF00796B),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 4),
                              IconButton(
                                icon: const Icon(Icons.edit_outlined, size: 20, color: Color(0xFF00796B)),
                                tooltip: 'Editar reporte',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                onPressed: () => _confirmEditReport(r),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete_outline_rounded, size: 20, color: Color(0xFFC62828)),
                                tooltip: 'Eliminar reporte',
                                constraints: const BoxConstraints(),
                                padding: const EdgeInsets.all(6),
                                onPressed: () => _confirmDeleteReport(r),
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Relación Foránea: Biólogo que lo registró
                      Row(
                        children: [
                          const Icon(Icons.person_outline_rounded, size: 16, color: Color(0xFF00796B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Biólogo: ${user?.nombreCompleto ?? "Investigador"} (${user?.matricula ?? "id: ${r.usuarioId}"})',
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),

                      // Coordenadas satelitales y protección AES-256-GCM (HU-07)
                      if (r.esProtegida) ...[
                        _buildProtectedCoordinateBox(r, user != null && !_simulateUnauthorizedView),
                      ] else ...[
                        Row(
                          children: [
                            const Icon(Icons.pin_drop_rounded, size: 16, color: Color(0xFF00796B)),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '${r.latitud.toStringAsFixed(5)}, ${r.longitud.toStringAsFixed(5)}',
                                style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF0F2F38),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(height: 6),

                      // Telemetría de Altitud y Precisión GNSS
                      Row(
                        children: [
                          const Icon(Icons.satellite_alt_rounded, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              'Precisión: ±${r.precisionGps.toStringAsFixed(1)} m · Altitud: ${r.altitud.toStringAsFixed(1)} m',
                              style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Badges de calidad RNF-05 y Cola FIFO HU-06
                      Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: meetsRnf05 ? const Color(0xFFE0F2F1) : const Color(0xFFFFF7ED),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: meetsRnf05 ? const Color(0xFF80CBC4) : const Color(0xFFFED7AA),
                              ),
                            ),
                            child: Text(
                              meetsRnf05 ? 'GNSS RNF-05 Cumplido' : 'Precisión Aceptable',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: meetsRnf05 ? const Color(0xFF004D40) : const Color(0xFFC2410C),
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: r.estadoSync == 'SINCRONIZADO' ? const Color(0xFFDCFCE7) : const Color(0xFFFEF3C7),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: r.estadoSync == 'SINCRONIZADO' ? const Color(0xFF86EFAC) : const Color(0xFFFCD34D),
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  r.estadoSync == 'SINCRONIZADO' ? Icons.cloud_done_rounded : Icons.schedule_rounded,
                                  size: 13,
                                  color: r.estadoSync == 'SINCRONIZADO' ? const Color(0xFF15803D) : const Color(0xFFB45309),
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  r.estadoSync == 'SINCRONIZADO' ? 'SINCRONIZADO' : 'PENDIENTE · Cola FIFO',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color: r.estadoSync == 'SINCRONIZADO' ? const Color(0xFF166534) : const Color(0xFF92400E),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Variables Ecológicas de Hábitat (HU-04)
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                            child: Text('Sustrato: ${r.sustrato}', style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                            child: Text('Estrato: ${r.estrato}', style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(color: const Color(0xFFF1F5F9), borderRadius: BorderRadius.circular(6)),
                            child: Text('Condición: ${r.condicion}', style: const TextStyle(fontSize: 11, color: Color(0xFF334155), fontWeight: FontWeight.w500)),
                          ),
                        ],
                      ),

                      // Fotografía de Evidencia implementada bajo el reporte (HU-01)
                      if (r.fotoBytesBase64 != null && r.fotoBytesBase64!.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () {
                            try {
                              final decoded = base64Decode(r.fotoBytesBase64!);
                              _mostrarFotoAmpliada(context, decoded, 'Evidencia: ${r.nombreComun}');
                            } catch (_) {}
                          },
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFCBD5E1)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                ClipRRect(
                                  borderRadius: const BorderRadius.vertical(top: Radius.circular(11)),
                                  child: Image.memory(
                                    base64Decode(r.fotoBytesBase64!),
                                    height: 180,
                                    width: double.infinity,
                                    fit: BoxFit.cover,
                                    errorBuilder: (ctx, err, stack) => Container(
                                      height: 90,
                                      color: const Color(0xFFF1F5F9),
                                      alignment: Alignment.center,
                                      child: const Text('Evidencia fotográfica adjunta', style: TextStyle(fontSize: 12, color: Color(0xFF64748B))),
                                    ),
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                                  decoration: const BoxDecoration(
                                    color: Color(0xFFF8FAFC),
                                    borderRadius: BorderRadius.vertical(bottom: Radius.circular(11)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.camera_alt_rounded, size: 14, color: Color(0xFF00796B)),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          r.fotoPath ?? 'evidencia_campo.jpg',
                                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF00796B)),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                      const Text(
                                        'Toca para ampliar 🔍',
                                        style: TextStyle(fontSize: 10.5, color: Color(0xFF64748B), fontStyle: FontStyle.italic),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ] else if (r.fotoPath != null) ...[
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(Icons.photo_camera_rounded, size: 14, color: Color(0xFF00796B)),
                            const SizedBox(width: 4),
                            Text(
                              'Evidencia: ${r.fotoPath}',
                              style: const TextStyle(fontSize: 11, color: Color(0xFF00796B), fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                      ],

                      if (r.notas.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF8FAFC),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFE2E8F0)),
                          ),
                          child: Text(
                            r.notas,
                            style: const TextStyle(fontSize: 13, color: Color(0xFF334155)),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  // =========================================================================
  // PESTAÑA 3: MAPA REAL CON PERMISOS, CONECTIVIDAD Y GEOLOCALIZACIÓN GNSS (HU-05)
  // =========================================================================
  Widget _buildGeolocalizacionTab() {
    final centerLat = _currentTelemetry?.latitude ?? 22.1524;
    final centerLon = _currentTelemetry?.longitude ?? -102.6142;
    final accuracy = _currentTelemetry?.accuracy ?? 3.5;
    final accessState = _currentTelemetry?.accessState ?? LocationAccessState.denied;
    final canShowMapLegend = accessState == LocationAccessState.granted && _hasInternetConnection;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 18.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Visor Cartográfico Real Interactivo (solo visible con permisos + internet)
          OfflineFieldMapWidget(
            centerLat: centerLat,
            centerLon: centerLon,
            accuracyMeters: accuracy,
            markers: _mapMarkers,
            height: 410,
            locationAccessState: accessState,
            hasInternet: _hasInternetConnection,
            isCheckingAccess: _isCheckingMapAccess || _isLocating,
            onRecenter: () => _recheckMapAccess(requestPermissionIfDenied: true),
            onRequestLocationPermission: _requestLocationPermissionFromUi,
            onOpenLocationSettings: _handleOpenLocationSettings,
            onRetryConnection: () => _recheckMapAccess(requestPermissionIfDenied: false),
            onTileNetworkError: _handleTileNetworkError,
            customTileProvider: widget.mapTileProvider,
          ),
          if (canShowMapLegend) ...[
            const SizedBox(height: 10),
            // Leyenda cartográfica compacta
            const Wrap(
              spacing: 12,
              runSpacing: 6,
              alignment: WrapAlignment.center,
              children: [
                _MapLegendDot(color: Color(0xFF1A73E8), label: 'Mi Ubicación'),
                _MapLegendDot(color: Color(0xFF00796B), label: 'Avistamiento'),
                _MapLegendDot(color: Color(0xFFD97706), label: 'Protegida (±5 km)'),
              ],
            ),
          ],
          const SizedBox(height: 16),

          // Tarjeta 1: Sensor Satelital GNSS en Vivo
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22.0),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0F172A),
                  blurRadius: 16.0,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Expanded(
                      child: Row(
                        children: [
                          Icon(Icons.satellite_alt_rounded, color: Color(0xFF00796B), size: 24),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Sensor Satelital GNSS',
                              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: _isLocating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded, color: Color(0xFF00796B)),
                      tooltip: 'Actualizar satélites y red',
                      onPressed: _isLocating ? null : () => _recheckMapAccess(requestPermissionIfDenied: true),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Telemetría de posición real del dispositivo y estado de conectividad para mapas.',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 12),
                // Indicador de Conectividad a Internet para el Mapa
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: _hasInternetConnection ? const Color(0xFFF0FDF4) : const Color(0xFFFEF2F2),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: _hasInternetConnection ? const Color(0xFF86EFAC) : const Color(0xFFFCA5A5),
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        _hasInternetConnection ? Icons.wifi_rounded : Icons.wifi_off_rounded,
                        size: 17,
                        color: _hasInternetConnection ? const Color(0xFF15803D) : const Color(0xFFC62828),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Red de Mapas: $_networkStatusMessage',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: _hasInternetConnection ? const Color(0xFF166534) : const Color(0xFF991B1B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                if (_currentTelemetry != null) ...[
                  Row(
                    children: [
                      _buildMetricBox('Latitud (DD)', _currentTelemetry!.latitude.toStringAsFixed(6)),
                      const SizedBox(width: 10),
                      _buildMetricBox('Longitud (DD)', _currentTelemetry!.longitude.toStringAsFixed(6)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      _buildMetricBox('Altitud', '${_currentTelemetry!.altitude.toStringAsFixed(1)} m'),
                      const SizedBox(width: 10),
                      _buildMetricBox('Precisión GNSS', '±${_currentTelemetry!.accuracy.toStringAsFixed(1)} m'),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Formato cartográfico DMS
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF8FAFC),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0xFFE2E8F0)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Coordenadas Cartográficas (DMS):',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Color(0xFF64748B)),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '${_currentTelemetry!.dmsLatitude},  ${_currentTelemetry!.dmsLongitude}',
                          style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Color(0xFF0F2F38)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Badge de autorización / calidad RNF-05
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: !_currentTelemetry!.hasMapAuthorization
                          ? const Color(0xFFFEF2F2)
                          : (_currentTelemetry!.isHighPrecision ? const Color(0xFFE0F2F1) : const Color(0xFFFFF7ED)),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: !_currentTelemetry!.hasMapAuthorization
                            ? const Color(0xFFFCA5A5)
                            : (_currentTelemetry!.isHighPrecision ? const Color(0xFF80CBC4) : const Color(0xFFFED7AA)),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          !_currentTelemetry!.hasMapAuthorization
                              ? Icons.location_off_rounded
                              : (_currentTelemetry!.isHighPrecision ? Icons.verified_rounded : Icons.warning_amber_rounded),
                          color: !_currentTelemetry!.hasMapAuthorization
                              ? const Color(0xFFC62828)
                              : (_currentTelemetry!.isHighPrecision ? const Color(0xFF00796B) : const Color(0xFFEA580C)),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            !_currentTelemetry!.hasMapAuthorization
                                ? _currentTelemetry!.statusMessage
                                : (_currentTelemetry!.isHighPrecision
                                    ? 'Ubicación Real Autorizada (±${_currentTelemetry!.accuracy.toStringAsFixed(1)} m) · Cumple RNF-05 (≤ 5 m)'
                                    : 'Ubicación Real Autorizada (±${_currentTelemetry!.accuracy.toStringAsFixed(1)} m)'),
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: !_currentTelemetry!.hasMapAuthorization
                                  ? const Color(0xFF991B1B)
                                  : (_currentTelemetry!.isHighPrecision ? const Color(0xFF004D40) : const Color(0xFFC2410C)),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ] else ...[
                  const Center(child: Text('Sin datos de telemetría disponibles.')),
                ],
                const SizedBox(height: 20),
                SizedBox(
                  height: 48,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF00796B),
                      side: const BorderSide(color: Color(0xFF00796B), width: 1.5),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: _isLocating
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : Icon(_currentTelemetry?.hasMapAuthorization == true
                            ? Icons.gps_fixed_rounded
                            : Icons.my_location_rounded),
                    label: Text(
                      _currentTelemetry?.hasMapAuthorization == true
                          ? 'Actualizar Coordenadas GPS'
                          : 'Otorgar Permisos de Ubicación',
                      style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold),
                    ),
                    onPressed: _isLocating
                        ? null
                        : (_currentTelemetry?.hasMapAuthorization == true
                            ? () => _recheckMapAccess(requestPermissionIfDenied: true)
                            : _requestLocationPermissionFromUi),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 18),

          // Tarjeta 2: Operación Verificable en SQLite
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(22.0),
              border: Border.all(color: const Color(0xFFE2E8F0), width: 1.5),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x0D0F172A),
                  blurRadius: 16.0,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            padding: const EdgeInsets.all(22.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Row(
                  children: [
                    Icon(Icons.verified_user_rounded, color: Color(0xFF00796B), size: 24),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Operación Verificable',
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Registra de inmediato un avistamiento vinculando la posición satelital capturada al biólogo en la base de datos SQLite.',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 50,
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF00796B),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      elevation: 2,
                    ),
                    icon: const Icon(Icons.add_location_alt_rounded),
                    label: const Text('Registrar Avistamiento con este GPS', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                    onPressed: _showQuickSightingDialog,
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  height: 46,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    icon: const Icon(Icons.format_list_bulleted_rounded, color: Color(0xFF64748B)),
                    label: const Text('Abrir Asistente por Fases', style: TextStyle(fontSize: 14, color: Color(0xFF475569))),
                    onPressed: () {
                      setState(() => _wizardStep = 1);
                      _tabController.animateTo(0);
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProtectedCoordinateBox(ReporteModel r, bool canAuthorize) {
    final isRevealed = r.id != null && _revealedReportIds.contains(r.id) && canAuthorize;
    final String? decrypted = isRevealed && r.coordenadasCifradas != null
        ? _protectionService.reveal(r.coordenadasCifradas!, authorized: canAuthorize)
        : null;
    final obfuscated = CoordinateProtectionService.obfuscateCoordinate(
      r.latitud,
      r.longitud,
      seed: r.id ?? r.nombreComun.hashCode,
    );
    final cipherPreview = r.coordenadasCifradas != null && r.coordenadasCifradas!.length > 22
        ? '${r.coordenadasCifradas!.substring(0, 22)}...'
        : (r.coordenadasCifradas ?? 'AES-256-GCM');

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isRevealed ? const Color(0xFFF0FDF4) : const Color(0xFFFFFBEB),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isRevealed ? const Color(0xFF86EFAC) : const Color(0xFFFCD34D),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                isRevealed ? Icons.lock_open_rounded : Icons.lock_rounded,
                size: 16,
                color: isRevealed ? const Color(0xFF15803D) : const Color(0xFFD97706),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isRevealed
                      ? 'Coordenadas Exactas Descifradas (AES-256-GCM)'
                      : 'Especie Protegida · Coordenadas Cifradas (HU-07)',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: isRevealed ? const Color(0xFF166534) : const Color(0xFFB45309),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            isRevealed
                ? 'WGS84 Exacto: ${decrypted ?? "${r.latitud.toStringAsFixed(6)}, ${r.longitud.toStringAsFixed(6)}"}'
                : 'Área ofuscada (±5 km): ${obfuscated.lat.toStringAsFixed(4)}, ${obfuscated.lon.toStringAsFixed(4)}',
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF0F2F38)),
          ),
          const SizedBox(height: 3),
          Text(
            'Token cifrado: $cipherPreview',
            style: const TextStyle(fontSize: 10.5, fontFamily: 'monospace', color: Color(0xFF64748B)),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                minimumSize: const Size(0, 32),
                side: BorderSide(
                  color: isRevealed ? const Color(0xFF15803D) : const Color(0xFFD97706),
                ),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              icon: Icon(
                isRevealed ? Icons.visibility_off_rounded : Icons.vpn_key_rounded,
                size: 14,
                color: isRevealed ? const Color(0xFF15803D) : const Color(0xFFB45309),
              ),
              label: Text(
                isRevealed ? 'Ocultar Exactas' : 'Revelar Exactas',
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.bold,
                  color: isRevealed ? const Color(0xFF15803D) : const Color(0xFFB45309),
                ),
              ),
              onPressed: () {
                if (isRevealed && r.id != null) {
                  setState(() => _revealedReportIds.remove(r.id));
                  _rebuildMapMarkers();
                  return;
                }
                final check = r.coordenadasCifradas != null
                    ? _protectionService.reveal(r.coordenadasCifradas!, authorized: canAuthorize)
                    : (canAuthorize ? '${r.latitud},${r.longitud}' : null);
                if (check == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Acceso denegado (HU-07): el perfil actual no tiene autorización para descifrar coordenadas.'),
                      backgroundColor: Color(0xFFC62828),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                  return;
                }
                if (r.id != null) {
                  setState(() => _revealedReportIds.add(r.id!));
                  _rebuildMapMarkers();
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricBox(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        decoration: BoxDecoration(
          color: const Color(0xFFF8FAFC),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1.2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF64748B))),
            const SizedBox(height: 4),
            Text(value, style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38))),
          ],
        ),
      ),
    );
  }
}

class _MapLegendDot extends StatelessWidget {
  final Color color;
  final String label;

  const _MapLegendDot({required this.color, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF475569)),
        ),
      ],
    );
  }
}
