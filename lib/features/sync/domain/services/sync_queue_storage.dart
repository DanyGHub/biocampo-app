import 'dart:collection';
import 'package:shared_preferences/shared_preferences.dart';

/// Almacenamiento de pendientes: IDs unicos en orden de llegada.
abstract class SyncQueueStorage {
  Future<void> addIfAbsent(String reportId);

  /// Devuelve una copia de los pendientes en orden FIFO.
  Future<List<String>> readAll();

  /// Elimina un ID una vez sincronizado exitosamente.
  Future<void> remove(String reportId) async {}

  /// Limpia por completo la cola local.
  Future<void> clear() async {}
}

/// Almacenamiento inicial; los pendientes viven durante esta instancia.
class InMemorySyncQueueStorage implements SyncQueueStorage {
  final LinkedHashSet<String> _pending = LinkedHashSet<String>();

  @override
  Future<void> addIfAbsent(String reportId) async {
    _pending.add(reportId);
  }

  @override
  Future<List<String>> readAll() async {
    return _pending.toList();
  }

  @override
  Future<void> remove(String reportId) async {
    _pending.remove(reportId);
  }

  @override
  Future<void> clear() async {
    _pending.clear();
  }
}

/// Almacenamiento persistente FIFO respaldado por SharedPreferences (Web & Móvil).
class SharedPreferencesSyncQueueStorage implements SyncQueueStorage {
  static const String _storageKey = 'biocampo_sync_queue_fifo_ids';

  @override
  Future<void> addIfAbsent(String reportId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_storageKey) ?? <String>[];
    if (!current.contains(reportId)) {
      current.add(reportId);
      await prefs.setStringList(_storageKey, current);
    }
  }

  @override
  Future<List<String>> readAll() async {
    final prefs = await SharedPreferences.getInstance();
    return List<String>.from(prefs.getStringList(_storageKey) ?? <String>[]);
  }

  @override
  Future<void> remove(String reportId) async {
    final prefs = await SharedPreferences.getInstance();
    final current = prefs.getStringList(_storageKey) ?? <String>[];
    current.remove(reportId);
    await prefs.setStringList(_storageKey, current);
  }

  @override
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
