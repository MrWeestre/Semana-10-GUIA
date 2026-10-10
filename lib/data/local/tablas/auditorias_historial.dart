import 'package:drift/drift.dart';

import 'auditorias.dart';

/// Registro inmutable de cambios realizados sobre una auditoría.
@TableIndex(
  name: 'idx_historial_auditoria_fecha',
  columns: {#auditoriaId, #fechaCambio},
)
class AuditoriasHistorial extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get auditoriaId => text().references(
        Auditorias,
        #id,
        onDelete: KeyAction.cascade,
      )();

  DateTimeColumn get fechaCambio =>
      dateTime().withDefault(currentDateAndTime)();
  TextColumn get campo => text()();
  TextColumn get valorAnterior => text().nullable()();
  TextColumn get valorNuevo => text().nullable()();
}
