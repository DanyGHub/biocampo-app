/// HU-06: contrato inicial S06. Pendiente implementar en la fase GREEN.
class SyncQueueService {
  Future<void> enqueue(String reportId) async {
    throw UnimplementedError('HU-06: encolado idempotente pendiente');
  }

  Future<List<String>> pendingIds() async {
    throw UnimplementedError('HU-06: consulta FIFO pendiente');
  }
}
