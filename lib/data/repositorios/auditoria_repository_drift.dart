import '../../core/fallos.dart';
import '../../core/id.dart';
import '../../domain/entidades/auditoria.dart';
import '../../domain/entidades/oportunidad_registro.dart';
import '../../domain/repositorios/auditoria_repository.dart';
import '../local/daos/auditorias_dao.dart';

/// **Implementación del repositorio de auditorías sobre drift/SQLite.**
///
/// Semana 9 (DIP: implementa la abstracción del dominio) + Semana 10
/// (persistencia local y transacciones).
///
/// Responsabilidades de esta clase (y solo estas):
///
///  * traducir los fallos de SQLite a [FalloLocal]/[FalloNoEncontrado];
///  * agrupar la escritura de la cabecera y su detalle en **una sola
///    transacción**, que es lo que garantiza que no queden auditorías a
///    medias si la aplicación se cierra;
///  * generar el identificador UUID en el dispositivo cuando la auditoría
///    todavía no lo tiene.
///
/// Nada de esto vive en la pantalla ni en el DAO: esa separación es la que
/// permite sustituir drift por Firestore en la Unidad III sin tocar la UI.
class AuditoriaRepositoryDrift implements AuditoriaRepository {
  AuditoriaRepositoryDrift(this._dao, {this.generadorId = generarUuidV4});

  final AuditoriasDao _dao;

  /// Se inyecta para poder producir identificadores predecibles en las
  /// pruebas (`() => 'id-fijo-1'`).
  final String Function() generadorId;

  @override
  Stream<List<Auditoria>> observarAuditorias({
    bool incluirEliminadas = false,
    bool soloEliminadas = false,
    int? limite,
    int offset = 0,
    EstadoAuditoria? estado,
  }) {
    return _dao
        .observar(
          incluirEliminadas: incluirEliminadas,
          soloEliminadas: soloEliminadas,
          limite: limite,
          offset: offset,
          estado: estado,
        )
        .handleError((Object error) {
      throw FalloLocal(
        'No se pudieron leer las auditorías guardadas.',
        causa: error,
      );
    });
  }

  @override
  Future<List<Auditoria>> listarAuditorias({
    bool incluirEliminadas = false,
    bool soloEliminadas = false,
    int? limite,
    int offset = 0,
    EstadoAuditoria? estado,
  }) async {
    try {
      return await _dao.listar(
        incluirEliminadas: incluirEliminadas,
        soloEliminadas: soloEliminadas,
        limite: limite,
        offset: offset,
        estado: estado,
      );
    } catch (error) {
      throw FalloLocal(
        'No se pudieron leer las auditorías guardadas.',
        causa: error,
      );
    }
  }

  @override
  Future<Auditoria> obtenerPorId(String id) async {
    try {
      final Auditoria? auditoria = await _dao.buscarPorId(id);
      if (auditoria == null) {
        throw FalloNoEncontrado('No existe la auditoría $id.');
      }
      return auditoria;
    } on Fallo {
      rethrow;
    } catch (error) {
      throw FalloLocal('No se pudo leer la auditoría $id.', causa: error);
    }
  }

  /// **Reto 1 — escritura cabecera + detalle.**
  ///
  /// TODO(reto-1a): implemente este método.
  ///
  /// Contrato:
  ///  1. si `auditoria.id` viene vacío, asígnele [generadorId]();
  ///  2. inserte la cabecera con `_dao.insertarCabecera(...)`;
  ///  3. inserte cada oportunidad con `_dao.insertarOportunidad(...)`,
  ///     rellenando `auditoriaId` con el identificador definitivo;
  ///  4. devuelva el identificador.
  ///
  /// Esqueleto de partida:
  /// ```dart
  /// final String id = auditoria.id.isEmpty ? generadorId() : auditoria.id;
  /// final Auditoria conId = auditoria.copyWith(id: id);
  /// final bool insertada = await _dao.insertarCabecera(conId);
  /// if (!insertada) {
  ///   throw const FalloDeValidacion('Ya existe una auditoría con ese id.');
  /// }
  /// for (final o in conId.oportunidades) {
  ///   await _dao.insertarOportunidad(o.copyWith(auditoriaId: id));
  /// }
  /// return id;
  /// ```
  ///
  /// **Atomicidad (Reto 5).** Este método escribe en dos tablas. Si el
  /// proceso se interrumpe entre la cabecera y el detalle, queda una
  /// auditoría a medias. La solución profesional consiste en envolver las
  /// escrituras en `db.transaction(...)`; en la sección 9.6 de la guía se
  /// explica cómo hacerlo y se propone como parte del Reto 5.
  @override
  Future<String> guardar(Auditoria auditoria) async {
    try {
      final String id = auditoria.id.isEmpty ? generadorId() : auditoria.id;
      final Auditoria conId = auditoria.copyWith(id: id);
      await _dao.transaccion(() async {
        final bool insertada = await _dao.insertarCabecera(conId);
        if (!insertada) {
          throw FalloDeValidacion(
            'Ya existe una auditoría con el identificador $id. '
            'Genere uno nuevo o use actualizar().',
          );
        }
        for (int i = 0; i < conId.oportunidades.length; i++) {
          final OportunidadRegistro oportunidad = conId.oportunidades[i];
          await _dao.insertarOportunidad(
            oportunidad.copyWith(
              auditoriaId: id,
              numero: oportunidad.numero == 0 ? i + 1 : oportunidad.numero,
            ),
          );
        }
      });
      return id;
    } on Fallo {
      rethrow;
    } catch (error) {
      throw FalloLocal(
        'No se pudo guardar la auditoría en el dispositivo.',
        causa: error,
      );
    }
  }

  @override
  Future<void> actualizar(Auditoria auditoria) async {
    try {
      await _dao.transaccion(() async {
        final Auditoria? anterior = await _dao.buscarPorId(auditoria.id);
        if (anterior == null) {
          throw FalloNoEncontrado(
            'No existe la auditoría ${auditoria.id} que intenta actualizar.',
          );
        }
        final int filas = await _dao.actualizarCabecera(auditoria);
        if (filas == 0) {
          throw FalloNoEncontrado(
            'No existe la auditoría ${auditoria.id} que intenta actualizar.',
          );
        }
        await _dao.registrarHistorial(anterior, auditoria);
        await _dao.borrarOportunidadesDe(auditoria.id);
        for (int i = 0; i < auditoria.oportunidades.length; i++) {
          final OportunidadRegistro oportunidad = auditoria.oportunidades[i];
          await _dao.insertarOportunidad(
            oportunidad.copyWith(
              auditoriaId: auditoria.id,
              numero: oportunidad.numero == 0 ? i + 1 : oportunidad.numero,
            ),
          );
        }
      });
    } on Fallo {
      rethrow;
    } catch (error) {
      throw FalloLocal('No se pudo actualizar la auditoría.', causa: error);
    }
  }

  @override
  Future<void> eliminarLogicamente(String id) async {
    try {
      await _dao.transaccion(() async {
        final Auditoria? anterior = await _dao.buscarPorId(id);
        if (anterior == null) throw FalloNoEncontrado('No existe la auditoría $id.');
        final Auditoria anulada = _cambiarEstadoEliminacion(anterior, true);
        final int filas = await _dao.marcarEliminada(id);
        if (filas == 0) throw FalloNoEncontrado('No existe la auditoría $id.');
        await _dao.registrarHistorial(anterior, anulada);
      });
    } on Fallo {
      rethrow;
    } catch (error) {
      throw FalloLocal('No se pudo anular la auditoría $id.', causa: error);
    }
  }

  @override
  Future<void> restaurar(String id) async {
    try {
      await _dao.transaccion(() async {
        final Auditoria? anterior = await _dao.buscarPorId(id);
        if (anterior == null) throw FalloNoEncontrado('No existe la auditoría $id.');
        if (!anterior.eliminada) return;
        final Auditoria restaurada = _cambiarEstadoEliminacion(anterior, false);
        final int filas = await _dao.restaurar(id);
        if (filas == 0) throw FalloNoEncontrado('No existe la auditoría $id.');
        await _dao.registrarHistorial(anterior, restaurada);
      });
    } on Fallo {
      rethrow;
    } catch (error) {
      throw FalloLocal('No se pudo restaurar la auditoría $id.', causa: error);
    }
  }

  @override
  Future<String> duplicar(String id) async {
    final Auditoria original = await obtenerPorId(id);
    final List<OportunidadRegistro> oportunidades = original.oportunidades
        .map((OportunidadRegistro o) => OportunidadRegistro(
              auditoriaId: '',
              numero: o.numero,
              momento: o.momento,
              accion: o.accion,
              observacion: o.observacion,
              duracionSegundos: o.duracionSegundos,
            ))
        .toList(growable: false);
    final Auditoria copia = Auditoria(
      id: '',
      establecimientoId: original.establecimientoId,
      establecimientoNombre: original.establecimientoNombre,
      observadorDni: original.observadorDni,
      observadorNombre: original.observadorNombre,
      observadoDni: original.observadoDni,
      observadoNombre: original.observadoNombre,
      fecha: DateTime.now(),
      inicioObservacion: null,
      finObservacion: null,
      numeroCamasServicio: original.numeroCamasServicio,
      consentimientoVerbal: original.consentimientoVerbal,
      observacionGeneral: original.observacionGeneral,
      estado: EstadoAuditoria.borrador,
      eliminada: false,
      sincronizadaEn: null,
      oportunidades: oportunidades,
    );
    return guardar(copia);
  }

  Auditoria _cambiarEstadoEliminacion(Auditoria anterior, bool eliminada) {
    return Auditoria(
      id: anterior.id,
      establecimientoId: anterior.establecimientoId,
      establecimientoNombre: anterior.establecimientoNombre,
      observadorDni: anterior.observadorDni,
      observadorNombre: anterior.observadorNombre,
      observadoDni: anterior.observadoDni,
      observadoNombre: anterior.observadoNombre,
      fecha: anterior.fecha,
      inicioObservacion: anterior.inicioObservacion,
      finObservacion: anterior.finObservacion,
      numeroCamasServicio: anterior.numeroCamasServicio,
      consentimientoVerbal: anterior.consentimientoVerbal,
      observacionGeneral: anterior.observacionGeneral,
      estado: anterior.estado,
      eliminada: eliminada,
      sincronizadaEn: anterior.sincronizadaEn,
      oportunidades: anterior.oportunidades,
    );
  }

  @override
  Future<OportunidadRegistro> agregarOportunidad(
    OportunidadRegistro oportunidad,
  ) async {
    try {
      final Auditoria auditoria = await obtenerPorId(oportunidad.auditoriaId);
      final int siguiente = auditoria.totalOportunidades + 1;
      return await _dao.insertarOportunidad(
        oportunidad.copyWith(numero: oportunidad.numero == 0
            ? siguiente
            : oportunidad.numero),
      );
    } on Fallo {
      rethrow;
    } catch (error) {
      throw FalloLocal(
        'No se pudo registrar la oportunidad.',
        causa: error,
      );
    }
  }

  @override
  Future<void> eliminarOportunidad(int id) async {
    try {
      await _dao.borrarOportunidad(id);
    } catch (error) {
      throw FalloLocal('No se pudo eliminar la oportunidad.', causa: error);
    }
  }

  @override
  Future<ResumenAdherencia> resumenAdherencia() async {
    try {
      return await _dao.resumenAdherencia();
    } catch (error) {
      throw FalloLocal(
        'No se pudieron calcular los indicadores locales.',
        causa: error,
      );
    }
  }

  @override
  Future<Map<EstadoAuditoria, int>> conteoPorEstado() async {
    try {
      return await _dao.conteoPorEstado();
    } catch (error) {
      throw FalloLocal(
        'No se pudo calcular el estado de sincronización.',
        causa: error,
      );
    }
  }

  @override
  Future<List<Auditoria>> listarPorRango(DateTime desde, DateTime hasta) async {
    try {
      return await _dao.listarPorRango(desde, hasta);
    } catch (error) {
      throw FalloLocal('No se pudieron consultar las auditorías por rango.', causa: error);
    }
  }
}
