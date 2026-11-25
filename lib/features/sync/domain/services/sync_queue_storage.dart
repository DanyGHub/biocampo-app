import 'dart:collection';

/// Almacenamiento de pendientes: IDs unicos en orden de llegada.
abstract class SyncQueueStorage {
  Future<void> addIfAbsent(String reportId);

  /// Devuelve una copia de los pendientes en orden FIFO.
  Future<List<String>> readAll();
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
}
