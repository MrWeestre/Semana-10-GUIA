import 'package:drift/drift.dart';

import 'auditorias.dart';

@TableIndex(name: 'idx_oportunidades_auditoria', columns: {#auditoriaId})
class Oportunidades extends Table {
  IntColumn get id => integer().autoIncrement()();

  TextColumn get auditoriaId => text().references(
        Auditorias,
        #id,
        onDelete: KeyAction.cascade,
      )();

  IntColumn get numero => integer()();
  TextColumn get momentoClave => text()();
  TextColumn get accionClave => text()();
  TextColumn get observacion => text().nullable()();

  /// Campo nullable añadido en el esquema v2.
  IntColumn get duracionSegundos => integer().nullable()();

  DateTimeColumn get registradoEn =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  List<Set<Column<Object>>> get uniqueKeys => <Set<Column<Object>>>[
        <Column<Object>>{auditoriaId, numero},
      ];
}
