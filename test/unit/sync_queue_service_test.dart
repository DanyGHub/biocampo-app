import 'package:flutter_test/flutter_test.dart';
import 'package:biocampo_app/features/sync/domain/services/sync_queue_service.dart';
import 'package:biocampo_app/features/sync/domain/services/sync_queue_storage.dart';

void main() {
  group('HU-06: almacenamiento de la cola', () {
    test(
        'Dos servicios con el mismo almacenamiento comparten pendientes unicos',
        () async {
      final storage = InMemorySyncQueueStorage();
      final first = SyncQueueService(storage: storage);
      final second = SyncQueueService(storage: storage);

      await first.enqueue('reporte-002');
      await second.enqueue('reporte-001');
      await second.enqueue('reporte-002');

      expect(await first.pendingIds(), ['reporte-002', 'reporte-001']);
      expect(await second.pendingIds(), ['reporte-002', 'reporte-001']);
    });

    test('Las instancias por defecto mantienen colas independientes', () async {
      final first = SyncQueueService();
      final second = SyncQueueService();

      await first.enqueue('reporte-001');

      expect(await first.pendingIds(), ['reporte-001']);
      expect(await second.pendingIds(), isEmpty);
    });

    test('Modificar una consulta no modifica los pendientes almacenados',
        () async {
      final queue = SyncQueueService();
      await queue.enqueue('reporte-001');
      final snapshot = await queue.pendingIds();

      snapshot.clear();
      snapshot.add('reporte-ajeno');

      expect(await queue.pendingIds(), ['reporte-001']);
    });
  });
}
