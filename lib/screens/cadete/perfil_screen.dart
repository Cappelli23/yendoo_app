import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class PerfilScreen extends StatefulWidget {
  const PerfilScreen({super.key});

  @override
  State<PerfilScreen> createState() => _PerfilScreenState();
}

class _PerfilScreenState extends State<PerfilScreen> {
  String? nombre;
  String? telefono;
  String? cadeteId;
  bool mostrarNumero = false;
  bool cargando = true;

  @override
  void initState() {
    super.initState();
    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final doc =
        await FirebaseFirestore.instance.collection('usuarios').doc(uid).get();
    final data = doc.data();

    if (!mounted) return; // 👈 Check antes de setState

    if (data != null) {
      setState(() {
        nombre = data['nombre'];
        telefono = data['telefono'];
        cadeteId = data['cadeteId'];
        mostrarNumero = data['mostrarNumero'] ?? false;
        cargando = false;
      });
    }
  }

  Future<void> _cambiarVisibilidad(bool valor) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    await FirebaseFirestore.instance
        .collection('usuarios')
        .doc(uid)
        .update({'mostrarNumero': valor});

    if (!mounted) return; // 👈 Check antes de usar context

    setState(() {
      mostrarNumero = valor;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(valor
            ? 'Tu número ahora es visible para los locales.'
            : 'Tu número ya no será visible.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil del Cadete')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Nombre: $nombre', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text('Teléfono: $telefono', style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 8),
            Text('ID del cadete: $cadeteId',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('¿Mostrar número al local?',
                    style: TextStyle(fontSize: 16)),
                Switch(
                  value: mostrarNumero,
                  onChanged: _cambiarVisibilidad,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
