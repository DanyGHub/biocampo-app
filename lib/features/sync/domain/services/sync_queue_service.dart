import 'sync_queue_storage.dart';

/// HU-06: cola FIFO de reportes sin duplicados.
/// Usa memoria por defecto; permite sustituir el almacenamiento.
class SyncQueueService {
  final SyncQueueStorage _storage;

  SyncQueueService({SyncQueueStorage? storage})
      : _storage = storage ?? InMemorySyncQueueStorage();

  Future<void> enqueue(String reportId) => _storage.addIfAbsent(reportId);

  Future<List<String>> pendingIds() => _storage.readAll();
}
