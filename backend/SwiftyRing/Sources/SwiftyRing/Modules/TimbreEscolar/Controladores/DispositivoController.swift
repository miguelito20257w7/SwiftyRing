//
//  DispositivoController.swift
//  SwiftyRing · Modules/TimbreEscolar
//
//  La API que consume el módulo físico ESP32. Cuatro conversaciones:
//
//    1. `GET  /api/dispositivo/horario`      — baja el horario semanal completo
//       y la calibración sísmica, para guardarlos en su flash (RF-28).
//    2. `GET  /api/dispositivo/comandos`     — pregunta cada ~2 s si la app
//       ordenó timbrar (RNF-04); esta consulta hace de latido "en línea".
//    3. `POST /api/dispositivo/activaciones` — reporta que sonó (automático o
//       botón físico) para la bitácora (RF-17) y las notificaciones (RF-36).
//    4. `POST /api/dispositivo/sismos`       — reporta un evento sísmico
//       confirmado (RF-22).
//
//  El módulo no es un usuario: se autentica con una llave fija en la cabecera
//  `X-Device-Key` (variable DEVICE_API_KEY). Si la llave no está configurada
//  en el servidor, los endpoints responden 503: mejor un error claro que un
//  módulo aceptado sin autenticar.
//

import Vapor
import Fluent

/// Autenticación del módulo físico por llave compartida.
struct DispositivoAuthMiddleware: AsyncMiddleware {
    func respond(to request: Request, chainingTo next: any AsyncResponder) async throws -> Response {
        guard let esperada = Environment.get("DEVICE_API_KEY"), !esperada.isEmpty else {
            throw Abort(.serviceUnavailable, reason: "DEVICE_API_KEY no está configurada en el servidor")
        }
        guard let recibida = request.headers.first(name: "X-Device-Key"), recibida == esperada else {
            throw Abort(.unauthorized, reason: "Llave de dispositivo inválida")
        }
        return try await next.respond(to: request)
    }
}

/// Un timbre como lo necesita el módulo: sin más metadatos que los que usa
/// para decidir cuándo sonar.
struct TimbreDispositivoDTO: Content {
    let id: UUID
    let etiqueta: String
    let hora: String
    let duracionSeg: Int
    let dias: [DiaSemana]
}

struct HorarioEspecialDispositivoDTO: Content {
    let nombre: String
    let fechaInicio: String
    let fechaFin: String
    let timbres: [TimbreDispositivoDTO]
}

/// Todo lo que el módulo guarda en flash para operar solo (RF-28, RF-31):
/// el horario habitual completo y, si existe, el especial con su rango. Van
/// los dos para que el módulo decida bien aunque pase días sin conexión y el
/// especial venza estando offline (RF-12).
struct HorarioDispositivoResponse: Content {
    let fechaServidor: String
    let horaServidor: String
    let umbralSismicoG: Double
    let sismoDuracionMinMs: Int
    let modoUps: Bool
    let duracionTimbreManualSeg: Int
    let habitual: [TimbreDispositivoDTO]
    let especial: HorarioEspecialDispositivoDTO?
}

struct ComandosResponse: Content {
    /// ¿Hay orden de timbre manual pendiente? (RF-14, RNF-04)
    let timbrar: Bool
    let duracionSeg: Int?
    let sincronizar: Bool
    let modoUps: Bool
    let duracionTimbreManualSeg: Int
    let reset: Bool?
    let otaUrl: String?
}

struct OrdenOtaRequest: Content {
    let url: String
}

struct FirmwareInfoResponse: Content {
    let version: String
    let url: String
}

struct ProvisionKeyResponse: Content {
    let deviceApiKey: String
    let apiBase: String
}

struct FirmwareUploadDTO: Content {
    var firmware: File
    var notificarOta: String?
    var claveAdmin: String?
}

struct ReporteActivacionRequest: Content {
    /// `automatico` o `manual_fisico`; los otros orígenes no salen del módulo.
    let tipo: String
    /// Timbre programado que la originó, si fue automática.
    let horarioTimbreId: UUID?
    let duracionSeg: Int?
    /// Hace cuántos segundos ocurrió. El módulo lo calcula con su propio
    /// reloj, así los reportes encolados offline llegan con su momento real
    /// aunque el módulo no sepa la fecha absoluta con precisión.
    let ocurridoHaceSeg: Int?
}

struct ReporteSismoRequest: Content {
    let intensidadG: Double
    let duracionMs: Int
    let timbreActivado: Bool?
    let ocurridoHaceSeg: Int?
}

struct DispositivoController: RouteCollection {

    /// Un reporte más viejo que esto no dispara notificaciones de próxima
    /// clase: avisarle a un docente de la clase que siguió a un timbre de hace
    /// horas (sincronización tardía) sería ruido, no información (RF-36).
    private static let ventanaNotificacionesSeg = 120

    /// Hasta cuándo sigue teniendo sentido avisar de un sismo (15 minutos).
    private static let ventanaAvisoSismoSeg = 900

    func boot(routes: any RoutesBuilder) throws {
        let dispositivo = routes.grouped("api", "dispositivo")
            .grouped(DispositivoAuthMiddleware())

        dispositivo.get("horario", use: horario)
        dispositivo.get("comandos", use: comandos)
        dispositivo.post("activaciones", use: reportarActivacion)
        dispositivo.post("sismos", use: reportarSismo)
        dispositivo.webSocket("canal", onUpgrade: canal)

        // Endpoints administrativos para la App Flutter
        let adminDispositivo = routes.grouped("api", "dispositivo")
            .grouped(SwiftyRingAuthMiddleware())

        adminDispositivo.get("provision-key", use: obtenerClaveAprovisionamiento)
        adminDispositivo.post("reset", use: ordenarResetDispositivo)
        adminDispositivo.post("ota", use: ordenarOtaDispositivo)
        adminDispositivo.get("firmware", "info", use: firmwareInfo)

        // Descarga de binario OTA para el ESP32
        routes.grouped("api", "dispositivo")
            .get("firmware", "download", use: descargarFirmware)

        // Web UI y endpoint para subir firmware por navegador (/update_firmware)
        routes.get("update_firmware", use: vistaUpdateFirmware)
        routes.on(.POST, "update_firmware", body: .collect(maxSize: "16mb"), use: procesarUploadFirmware)
    }

    /// RF-28: el paquete completo que el módulo guarda en LittleFS. También
    /// deja constancia de la sincronización (`ultima_sync` en configuración).
    func horario(req: Request) async throws -> HorarioDispositivoResponse {
        await EstadoModulo.compartido.registrarContacto()

        let config = try await ConfiguracionSistema.actual(on: req.db)
        config.ultimaSync = Date()
        try await config.save(on: req.db)

        let habituales = try await HorarioTimbre.query(on: req.db)
            .filter(\.$activo == true)
            .with(\.$dias)
            .sort(\.$hora)
            .all()
            .map { timbre in
                TimbreDispositivoDTO(
                    id: try timbre.requireID(),
                    etiqueta: timbre.etiqueta,
                    hora: timbre.hora,
                    duracionSeg: timbre.duracionSeg,
                    dias: timbre.dias.map(\.dia).ordenados()
                )
            }

        // El especial vigente hoy o el próximo a entrar en vigencia: si el
        // módulo pierde conexión hoy, mañana puede empezar una semana de
        // exámenes y debe tenerla ya en la flash.
        let hoy = FormatoTiempo.hoyISO()
        let especial = try await HorarioEspecial.query(on: req.db)
            .filter(\.$activo == true)
            .filter(\.$fechaFin >= hoy)
            .sort(\.$fechaInicio)
            .with(\.$timbres, { $0.with(\.$dias) })
            .first()

        let especialDTO = try especial.map { horario in
            HorarioEspecialDispositivoDTO(
                nombre: horario.nombre,
                fechaInicio: horario.fechaInicio,
                fechaFin: horario.fechaFin,
                timbres: try horario.timbres
                    .sorted { $0.hora < $1.hora }
                    .map { timbre in
                        TimbreDispositivoDTO(
                            id: try timbre.requireID(),
                            etiqueta: timbre.etiqueta,
                            hora: timbre.hora,
                            duracionSeg: timbre.duracionSeg,
                            dias: timbre.dias.map(\.dia).ordenados()
                        )
                    }
            )
        }

        return HorarioDispositivoResponse(
            fechaServidor: hoy,
            horaServidor: FormatoTiempo.horaActual(),
            umbralSismicoG: config.umbralSismicoG,
            sismoDuracionMinMs: config.sismoDuracionMinMs,
            modoUps: config.modoUps,
            duracionTimbreManualSeg: config.duracionTimbreManualSeg,
            habitual: habituales,
            especial: especialDTO
        )
    }

    /// El latido del módulo: registra el contacto y entrega la orden de
    /// timbre pendiente, si la app dejó una (RNF-04: el módulo consulta cada
    /// ~2 s, así la orden llega dentro del plazo).
    func comandos(req: Request) async throws -> ComandosResponse {
        await EstadoModulo.compartido.registrarContacto()
        let duracion = await EstadoModulo.compartido.retirarOrden()
        let sincronizar = await EstadoModulo.compartido.retirarOrdenSincronizacion()
        let reset = await EstadoModulo.compartido.retirarOrdenReset()
        let otaUrl = await EstadoModulo.compartido.retirarOrdenOta()
        let config = try await ConfiguracionSistema.actual(on: req.db)
        return ComandosResponse(
            timbrar: duracion != nil,
            duracionSeg: duracion,
            sincronizar: sincronizar,
            modoUps: config.modoUps,
            duracionTimbreManualSeg: config.duracionTimbreManualSeg,
            reset: reset ? true : nil,
            otaUrl: otaUrl
        )
    }

    func ordenarResetDispositivo(req: Request) async throws -> HTTPStatus {
        try req.exigirRol(.admin)
        await EstadoModulo.compartido.ordenarReset()
        return .ok
    }

    func ordenarOtaDispositivo(req: Request) async throws -> HTTPStatus {
        try req.exigirRol(.admin)
        let datos = try req.content.decode(OrdenOtaRequest.self)
        await EstadoModulo.compartido.ordenarOta(url: datos.url)
        return .ok
    }

    func firmwareInfo(req: Request) async throws -> FirmwareInfoResponse {
        try req.exigirRol(.admin)
        return FirmwareInfoResponse(
            version: "1.3.0",
            url: "/api/dispositivo/firmware/download"
        )
    }

    func obtenerClaveAprovisionamiento(req: Request) async throws -> ProvisionKeyResponse {
        try req.exigirRol(.admin)
        let key = Environment.get("DEVICE_API_KEY") ?? "dev-esp32-timbre-2026"
        let esquema = req.headers.first(name: "X-Forwarded-Proto") ?? (req.url.scheme ?? "https")
        let host = req.headers.first(name: "X-Forwarded-Host") ?? (req.headers.first(name: "Host") ?? "swiftyring.swiftydevs.dev")
        let apiBase = "\(esquema)://\(host)/api"

        return ProvisionKeyResponse(
            deviceApiKey: key,
            apiBase: apiBase
        )
    }

    func vistaUpdateFirmware(req: Request) async throws -> Response {
        let moduloOnline = await EstadoModulo.compartido.enLinea()
        let rutaBin = req.application.directory.publicDirectory + "firmware/swiftyring_timbre.bin"

        var infoArchivo = "No hay firmware cargado todavía"
        if let attrs = try? FileManager.default.attributesOfItem(atPath: rutaBin),
           let tamano = attrs[.size] as? Int64 {
            let df = DateFormatter()
            df.dateFormat = "yyyy-MM-dd HH:mm:ss"
            df.timeZone = FormatoTiempo.zonaColombia
            let fecha = (attrs[.modificationDate] as? Date).map { df.string(from: $0) } ?? "Desconocida"
            let mb = Double(tamano) / (1024.0 * 1024.0)
            infoArchivo = String(format: "swiftyring_timbre.bin (%.2f MB · %d bytes)<br>Última actualización: %@", mb, tamano, fecha)
        }

        let exito = req.query[String.self, at: "exito"] == "1"
        let otaDisparada = req.query[String.self, at: "ota"] == "1"
        let bytesSubidos = req.query[Int.self, at: "bytes"] ?? 0

        var bannerHtml = ""
        if exito {
            let kb = bytesSubidos / 1024
            let msgOta = otaDisparada ? " · Orden de actualización OTA enviada al módulo físico." : ""
            bannerHtml = "<div class=\"alert success\" style=\"display:block;\">✓ Firmware subido correctamente (\(kb) KB)\(msgOta)</div>"
        }

        let html = """
        <!DOCTYPE html>
        <html lang="es">
        <head>
            <meta charset="UTF-8">
            <meta name="viewport" content="width=device-width, initial-scale=1.0">
            <title>SwiftyRing · Actualizador de Firmware</title>
            <style>
                :root {
                    --bg: #0C0E12;
                    --card: #151921;
                    --card-border: #222936;
                    --accent: #E5A93C;
                    --text: #F3F4F6;
                    --muted: #9CA3AF;
                    --success: #10B981;
                    --danger: #EF4444;
                }
                * { box-sizing: border-box; margin: 0; padding: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
                body { background: var(--bg); color: var(--text); display: flex; justify-content: center; align-items: center; min-height: 100vh; padding: 20px; }
                .container { width: 100%; max-width: 540px; background: var(--card); border: 1px solid var(--card-border); border-radius: 20px; padding: 32px; box-shadow: 0 20px 40px rgba(0,0,0,0.6); }
                .header { display: flex; align-items: center; justify-content: space-between; margin-bottom: 20px; }
                .logo-area { display: flex; align-items: center; gap: 10px; }
                .logo-dot { width: 14px; height: 14px; background: var(--accent); border-radius: 50%; box-shadow: 0 0 12px var(--accent); }
                .title { font-size: 20px; font-weight: 700; color: #fff; }
                .badge { padding: 4px 12px; border-radius: 999px; font-size: 12px; font-weight: 600; display: inline-flex; align-items: center; gap: 6px; }
                .badge.online { background: rgba(16, 185, 129, 0.15); color: var(--success); border: 1px solid rgba(16, 185, 129, 0.3); }
                .badge.offline { background: rgba(239, 68, 68, 0.15); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.3); }
                .info-box { background: rgba(255, 255, 255, 0.03); border: 1px solid var(--card-border); border-radius: 12px; padding: 14px 16px; margin-bottom: 24px; font-size: 13px; color: var(--muted); line-height: 1.5; }
                .info-box strong { color: var(--text); }
                .dropzone { border: 2px dashed var(--card-border); border-radius: 14px; padding: 36px 20px; text-align: center; cursor: pointer; transition: all 0.2s ease; margin-bottom: 20px; position: relative; }
                .dropzone:hover, .dropzone.dragover { border-color: var(--accent); background: rgba(229, 169, 60, 0.05); }
                .dropzone input[type="file"] { position: absolute; inset: 0; width: 100%; height: 100%; opacity: 0; cursor: pointer; }
                .upload-icon { font-size: 36px; color: var(--accent); margin-bottom: 10px; display: block; }
                .dropzone p { font-size: 14px; color: var(--muted); }
                .file-selected { margin-top: 10px; font-size: 14px; font-weight: 600; color: var(--accent); word-break: break-all; }
                .form-group { margin-bottom: 16px; }
                label { display: block; font-size: 13px; font-weight: 600; margin-bottom: 6px; color: var(--muted); }
                input[type="password"], input[type="text"] { width: 100%; background: #0E1116; border: 1px solid var(--card-border); border-radius: 10px; padding: 12px 14px; color: #fff; font-size: 14px; outline: none; }
                input[type="password"]:focus, input[type="text"]:focus { border-color: var(--accent); }
                .checkbox-row { display: flex; align-items: center; gap: 10px; margin-bottom: 24px; font-size: 14px; cursor: pointer; color: var(--text); }
                .checkbox-row input { width: 18px; height: 18px; accent-color: var(--accent); }
                .btn { width: 100%; background: var(--accent); color: #0C0E12; border: none; border-radius: 12px; padding: 14px; font-size: 15px; font-weight: 700; cursor: pointer; transition: opacity 0.2s; }
                .btn:hover { opacity: 0.92; }
                .btn:disabled { opacity: 0.5; cursor: not-allowed; }
                .progress-wrap { display: none; margin-top: 20px; }
                .progress-bar-bg { width: 100%; height: 8px; background: #222936; border-radius: 4px; overflow: hidden; margin-top: 8px; }
                .progress-bar-fill { height: 100%; width: 0%; background: var(--accent); transition: width 0.1s linear; }
                .alert { padding: 12px 16px; border-radius: 10px; font-size: 13px; margin-bottom: 20px; line-height: 1.4; }
                .alert.success { background: rgba(16, 185, 129, 0.15); color: #34D399; border: 1px solid rgba(16, 185, 129, 0.3); }
                .alert.error { background: rgba(239, 68, 68, 0.15); color: #F87171; border: 1px solid rgba(239, 68, 68, 0.3); }
                .footer-links { margin-top: 20px; text-align: center; font-size: 12px; color: var(--muted); }
                .footer-links a { color: var(--accent); text-decoration: none; }
            </style>
        </head>
        <body>
            <div class="container">
                <div class="header">
                    <div class="logo-area">
                        <div class="logo-dot"></div>
                        <h1 class="title">SwiftyRing OTA</h1>
                    </div>
                    <span class="badge \(moduloOnline ? "online" : "offline")">
                        ● \(moduloOnline ? "MÓDULO ONLINE" : "MÓDULO OFFLINE")
                    </span>
                </div>

                \(bannerHtml)
                <div id="dynamicAlert" class="alert" style="display:none;"></div>

                <div class="info-box">
                    <strong>Firmware actual en el servidor:</strong><br>
                    \(infoArchivo)
                </div>

                <form id="uploadForm" action="/update_firmware" method="POST" enctype="multipart/form-data">
                    <div class="dropzone" id="dropzone">
                        <input type="file" id="firmwareInput" name="firmware" accept=".bin" required>
                        <span class="upload-icon">⚡</span>
                        <p><strong>Haz clic o arrastra aquí tu archivo .bin</strong></p>
                        <p style="font-size: 12px; margin-top: 4px;">swiftyring_timbre.bin (ESP32-C3)</p>
                        <div id="fileSelected" class="file-selected" style="display:none;"></div>
                    </div>

                    <div class="form-group">
                        <label for="claveAdmin">Clave de Autorización (DEVICE_API_KEY)</label>
                        <input type="password" id="claveAdmin" name="claveAdmin" placeholder="Opcional si ya está configurada en .env">
                    </div>

                    <label class="checkbox-row">
                        <input type="checkbox" name="notificarOta" value="true" checked>
                        <span>Notificar y flashear módulo físico inmediatamente por OTA</span>
                    </label>

                    <button type="submit" id="btnSubmit" class="btn">Subir Firmware y Ejecutar OTA</button>

                    <div id="progressWrap" class="progress-wrap">
                        <div style="display: flex; justify-content: space-between; font-size: 12px; color: var(--muted);">
                            <span>Subiendo firmware al servidor...</span>
                            <span id="progressText">0%</span>
                        </div>
                        <div class="progress-bar-bg">
                            <div id="progressBar" class="progress-bar-fill"></div>
                        </div>
                    </div>
                </form>

                <div class="footer-links">
                    <a href="/api/dispositivo/firmware/download" download>Descargar firmware actual (.bin)</a>
                </div>
            </div>

            <script>
                const input = document.getElementById('firmwareInput');
                const fileSelected = document.getElementById('fileSelected');
                const dropzone = document.getElementById('dropzone');
                const form = document.getElementById('uploadForm');
                const btn = document.getElementById('btnSubmit');
                const progressWrap = document.getElementById('progressWrap');
                const progressBar = document.getElementById('progressBar');
                const progressText = document.getElementById('progressText');
                const alertBox = document.getElementById('dynamicAlert');

                input.addEventListener('change', (e) => {
                    if (input.files.length > 0) {
                        const file = input.files[0];
                        const mb = (file.size / (1024 * 1024)).toFixed(2);
                        fileSelected.textContent = `Archivo: ${file.name} (${mb} MB)`;
                        fileSelected.style.display = 'block';
                    }
                });

                ['dragenter', 'dragover'].forEach(name => {
                    dropzone.addEventListener(name, (e) => { e.preventDefault(); dropzone.classList.add('dragover'); });
                });
                ['dragleave', 'drop'].forEach(name => {
                    dropzone.addEventListener(name, (e) => { e.preventDefault(); dropzone.classList.remove('dragover'); });
                });

                form.addEventListener('submit', (e) => {
                    if (!window.fetch || !window.FormData) return;
                    e.preventDefault();

                    if (!input.files || input.files.length === 0) {
                        alert('Selecciona un archivo .bin primero');
                        return;
                    }

                    btn.disabled = true;
                    btn.textContent = 'Procesando...';
                    progressWrap.style.display = 'block';
                    alertBox.style.display = 'none';

                    const formData = new FormData(form);
                    const xhr = new XMLHttpRequest();
                    xhr.open('POST', '/update_firmware', true);
                    xhr.setRequestHeader('Accept', 'application/json');

                    xhr.upload.onprogress = (evt) => {
                        if (evt.lengthComputable) {
                            const pct = Math.round((evt.loaded / evt.total) * 100);
                            progressBar.style.width = pct + '%';
                            progressText.textContent = pct + '%';
                        }
                    };

                    xhr.onload = () => {
                        btn.disabled = false;
                        btn.textContent = 'Subir Firmware y Ejecutar OTA';
                        if (xhr.status >= 200 && xhr.status < 300) {
                            try {
                                const data = JSON.parse(xhr.responseText);
                                alertBox.className = 'alert success';
                                alertBox.innerHTML = `✓ ${data.mensaje || 'Firmware cargado exitosamente.'}`;
                                alertBox.style.display = 'block';
                            } catch (_) {
                                alertBox.className = 'alert success';
                                alertBox.textContent = '✓ Firmware actualizado correctamente.';
                                alertBox.style.display = 'block';
                            }
                        } else {
                            try {
                                const err = JSON.parse(xhr.responseText);
                                alertBox.className = 'alert error';
                                alertBox.textContent = `Error: ${err.reason || err.mensaje || xhr.statusText}`;
                                alertBox.style.display = 'block';
                            } catch (_) {
                                alertBox.className = 'alert error';
                                alertBox.textContent = `Error del servidor (${xhr.status})`;
                                alertBox.style.display = 'block';
                            }
                        }
                    };

                    xhr.onerror = () => {
                        btn.disabled = false;
                        btn.textContent = 'Subir Firmware y Ejecutar OTA';
                        alertBox.className = 'alert error';
                        alertBox.textContent = 'Error de red al subir el archivo.';
                        alertBox.style.display = 'block';
                    };

                    xhr.send(formData);
                });
            </script>
        </body>
        </html>
        """

        return Response(
            status: .ok,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            body: .init(string: html)
        )
    }

    func procesarUploadFirmware(req: Request) async throws -> Response {
        let dto = try req.content.decode(FirmwareUploadDTO.self)

        if let esperada = Environment.get("DEVICE_API_KEY"), !esperada.isEmpty {
            if let recibida = dto.claveAdmin, !recibida.isEmpty {
                guard recibida == esperada else {
                    throw Abort(.unauthorized, reason: "Clave de autorización incorrecta")
                }
            }
        }

        let nombre = dto.firmware.filename.lowercased()
        guard nombre.hasSuffix(".bin") else {
            throw Abort(.badRequest, reason: "El archivo debe tener extensión .bin")
        }

        let datos = Data(dto.firmware.data.readableBytesView)
        guard !datos.isEmpty else {
            throw Abort(.badRequest, reason: "El archivo recibido está vacío")
        }

        let dirFirmware = req.application.directory.publicDirectory + "firmware"
        try FileManager.default.createDirectory(atPath: dirFirmware, withIntermediateDirectories: true)
        let rutaDestino = dirFirmware + "/swiftyring_timbre.bin"
        try datos.write(to: URL(fileURLWithPath: rutaDestino))

        var otaNotificada = false
        if dto.notificarOta == "true" || dto.notificarOta == "on" || dto.notificarOta == "1" {
            let esquema = req.headers.first(name: "X-Forwarded-Proto") ?? (req.url.scheme ?? "https")
            let host = req.headers.first(name: "X-Forwarded-Host") ?? (req.headers.first(name: "Host") ?? "swiftyring.swiftydevs.dev")
            let urlDescarga = "\(esquema)://\(host)/api/dispositivo/firmware/download"
            await EstadoModulo.compartido.ordenarOta(url: urlDescarga)
            otaNotificada = true
        }

        struct UploadResult: Content {
            let status: String
            let mensaje: String
            let bytes: Int
            let otaNotificada: Bool
        }

        let resultado = UploadResult(
            status: "ok",
            mensaje: otaNotificada
                ? "Firmware guardado exitosamente (\(datos.count / 1024) KB). Orden OTA enviada al módulo físico."
                : "Firmware guardado exitosamente (\(datos.count / 1024) KB).",
            bytes: datos.count,
            otaNotificada: otaNotificada
        )

        if req.headers.first(name: "Accept")?.contains("application/json") == true ||
           req.headers.first(name: "X-Requested-With") == "XMLHttpRequest" {
            return try await resultado.encodeResponse(for: req)
        }

        return req.redirect(to: "/update_firmware?exito=1&bytes=\(datos.count)&ota=\(otaNotificada ? 1 : 0)")
    }

    func descargarFirmware(req: Request) async throws -> Response {
        let posiblesRutas = [
            Environment.get("FIRMWARE_BIN_PATH"),
            req.application.directory.publicDirectory + "firmware/swiftyring_timbre.bin",
            req.application.directory.workingDirectory + "firmware/swiftyring_timbre.bin",
            req.application.directory.workingDirectory + "../firmware/timbre-idf/build/swiftyring_timbre.bin"
        ].compactMap { $0 }

        guard let rutaValida = posiblesRutas.first(where: { FileManager.default.fileExists(atPath: $0) }) else {
            throw Abort(.notFound, reason: "No hay binario de firmware compilado disponible en el servidor")
        }

        return req.fileio.streamFile(at: rutaValida)
    }

    /// RF-17: bitácora de lo que sonó en el colegio, venga del horario
    /// automático (RF-31) o del botón físico (RF-15).
    func reportarActivacion(req: Request) async throws -> HTTPStatus {
        await EstadoModulo.compartido.registrarContacto()
        let datos = try req.content.decode(ReporteActivacionRequest.self)

        guard let tipo = TipoActivacion(rawValue: datos.tipo),
              tipo == .automatico || tipo == .manualFisico
        else {
            throw Abort(.badRequest, reason: "Tipo inválido: el módulo solo reporta automatico o manual_fisico")
        }

        let haceSeg = max(0, datos.ocurridoHaceSeg ?? 0)
        let activacion = ActivacionTimbre(
            tipo: tipo,
            ocurridoAt: Date().addingTimeInterval(-Double(haceSeg)),
            horarioTimbreID: datos.horarioTimbreId,
            duracionSeg: datos.duracionSeg
        )
        try await activacion.create(on: req.db)

        if haceSeg <= Self.ventanaNotificacionesSeg {
            _ = try await NotificadorProximaClase.generar(
                activacionID: activacion.requireID(),
                on: req
            )
        }

        return .created
    }

    /// RF-22: el módulo detectó y confirmó un sismo. Queda el evento (RF-23),
    /// su activación de timbre y las notificaciones de clase si es reciente.
    func reportarSismo(req: Request) async throws -> HTTPStatus {
        await EstadoModulo.compartido.registrarContacto()
        let datos = try req.content.decode(ReporteSismoRequest.self)

        guard datos.intensidadG > 0, datos.duracionMs > 0 else {
            throw Abort(.badRequest, reason: "Intensidad y duración deben ser positivas")
        }

        let haceSeg = max(0, datos.ocurridoHaceSeg ?? 0)
        let ocurridoAt = Date().addingTimeInterval(-Double(haceSeg))
        let timbreActivado = datos.timbreActivado ?? true

        let evento = EventoSismico(
            intensidadG: datos.intensidadG,
            duracionMs: datos.duracionMs,
            ocurridoAt: ocurridoAt,
            timbreActivado: timbreActivado
        )

        try await req.db.transaction { db in
            if timbreActivado {
                let activacion = ActivacionTimbre(tipo: .sismico, ocurridoAt: ocurridoAt, duracionSeg: 30)
                try await activacion.create(on: db)
                evento.activacionID = try activacion.requireID()
            }
            try await evento.create(on: db)
        }

        // RF-20: el administrador se entera aunque el sismo no haya activado el
        // timbre. La ventana es más ancha que la de las clases porque tres
        // minutos de retraso no vuelven irrelevante una emergencia; pero
        // tampoco es infinita, para que un módulo que estuvo días sin conexión
        // no despierte a nadie con una ráfaga de alarmas viejas.
        if haceSeg <= Self.ventanaAvisoSismoSeg {
            await NotificadorSismo.avisar(evento, on: req)
        }

        if timbreActivado, haceSeg <= Self.ventanaNotificacionesSeg,
           let activacionID = evento.activacionID {
            _ = try await NotificadorProximaClase.generar(activacionID: activacionID, on: req)
        }

        return .created
    }

    /// Canal WebSocket persistente con el módulo ESP32. Reemplaza el polling
    /// de comandos: el servidor le empuja las órdenes al instante.
    func canal(req: Request, ws: WebSocket) async {
        req.logger.info("módulo ESP32 conectado por WebSocket")
        await EstadoModulo.compartido.registrarConexion(ws)

        // El módulo acaba de conectar: que sincronice el horario por si
        // cambió mientras estaba desconectado (sincronización silenciosa).
        await EstadoModulo.compartido.notificarSincronizacion(motivo: "inicio")

        ws.onClose.whenComplete { _ in
            Task {
                await EstadoModulo.compartido.desregistrarConexion()
                req.logger.info("módulo ESP32 desconectado del WebSocket")
            }
        }
    }
}
