import 'sync_queue_storage.dart';

/// HU-06: cola FIFO de reportes sin duplicados.
/// Usa memoria por defecto; permite sustituir el almacenamiento.
class SyncQueueService {
  final SyncQueueStorage _storage;

  SyncQueueService({SyncQueueStorage? storage})
      : _storage = storage ?? InMemorySyncQueueStorage();

  Future<void> enqueue(String reportId) => _storage.addIfAbsent(reportId);

  Future<List<String>> pendingIds() => _storage.readAll();

  Future<void> remove(String reportId) => _storage.remove(reportId);

  Future<void> clear() => _storage.clear();

  /// Procesa la cola en orden estricto FIFO únicamente cuando existe red activa.
  Future<int> flushQueue({
    required bool isOnline,
    Future<bool> Function(String reportId)? onSend,
  }) async {
    if (!isOnline) return 0;

    final pending = await pendingIds();
    int syncedCount = 0;
    for (final id in pending) {
      final ok = onSend != null ? await onSend(id) : true;
      if (ok) {
        await _storage.remove(id);
        syncedCount++;
      } else {
        // Preservar orden FIFO ante falla de red transitoria
        break;
      }
    }
    return syncedCount;
  }
}
