import 'package:flutter/material.dart';

import '../../services/notificaciones_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/comprobar_celular.dart';
import '../../utils/pasos_permisos_paciente.dart';
import 'comprobar_celular_screen.dart';

typedef SolicitarPermisoPaso = Future<bool?> Function(PasoPermisoPaciente paso);
typedef ComprobarPermisoPaso = Future<bool?> Function(PasoPermisoPaciente paso);
typedef AbrirAjustesApp = Future<void> Function();

class AsistentePermisosPacienteScreen extends StatefulWidget {
  final int? sdkInt;
  final String? fabricante;
  final SolicitarPermisoPaso? solicitar;
  final ComprobarPermisoPaso? comprobar;
  final AbrirAjustesApp? abrirAjustes;

  const AsistentePermisosPacienteScreen({
    super.key,
    this.sdkInt,
    this.fabricante,
    this.solicitar,
    this.comprobar,
    this.abrirAjustes,
  });

  @override
  State<AsistentePermisosPacienteScreen> createState() =>
      _AsistentePermisosPacienteScreenState();
}

class _AsistentePermisosPacienteScreenState
    extends State<AsistentePermisosPacienteScreen>
    with WidgetsBindingObserver {
  late final List<PasoPermisoPaciente> _pasos = pasosAplicables(widget.sdkInt);
  int _indice = 0;
  final Map<PasoPermisoPaciente, bool?> _concedidos = {};
  bool _ocupado = false;
  bool _mostrarResumen = false;

  SolicitarPermisoPaso get _solicitar =>
      widget.solicitar ??
      ((PasoPermisoPaciente paso) async {
        await _solicitarReal(paso);
        return null;
      });
  ComprobarPermisoPaso get _comprobar => widget.comprobar ?? _comprobarReal;
  AbrirAjustesApp get _abrirAjustes => widget.abrirAjustes ?? _abrirAjustesReal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _comprobarPasoActual();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _comprobarPasoActual();
  }

  Future<void> _solicitarReal(PasoPermisoPaciente paso) async {
    final n = NotificacionesService();
    switch (paso) {
      case PasoPermisoPaciente.notificaciones:
        await n.pedirPermiso();
        return;
      case PasoPermisoPaciente.alarmasExactas:
        await n.solicitarPermisoAlarmasExactas();
        return;
      case PasoPermisoPaciente.pantallaCompleta:
        await n.solicitarPermisoPantallaCompleta();
        return;
      case PasoPermisoPaciente.canalAlarmas:
        await n.abrirAjustesCanalAlarmas();
        return;
      case PasoPermisoPaciente.bateria:
        await n.abrirAjustesBateria();
        return;
      case PasoPermisoPaciente.inicioAutomatico:
        await n.abrirDetallesApp();
        return;
    }
  }

  Future<bool?> _comprobarReal(PasoPermisoPaciente paso) async {
    final n = NotificacionesService();
    switch (paso) {
      case PasoPermisoPaciente.notificaciones:
        return n.notificacionesHabilitadas();
      case PasoPermisoPaciente.alarmasExactas:
        if ((widget.sdkInt ?? 0) < 31) return true;
        return n.puedeProgramarAlarmasExactas();
      case PasoPermisoPaciente.pantallaCompleta:
        if ((widget.sdkInt ?? 0) < 34) return true;
        return n.puedeUsarPantallaCompleta();
      case PasoPermisoPaciente.canalAlarmas:
        final canal = await n.canalDeAlarmas();
        return !canalAlarmasEnProblema(
          canal,
          notificacionesHabilitadas: true,
        );
      case PasoPermisoPaciente.bateria:
        final energia = await n.estadoEnergia();
        return energia?['ignoringBatteryOptimizations'] as bool?;
      case PasoPermisoPaciente.inicioAutomatico:
        return true;
    }
  }

  Future<void> _abrirAjustesReal() async {
    await NotificacionesService().abrirDetallesApp();
  }

  Future<void> _comprobarPasoActual() async {
    if (_mostrarResumen || _pasos.isEmpty || _indice >= _pasos.length) return;
    final paso = _pasos[_indice];
    final valor = await _comprobar(paso);
    if (!mounted) return;
    setState(() => _concedidos[paso] = valor);
  }

  Future<void> _permitir() async {
    if (_ocupado || _pasos.isEmpty || _indice >= _pasos.length) return;
    setState(() => _ocupado = true);
    final paso = _pasos[_indice];
    try {
      await _solicitar(paso);
      await _comprobarPasoActual();
      final concedido = _concedidos[paso] == true;
      if (concedido && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 250));
        if (mounted) _siguiente();
      }
    } finally {
      if (mounted) setState(() => _ocupado = false);
    }
  }

  void _ahoraNo() => _siguiente();

  void _siguiente() {
    if (_indice + 1 >= _pasos.length) {
      setState(() => _mostrarResumen = true);
    } else {
      setState(() => _indice++);
      _comprobarPasoActual();
    }
  }

  Future<void> _abrirAjustesYComprobar() async {
    await _abrirAjustes();
    await _comprobarPasoActual();
  }

  @override
  Widget build(BuildContext context) {
    if (_pasos.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Permisos')),
        body: const Center(child: Text('Tu Android no necesita pasos extra.')),
      );
    }

    if (_mostrarResumen) return _buildResumen();

    final paso = _pasos[_indice];
    final concedido = _concedidos[paso];

    return Scaffold(
      appBar: AppBar(
        title: Text('Paso ${_indice + 1} de ${_pasos.length}'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                paso.titulo,
                style: AppType.title.copyWith(color: AppColors.onGreen),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(paso.explicacion),
              const SizedBox(height: AppSpacing.sm),
              if (concedido == true)
                const Text('Listo: ya esta concedido.')
              else if (concedido == false)
                const Text(
                  'Android ya no muestra el dialogo. Abre los ajustes de la app '
                  'para concederlo manualmente.',
                ),
              const SizedBox(height: AppSpacing.sm),
              ElevatedButton(
                onPressed: _ocupado ? null : _permitir,
                child: Text(_ocupado ? 'Abriendo...' : 'Permitir'),
              ),
              if (concedido == false) ...[
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: _ocupado ? null : _abrirAjustesYComprobar,
                  child: const Text('Abrir ajustes'),
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: _ocupado ? null : _ahoraNo,
                child: const Text('Ahora no'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildResumen() {
    final estados = _pasos
        .map((p) => estadoDePaso(p, widget.sdkInt, _concedidos[p]))
        .toList();
    final resumen = resumenPasos(estados);

    return Scaffold(
      appBar: AppBar(title: const Text('Resumen')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                resumen.todoListo
                    ? 'Todo listo.'
                    : 'Quedan ${resumen.pendientes} pasos pendientes.',
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final paso in _pasos)
                ListTile(
                  leading: Icon(
                    _concedidos[paso] == true
                        ? Icons.check_circle
                        : Icons.cancel,
                    color: _concedidos[paso] == true
                        ? AppColors.accent
                        : AppColors.warning,
                  ),
                  title: Text(paso.titulo),
                  subtitle: Text(paso.explicacion),
                ),
              const SizedBox(height: AppSpacing.sm),
              ElevatedButton(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ComprobarCelularScreen(),
                    ),
                  );
                },
                child: const Text('Comprobar mi celular'),
              ),
              const SizedBox(height: AppSpacing.xs),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Listo'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
