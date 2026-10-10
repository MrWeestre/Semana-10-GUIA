import 'package:drift/drift.dart';

import 'establecimientos.dart';
import 'personal.dart';

/// Cabecera de una auditoría de higiene de manos.
@TableIndex(name: 'idx_auditorias_estado_fecha', columns: {#estado, #fecha})
class Auditorias extends Table {
  TextColumn get id => text()();

  TextColumn get establecimientoId => text().references(
        Establecimientos,
        #codigoUnico,
        onDelete: KeyAction.restrict,
      )();

  TextColumn get establecimientoNombre => text()();

  @ReferenceName('auditoriasComoObservador')
  TextColumn get observadorDni =>
      text().references(Personal, #dni, onDelete: KeyAction.restrict)();
  TextColumn get observadorNombre => text()();

  @ReferenceName('auditoriasComoObservado')
  TextColumn get observadoDni =>
      text().references(Personal, #dni, onDelete: KeyAction.restrict)();
  TextColumn get observadoNombre => text()();

  DateTimeColumn get fecha => dateTime()();

  DateTimeColumn get inicioObservacion => dateTime().nullable()();
  DateTimeColumn get finObservacion => dateTime().nullable()();
  IntColumn get numeroCamasServicio => integer().nullable()();
  BoolColumn get consentimientoVerbal => boolean().nullable()();

  /// Campo añadido en el esquema v2. Nullable para conservar auditorías v1.
  TextColumn get observacionGeneral => text().nullable()();

  TextColumn get estado => text().withDefault(const Constant('borrador'))();
  BoolColumn get eliminada => boolean().withDefault(const Constant(false))();
  DateTimeColumn get sincronizadaEn => dateTime().nullable()();
  DateTimeColumn get creadoEn => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get actualizadoEn =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column<Object>> get primaryKey => <Column<Object>>{id};
}
