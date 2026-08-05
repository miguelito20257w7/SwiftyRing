import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/network/api_client.dart';
import 'package:swiftyring/core/red/servidor.dart';
import 'package:swiftyring/core/shared_widgets/boton_principal.dart';
import 'package:swiftyring/core/shared_widgets/fondo_decorado.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/core/theme/responsive.dart';

/// Ajustes de red — a qué servidor le habla la app.
///
/// Es la pantalla detrás del chip "Ajustes de red" de la bienvenida (nodo
/// 1:826 del prototipo), que hasta ahora era decorativo. Se llega desde ahí
/// porque la dirección hay que poder corregirla **antes** de iniciar sesión:
/// si apunta mal, el login no es que falle, es que no llega a ninguna parte.
///
/// El administrador también entra desde Configuración, ya con sesión abierta.
class AjustesRedPage extends ConsumerStatefulWidget {
  const AjustesRedPage({super.key});

  @override
  ConsumerState<AjustesRedPage> createState() => _AjustesRedPageState();
}

class _AjustesRedPageState extends ConsumerState<AjustesRedPage> {
  late final TextEditingController _direccion;
  String? _error;
  ResultadoPrueba? _resultado;
  bool _probando = false;
  bool _guardando = false;

  @override
  void initState() {
    super.initState();
    _direccion = TextEditingController(text: ref.read(servidorProvider));
  }

  @override
  void dispose() {
    _direccion.dispose();
    super.dispose();
  }

  /// Normaliza lo escrito y deja el error a la vista si no sirve.
  String? _origenValido() {
    final (origen: origen, error: error) = Servidor.normalizar(_direccion.text);
    setState(() {
      _error = error;
      if (error != null) _resultado = null;
    });
    return origen;
  }

  Future<void> _probar() async {
    final origen = _origenValido();
    if (origen == null) return;

    setState(() {
      _probando = true;
      _resultado = null;
    });
    final resultado = await ApiClient.probar(origen);
    if (!mounted) return;
    setState(() {
      _probando = false;
      _resultado = resultado;
      // Al probar se muestra la dirección ya normalizada: así el usuario ve
      // exactamente contra qué se hizo la prueba.
      _direccion.text = origen;
    });
  }

  Future<void> _guardar() async {
    final origen = _origenValido();
    if (origen == null) return;

    setState(() => _guardando = true);
    await ref.read(servidorProvider.notifier).cambiar(origen);
    if (!mounted) return;
    setState(() => _guardando = false);

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('La app ahora usa $origen')),
    );
    if (context.canPop()) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    // Se recalcula en cada pulsación para que el aviso de HTTPS aparezca
    // mientras se escribe, no solo al guardar.
    final (origen: origenPrevisto, error: _) = Servidor.normalizar(
      _direccion.text,
    );
    final inseguro = origenPrevisto != null && Servidor.esInseguro(origenPrevisto);

    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        foregroundColor: AppColors.dorado,
        title: Text('Ajustes de red', style: AppTextStyles.enlace),
      ),
      body: Stack(
        children: [
          const FondoDecorado(),
          SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.symmetric(
                horizontal: context.margenLateral,
                vertical: 24,
              ),
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: context.anchoContenido),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Servidor', style: AppTextStyles.titulo),
                      const SizedBox(height: 8),
                      Text(
                        'La dirección del servidor de tu colegio. Si no sabes '
                        'cuál es, pídesela a quien instaló el sistema.',
                        style: AppTextStyles.subtitulo,
                      ),
                      const SizedBox(height: 32),
                      TextField(
                        controller: _direccion,
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        onChanged: (_) => setState(() {
                          _error = null;
                          _resultado = null;
                        }),
                        onSubmitted: (_) => _probar(),
                        style: GoogleFonts.workSans(
                          fontSize: 16,
                          color: AppColors.textoApoyo,
                        ),
                        decoration: InputDecoration(
                          labelText: 'Dirección',
                          hintText: 'https://timbre.micolegio.edu.co',
                          errorText: _error,
                          prefixIcon: const Icon(
                            Icons.dns_outlined,
                            color: AppColors.chipTexto,
                          ),
                          filled: true,
                          fillColor: AppColors.blanco,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(
                              AppSizes.botonRadio,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No hace falta escribir «/api»: la app lo agrega sola.',
                        style: AppTextStyles.chip,
                      ),
                      if (inseguro) ...[
                        const SizedBox(height: 16),
                        const _Aviso(
                          icono: Icons.lock_open_outlined,
                          color: Color(0xFF8A6D00),
                          texto:
                              'Esta conexión no va cifrada. Para un servidor en '
                              'internet usa https:// con certificado válido; sin '
                              'él, las contraseñas viajan a la vista.',
                        ),
                      ],
                      if (_resultado case final resultado?) ...[
                        const SizedBox(height: 16),
                        _Aviso(
                          icono: resultado.exitoso
                              ? Icons.check_circle_outline
                              : Icons.error_outline,
                          color: resultado.exitoso
                              ? const Color(0xFF00796B)
                              : AppColors.error,
                          texto:
                              resultado.mensaje ??
                              'Conexión correcta: es un servidor de SwiftyRing.',
                        ),
                      ],
                      const SizedBox(height: 32),
                      OutlinedButton.icon(
                        onPressed: _probando ? null : _probar,
                        icon: _probando
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : const Icon(Icons.wifi_tethering),
                        label: Text(_probando ? 'Probando…' : 'Probar conexión'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.dorado,
                          minimumSize: const Size.fromHeight(48),
                          side: const BorderSide(color: AppColors.dorado),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(
                              AppSizes.botonRadio,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      BotonPrincipal(
                        texto: 'Guardar',
                        cargando: _guardando,
                        onPressed: _guardar,
                      ),
                      const SizedBox(height: 24),
                      Center(
                        child: TextButton(
                          onPressed: () {
                            _direccion.text = Servidor.desarrollo;
                            setState(() {
                              _error = null;
                              _resultado = null;
                            });
                          },
                          child: Text(
                            'Usar la dirección de desarrollo',
                            style: AppTextStyles.chip,
                          ),
                        ),
                      ),
                    ],
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

class _Aviso extends StatelessWidget {
  final IconData icono;
  final Color color;
  final String texto;

  const _Aviso({required this.icono, required this.color, required this.texto});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icono, size: 20, color: color),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              texto,
              style: GoogleFonts.workSans(
                fontSize: 14,
                height: 20 / 14,
                color: color,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
