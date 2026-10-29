import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:swiftyring/core/red/servidor.dart';
import 'package:swiftyring/core/theme/app_theme.dart';
import 'package:swiftyring/modules/timbre_escolar/presentation/widgets/timbre_ui.dart';
import 'package:swiftyring/modules/timbre_escolar/providers.dart';
import 'package:swiftyring/modules/timbre_escolar/timbre_escolar_routes.dart';

/// Modelo de red WiFi detectada por el ESP32
class RedWifiScan {
  final String ssid;
  final int rssi;
  final int auth;

  RedWifiScan({required this.ssid, required this.rssi, required this.auth});

  factory RedWifiScan.fromJson(Map<String, dynamic> json) {
    return RedWifiScan(
      ssid: json['ssid'] ?? '',
      rssi: json['rssi'] ?? -100,
      auth: json['auth'] ?? 0,
    );
  }
}

/// Setup Wizard paso a paso para configurar el módulo físico ESP32-C3
class SetupWizardPage extends ConsumerStatefulWidget {
  const SetupWizardPage({super.key});

  @override
  ConsumerState<SetupWizardPage> createState() => _SetupWizardPageState();
}

class _SetupWizardPageState extends ConsumerState<SetupWizardPage> {
  final _dioLocal = Dio(
    BaseOptions(
      baseUrl: 'http://192.168.4.1',
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );

  int _pasoActual = 0;
  bool _cargando = false;
  String? _error;

  // Datos detectados del módulo
  String? _nombreModulo;

  // Redes escaneadas
  List<RedWifiScan> _redes = [];
  String? _ssidSeleccionado;
  final _ssidPersonalizadoCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _apiBaseCtrl = TextEditingController();
  final _apiKeyCtrl = TextEditingController();
  final _codigoManualCtrl = TextEditingController();
  String? _codigoAutorizacion;
  bool _mostrarPassword = false;
  bool _codigoObtenido = false;
  bool _cargandoCodigo = false;
  bool _mostrarCampoManual = false;

  @override
  void initState() {
    super.initState();
    final servidor = ref.read(servidorProvider);
    _apiBaseCtrl.text = '$servidor/api';
    _solicitarCodigoAlServidor();
  }

  Future<void> _solicitarCodigoAlServidor() async {
    setState(() => _cargandoCodigo = true);
    try {
      final res = await ref.read(timbreApiProvider).solicitarCodigoSetup();
      final codigo = res['codigo'] as String?;
      final apiBase = res['apiBase'] as String?;
      if (mounted && codigo != null && codigo.isNotEmpty) {
        setState(() {
          _codigoAutorizacion = codigo;
          _codigoManualCtrl.text = codigo;
          _codigoObtenido = true;
          if (apiBase != null && apiBase.isNotEmpty && _apiBaseCtrl.text.isEmpty) {
            _apiBaseCtrl.text = apiBase;
          }
        });
      }
    } catch (_) {
      // Si el teléfono ya está conectado al SoftAP sin internet, el usuario puede
      // escribir el código generado desde la web o reintentar cuando tenga red.
    } finally {
      if (mounted) setState(() => _cargandoCodigo = false);
    }
  }

  @override
  void dispose() {
    _ssidPersonalizadoCtrl.dispose();
    _passwordCtrl.dispose();
    _apiBaseCtrl.dispose();
    _apiKeyCtrl.dispose();
    _codigoManualCtrl.dispose();
    super.dispose();
  }

  // Paso 1: Verificar conexión con el SoftAP del ESP32
  Future<void> _verificarModulo() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final res = await _dioLocal.get('/api/info');
      if (res.statusCode == 200 && res.data != null) {
        setState(() {
          _nombreModulo = res.data['ssid_ap'] ?? 'SwiftyRing-Setup';
          _pasoActual = 1;
        });
        _escanearRedes();
      } else {
        setState(() => _error = 'Respuesta inesperada del módulo.');
      }
    } catch (e) {
      setState(() {
        _error =
            'No se pudo conectar al módulo en 192.168.4.1.\n'
            'Asegúrate de estar conectado a la red WiFi "SwiftyRing-XXXX" desde los ajustes de tu teléfono.';
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // Paso 2: Escanear redes WiFi disponibles
  Future<void> _escanearRedes() async {
    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final res = await _dioLocal.get('/api/scan');
      if (res.statusCode == 200 && res.data is List) {
        final lista = (res.data as List)
            .map((e) => RedWifiScan.fromJson(e))
            .where((r) => r.ssid.isNotEmpty)
            .toList();
        setState(() {
          _redes = lista;
          if (lista.isNotEmpty && _ssidSeleccionado == null) {
            _ssidSeleccionado = lista.first.ssid;
          }
        });
      }
    } catch (e) {
      setState(() {
        _error = 'Error al escanear redes WiFi. Puedes escribir el SSID manualmente.';
      });
    } finally {
      if (mounted) setState(() => _cargando = false);
    }
  }

  // Paso 4: Enviar configuración al módulo
  Future<void> _enviarConfiguracion() async {
    final ssid = _ssidSeleccionado == '__manual__'
        ? _ssidPersonalizadoCtrl.text.trim()
        : (_ssidSeleccionado ?? '');

    if (ssid.isEmpty) {
      setState(() => _error = 'Por favor selecciona o ingresa el nombre de la red WiFi.');
      return;
    }

    final codigoParaEnviar = (_codigoAutorizacion != null && _codigoAutorizacion!.isNotEmpty)
        ? _codigoAutorizacion!
        : _codigoManualCtrl.text.trim();

    if (codigoParaEnviar.isEmpty && _apiKeyCtrl.text.trim().isEmpty) {
      setState(() => _error = 'Debes tener un código de autorización o clave para vincular el módulo.');
      return;
    }

    setState(() {
      _cargando = true;
      _error = null;
    });

    try {
      final cuerpo = {
        'ssid': ssid,
        'password': _passwordCtrl.text.trim(),
        'api_base': _apiBaseCtrl.text.trim(),
        if (codigoParaEnviar.isNotEmpty) 'codigo_autorizacion': codigoParaEnviar,
        if (_apiKeyCtrl.text.trim().isNotEmpty) 'device_api_key': _apiKeyCtrl.text.trim(),
      };

      final res = await _dioLocal.post('/api/setup', data: cuerpo);
      if (res.statusCode == 200) {
        const storage = FlutterSecureStorage();
        await storage.write(key: 'modulo_configurado', value: 'true');

        if (mounted) {
          setState(() {
            _pasoActual = 3; // Éxito
            _cargando = false;
          });
        }
      } else {
        setState(() => _error = 'El módulo rechazó la configuración.');
      }
    } catch (e) {
      // Como el ESP32 reinicia tras responder, puede cortar el socket inmediatamente con éxito
      const storage = FlutterSecureStorage();
      await storage.write(key: 'modulo_configurado', value: 'true');

      if (mounted) {
        setState(() {
          _pasoActual = 3;
          _cargando = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(
        title: Text(
          'Configuración del Módulo Físico',
          style: GoogleFonts.plusJakartaSans(
            fontWeight: FontWeight.w700,
            color: TimbreColors.tinta,
          ),
        ),
        backgroundColor: AppColors.fondo,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: TimbreColors.tinta),
          onPressed: () => context.pop(),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Barra de progreso de pasos
              Row(
                children: List.generate(4, (index) {
                  final activo = index <= _pasoActual;
                  return Expanded(
                    child: Container(
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      decoration: BoxDecoration(
                        color: activo ? AppColors.dorado : TimbreColors.grisChip,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 24),

              if (_error != null) ...[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEBEE),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline, color: Colors.red),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          _error!,
                          style: GoogleFonts.workSans(
                            color: Colors.red.shade900,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
              ],

              // Contenido según el paso
              if (_pasoActual == 0) _construirPasoConexion(),
              if (_pasoActual == 1) _construirPasoWifi(),
              if (_pasoActual == 2) _construirPasoServidor(),
              if (_pasoActual == 3) _construirPasoExito(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _construirPasoConexion() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paso 1: Conecta con el módulo', style: TimbreTextos.titulo),
        const SizedBox(height: 8),
        Text(
          'Enciende el timbre físico. Si es la primera vez o fue restablecido, '
          'verás en su pantalla OLED el mensaje "[ MODO CONFIG ]".',
          style: AppTextStyles.cuerpo,
        ),
        const SizedBox(height: 16),

        if (_codigoObtenido && _codigoAutorizacion != null) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: const Color(0xFFE8F5E9),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFFA5D6A7)),
            ),
            child: Row(
              children: [
                const Icon(Icons.verified_user_rounded, color: Color(0xFF2E7D32), size: 28),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Código de vinculación listo:',
                        style: GoogleFonts.workSans(fontSize: 12, color: const Color(0xFF2E7D32)),
                      ),
                      Text(
                        _codigoAutorizacion!,
                        style: GoogleFonts.plusJakartaSans(
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF1B5E20),
                          letterSpacing: 1.5,
                        ),
                      ),
                      Text(
                        'El módulo lo canjeará por su clave al conectarse.',
                        style: GoogleFonts.workSans(fontSize: 11, color: const Color(0xFF388E3C)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ] else if (_cargandoCodigo) ...[
          const Center(
            child: Padding(
              padding: EdgeInsets.all(12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  SizedBox(width: 10),
                  Text('Generando código con el servidor...'),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.blanco,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.chipFondo),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.wifi, color: AppColors.dorado, size: 28),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Red WiFi temporal:', style: TimbreTextos.rotulo),
                        Text(
                          'SwiftyRing-XXXX',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                            color: TimbreColors.tinta,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),
              Text(
                '1. Abre los Ajustes de WiFi de tu dispositivo.\n'
                '2. Conéctate a la red "SwiftyRing-XXXX" (es abierta, no requiere clave).\n'
                '3. Vuelve a esta app y pulsa el botón continuar.',
                style: GoogleFonts.workSans(fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dorado,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _cargando ? null : _verificarModulo,
            child: _cargando
                ? const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                  )
                : const Text('Ya estoy conectado al módulo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _construirPasoWifi() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paso 2: Red WiFi del Colegio', style: TimbreTextos.titulo),
        const SizedBox(height: 8),
        Text(
          'Conectado a ${_nombreModulo ?? "módulo"}. '
          'Selecciona la red WiFi a la que se conectará el timbre.',
          style: AppTextStyles.cuerpo,
        ),
        const SizedBox(height: 20),

        if (_cargando && _redes.isEmpty)
          const Center(
            child: Padding(
              padding: EdgeInsets.all(32),
              child: CircularProgressIndicator(color: AppColors.dorado),
            ),
          )
        else ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: AppColors.blanco,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.chipFondo),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                value: _ssidSeleccionado,
                items: [
                  ..._redes.map(
                    (r) => DropdownMenuItem(
                      value: r.ssid,
                      child: Row(
                        children: [
                          const Icon(Icons.wifi, size: 20, color: AppColors.dorado),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              r.ssid,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.workSans(fontWeight: FontWeight.w600),
                            ),
                          ),
                          Text(
                            '${r.rssi} dBm',
                            style: GoogleFonts.workSans(fontSize: 12, color: AppColors.textoApoyo),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const DropdownMenuItem(
                    value: '__manual__',
                    child: Row(
                      children: [
                        Icon(Icons.edit, size: 20, color: AppColors.textoApoyo),
                        SizedBox(width: 10),
                        Text('Ingresar red manualmente...'),
                      ],
                    ),
                  ),
                ],
                onChanged: (val) {
                  setState(() => _ssidSeleccionado = val);
                },
              ),
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: _cargando ? null : _escanearRedes,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Volver a escanear'),
            ),
          ),
          if (_ssidSeleccionado == '__manual__') ...[
            const SizedBox(height: 8),
            TextField(
              controller: _ssidPersonalizadoCtrl,
              decoration: InputDecoration(
                labelText: 'Nombre de la red (SSID)',
                filled: true,
                fillColor: AppColors.blanco,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
          const SizedBox(height: 16),
          TextField(
            controller: _passwordCtrl,
            obscureText: !_mostrarPassword,
            decoration: InputDecoration(
              labelText: 'Contraseña de la red WiFi',
              filled: true,
              fillColor: AppColors.blanco,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              suffixIcon: IconButton(
                icon: Icon(_mostrarPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _mostrarPassword = !_mostrarPassword),
              ),
            ),
          ),
        ],

        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dorado,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: () {
              final ssid = _ssidSeleccionado == '__manual__'
                  ? _ssidPersonalizadoCtrl.text.trim()
                  : (_ssidSeleccionado ?? '');
              if (ssid.isEmpty) {
                setState(() => _error = 'Selecciona o escribe el nombre de la red WiFi.');
                return;
              }
              setState(() {
                _error = null;
                _pasoActual = 2;
              });
            },
            child: const Text('Continuar a Servidor', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _construirPasoServidor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Paso 3: Servidor y Credenciales', style: TimbreTextos.titulo),
        const SizedBox(height: 8),
        Text(
          'Configura la dirección del servidor Vapor al que el módulo reportará eventos.',
          style: AppTextStyles.cuerpo,
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _apiBaseCtrl,
          decoration: InputDecoration(
            labelText: 'URL Base de la API',
            helperText: 'Ej: https://swiftyring.swiftydevs.dev/api',
            filled: true,
            fillColor: AppColors.blanco,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFE8F5E9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFA5D6A7)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.security_rounded, color: Color(0xFF2E7D32), size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Vinculación Automática por Servidor',
                          style: GoogleFonts.plusJakartaSans(
                            fontWeight: FontWeight.w700,
                            color: const Color(0xFF1B5E20),
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Código: ${_codigoAutorizacion ?? (_codigoManualCtrl.text.isNotEmpty ? _codigoManualCtrl.text : "Pendiente")}',
                          style: GoogleFonts.plusJakartaSans(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: const Color(0xFF2E7D32),
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Text(
                'Tu teléfono no requiere internet durante la configuración del módulo. '
                'Una vez configurado, el timbre físico se conectará a la red del colegio y canjeará '
                'este código de autorización con el backend para obtener su clave de dispositivo.',
                style: GoogleFonts.workSans(
                  color: const Color(0xFF2E7D32),
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: TextButton.icon(
            onPressed: () => setState(() => _mostrarCampoManual = !_mostrarCampoManual),
            icon: Icon(_mostrarCampoManual ? Icons.expand_less : Icons.expand_more, size: 18),
            label: Text(_mostrarCampoManual ? 'Ocultar opciones manuales' : 'Opciones manuales de código / clave'),
          ),
        ),
        if (_mostrarCampoManual) ...[
          const SizedBox(height: 8),
          TextField(
            controller: _codigoManualCtrl,
            decoration: InputDecoration(
              labelText: 'Código de Autorización',
              helperText: 'Código temporal de un solo uso generado por el servidor',
              filled: true,
              fillColor: AppColors.blanco,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              suffixIcon: _cargandoCodigo
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : IconButton(
                      icon: const Icon(Icons.refresh),
                      tooltip: 'Generar nuevo código en el servidor',
                      onPressed: _solicitarCodigoAlServidor,
                    ),
            ),
          ),
          const SizedBox(height: 14),
          TextField(
            controller: _apiKeyCtrl,
            decoration: InputDecoration(
              labelText: 'Clave Directa (Opcional si usas código)',
              helperText: 'Solo para configuración manual directa con DEVICE_API_KEY',
              filled: true,
              fillColor: AppColors.blanco,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
        const SizedBox(height: 32),
        SizedBox(
          width: double.infinity,
          height: 50,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.dorado,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
            onPressed: _cargando ? null : _enviarConfiguracion,
            child: _cargando
                ? const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                      ),
                      SizedBox(width: 12),
                      Text('Guardando en el módulo...'),
                    ],
                  )
                : const Text('Guardar y Reiniciar Módulo', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ),
      ],
    );
  }

  Widget _construirPasoExito() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const SizedBox(height: 30),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: const BoxDecoration(
              color: Color(0xFFCDEFE8),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.check_circle_rounded, color: Color(0xFF00796B), size: 64),
          ),
          const SizedBox(height: 24),
          Text(
            '¡Módulo Configurado!',
            style: GoogleFonts.plusJakartaSans(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              color: TimbreColors.tinta,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Las credenciales se guardaron en la memoria del timbre físico. '
            'El módulo se está reiniciando y se conectará automáticamente a la red del colegio.',
            textAlign: TextAlign.center,
            style: AppTextStyles.cuerpo,
          ),
          const SizedBox(height: 40),
          SizedBox(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.dorado,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              onPressed: () {
                context.go(RutasTimbre.ajustes);
              },
              child: const Text('Ir a Ajustes del Sistema', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }
}
