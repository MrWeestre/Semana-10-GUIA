import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/fallos.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/entidades/auditoria.dart';
import '../../domain/entidades/catalogos.dart';
import '../../domain/entidades/oportunidad_registro.dart';
import '../../domain/repositorios/auditoria_repository.dart';
import '../di.dart';
import '../widgets/estados_vista.dart';

/// Formulario de edición. Carga la auditoría existente y actualiza la cabecera
/// y sus oportunidades a través del contrato del repositorio.
class PantallaEditarAuditoria extends StatefulWidget {
  const PantallaEditarAuditoria({super.key, required this.auditoriaId});

  final String auditoriaId;

  @override
  State<PantallaEditarAuditoria> createState() => _PantallaEditarAuditoriaState();
}

class _PantallaEditarAuditoriaState extends State<PantallaEditarAuditoria> {
  late Future<Auditoria> _futuro;
  final TextEditingController _observacionGeneral = TextEditingController();
  final List<_OportunidadEditable> _oportunidades = <_OportunidadEditable>[];
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _futuro = _cargar();
  }

  void _recargar() {
    setState(() {
      _futuro = _cargar();
    });
  }

  Future<Auditoria> _cargar() async {
    final Auditoria auditoria =
        await getIt<AuditoriaRepository>().obtenerPorId(widget.auditoriaId);
    _observacionGeneral.text = auditoria.observacionGeneral ?? '';
    _oportunidades.addAll(auditoria.oportunidades.map(_OportunidadEditable.new));
    return auditoria;
  }

  @override
  void dispose() {
    _observacionGeneral.dispose();
    for (final _OportunidadEditable oportunidad in _oportunidades) {
      oportunidad.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Editar auditoría')),
      body: FutureBuilder<Auditoria>(
        future: _futuro,
        builder: (BuildContext context, AsyncSnapshot<Auditoria> snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const EstadoCarga(mensaje: 'Cargando datos de la auditoría…');
          }
          if (snapshot.hasError || !snapshot.hasData) {
            return EstadoError(
              mensaje: '${snapshot.error ?? 'No se encontró la auditoría.'}',
              alReintentar: _recargar,
            );
          }
          final Auditoria original = snapshot.data!;
          return SafeArea(
            child: Form(
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: <Widget>[
                  Text(original.establecimientoNombre,
                      style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 4),
                  Text('Observado: ${original.observadoNombre} · ${original.fecha.day}/${original.fecha.month}/${original.fecha.year}'),
                  const SizedBox(height: 20),
                  TextFormField(
                    controller: _observacionGeneral,
                    minLines: 2,
                    maxLines: 5,
                    decoration: const InputDecoration(
                      labelText: 'Observación general',
                      hintText: 'Nota opcional sobre la auditoría',
                      border: OutlineInputBorder(),
                      alignLabelWithHint: true,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text('Oportunidades observadas', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
                  const SizedBox(height: 8),
                  if (_oportunidades.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Text('Esta auditoría todavía no contiene oportunidades.'),
                    ),
                  ..._oportunidades.map((item) => _tarjetaOportunidad(item)),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: _guardando ? null : () => _guardar(original),
                    icon: _guardando
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.save_outlined),
                    label: Text(_guardando ? 'Guardando…' : 'Guardar cambios'),
                  ),
                  const SizedBox(height: 20),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _tarjetaOportunidad(_OportunidadEditable item) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('Oportunidad ${item.original.numero}', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            DropdownButtonFormField<Momento>(
              value: item.momento,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Momento'),
              items: Momento.values.map((Momento m) => DropdownMenuItem<Momento>(value: m, child: Text(m.etiqueta, overflow: TextOverflow.ellipsis))).toList(),
              onChanged: (Momento? value) => setState(() { if (value != null) item.momento = value; }),
            ),
            DropdownButtonFormField<Accion>(
              value: item.accion,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Acción observada'),
              items: Accion.values.map((Accion a) => DropdownMenuItem<Accion>(value: a, child: Text(a.etiqueta))).toList(),
              onChanged: (Accion? value) => setState(() { if (value != null) item.accion = value; }),
            ),
            TextFormField(
              controller: item.observacion,
              decoration: const InputDecoration(labelText: 'Observación de la oportunidad'),
            ),
            TextFormField(
              controller: item.duracion,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: 'Duración en segundos (opcional)'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _guardar(Auditoria original) async {
    final List<OportunidadRegistro> oportunidades = <OportunidadRegistro>[];
    for (final _OportunidadEditable item in _oportunidades) {
      final String textoDuracion = item.duracion.text.trim();
      final int? duracion = textoDuracion.isEmpty ? null : int.tryParse(textoDuracion);
      if (textoDuracion.isNotEmpty && (duracion == null || duracion < 0)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('La duración debe ser un entero igual o mayor que cero.'), backgroundColor: AppColors.alerta),
        );
        return;
      }
      final String textoObservacion = item.observacion.text.trim();
      oportunidades.add(OportunidadRegistro(
        id: item.original.id,
        auditoriaId: original.id,
        numero: item.original.numero,
        momento: item.momento,
        accion: item.accion,
        observacion: textoObservacion.isEmpty ? null : textoObservacion,
        duracionSegundos: duracion,
      ));
    }

    final Auditoria actualizada = Auditoria(
      id: original.id,
      establecimientoId: original.establecimientoId,
      establecimientoNombre: original.establecimientoNombre,
      observadorDni: original.observadorDni,
      observadorNombre: original.observadorNombre,
      observadoDni: original.observadoDni,
      observadoNombre: original.observadoNombre,
      fecha: original.fecha,
      inicioObservacion: original.inicioObservacion,
      finObservacion: original.finObservacion,
      numeroCamasServicio: original.numeroCamasServicio,
      consentimientoVerbal: original.consentimientoVerbal,
      observacionGeneral: _observacionGeneral.text.trim().isEmpty ? null : _observacionGeneral.text.trim(),
      estado: original.estado,
      eliminada: original.eliminada,
      sincronizadaEn: original.sincronizadaEn,
      oportunidades: oportunidades,
    );

    setState(() => _guardando = true);
    try {
      await getIt<AuditoriaRepository>().actualizar(actualizada);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cambios guardados.')));
      context.pop();
    } on Fallo catch (fallo) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(fallo.mensaje), backgroundColor: AppColors.alerta));
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }
}

class _OportunidadEditable {
  _OportunidadEditable(this.original)
      : momento = original.momento,
        accion = original.accion,
        observacion = TextEditingController(text: original.observacion ?? ''),
        duracion = TextEditingController(text: original.duracionSegundos?.toString() ?? '');

  final OportunidadRegistro original;
  Momento momento;
  Accion accion;
  final TextEditingController observacion;
  final TextEditingController duracion;

  void dispose() {
    observacion.dispose();
    duracion.dispose();
  }
}
