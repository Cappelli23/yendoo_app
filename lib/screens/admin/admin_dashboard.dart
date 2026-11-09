import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class AdminDashboardScreen extends StatelessWidget {
  const AdminDashboardScreen({super.key});

  Widget _responsiveButton(
    BuildContext context,
    IconData icon,
    String label,
    VoidCallback onTap, {
    Color color = const Color(0xFF2478F2),
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(18),
          child: Container(
            padding: const EdgeInsets.symmetric(
              horizontal: 18,
              vertical: 19,
            ),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: const Color(0xFFE5ECF5),
              ),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF102747).withValues(alpha: 0.05),
                  blurRadius: 16,
                  offset: const Offset(0, 5),
                ),
              ],
            ),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.11),
                    borderRadius: BorderRadius.circular(15),
                  ),
                  child: Icon(
                    icon,
                    color: color,
                    size: 27,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: const TextStyle(
                      color: Color(0xFF172C4D),
                      fontSize: 17,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const Icon(
                  Icons.chevron_right_rounded,
                  color: Color(0xFF8393AA),
                  size: 27,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5FB),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Color(0xFF101E34),
                  Color(0xFF203F69),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.vertical(
                bottom: Radius.circular(30),
              ),
            ),
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 25, 24, 36),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Row(
                      children: [
                        Icon(
                          Icons.delivery_dining_rounded,
                          color: Color(0xFF48A1FF),
                          size: 36,
                        ),
                        SizedBox(width: 10),
                        Text(
                          'Yendo',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 32,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 22),
                    const Text(
                      'Panel de Administrador',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Administrá tu servicio desde un solo lugar',
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(bottom: 18),
                    child: Text(
                      'Administración',
                      style: TextStyle(
                        color: Color(0xFF172C4D),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _responsiveButton(
                    context,
                    Icons.storefront_rounded,
                    'Ver Locales',
                    () => Navigator.pushNamed(
                      context,
                      '/verLocalesAdmin',
                    ),
                    color: const Color(0xFF13A878),
                  ),
                  _responsiveButton(
                    context,
                    Icons.account_balance_wallet_rounded,
                    'Cargar saldo',
                    () => Navigator.pushNamed(
                      context,
                      '/cargarSaldoAdmin',
                    ),
                    color: const Color(0xFF2478F2),
                  ),
                  _responsiveButton(
                    context,
                    Icons.delivery_dining_rounded,
                    'Ver Cadetes',
                    () => Navigator.pushNamed(
                      context,
                      '/verCadetesAdmin',
                    ),
                    color: const Color(0xFFFF873D),
                  ),
                  _responsiveButton(
                    context,
                    Icons.warning_amber_rounded,
                    'Administrar zonas rojas',
                    () => Navigator.pushNamed(
                      context,
                      '/zonasRojasAdmin',
                    ),
                    color: const Color(0xFFE53935),
                  ),
                  const SizedBox(height: 30),
                  const Padding(
                    padding: EdgeInsets.only(bottom: 15),
                    child: Text(
                      'Cuenta',
                      style: TextStyle(
                        color: Color(0xFF172C4D),
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  _responsiveButton(
                    context,
                    Icons.logout_rounded,
                    'Cerrar sesión',
                    () async {
                      await FirebaseAuth.instance.signOut();
                      if (context.mounted) {
                        Navigator.pushNamedAndRemoveUntil(
                          context,
                          '/login',
                          (_) => false,
                        );
                      }
                    },
                    color: const Color(0xFFE34B57),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
