import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';
import 'package:swiftyring/core/shared_widgets/boton_principal.dart';
import 'package:swiftyring/core/shared_widgets/fondo_decorado.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';

/// F-01, segunda mitad — formulario de inicio de sesión (RF-01).
///
/// OJO: esta pantalla NO existe en el prototipo de Figma. El frame
/// "Bienvenida y Login (Yellow)" solo contiene la bienvenida (Screen 1); no hay
/// ningún frame con los campos de correo y contraseña que pide F-01. Se
/// construyó reutilizando los mismos tokens de la bienvenida (colores,
/// tipografías, radios, sombras) para que no desentone. Cuando el prototipo
/// tenga su Screen 2, hay que volver aquí y ajustarla.
///
/// Es el **único** formulario de credenciales de la aplicación: ningún módulo
/// pide contraseña por su cuenta (Contrato de integración, sección 3.1).
class LoginPage extends ConsumerStatefulWidget {
  const LoginPage({super.key});

  @override
  ConsumerState<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends ConsumerState<LoginPage> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _mostrarPassword = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _enviar() async {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    // No hay navegación aquí: al cambiar el estado de sesión, el redirect del
    // router lleva al inicio. Una sola regla de navegación, en un solo lugar.
    await ref
        .read(authProvider.notifier)
        .login(
          email: _emailController.text.trim(),
          password: _passwordController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final estado = ref.watch(authProvider);

    return Scaffold(
      backgroundColor: AppColors.fondo,
      body: Stack(
        children: [
          const FondoDecorado(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.margenLateral,
                vertical: 24,
              ),
              // En pantallas anchas el formulario se centra en vez de pegarse
              // al borde izquierdo; en un teléfono el `maxWidth` no llega a
              // aplicarse y queda igual que en el prototipo.
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: context.anchoContenido),
                  child: Form(
                    key: _formKey,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        IconButton(
                          onPressed: () =>
                              context.canPop() ? context.pop() : null,
                          icon: const Icon(Icons.arrow_back),
                          color: AppColors.dorado,
                          padding: EdgeInsets.zero,
                          alignment: Alignment.centerLeft,
                        ),
                        const SizedBox(height: 24),
                        Text('Iniciar Sesión', style: AppTextStyles.titulo),
                        const SizedBox(height: 8),
                        Text(
                          'Ingresa con tu correo institucional',
                          style: AppTextStyles.subtitulo,
                        ),
                        const SizedBox(height: 40),
                        _CampoTexto(
                          controller: _emailController,
                          etiqueta: 'Correo electrónico',
                          icono: Icons.mail_outline,
                          teclado: TextInputType.emailAddress,
                          validador: (valor) {
                            final texto = (valor ?? '').trim();
                            if (texto.isEmpty) return 'Escribe tu correo';
                            if (!texto.contains('@') || !texto.contains('.')) {
                              return 'Ese correo no parece válido';
                            }
                            return null;
                          },
                        ),
                        const SizedBox(height: 20),
                        _CampoTexto(
                          controller: _passwordController,
                          etiqueta: 'Contraseña',
                          icono: Icons.lock_outline,
                          ocultarTexto: !_mostrarPassword,
                          accionTeclado: TextInputAction.done,
                          alEnviar: (_) => _enviar(),
                          sufijo: IconButton(
                            onPressed: () => setState(
                              () => _mostrarPassword = !_mostrarPassword,
                            ),
                            icon: Icon(
                              _mostrarPassword
                                  ? Icons.visibility_off_outlined
                                  : Icons.visibility_outlined,
                              color: AppColors.chipTexto,
                            ),
                          ),
                          validador: (valor) => (valor ?? '').isEmpty
                              ? 'Escribe tu contraseña'
                              : null,
                        ),
                        if (estado.error != null) ...[
                          const SizedBox(height: 20),
                          _AvisoError(mensaje: estado.error!),
                        ],
                        const SizedBox(height: 32),
                        BotonPrincipal(
                          texto: 'Entrar',
                          cargando: estado.enviando,
                          onPressed: _enviar,
                        ),
                        const SizedBox(height: 24),
                        Center(
                          child: Text(
                            '¿Olvidaste tu contraseña? Habla con el administrador',
                            textAlign: TextAlign.center,
                            style: AppTextStyles.cuerpo,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CampoTexto extends StatelessWidget {
  final TextEditingController controller;
  final String etiqueta;
  final IconData icono;
  final bool ocultarTexto;
  final TextInputType? teclado;
  final TextInputAction? accionTeclado;
  final Widget? sufijo;
  final String? Function(String?)? validador;
  final void Function(String)? alEnviar;

  const _CampoTexto({
    required this.controller,
    required this.etiqueta,
    required this.icono,
    this.ocultarTexto = false,
    this.teclado,
    this.accionTeclado,
    this.sufijo,
    this.validador,
    this.alEnviar,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      obscureText: ocultarTexto,
      keyboardType: teclado,
      textInputAction: accionTeclado ?? TextInputAction.next,
      onFieldSubmitted: alEnviar,
      validator: validador,
      style: GoogleFonts.workSans(fontSize: 16, color: AppColors.textoApoyo),
      decoration: InputDecoration(
        labelText: etiqueta,
        labelStyle: AppTextStyles.cuerpo,
        prefixIcon: Icon(icono, color: AppColors.chipTexto),
        suffixIcon: sufijo,
        filled: true,
        fillColor: AppColors.blanco,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 20,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.botonRadio),
          borderSide: const BorderSide(color: AppColors.chipFondo),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.botonRadio),
          borderSide: const BorderSide(color: AppColors.chipFondo),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSizes.botonRadio),
          borderSide: const BorderSide(color: AppColors.dorado, width: 2),
        ),
      ),
    );
  }
}

class _AvisoError extends StatelessWidget {
  final String mensaje;

  const _AvisoError({required this.mensaje});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: AppColors.error, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              mensaje,
              style: GoogleFonts.workSans(
                fontSize: 14,
                height: 20 / 14,
                color: AppColors.error,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
