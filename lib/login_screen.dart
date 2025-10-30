import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController emailController = TextEditingController();
  final TextEditingController passwordController = TextEditingController();
  bool isObscure = true;
  bool isLoading = false;

  @override
  void dispose() {
    emailController.dispose();
    passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() => isLoading = true);

    try {
      final userCredential =
          await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: emailController.text.trim(),
        password: passwordController.text.trim(),
      );

      final uid = userCredential.user!.uid;
      debugPrint('UID: $uid');

      final doc = await FirebaseFirestore.instance
          .collection('usuarios')
          .doc(uid)
          .get();

      if (!doc.exists) {
        throw Exception('No se encontró el documento del usuario.');
      }

      final data = doc.data();
      debugPrint('Datos del usuario: $data');

      if (data == null || !data.containsKey('rol')) {
        throw Exception('Usuario sin rol asignado.');
      }

      final rol = data['rol'];
      debugPrint('Rol detectado: $rol');

      if (!mounted) return;

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;

        if (rol == 'local') {
          Navigator.pushReplacementNamed(context, '/localDashboard');
        } else if (rol == 'cadete') {
          Navigator.pushReplacementNamed(context, '/cadeteDashboard');
        } else if (rol == 'admin') {
          Navigator.pushReplacementNamed(context, '/adminDashboard');
        } else {
          _mostrarError('Rol no reconocido: $rol');
        }
      });
    } on FirebaseAuthException catch (e) {
      String mensaje = 'Ocurrió un error de autenticación.';
      if (e.code == 'user-not-found') {
        mensaje = 'Usuario no encontrado';
      } else if (e.code == 'wrong-password') {
        mensaje = 'Contraseña incorrecta';
      }
      _mostrarError(mensaje);
    } catch (e, stack) {
      debugPrint('ERROR LOGIN: $e');
      debugPrint('STACK TRACE: $stack');
      _mostrarError('Error inesperado: ${e.toString()}');
    } finally {
      if (mounted) setState(() => isLoading = false);
    }
  }

  void _mostrarError(String mensaje) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensaje),
      backgroundColor: Colors.red,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFB3E5FC),
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32.0),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Image.asset('assets/logo.png', height: 120),
                  const SizedBox(height: 48),
                  TextField(
                    controller: emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: InputDecoration(
                      hintText: 'Correo electrónico',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 18.0, horizontal: 20.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.email_outlined),
                    ),
                  ),
                  const SizedBox(height: 20),
                  TextField(
                    controller: passwordController,
                    obscureText: isObscure,
                    decoration: InputDecoration(
                      hintText: 'Contraseña',
                      filled: true,
                      fillColor: Colors.white,
                      contentPadding: const EdgeInsets.symmetric(
                          vertical: 18.0, horizontal: 20.0),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(30.0),
                        borderSide: BorderSide.none,
                      ),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(isObscure
                            ? Icons.visibility_off
                            : Icons.visibility),
                        onPressed: () {
                          setState(() {
                            isObscure = !isObscure;
                          });
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blueAccent,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 16.0),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(30.0),
                        ),
                        textStyle: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                        elevation: 2,
                      ),
                      child: isLoading
                          ? const CircularProgressIndicator(color: Colors.white)
                          : const Text('Iniciar sesión'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
