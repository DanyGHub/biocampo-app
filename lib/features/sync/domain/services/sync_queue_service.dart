/// HU-06: cola FIFO inicial en memoria, sin duplicados.
class SyncQueueService {
  final List<String> _pending = [];

  Future<void> enqueue(String reportId) async {
    // TODO(refactor): separar el almacenamiento de la politica de encolado.
    if (!_pending.contains(reportId)) {
      _pending.add(reportId);
    }
  }

  Future<List<String>> pendingIds() async {
    return List<String>.from(_pending);
  }
}
