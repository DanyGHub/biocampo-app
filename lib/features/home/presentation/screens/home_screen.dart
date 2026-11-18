import 'package:flutter/material.dart';
import 'package:biocampo_app/core/database/app_database.dart';
import 'package:biocampo_app/features/auth/domain/services/auth_service.dart';
import 'package:biocampo_app/features/location/domain/services/location_service.dart';
import 'package:biocampo_app/features/reports/domain/models/reporte_model.dart';
import 'package:biocampo_app/features/auth/presentation/screens/login_screen.dart';

class HomeScreen extends StatefulWidget {
  final AuthService authService;

  const HomeScreen({super.key, required this.authService});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // Estado del Wizard de Generación de Reporte
  int _wizardStep = 0; // 0: Inicio, 1: Datos, 2: GPS, 3: Fotos, 4: Confirmación
  final _especieController = TextEditingController();
  final _notasController = TextEditingController();
  bool _fotoSeleccionada = false;

  // Estado de Geolocalización y Base de Datos
  GpsTelemetry? _currentTelemetry;
  bool _isLocating = false;
  bool _isSaving = false;
  List<ReporteModel> _reportes = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadInitialLocationAndReports();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _especieController.dispose();
    _notasController.dispose();
    super.dispose();
  }

  Future<void> _loadInitialLocationAndReports() async {
    await _refreshReports();
    await _acquireGpsLocation();
  }

  Future<void> _refreshReports() async {
    final list = await AppDatabase.instance.getReportes(
      usuarioId: widget.authService.currentUser?.id,
    );
    if (mounted) {
      setState(() => _reportes = list);
    }
  }

  Future<void> _acquireGpsLocation() async {
    setState(() => _isLocating = true);
    final telemetry = await LocationService.getCurrentLocation();
    if (mounted) {
      setState(() {
        _currentTelemetry = telemetry;
        _isLocating = false;
      });
    }
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

    final nuevoReporte = ReporteModel(
      usuarioId: user.id!,
      fechaHora: DateTime.now().toIso8601String(),
      latitud: telemetry.latitude,
      longitud: telemetry.longitude,
      altitud: telemetry.altitude,
      precisionGps: telemetry.accuracy,
      nombreComun: especie,
      notas: _notasController.text.trim(),
      estadoSync: 'PENDIENTE',
    );

    try {
      await AppDatabase.instance.insertReporte(nuevoReporte);
      _especieController.clear();
      _notasController.clear();
      _fotoSeleccionada = false;
      _wizardStep = 0; // Regresar inicio del wizard
      await _refreshReports();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Reporte guardado exitosamente.', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
          backgroundColor: Color(0xFF00796B),
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
    );

    try {
      await AppDatabase.instance.insertReporte(reporte);
      await _refreshReports();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('¡Reporte de "$especie" guardado con éxito!'),
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
              icon: Icon(Icons.satellite_alt_rounded, size: 21),
              text: 'Geolocalización',
            ),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Banner superior de Usuario activo (compacto y sutil)
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
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: const Color(0xFFE0F2F1),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.circle, color: Color(0xFF00796B), size: 8),
                        SizedBox(width: 4),
                        Text(
                          'En Línea',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Color(0xFF004D40)),
                        ),
                      ],
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
                physics: const BouncingScrollPhysics(),
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
        const Text('Especie / Taxón *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 6),
        TextField(
          controller: _especieController,
          style: const TextStyle(fontSize: 15.5, color: Color(0xFF0F2F38)),
          decoration: InputDecoration(
            hintText: 'Ej. Jaguarundi (Herpailurus yagouaroundi)',
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 16),
        const Text('Notas de Campo / Hábitat *', style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Color(0xFF1E293B))),
        const SizedBox(height: 6),
        TextField(
          controller: _notasController,
          maxLines: 3,
          style: const TextStyle(fontSize: 15.5, color: Color(0xFF0F2F38)),
          decoration: InputDecoration(
            hintText: 'Observaciones de terreno, comportamiento o clima...',
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
            const Text(
              'Fase 2: Ubicación Satelital',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
            ),
            IconButton(
              icon: _isLocating
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh_rounded, color: Color(0xFF00796B)),
              onPressed: _isLocating ? null : _acquireGpsLocation,
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

  // Fase 3: Fotos y Capturas (Opcional)
  Widget _buildFase3Fotos() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text(
          'Fase 3: Fotos y Evidencia',
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
        ),
        const SizedBox(height: 6),
        const Text(
          'Adjunta evidencia fotográfica del ejemplar o hábitat (Opcional).',
          style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
        ),
        const SizedBox(height: 20),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFF8FAFC),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: const Color(0xFFCBD5E1), style: BorderStyle.solid),
          ),
          child: Column(
            children: [
              Icon(
                _fotoSeleccionada ? Icons.check_circle_rounded : Icons.photo_camera_rounded,
                size: 46,
                color: _fotoSeleccionada ? const Color(0xFF00796B) : const Color(0xFF94A3B8),
              ),
              const SizedBox(height: 10),
              Text(
                _fotoSeleccionada ? 'Fotografía de campo adjuntada' : 'Sin fotografía adjunta',
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
              ),
              const SizedBox(height: 4),
              const Text(
                'Apartado opcional para la versión Alpha.',
                style: TextStyle(fontSize: 12.5, color: Color(0xFF64748B)),
              ),
              const SizedBox(height: 14),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                icon: Icon(_fotoSeleccionada ? Icons.refresh : Icons.add_a_photo_outlined),
                label: Text(_fotoSeleccionada ? 'Cambiar Foto' : 'Adjuntar Foto (Simulada)'),
                onPressed: () => setState(() => _fotoSeleccionada = !_fotoSeleccionada),
              ),
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
              _summaryRow('Especie:', _especieController.text),
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
              _summaryRow('Fotografía:', _fotoSeleccionada ? 'Adjunta' : 'Sin foto (Opcional)'),
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
              const Text(
                'Reportes Guardados',
                style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
              ),
              IconButton(
                icon: const Icon(Icons.sync_rounded, color: Color(0xFF00796B)),
                tooltip: 'Actualizar lista',
                onPressed: _refreshReports,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Total: ${_reportes.length} avistamientos persistidos en la base SQLite local.',
            style: const TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
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
                            child: Text(
                              r.nombreComun,
                              style: const TextStyle(
                                fontSize: 17,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF0F2F38),
                              ),
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

                      // Coordenadas satelitales
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
                      const SizedBox(height: 6),

                      // Telemetría de Altitud y Precisión GNSS
                      Row(
                        children: [
                          const Icon(Icons.satellite_alt_rounded, size: 16, color: Color(0xFF64748B)),
                          const SizedBox(width: 6),
                          Text(
                            'Precisión: ±${r.precisionGps.toStringAsFixed(1)} m · Altitud: ${r.altitud.toStringAsFixed(1)} m',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w500, color: Color(0xFF64748B)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),

                      // Badge de calidad RNF-05
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
                          meetsRnf05 ? 'GNSS de Alta Precisión (RNF-05 Cumplido)' : 'Precisión Satelital Aceptable',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: meetsRnf05 ? const Color(0xFF004D40) : const Color(0xFFC2410C),
                          ),
                        ),
                      ),

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
  // PESTAÑA 3: GEOLOCALIZACIÓN SATELITAL GNSS
  // =========================================================================
  Widget _buildGeolocalizacionTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 20.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
                    const Row(
                      children: [
                        Icon(Icons.satellite_alt_rounded, color: Color(0xFF00796B), size: 24),
                        SizedBox(width: 8),
                        Text(
                          'Sensor Satelital GNSS',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
                        ),
                      ],
                    ),
                    IconButton(
                      icon: _isLocating
                          ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                          : const Icon(Icons.refresh_rounded, color: Color(0xFF00796B)),
                      tooltip: 'Actualizar satélites',
                      onPressed: _isLocating ? null : _acquireGpsLocation,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                const Text(
                  'Telemetría de posición en tiempo real obtenida mediante satélites.',
                  style: TextStyle(fontSize: 13.5, color: Color(0xFF64748B)),
                ),
                const SizedBox(height: 20),

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
                  // Badge de calidad RNF-05
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _currentTelemetry!.isHighPrecision ? const Color(0xFFE0F2F1) : const Color(0xFFFFF7ED),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _currentTelemetry!.isHighPrecision ? const Color(0xFF80CBC4) : const Color(0xFFFED7AA),
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _currentTelemetry!.isHighPrecision ? Icons.verified_rounded : Icons.warning_amber_rounded,
                          color: _currentTelemetry!.isHighPrecision ? const Color(0xFF00796B) : const Color(0xFFEA580C),
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _currentTelemetry!.isHighPrecision
                                ? 'Precisión Satelital Óptima (±${_currentTelemetry!.accuracy.toStringAsFixed(1)} m) · Cumple RNF-05 (≤ 5 m)'
                                : 'Calibrando Señal GNSS (±${_currentTelemetry!.accuracy.toStringAsFixed(1)} m)',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w600,
                              color: _currentTelemetry!.isHighPrecision ? const Color(0xFF004D40) : const Color(0xFFC2410C),
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
                        : const Icon(Icons.gps_fixed_rounded),
                    label: const Text('Actualizar Coordenadas GPS', style: TextStyle(fontSize: 14.5, fontWeight: FontWeight.bold)),
                    onPressed: _isLocating ? null : _acquireGpsLocation,
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
                    Text(
                      'Operación Verificable',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF0F2F38)),
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
