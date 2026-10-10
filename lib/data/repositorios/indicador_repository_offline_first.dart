import 'package:flutter/foundation.dart';

import '../../core/fallos.dart';
import '../../domain/entidades/indicador_higiene.dart';
import '../../domain/repositorios/indicador_repository.dart';
import '../local/daos/indicadores_dao.dart';
import '../remoto/higiene_api_service.dart';

class IndicadorRepositoryOfflineFirst implements IndicadorRepository {
  IndicadorRepositoryOfflineFirst({
    required IndicadoresDao dao,
    required HigieneApiService servicio,
    this.vigencia = const Duration(hours: 24),
    Map<String, Duration>? politicaVigencia,
    DateTime Function()? reloj,
  })  : _dao = dao,
        _servicio = servicio,
        _reloj = reloj ?? DateTime.now,
        _vigencias = <String, Duration>{
          ...vigenciasPorDefecto,
          if (politicaVigencia != null) ...politicaVigencia,
          HigieneApiService.codigoIndicador:
              politicaVigencia?[HigieneApiService.codigoIndicador] ?? vigencia,
        };

  static const Map<String, Duration> vigenciasPorDefecto =
      <String, Duration>{
    HigieneApiService.codigoIndicador: Duration(hours: 24),
    'establecimientos': Duration(days: 7),
    'auditorias': Duration(minutes: 5),
  };

  final IndicadoresDao _dao;
  final HigieneApiService _servicio;
  final DateTime Function() _reloj;
  final Map<String, Duration> _vigencias;

  /// Vigencia por defecto conservada para compatibilidad con la guía base.
  final Duration vigencia;

  Map<String, Duration> get politicaVigencia =>
      Map<String, Duration>.unmodifiable(_vigencias);

  Duration vigenciaDe(String codigo) =>
      _vigencias[codigo] ?? const Duration(hours: 24);

  @override
  bool cacheEsVigente(
    DateTime? ultimaSincronizacion, {
    DateTime? ahora,
    String codigo = HigieneApiService.codigoIndicador,
  }) {
    if (ultimaSincronizacion == null) return false;
    final DateTime momento = ahora ?? _reloj();
    final Duration edad = momento.difference(ultimaSincronizacion);
    return !edad.isNegative && edad <= vigenciaDe(codigo);
  }

  @override
  Future<ResultadoIndicadores> obtenerIndicadores({
    bool forzarRefresco = false,
  }) async {
    const String codigo = HigieneApiService.codigoIndicador;
    final DateTime ahora = _reloj();
    final DateTime? ultima = await _dao.ultimaSincronizacion(codigo);
    final bool vigente = cacheEsVigente(ultima, ahora: ahora, codigo: codigo);

    if (!forzarRefresco && vigente) {
      final List<IndicadorHigiene> locales = await _dao.leerTodo();
      if (locales.isNotEmpty) {
        return ResultadoIndicadores(
          indicadores: locales,
          origen: OrigenDatos.cacheLocal,
          actualizadoEn: ultima,
          datosObsoletos: false,
        );
      }
    }

    try {
      final List<IndicadorHigiene> remotas =
          await _servicio.obtenerIndicadoresPeru();
      await _dao.reemplazarTodo(remotas, momento: _reloj(), codigo: codigo);
      return ResultadoIndicadores(
        indicadores: remotas,
        origen: OrigenDatos.red,
        actualizadoEn: _reloj(),
        datosObsoletos: false,
      );
    } on FalloRemoto catch (error) {
      debugPrint('ManosSeguras: falló la descarga de $codigo: $error');
      try {
        await _dao.registrarIntentoFallido(codigo);
      } catch (errorRegistro) {
        debugPrint('ManosSeguras: no se pudo registrar el intento: $errorRegistro');
      }

      final List<IndicadorHigiene> locales = await _dao.leerTodo();
      if (locales.isNotEmpty) {
        return ResultadoIndicadores(
          indicadores: locales,
          origen: OrigenDatos.cacheLocal,
          actualizadoEn: ultima,
          datosObsoletos: !vigente,
        );
      }

      // Nivel 3: el respaldo empaquetado garantiza una primera ejecución
      // operativa incluso cuando nunca hubo red ni una caché local.
      return ResultadoIndicadores(
        indicadores: _servicio.respaldoLocal(),
        origen: OrigenDatos.respaldo,
        datosObsoletos: false,
      );
    }
  }

  @override
  Future<List<IndicadorHigiene>> leerCache() => _dao.leerTodo();

  @override
  Future<void> guardarEnCache(
    List<IndicadorHigiene> indicadores, {
    DateTime? momento,
  }) {
    return _dao.reemplazarTodo(
      indicadores,
      momento: momento ?? _reloj(),
    );
  }

  @override
  Future<DateTime?> ultimaSincronizacion() =>
      _dao.ultimaSincronizacion(HigieneApiService.codigoIndicador);

  @override
  Future<void> limpiarCache() => _dao.limpiar();

  @override
  Future<void> invalidar(String codigo) => _dao.invalidar(codigo);
}
