import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/paciente.dart';
import '../services/imagen_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_tokens.dart';

/// Función que convierte el base64 de una foto en bytes.
///
/// Se puede inyectar en tests para contar cuántas veces se decodifica.
typedef DecodificadorFoto = Uint8List? Function(String);

/// Avatar del paciente: su foto en base64 si existe; si no, su inicial.
class AvatarPaciente extends StatefulWidget {
  final Paciente paciente;
  final double radio;
  final DecodificadorFoto? decodificador;

  const AvatarPaciente({
    super.key,
    required this.paciente,
    this.radio = AppSizes.avatar / 2,
    this.decodificador,
  });

  @override
  State<AvatarPaciente> createState() => _AvatarPacienteState();
}

class _AvatarPacienteState extends State<AvatarPaciente> {
  Uint8List? _bytes;
  bool _errorFoto = false;

  @override
  void initState() {
    super.initState();
    _cargarFoto();
  }

  @override
  void didUpdateWidget(covariant AvatarPaciente oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.paciente.fotoBase64 != widget.paciente.fotoBase64) {
      _cargarFoto();
    }
  }

  void _cargarFoto() {
    final foto = widget.paciente.fotoBase64;
    _bytes = (foto != null && foto.isNotEmpty)
        ? (widget.decodificador ?? ImagenService.decodificar)(foto)
        : null;
    _errorFoto = false;
  }

  String get _inicial {
    final nombre = widget.paciente.nombre.trim();
    if (nombre.isEmpty) return '?';
    return String.fromCharCode(nombre.runes.first).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.of(context).devicePixelRatio;
    final lado = (widget.radio * 2 * dpr).round().clamp(1, 4096).toInt();
    final imagen = (!_errorFoto && _bytes != null)
        ? ResizeImage(
            MemoryImage(_bytes!),
            width: lado,
            height: lado,
            allowUpscaling: false,
          )
        : null;

    return CircleAvatar(
      radius: widget.radio,
      backgroundColor: AppColors.primary,
      foregroundColor: AppColors.onGreen,
      foregroundImage: imagen,
      onForegroundImageError: imagen == null
          ? null
          : (_, _) {
              if (!mounted) return;
              setState(() => _errorFoto = true);
            },
      child: imagen == null
          ? Text(
              _inicial,
              style: AppType.title.copyWith(
                color: AppColors.onGreen,
                fontSize: widget.radio * 0.9,
              ),
            )
          : null,
    );
  }
}
