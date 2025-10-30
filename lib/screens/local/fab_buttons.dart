import 'package:flutter/material.dart';

class LocalFABButtons extends StatelessWidget {
  final bool buttonsVisible;
  final void Function(String action) onPressed;

  const LocalFABButtons({
    super.key, // ✅ super parameter usado aquí
    required this.buttonsVisible,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    if (!buttonsVisible) return const SizedBox.shrink();

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        FloatingActionButton.extended(
          heroTag: 'generar',
          label: const Text('Generar pedido'),
          icon: const Icon(Icons.add_location_alt),
          onPressed: () => onPressed("generar"),
        ),
        FloatingActionButton.extended(
          heroTag: 'personalizar',
          label: const Text('Personalizar'),
          icon: const Icon(Icons.group_add),
          onPressed: () => onPressed("personalizar"),
        ),
        FloatingActionButton.extended(
          heroTag: 'cadetes',
          label: const Text('Ver cadetes'),
          icon: const Icon(Icons.people),
          onPressed: () => onPressed("verCadetes"),
        ),
        FloatingActionButton.extended(
          heroTag: 'historial',
          label: const Text('Historial'),
          icon: const Icon(Icons.history),
          onPressed: () => onPressed("historial"),
        ),
        FloatingActionButton.extended(
          heroTag: 'logout',
          label: const Text('Salir'),
          icon: const Icon(Icons.logout),
          backgroundColor: Colors.red,
          onPressed: () => onPressed("logout"),
        ),
      ],
    );
  }
}
