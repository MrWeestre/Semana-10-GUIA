import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/fallos.dart';
import '../../core/id.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entidades/auditoria.dart';
import '../../domain/repositorios/auditoria_repository.dart';
import '../di.dart';
import '../widgets/estados_vista.dart';
import '../widgets/tarjetas.dart';

/// Listado local paginado y papelera de auditorías.
class PantallaAuditorias extends StatefulWidget {
  const PantallaAuditorias({super.key});

  @override
  State<PantallaAuditorias> createState() => _PantallaAuditoriasState();
}

class _PantallaAuditoriasState extends State<PantallaAuditorias> {
  static const int _tamanoPagina = 20;
  bool _mostrarPapelera = false;
  int _pagina = 0;

  void _refrescar() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final AuditoriaRepository repositorio = getIt<AuditoriaRepository>();
    return Scaffold(
      appBar: AppBar(
        title: Text(_mostrarPapelera ? 'Papelera de auditorías' : 'Auditorías guardadas'),
        actions: <Widget>[
          IconButton(
            tooltip: _mostrarPapelera ? 'Volver a auditorías' : 'Abrir papelera',
            onPressed: () => setState(() {
              _mostrarPapelera = !_mostrarPapelera;
              _pagina = 0;
            }),
            icon: Icon(_mostrarPapelera ? Icons.assignment_outlined : Icons.delete_outline),
          ),
          IconButton(
            tooltip: 'Recargar',
            onPressed: _refrescar,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: StreamBuilder<List<Auditoria>>(
        stream: repositorio.observarAuditorias(
          incluirEliminadas: _mostrarPapelera,
          soloEliminadas: _mostrarPapelera,
          limite: _tamanoPagina + 1,
          offset: _pagina * _tamanoPagina,
        ),
        builder: (BuildContext context, AsyncSnapshot<List<Auditoria>> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const EstadoCarga(mensaje: 'Leyendo la base local…');
          }
          if (snapshot.hasError) {
            return EstadoError(mensaje: '${snapshot.error}', alReintentar: _refrescar);
          }

          final List<Auditoria> recibidas = snapshot.data ?? const <Auditoria>[];
          final bool haySiguiente = recibidas.length > _tamanoPagina;
          final List<Auditoria> auditorias = recibidas.take(_tamanoPagina).toList(growable: false);
          if (auditorias.isEmpty) {
            return EstadoVacio(
              mensaje: _mostrarPapelera
                  ? 'La papelera está vacía.'
                  : 'Todavía no hay auditorías en el dispositivo.\\nCapture una desde "Comenzar auditoría".',
              icono: _mostrarPapelera ? Icons.delete_outline : Icons.folder_off_outlined,
              accionEtiqueta: _mostrarPapelera ? null : 'Capturar auditoría',
              alAccionar: _mostrarPapelera ? null : () => context.go('/oportunidades'),
            );
          }

          final int totalOportunidades = auditorias.fold<int>(0, (int total, Auditoria a) => total + a.totalOportunidades);
          final int totalCumplidas = auditorias.fold<int>(0, (int total, Auditoria a) => total + a.oportunidadesCumplidas);
          final double adherencia = totalOportunidades == 0 ? 0 : totalCumplidas / totalOportunidades * 100;

          return Column(
            children: <Widget>[
              Expanded(
                child: RefreshIndicator(
                  onRefresh: () async => _refrescar(),
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: <Widget>[
                      if (!_mostrarPapelera)
                        TarjetaBase(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Resumen de esta página',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: AppColors.textPrimary),
                              ),
                              const SizedBox(height: 12),
                              Row(children: <Widget>[
                                _Metrica(etiqueta: 'Auditorías', valor: '${auditorias.length}'),
                                _Metrica(etiqueta: 'Oportunidades', valor: '$totalOportunidades'),
                                _Metrica(etiqueta: 'Adherencia', valor: formatearPorcentaje(adherencia)),
                              ]),
                            ],
                          ),
                        ),
                      const SizedBox(height: 8),
                      TituloSeccion(
                        _mostrarPapelera ? 'Auditorías anuladas' : 'Detalle por auditoría',
                        icono: _mostrarPapelera ? Icons.delete_outline : Icons.list_alt,
                      ),
                      ...auditorias.map((Auditoria auditoria) => TarjetaAuditoria(
                        auditoria: auditoria,
                        alTocar: _mostrarPapelera ? null : () => context.push('/auditorias/${auditoria.id}'),
                        alEditar: _mostrarPapelera ? null : () => context.push('/auditorias/${auditoria.id}/editar'),
                        alDuplicar: _mostrarPapelera ? null : () => _duplicar(context, auditoria),
                        alAnular: _mostrarPapelera ? null : () => _confirmarAnulacion(context, auditoria),
                        alRestaurar: _mostrarPapelera ? () => _restaurar(context, auditoria) : null,
                      )),
                    ],
                  ),
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: <Widget>[
                      Text('Página ${_pagina + 1} · ${auditorias.length} registros'),
                      Row(children: <Widget>[
                        IconButton(
                          tooltip: 'Página anterior',
                          onPressed: _pagina == 0 ? null : () => setState(() => _pagina--),
                          icon: const Icon(Icons.chevron_left),
                        ),
                        IconButton(
                          tooltip: 'Página siguiente',
                          onPressed: !haySiguiente ? null : () => setState(() => _pagina++),
                          icon: const Icon(Icons.chevron_right),
                        ),
                      ]),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: _mostrarPapelera
          ? null
          : FloatingActionButton.extended(
              onPressed: () => context.go('/oportunidades'),
              icon: const Icon(Icons.add),
              label: const Text('Nueva auditoría'),
            ),
    );
  }

  Future<void> _confirmarAnulacion(BuildContext context, Auditoria auditoria) async {
    final bool? confirmado = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) => AlertDialog(
        title: const Text('Anular auditoría'),
        content: Text('La auditoría del ${formatearFecha(auditoria.fecha)} pasará a la papelera. El registro se conserva para mantener la trazabilidad.'),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.of(dialogContext).pop(true), child: const Text('Anular')),
        ],
      ),
    );
    if (confirmado != true) return;
    try {
      await getIt<AuditoriaRepository>().eliminarLogicamente(auditoria.id);
      if (!context.mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auditoría enviada a la papelera.')));
    } on Fallo catch (fallo) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fallo.mensaje), backgroundColor: AppColors.alerta));
    }
  }

  Future<void> _restaurar(BuildContext context, Auditoria auditoria) async {
    try {
      await getIt<AuditoriaRepository>().restaurar(auditoria.id);
      if (!context.mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auditoría restaurada.')));
    } on Fallo catch (fallo) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fallo.mensaje), backgroundColor: AppColors.alerta));
    }
  }

  Future<void> _duplicar(BuildContext context, Auditoria auditoria) async {
    try {
      final String id = await getIt<AuditoriaRepository>().duplicar(auditoria.id);
      if (!context.mounted) return;
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Auditoría duplicada como borrador.')));
      context.push('/auditorias/$id');
    } on Fallo catch (fallo) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fallo.mensaje), backgroundColor: AppColors.alerta));
    }
  }
}

class _Metrica extends StatelessWidget {
  const _Metrica({required this.etiqueta, required this.valor});
  final String etiqueta;
  final String valor;

  @override
  Widget build(BuildContext context) => Expanded(
    child: Column(children: <Widget>[
      Text(valor, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: AppColors.navy)),
      const SizedBox(height: 2),
      Text(etiqueta, textAlign: TextAlign.center, style: const TextStyle(fontSize: 11, color: AppColors.textSecondary)),
    ]),
  );
}
