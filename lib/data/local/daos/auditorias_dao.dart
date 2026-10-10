import 'package:drift/drift.dart';

import '../../../domain/entidades/auditoria.dart';
import '../../../domain/entidades/oportunidad_registro.dart';
import '../../local/manos_seguras_db.dart' as db;
import '../../mapeadores/mapeadores.dart';
import '../aliases.dart' as g;

abstract interface class AuditoriasDao {
  Stream<List<Auditoria>> observar({
    bool incluirEliminadas = false,
    bool soloEliminadas = false,
    int? limite,
    int offset = 0,
    EstadoAuditoria? estado,
  });

  Future<List<Auditoria>> listar({
    bool incluirEliminadas = false,
    bool soloEliminadas = false,
    int? limite,
    int offset = 0,
    EstadoAuditoria? estado,
  });

  Future<Auditoria?> buscarPorId(String id);
  Future<bool> insertarCabecera(Auditoria auditoria);
  Future<int> actualizarCabecera(Auditoria auditoria);
  Future<int> marcarEliminada(String id);
  Future<int> restaurar(String id);
  Future<void> registrarHistorial(Auditoria anterior, Auditoria nueva);
  Future<T> transaccion<T>(Future<T> Function() operacion);
  Future<int> borrarOportunidadesDe(String auditoriaId);
  Future<OportunidadRegistro> insertarOportunidad(
    OportunidadRegistro oportunidad,
  );
  Future<int> borrarOportunidad(int id);
  Future<Map<EstadoAuditoria, int>> conteoPorEstado();
  Future<ResumenAdherencia> resumenAdherencia();
  Future<Map<String, ({int total, int cumplidas})>> resumenPorMomento();
  Future<List<Auditoria>> listarPorRango(DateTime desde, DateTime hasta);
  Future<List<String>> explicarPlanListado();
}

class DriftAuditoriasDao extends DatabaseAccessor<db.ManosSegurasDb>
    implements AuditoriasDao {
  DriftAuditoriasDao(super.db);

  @override
  Stream<List<Auditoria>> observar({
    bool incluirEliminadas = false,
    bool soloEliminadas = false,
    int? limite,
    int offset = 0,
    EstadoAuditoria? estado,
  }) {
    final SimpleSelectStatement<g.TablaAuditorias, db.Auditoria> consulta =
        select(attachedDatabase.auditorias);
    _aplicarFiltros(
      consulta,
      incluirEliminadas: incluirEliminadas,
      soloEliminadas: soloEliminadas,
      estado: estado,
      limite: limite,
      offset: offset,
    );
    return consulta.watch().asyncMap(
          (List<db.Auditoria> filas) =>
              _conOportunidades(filas, incluirEliminadas: incluirEliminadas),
        );
  }

  @override
  Future<List<Auditoria>> listar({
    bool incluirEliminadas = false,
    bool soloEliminadas = false,
    int? limite,
    int offset = 0,
    EstadoAuditoria? estado,
  }) async {
    final List<db.Auditoria> filas = await _cabeceras(
      incluirEliminadas: incluirEliminadas,
      soloEliminadas: soloEliminadas,
      limite: limite,
      offset: offset,
      estado: estado,
    );
    return _conOportunidades(filas, incluirEliminadas: incluirEliminadas);
  }

  @override
  Future<Auditoria?> buscarPorId(String id) async {
    final db.Auditoria? cabecera = await (select(attachedDatabase.auditorias)
          ..where((g.TablaAuditorias t) => t.id.equals(id)))
        .getSingleOrNull();
    if (cabecera == null) return null;

    final List<db.Oportunidade> oportunidades = await _oportunidadesDe(id);
    return AuditoriaMapper.desdeFilas(cabecera, oportunidades);
  }

  @override
  Future<bool> insertarCabecera(Auditoria auditoria) async {
    final db.Auditoria? existente = await (select(attachedDatabase.auditorias)
          ..where((g.TablaAuditorias t) => t.id.equals(auditoria.id)))
        .getSingleOrNull();
    if (existente != null) return false;

    await into(attachedDatabase.auditorias).insert(auditoria.aCabeceraFila());
    return true;
  }

  @override
  Future<int> actualizarCabecera(Auditoria auditoria) {
    return (update(attachedDatabase.auditorias)
          ..where((g.TablaAuditorias t) => t.id.equals(auditoria.id)))
        .write(
      auditoria.aCabeceraFila().copyWith(
        actualizadoEn: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  @override
  Future<int> marcarEliminada(String id) {
    return (update(attachedDatabase.auditorias)
          ..where((g.TablaAuditorias t) => t.id.equals(id)))
        .write(
      db.AuditoriasCompanion(
        eliminada: const Value<bool>(true),
        actualizadoEn: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  @override
  Future<int> restaurar(String id) {
    return (update(attachedDatabase.auditorias)
          ..where((g.TablaAuditorias t) => t.id.equals(id)))
        .write(
      db.AuditoriasCompanion(
        eliminada: const Value<bool>(false),
        actualizadoEn: Value<DateTime>(DateTime.now()),
      ),
    );
  }

  @override
  Future<void> registrarHistorial(Auditoria anterior, Auditoria nueva) async {
    final Map<String, ({String? anterior, String? nuevo})> valores =
        <String, ({String? anterior, String? nuevo})>{
      'establecimientoId': (
        anterior: anterior.establecimientoId,
        nuevo: nueva.establecimientoId,
      ),
      'establecimientoNombre': (
        anterior: anterior.establecimientoNombre,
        nuevo: nueva.establecimientoNombre,
      ),
      'observadorDni': (
        anterior: anterior.observadorDni,
        nuevo: nueva.observadorDni,
      ),
      'observadorNombre': (
        anterior: anterior.observadorNombre,
        nuevo: nueva.observadorNombre,
      ),
      'observadoDni': (
        anterior: anterior.observadoDni,
        nuevo: nueva.observadoDni,
      ),
      'observadoNombre': (
        anterior: anterior.observadoNombre,
        nuevo: nueva.observadoNombre,
      ),
      'fecha': (
        anterior: anterior.fecha.toIso8601String(),
        nuevo: nueva.fecha.toIso8601String(),
      ),
      'inicioObservacion': (
        anterior: anterior.inicioObservacion?.toIso8601String(),
        nuevo: nueva.inicioObservacion?.toIso8601String(),
      ),
      'finObservacion': (
        anterior: anterior.finObservacion?.toIso8601String(),
        nuevo: nueva.finObservacion?.toIso8601String(),
      ),
      'numeroCamasServicio': (
        anterior: anterior.numeroCamasServicio?.toString(),
        nuevo: nueva.numeroCamasServicio?.toString(),
      ),
      'consentimientoVerbal': (
        anterior: anterior.consentimientoVerbal?.toString(),
        nuevo: nueva.consentimientoVerbal?.toString(),
      ),
      'observacionGeneral': (
        anterior: anterior.observacionGeneral,
        nuevo: nueva.observacionGeneral,
      ),
      'estado': (
        anterior: anterior.estado.clave,
        nuevo: nueva.estado.clave,
      ),
      'eliminada': (
        anterior: anterior.eliminada.toString(),
        nuevo: nueva.eliminada.toString(),
      ),
      'sincronizadaEn': (
        anterior: anterior.sincronizadaEn?.toIso8601String(),
        nuevo: nueva.sincronizadaEn?.toIso8601String(),
      ),
    };

    for (final MapEntry<String, ({String? anterior, String? nuevo})> entrada
        in valores.entries) {
      if (entrada.value.anterior == entrada.value.nuevo) continue;
      await _insertarCambioHistorial(
        auditoriaId: nueva.id,
        campo: entrada.key,
        anterior: entrada.value.anterior,
        nuevo: entrada.value.nuevo,
      );
    }

    // El detalle también forma parte de la trazabilidad. Se identifican las
    // oportunidades por su número dentro de la auditoría, no por el id SQL,
    // porque el formulario reemplaza las filas del detalle al actualizar.
    final Map<int, OportunidadRegistro> anteriores = <int, OportunidadRegistro>{
      for (final OportunidadRegistro o in anterior.oportunidades) o.numero: o,
    };
    final Map<int, OportunidadRegistro> nuevos = <int, OportunidadRegistro>{
      for (final OportunidadRegistro o in nueva.oportunidades) o.numero: o,
    };
    final Set<int> numeros = <int>{...anteriores.keys, ...nuevos.keys};
    for (final int numero in numeros) {
      final OportunidadRegistro? viejo = anteriores[numero];
      final OportunidadRegistro? nuevo = nuevos[numero];
      if (viejo == null || nuevo == null) {
        await _insertarCambioHistorial(
          auditoriaId: nueva.id,
          campo: 'oportunidad[$numero]',
          anterior: viejo == null ? null : 'presente',
          nuevo: nuevo == null ? null : 'presente',
        );
        continue;
      }
      final Map<String, ({String? anterior, String? nuevo})> detalle =
          <String, ({String? anterior, String? nuevo})>{
        'momento': (anterior: viejo.momento.clave, nuevo: nuevo.momento.clave),
        'accion': (anterior: viejo.accion.clave, nuevo: nuevo.accion.clave),
        'observacion': (anterior: viejo.observacion, nuevo: nuevo.observacion),
        'duracionSegundos': (
          anterior: viejo.duracionSegundos?.toString(),
          nuevo: nuevo.duracionSegundos?.toString(),
        ),
      };
      for (final MapEntry<String, ({String? anterior, String? nuevo})> campo
          in detalle.entries) {
        if (campo.value.anterior == campo.value.nuevo) continue;
        await _insertarCambioHistorial(
          auditoriaId: nueva.id,
          campo: 'oportunidad[$numero].${campo.key}',
          anterior: campo.value.anterior,
          nuevo: campo.value.nuevo,
        );
      }
    }
  }

  Future<void> _insertarCambioHistorial({
    required String auditoriaId,
    required String campo,
    required String? anterior,
    required String? nuevo,
  }) async {
    await into(attachedDatabase.auditoriasHistorial).insert(
      db.AuditoriasHistorialCompanion.insert(
        auditoriaId: auditoriaId,
        campo: campo,
        valorAnterior: Value<String?>(anterior),
        valorNuevo: Value<String?>(nuevo),
      ),
    );
  }

  @override
  Future<T> transaccion<T>(Future<T> Function() operacion) {
    return attachedDatabase.transaction<T>(operacion);
  }

  @override
  Future<int> borrarOportunidadesDe(String auditoriaId) {
    return (delete(attachedDatabase.oportunidades)
          ..where((g.TablaOportunidades t) => t.auditoriaId.equals(auditoriaId)))
        .go();
  }

  @override
  Future<OportunidadRegistro> insertarOportunidad(
    OportunidadRegistro oportunidad,
  ) async {
    final int id = await into(attachedDatabase.oportunidades)
        .insert(oportunidad.aFila());
    return oportunidad.copyWith(id: id);
  }

  @override
  Future<int> borrarOportunidad(int id) {
    return (delete(attachedDatabase.oportunidades)
          ..where((g.TablaOportunidades t) => t.id.equals(id)))
        .go();
  }

  @override
  Future<Map<EstadoAuditoria, int>> conteoPorEstado() async {
    final List<QueryRow> filas = await customSelect(
      'SELECT estado, COUNT(*) AS total FROM auditorias '
      'WHERE eliminada = 0 GROUP BY estado',
      readsFrom: <ResultSetImplementation<Object?, Object?>>{
        attachedDatabase.auditorias,
      },
    ).get();

    final Map<EstadoAuditoria, int> conteo = <EstadoAuditoria, int>{
      for (final EstadoAuditoria estado in EstadoAuditoria.values) estado: 0,
    };
    for (final QueryRow fila in filas) {
      final EstadoAuditoria estado =
          EstadoAuditoria.desdeClave(fila.read<String>('estado'));
      conteo[estado] = fila.read<int>('total');
    }
    return conteo;
  }

  @override
  Future<ResumenAdherencia> resumenAdherencia() async {
    final QueryRow fila = await customSelect(
      "SELECT "
      "COUNT(DISTINCT a.id) AS total_auditorias, "
      "COUNT(o.id) AS total_oportunidades, "
      "COALESCE(SUM(CASE WHEN o.accion_clave = 'omision' "
      "THEN 0 ELSE 1 END), 0) AS total_cumplidas, "
      "MAX(a.fecha) AS ultima "
      "FROM auditorias a "
      "LEFT JOIN oportunidades o ON o.auditoria_id = a.id "
      "WHERE a.eliminada = 0",
      readsFrom: <ResultSetImplementation<Object?, Object?>>{
        attachedDatabase.auditorias,
        attachedDatabase.oportunidades,
      },
    ).getSingle();

    final int totalOportunidades = fila.read<int?>('total_oportunidades') ?? 0;
    if (totalOportunidades == 0) return ResumenAdherencia.vacio();
    final int totalCumplidas = fila.read<int?>('total_cumplidas') ?? 0;
    return ResumenAdherencia(
      totalAuditorias: fila.read<int?>('total_auditorias') ?? 0,
      totalOportunidades: totalOportunidades,
      totalCumplidas: totalCumplidas,
      promedioAdherencia: totalCumplidas / totalOportunidades * 100,
      ultimaAuditoria: fila.read<DateTime?>('ultima'),
    );
  }

  @override
  Future<Map<String, ({int total, int cumplidas})>> resumenPorMomento() async {
    final List<QueryRow> filas = await customSelect(
      "SELECT o.momento_clave AS momento, COUNT(o.id) AS total, "
      "COALESCE(SUM(CASE WHEN o.accion_clave = 'omision' THEN 0 ELSE 1 END), 0) "
      "AS cumplidas FROM oportunidades o "
      "INNER JOIN auditorias a ON a.id = o.auditoria_id "
      "WHERE a.eliminada = 0 GROUP BY o.momento_clave",
      readsFrom: <ResultSetImplementation<Object?, Object?>>{
        attachedDatabase.auditorias,
        attachedDatabase.oportunidades,
      },
    ).get();
    return <String, ({int total, int cumplidas})>{
      for (final QueryRow fila in filas)
        fila.read<String>('momento'): (
          total: fila.read<int>('total'),
          cumplidas: fila.read<int>('cumplidas'),
        ),
    };
  }

  @override
  Future<List<Auditoria>> listarPorRango(DateTime desde, DateTime hasta) async {
    final consulta = select(attachedDatabase.auditorias)
      ..where((g.TablaAuditorias t) => t.eliminada.equals(false))
      ..where((g.TablaAuditorias t) => t.fecha.isBiggerOrEqualValue(desde))
      ..where((g.TablaAuditorias t) => t.fecha.isSmallerOrEqualValue(hasta))
      ..orderBy(<OrderClauseGenerator<g.TablaAuditorias>>[
        (g.TablaAuditorias t) =>
            OrderingTerm(expression: t.fecha, mode: OrderingMode.desc),
      ]);
    final List<db.Auditoria> filas = await consulta.get();
    return _conOportunidades(filas);
  }

  @override
  Future<List<String>> explicarPlanListado() async {
    final List<QueryRow> filas = await customSelect(
      "EXPLAIN QUERY PLAN SELECT id FROM auditorias "
      "WHERE eliminada = 0 AND estado = 'borrador' "
      'ORDER BY fecha DESC LIMIT 20 OFFSET 0',
      readsFrom: <ResultSetImplementation<Object?, Object?>>{
        attachedDatabase.auditorias,
      },
    ).get();
    return filas.map((QueryRow f) => f.read<String>('detail')).toList();
  }

  Future<List<db.Auditoria>> _cabeceras({
    bool incluirEliminadas = false,
    bool soloEliminadas = false,
    int? limite,
    int offset = 0,
    EstadoAuditoria? estado,
  }) {
    final SimpleSelectStatement<g.TablaAuditorias, db.Auditoria> consulta =
        select(attachedDatabase.auditorias)
          ..orderBy(<OrderClauseGenerator<g.TablaAuditorias>>[
            (g.TablaAuditorias t) => OrderingTerm(
              expression: t.fecha,
              mode: OrderingMode.desc,
            ),
          ]);
    _aplicarFiltros(
      consulta,
      incluirEliminadas: incluirEliminadas,
      soloEliminadas: soloEliminadas,
      estado: estado,
      limite: limite,
      offset: offset,
    );
    return consulta.get();
  }

  void _aplicarFiltros(
    SimpleSelectStatement<g.TablaAuditorias, db.Auditoria> consulta, {
    required bool incluirEliminadas,
    required bool soloEliminadas,
    required EstadoAuditoria? estado,
    required int? limite,
    required int offset,
  }) {
    if (soloEliminadas) {
      consulta.where((g.TablaAuditorias t) => t.eliminada.equals(true));
    } else if (!incluirEliminadas) {
      consulta.where((g.TablaAuditorias t) => t.eliminada.equals(false));
    }
    if (estado != null) {
      consulta.where((g.TablaAuditorias t) => t.estado.equals(estado.clave));
    }
    if (limite != null) {
      consulta.limit(limite, offset: offset);
    }
  }

  Future<List<db.Oportunidade>> _oportunidadesDe(String auditoriaId) {
    return (select(attachedDatabase.oportunidades)
          ..where((g.TablaOportunidades t) => t.auditoriaId.equals(auditoriaId))
          ..orderBy(<OrderClauseGenerator<g.TablaOportunidades>>[
            (g.TablaOportunidades t) => OrderingTerm(expression: t.numero),
          ]))
        .get();
  }

  Future<List<Auditoria>> _conOportunidades(
    List<db.Auditoria> filas, {
    bool incluirEliminadas = false,
  }) async {
    final List<Auditoria> resultado = <Auditoria>[];
    for (final db.Auditoria fila in filas) {
      final List<db.Oportunidade> oportunidades =
          await _oportunidadesDe(fila.id);
      resultado.add(AuditoriaMapper.desdeFilas(fila, oportunidades));
    }
    return resultado;
  }
}
