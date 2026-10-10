import 'package:drift/drift.dart';

import '../../../domain/entidades/indicador_higiene.dart';
import '../../local/manos_seguras_db.dart' as db;
import '../../mapeadores/indicador_mapper.dart';
import '../../remoto/higiene_api_service.dart';
import '../aliases.dart' as g;



/// **DAO de la caché local del indicador de la OMS.**
///
/// Semana 10 — temática 2.2.3. Manipula dos tablas:
///
///  * `indicadores_cache` → los 16 años de la serie histórica;
///  * `sincronizaciones`  → la marca de tiempo de la última descarga
///    exitosa, que es la que decide si la caché está vigente.
abstract interface class IndicadoresDao {
  /// Registros guardados, ordenados por año.
  Future<List<IndicadorHigiene>> leerTodo();

  /// Igual que [leerTodo] pero reactivo (Semana 12: Riverpod).
  Stream<List<IndicadorHigiene>> observarTodo();

  /// Inserta o reemplaza una lista completa en **una sola transacción**.
  ///
  /// **Reto 2:** la operación debe ser atómica (o se guardan todos los
  /// registros o no se guarda ninguno) y debe escribir la marca de tiempo.
  Future<void> reemplazarTodo(
    List<IndicadorHigiene> indicadores, {
    required DateTime momento,
    String codigo = HigieneApiService.codigoIndicador,
  });

  /// Fecha de la última sincronización del recurso, o `null`.
  Future<DateTime?> ultimaSincronizacion(String codigo);
  Future<int> registrarIntentoFallido(String codigo);
  Future<int> intentosFallidos(String codigo);
  Future<void> invalidar(String codigo);

  /// Elimina todos los registros de la caché (sin tocar `sincronizaciones`).
  Future<void> limpiar();
}

/// Implementación con drift (ver Anexo A, Error 7: por qué no lleva
/// `@DriftAccessor`).
class DriftIndicadoresDao extends DatabaseAccessor<db.ManosSegurasDb>
    implements IndicadoresDao {
  DriftIndicadoresDao(super.db);

  @override
  Future<List<IndicadorHigiene>> leerTodo() async {
    final List<db.IndicadoresCacheData> filas =
        await (select(attachedDatabase.indicadoresCache)
              ..orderBy(<OrderClauseGenerator<g.TablaIndicadoresCache>>[
                (g.TablaIndicadoresCache t) => OrderingTerm(expression: t.anio),
              ]))
            .get();
    return filas.map(IndicadorMapper.desdeFila).toList();
  }

  @override
  Stream<List<IndicadorHigiene>> observarTodo() {
    return (select(attachedDatabase.indicadoresCache)
          ..orderBy(<OrderClauseGenerator<g.TablaIndicadoresCache>>[
            (g.TablaIndicadoresCache t) => OrderingTerm(expression: t.anio),
          ]))
        .watch()
        .map(
          (List<db.IndicadoresCacheData> filas) =>
              filas.map(IndicadorMapper.desdeFila).toList(),
        );
  }

  /// **Versión base del Reto 2: guardado atómico de la caché.**
  ///
  /// Tres cosas ocurren dentro de la misma transacción:
  ///  1. se vacía la caché anterior;
  ///  2. se insertan los registros nuevos en un solo lote (`batch`);
  ///  3. se actualiza la marca de sincronización con la hora del servidor.
  ///
  /// Si algo falla, la caché anterior sigue intacta: la aplicación nunca se
  /// queda sin datos por una descarga a medias.
  ///
  @override
  Future<void> reemplazarTodo(
    List<IndicadorHigiene> indicadores, {
    required DateTime momento,
    String codigo = HigieneApiService.codigoIndicador,
  }) async {
    await transaction(() async {
      await (delete(attachedDatabase.indicadoresCache)
            ..where((g.TablaIndicadoresCache t) => t.codigoIndicador.equals(codigo)))
          .go();

      await batch((Batch b) {
        b.insertAll(
          attachedDatabase.indicadoresCache,
          indicadores
              .map(
                (IndicadorHigiene i) =>
                    IndicadorMapper.aFila(i, descargadoEn: momento),
              )
              .toList(),
        );
      });

      await into(attachedDatabase.sincronizaciones).insertOnConflictUpdate(
        db.SincronizacionesCompanion.insert(
          codigo: codigo,
          ultimaSincronizacion: momento,
          registros: Value<int>(indicadores.length),
          intentosFallidosConsecutivos: const Value<int>(0),
        ),
      );
    });
  }

  @override
  Future<DateTime?> ultimaSincronizacion(String codigo) async {
    final db.Sincronizacione? fila =
        await (select(attachedDatabase.sincronizaciones)
              ..where((g.TablaSincronizaciones t) => t.codigo.equals(codigo)))
            .getSingleOrNull();
    return fila?.ultimaSincronizacion;
  }

  @override
  Future<int> registrarIntentoFallido(String codigo) async {
    return transaction<int>(() async {
      final db.Sincronizacione? fila =
          await (select(attachedDatabase.sincronizaciones)
                ..where((g.TablaSincronizaciones t) => t.codigo.equals(codigo)))
              .getSingleOrNull();
      final int intentos = (fila?.intentosFallidosConsecutivos ?? 0) + 1;
      if (fila == null) {
        // Epoch indica que todavía no hubo una descarga exitosa; no se debe
        // presentar como una marca de vigencia reciente.
        await into(attachedDatabase.sincronizaciones).insert(
          db.SincronizacionesCompanion.insert(
            codigo: codigo,
            ultimaSincronizacion: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
            registros: const Value<int>(0),
            intentosFallidosConsecutivos: Value<int>(intentos),
          ),
        );
      } else {
        await (update(attachedDatabase.sincronizaciones)
              ..where((g.TablaSincronizaciones t) => t.codigo.equals(codigo)))
            .write(
          db.SincronizacionesCompanion(
            intentosFallidosConsecutivos: Value<int>(intentos),
          ),
        );
      }
      return intentos;
    });
  }

  @override
  Future<int> intentosFallidos(String codigo) async {
    final db.Sincronizacione? fila =
        await (select(attachedDatabase.sincronizaciones)
              ..where((g.TablaSincronizaciones t) => t.codigo.equals(codigo)))
            .getSingleOrNull();
    return fila?.intentosFallidosConsecutivos ?? 0;
  }

  @override
  Future<void> invalidar(String codigo) async {
    await (delete(attachedDatabase.sincronizaciones)
          ..where((g.TablaSincronizaciones t) => t.codigo.equals(codigo)))
        .go();
  }

  @override
  Future<void> limpiar() {
    return delete(attachedDatabase.indicadoresCache).go();
  }
}
