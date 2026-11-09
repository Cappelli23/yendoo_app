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
  bool guardandoHorarios = false;

  final List<String> dias = [
    'Lunes',
    'Martes',
    'Miércoles',
    'Jueves',
    'Viernes',
    'Sábado',
    'Domingo',
  ];

  late Map<String, Map<String, dynamic>> horarios;

  @override
  void initState() {
    super.initState();

    horarios = {
      for (final dia in dias)
        dia: {
          'activo': false,
          'desde': '19:00',
          'hasta': '00:00',
        },
    };

    _cargarDatos();
  }

  Future<void> _cargarDatos() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;

    if (uid == null) {
      if (mounted) setState(() => cargando = false);
      return;
    }

    try {
      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      final data = doc.data();

      if (!mounted) return;

      if (data != null) {
        final horariosGuardados = data['horariosTrabajo'];

        setState(() {
          nombre = data['nombre']?.toString();
          telefono = data['telefono']?.toString();
          cadeteId = data['cadeteId']?.toString();
          mostrarNumero = data['mostrarNumero'] == true;

          if (horariosGuardados is Map) {
            for (final dia in dias) {
              final valor = horariosGuardados[dia];

              if (valor is Map) {
                horarios[dia] = {
                  'activo': valor['activo'] == true,
                  'desde': valor['desde']?.toString() ?? '19:00',
                  'hasta': valor['hasta']?.toString() ?? '00:00',
                };
              }
            }
          }

          cargando = false;
        });
      } else {
        setState(() => cargando = false);
      }
    } catch (e) {
      if (!mounted) return;

      setState(() => cargando = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error cargando perfil: $e')),
      );
    }
  }

  Future<void> _cambiarVisibilidad(bool valor) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    try {
      await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .update({'mostrarNumero': valor});

      if (!mounted) return;

      setState(() {
        mostrarNumero = valor;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            valor
                ? 'Tu número ahora es visible para los locales.'
                : 'Tu número ya no será visible.',
          ),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error actualizando número: $e')),
      );
    }
  }

  Future<void> _elegirHora(String dia, String campo) async {
    final actual = horarios[dia]![campo].toString();
    final partes = actual.split(':');

    final inicial = TimeOfDay(
      hour: int.parse(partes[0]),
      minute: int.parse(partes[1]),
    );

    final seleccionada = await showTimePicker(
      context: context,
      initialTime: inicial,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            alwaysUse24HourFormat: true,
          ),
          child: child!,
        );
      },
    );

    if (seleccionada == null || !mounted) return;

    final hora = '${seleccionada.hour.toString().padLeft(2, '0')}:'
        '${seleccionada.minute.toString().padLeft(2, '0')}';

    setState(() {
      horarios[dia]![campo] = hora;
    });
  }

  Future<void> _guardarHorarios() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || guardandoHorarios) return;

    setState(() => guardandoHorarios = true);

    try {
      await FirebaseFirestore.instance.collection('usuarios').doc(uid).update({
        'horariosTrabajo': horarios,
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Horarios guardados correctamente.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error guardando horarios: $e')),
      );
    } finally {
      if (mounted) {
        setState(() => guardandoHorarios = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (cargando) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Perfil del Cadete'),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'Nombre: ${nombre ?? ''}',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'Teléfono: ${telefono ?? ''}',
            style: const TextStyle(fontSize: 18),
          ),
          const SizedBox(height: 8),
          Text(
            'ID del cadete: ${cadeteId ?? ''}',
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Expanded(
                child: Text(
                  '¿Mostrar número al local?',
                  style: TextStyle(fontSize: 16),
                ),
              ),
              Switch(
                value: mostrarNumero,
                onChanged: _cambiarVisibilidad,
              ),
            ],
          ),
          const Divider(height: 32),
          const Row(
            children: [
              Icon(Icons.schedule, size: 26),
              SizedBox(width: 10),
              Text(
                'Mis horarios de trabajo',
                style: TextStyle(
                  fontSize: 19,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Text(
            'Seleccioná los días y horarios en los que '
            'tenés previsto trabajar.',
            style: TextStyle(color: Colors.grey),
          ),
          const SizedBox(height: 12),
          ...dias.map((dia) {
            final datos = horarios[dia]!;
            final activo = datos['activo'] == true;

            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            dia,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Switch(
                          value: activo,
                          onChanged: (valor) {
                            setState(() {
                              horarios[dia]!['activo'] = valor;
                            });
                          },
                        ),
                      ],
                    ),
                    if (activo) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _elegirHora(dia, 'desde'),
                              child: Column(
                                children: [
                                  const Text('Desde'),
                                  const SizedBox(height: 4),
                                  Text(
                                    datos['desde'].toString(),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton(
                              onPressed: () => _elegirHora(dia, 'hasta'),
                              child: Column(
                                children: [
                                  const Text('Hasta'),
                                  const SizedBox(height: 4),
                                  Text(
                                    datos['hasta'].toString(),
                                    style: const TextStyle(
                                      fontSize: 17,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: guardandoHorarios ? null : _guardarHorarios,
            icon: guardandoHorarios
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  )
                : const Icon(Icons.save),
            label: Text(
              guardandoHorarios ? 'Guardando...' : 'Guardar horarios',
            ),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
            ),
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
