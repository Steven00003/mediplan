import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../models/medico.dart';
import '../../services/firestore_service.dart';
import '../../services/imagen_service.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_tokens.dart';
import '../../utils/errores_amigables.dart';
import '../../utils/validacion_perfil_medico.dart';
import '../../widgets/dialogo_accion_delicada.dart';
import '../../widgets/estados.dart';
import '../../widgets/snackbars.dart';

/// Perfil del doctor que ven sus pacientes vinculados.
class MiPerfilMedicoScreen extends StatefulWidget {
  const MiPerfilMedicoScreen({super.key});

  @override
  State<MiPerfilMedicoScreen> createState() => _MiPerfilMedicoScreenState();
}

class _MiPerfilMedicoScreenState extends State<MiPerfilMedicoScreen> {
  final _fs = FirestoreService();
  final _imagen = ImagenService();
  final _picker = ImagePicker();
  final _nombre = TextEditingController();
  final _titulo = TextEditingController();
  final _especialidad = TextEditingController();

  String? _uid;
  String? _fotoBase64;
  bool _cargando = true;
  bool _guardando = false;
  Map<String, String> _errores = {};

  @override
  void initState() {
    super.initState();
    _cargar();
  }

  @override
  void dispose() {
    _nombre.dispose();
    _titulo.dispose();
    _especialidad.dispose();
    super.dispose();
  }

  Future<void> _cargar() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      setState(() => _cargando = false);
      return;
    }
    try {
      final medico = await _fs.getMedico(uid);
      if (!mounted) return;
      _uid = uid;
      _nombre.text = medico?.nombre ?? '';
      _titulo.text = medico?.titulo ?? '';
      _especialidad.text = medico?.especialidad ?? '';
      _fotoBase64 = medico?.fotoBase64;
      setState(() => _cargando = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _cargando = false;
          _errores = {'general': mensajeErrorAmigable(e)};
        });
      }
    }
  }

  Future<void> _elegirFoto(ImageSource origen) async {
    final foto = await _picker.pickImage(source: origen, imageQuality: 85);
    if (foto == null) return;
    final bytes = await foto.readAsBytes();
    final base64 = await _imagen.fotoPerfilABase64(bytes);
    if (base64 == null || !mounted) return;
    setState(() {
      _fotoBase64 = base64;
      _errores.remove('fotoBase64');
    });
  }

  Future<void> _guardar() async {
    if (_guardando || _uid == null) return;
    final errores = validarPerfilMedico(
      nombre: _nombre.text,
      titulo: _titulo.text,
      especialidad: _especialidad.text,
      fotoBase64: _fotoBase64,
    );
    setState(() => _errores = errores);
    if (errores.isNotEmpty) return;

    setState(() => _guardando = true);
    try {
      await _fs.guardarPerfilMedico(
        Medico(
          uid: _uid!,
          nombre: _nombre.text.trim(),
          titulo: _titulo.text.trim(),
          especialidad: _especialidad.text.trim(),
          fotoBase64: _fotoBase64,
        ),
      );
      if (mounted) mostrarSnackExito(context, 'Perfil guardado.');
    } catch (e) {
      if (mounted) {
        mostrarSnackError(
          context,
          mensajeErrorAmigable(e, contexto: 'Error guardando el perfil'),
        );
      }
    } finally {
      if (mounted) setState(() => _guardando = false);
    }
  }

  Future<bool> _descartar() async {
    return mostrarDialogoAccionDelicada(
      context,
      titulo: 'Descartar cambios',
      mensaje: 'Se perderán los cambios que no hayas guardado.',
      textoAccion: 'Descartar',
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final salir = await _descartar();
        if (salir && mounted && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('Mi perfil')),
        body: _cargando
            ? const EstadoCargando(texto: 'Cargando perfil...')
            : ListView(
                padding: const EdgeInsets.all(AppSpacing.sm),
                children: [
                  const Text(
                    'Este perfil lo ven tus pacientes vinculados.',
                    style: TextStyle(color: AppColors.textSecondary),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Icon(
                        Icons.person,
                        size: 64,
                        color: AppColors.primaryStrong,
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Wrap(
                          spacing: AppSpacing.xs,
                          children: [
                            TextButton.icon(
                              onPressed: () => _elegirFoto(ImageSource.camera),
                              icon: const Icon(Icons.camera_alt),
                              label: const Text('Cámara'),
                            ),
                            TextButton.icon(
                              onPressed: () => _elegirFoto(ImageSource.gallery),
                              icon: const Icon(Icons.photo_library),
                              label: const Text('Galería'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  _campo('Nombre', _nombre, _errores['nombre']),
                  _campo('Estudios / título', _titulo, _errores['titulo']),
                  _campo(
                    'Especialidad',
                    _especialidad,
                    _errores['especialidad'],
                  ),
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    'Así te verá tu paciente',
                    style: AppType.title.copyWith(color: AppColors.onGreen),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Card(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.sm),
                      child: Column(
                        children: [
                          const Icon(
                            Icons.person,
                            size: 56,
                            color: AppColors.primaryStrong,
                          ),
                          const SizedBox(height: AppSpacing.xs),
                          Text(
                            _nombre.text.trim().isEmpty
                                ? 'Tu nombre'
                                : _nombre.text.trim(),
                            style: AppType.title.copyWith(
                              color: AppColors.onGreen,
                            ),
                          ),
                          if (_especialidad.text.trim().isNotEmpty)
                            Text(
                              _especialidad.text.trim(),
                              style: AppType.body.copyWith(
                                color: AppColors.textSecondary,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _guardando ? null : _guardar,
                      child: Text(
                        _guardando ? 'Guardando...' : 'Guardar perfil',
                      ),
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _campo(
    String etiqueta,
    TextEditingController controller,
    String? error,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: TextField(
        controller: controller,
        maxLines: etiqueta == 'Estudios / título' ? 3 : 1,
        decoration: InputDecoration(
          labelText: etiqueta,
          errorText: error,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}
