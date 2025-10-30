import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Widget _responsiveButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = Colors.blueAccent,
  }) {
    final screenWidth = MediaQuery.of(context).size.width;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: SizedBox(
        width: screenWidth * 0.85,
        child: ElevatedButton.icon(
          icon: Icon(icon),
          label: Text(label),
          style: ElevatedButton.styleFrom(
            backgroundColor: color,
            foregroundColor: Colors.white,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onPressed: onTap,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFE0F7FA), // celeste claro
      appBar: AppBar(
        title: const Text('Panel de Administrador'),
        backgroundColor: Colors.lightBlue,
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.only(top: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _responsiveButton(
                context,
                Icons.store,
                'Ver Locales',
                () => Navigator.pushNamed(context, '/verLocalesAdmin'),
              ),
              _responsiveButton(
                context,
                Icons.delivery_dining,
                'Ver Cadetes',
                () => Navigator.pushNamed(context, '/verCadetesAdmin'),
              ),
              const SizedBox(height: 40),
              _responsiveButton(
                context,
                Icons.logout,
                'Cerrar sesión',
                () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    Navigator.pushNamedAndRemoveUntil(
                        context, '/login', (_) => false);
                  }
                },
                color: Colors.red,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
