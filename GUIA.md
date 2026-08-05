# Guía de trabajo

Cómo agregar cosas a este proyecto sin tener que entender toda la arquitectura.

Está pensada para copiar y pegar. Si algo no está aquí, probablemente no hace falta todavía.

---

## La idea, en una frase

**Es un edificio con recepción y dos oficinas.**

La recepción (`core/`) tiene la entrada con contraseña y el directorio de oficinas. Las oficinas (`modules/`) son SwiftyRing y Control Baños. La recepción no sabe qué hay dentro de cada oficina: solo tiene el cartelito que cada oficina escribió sobre sí misma.

```
app/lib/
├── core/       ← la recepción. Compartida. Ya está hecha.
├── modules/
│   ├── timbre_escolar/    ← oficina 1
│   └── proyecto_banos/    ← oficina 2
└── main.dart   ← quien cuelga el directorio
```

**La única regla:** tu módulo puede usar `core/`. No puede usar el otro módulo, y `core/` no puede usar el tuyo.

Para comprobarlo:

```bash
cd app && ./tool/check_module_isolation.sh
```

---

## Dónde trabaja cada equipo

| Equipo | Su carpeta en la app | Su parte del backend |
|---|---|---|
| Miguel — Timbre Escolar | `app/lib/modules/timbre_escolar/` | `backend/SwiftyRing/Sources/SwiftyRing/Modules/TimbreEscolar/` |
| Jhoan, Isabel, Juan Esteban — Control Baños | `app/lib/modules/proyecto_banos/` | Repositorio aparte: `controlbanos-backend` |

Nadie edita `core/` sin avisar al otro equipo. Es de los dos.

---

## Receta 1 · Agregar una pantalla a mi módulo

Ejemplo: la pantalla de horarios del timbre.

**Paso 1.** Crear el archivo:

`app/lib/modules/timbre_escolar/presentation/pages/horarios_page.dart`

```dart
import 'package:flutter/material.dart';
import 'package:swiftyring/core/theme/app_theme.dart';

class HorariosPage extends StatelessWidget {
  const HorariosPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.fondo,
      appBar: AppBar(title: const Text('Horarios')),
      body: const Center(child: Text('Aquí van los horarios')),
    );
  }
}
```

**Paso 2.** Registrar la ruta en `timbre_escolar_routes.dart`, dentro de `rutas:`

```dart
GoRoute(
  path: '/timbre/horarios',
  builder: (context, state) => const HorariosPage(),
),
```

**Paso 3.** Navegar hasta ella desde donde quieras:

```dart
context.push('/timbre/horarios');
```

Eso es todo. No hay que tocar `core/` ni `main.dart`.

---

## Receta 2 · Saber quién está usando la app

En cualquier widget, cambiá `StatelessWidget` por `ConsumerWidget`:

```dart
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:swiftyring/core/auth/auth_provider.dart';

class MiPantalla extends ConsumerWidget {
  const MiPantalla({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final sesion = ref.watch(authProvider).session;
    if (sesion == null) return const SizedBox.shrink();

    return Text('Hola ${sesion.nombre}, sos ${sesion.rol.etiqueta}');
  }
}
```

Lo que tenés disponible: `sesion.nombre`, `sesion.email`, `sesion.rol`, `sesion.primerNombre`.

**No pidas contraseña en tu módulo.** El login ya pasó; la identidad te llega resuelta.

---

## Receta 3 · Mostrar u ocultar algo según el rol

```dart
if (sesion.rol.puedeAdministrar) {
  // solo el admin
}

if (sesion.rol == RolUsuario.profesor) {
  // solo profesores
}
```

Los tres roles son `admin`, `operador` y `profesor`. Para Control Baños: "docente" es `profesor` y "coordinador" es `admin`.

---

## Receta 4 · Llamar a la API

```dart
import 'package:swiftyring/core/auth/auth_provider.dart';

final dio = ref.read(apiProvider).dio;
final respuesta = await dio.get('/timbre/horarios');
```

El token ya va puesto en la cabecera: no hay que agregarlo. La URL base ya apunta al backend, así que las rutas se escriben relativas (`/timbre/horarios`, no `http://...`).

Si el backend responde un error, `respuesta.statusCode` te lo dice y `respuesta.data['reason']` trae el mensaje.

---

## Receta 5 · Agregar una tabla al backend (Vapor)

**Paso 1.** El modelo, en `Modules/TimbreEscolar/HorarioTimbre.swift`:

```swift
import Fluent
import Foundation

final class HorarioTimbre: Model, @unchecked Sendable {
    static let schema = "horario_timbres"

    @ID(key: .id) var id: UUID?
    @Field(key: "etiqueta") var etiqueta: String
    @Field(key: "duracion_seg") var duracionSeg: Int

    init() { }
}
```

**Paso 2.** La migración, en el mismo sitio:

```swift
import Fluent

struct CreateHorarioTimbre: AsyncMigration {
    func prepare(on database: any Database) async throws {
        try await database.schema("horario_timbres")
            .id()
            .field("etiqueta", .string, .required)
            .field("duracion_seg", .int, .required)
            .create()
    }

    func revert(on database: any Database) async throws {
        try await database.schema("horario_timbres").delete()
    }
}
```

**Paso 3.** Registrarla en `Modules/TimbreEscolar/TimbreEscolar.swift`:

```swift
static var migraciones: [any AsyncMigration] {
    [CreateHorarioTimbre()]
}
```

**Paso 4.** Aplicarla:

```bash
cd backend/SwiftyRing
swift run SwiftyRing migrate --yes --env development
```

---

## Receta 6 · Agregar un endpoint al backend

**Paso 1.** El controlador, en `Modules/TimbreEscolar/HorariosController.swift`:

```swift
import Vapor
import Fluent

struct HorariosController: RouteCollection {
    func boot(routes: any RoutesBuilder) throws {
        // Todo lo protegido cuelga del middleware: sin token no se entra.
        let protegidas = routes.grouped("api", "timbre")
            .grouped(SwiftyRingAuthMiddleware())

        protegidas.get("horarios", use: listar)
    }

    func listar(req: Request) async throws -> [HorarioTimbre] {
        let payload = try req.requireSwiftyRingPayload()
        // payload.rol, payload.nombre, payload.usuarioID están disponibles

        return try await HorarioTimbre.query(on: req.db).all()
    }
}
```

**Paso 2.** Registrarlo en `TimbreEscolar.swift`:

```swift
static func registrarRutas(_ app: Application) throws {
    try app.register(collection: HorariosController())
}
```

---

## Cómo correr todo

**Backend** (hace falta Postgres.app abierto):

```bash
cd backend/SwiftyRing && swift run SwiftyRing serve --env development --hostname 127.0.0.1 --port 8080
```

**App:**

```bash
cd app && flutter run
```

**Usuario de prueba:** `andrea@santasofia.edu.co` / `Admin123*` (rol admin, solo para desarrollo).

**A qué servidor le habla la app.** Ya no está escrito en el código: se elige
desde el chip **"Ajustes de red"** de la pantalla de bienvenida, o desde
Configuración si ya entraste. Recién instalada apunta al computador de
desarrollo (`10.0.2.2:8080` en el emulador de Android, `127.0.0.1:8080` en el
resto), así que para trabajar no hay que tocar nada.

Se escribe solo la dirección del servidor —la app le agrega `/api` sola— y el
botón *Probar conexión* comprueba que ahí hay de verdad un servidor de
SwiftyRing antes de guardar. Si la dirección no es `https://`, avisa: RNF-06
pide HTTPS, y una contraseña que viaja sin cifrar la lee cualquiera en la red
del colegio. No avisa cuando apuntás a la red local, donde no hay certificado
posible.

**Antes de entregar:**

```bash
cd app && flutter analyze && flutter test && ./tool/check_module_isolation.sh
```

---

## Receta 7 · Encender las notificaciones push (FCM)

El código de las notificaciones ya está completo en los dos lados: cuando suena
el timbre, el backend calcula la próxima clase de cada profesor, la guarda y
trata de enviarla al teléfono. Lo único que falta es **crear el proyecto de
Firebase**, porque eso necesita tu cuenta de Google y no se puede automatizar.

Mientras no lo hagas, todo funciona igual: las notificaciones se calculan y se
registran, y en el historial aparecen con "enviada: false". El timbre nunca
depende de que Google responda.

### Estado actual (agosto 2026)

**Ya está hecho todo lo de desarrollo.** Los pasos de abajo quedan escritos
porque hay que repetirlos el día que se cree un proyecto nuevo (otro colegio,
otra cuenta), no porque falten:

- Proyecto de Firebase `swiftyring`, con la app Android y la iOS registradas,
  las dos con el identificador `dev.swiftydevs.swiftyring`.
- `google-services.json`, `GoogleService-Info.plist` y `firebase_options.dart`
  generados, y el plugin de Google conectado a Gradle.
- Proyecto de Xcode con los entitlements de APNs y el `UIBackgroundModes`.
- Llave APNs subida a Firebase (Key ID `KWWAGT57D6`, Team ID `WFLZKCYTXB`).
- Credencial del backend en `keys/fcm-cuenta-servicio.json`, con
  `FCM_CREDENTIALS_PATH` puesta en `.env.development`. Verificada contra Google:
  entrega token de acceso y FCM acepta las peticiones.

**Lo que falta:** repetir el paso 3 en el servidor de producción, y probar en un
teléfono de verdad (paso 4).

El identificador de la app, que la consola pide tanto para Android como para
iOS, es el mismo en los dos: **`dev.swiftydevs.swiftyring`**.

### Paso 1 · Crear el proyecto

En [console.firebase.google.com](https://console.firebase.google.com): crear un
proyecto (por ejemplo `swiftyring-santasofia`). No hace falta Google Analytics.

### Paso 2 · Conectar la app

```bash
firebase login
```

```bash
cd app && ~/.pub-cache/bin/flutterfire configure
```

(La segunda línea es larga porque `~/.pub-cache/bin` no está en el PATH. Para
poder escribir solo `flutterfire`, agregá `export PATH="$PATH:$HOME/.pub-cache/bin"`
al final de tu `~/.zshrc`.)

Elegí el proyecto y marcá Android e iOS. El comando genera
`lib/firebase_options.dart`, `android/app/google-services.json` y
`ios/Runner/GoogleService-Info.plist`, y de paso agrega solo el plugin de
Google a los archivos de Gradle. Con eso la app ya consigue su token y lo
registra sola al entrar al módulo.

Esos tres archivos **sí se suben a git**. No son secretos: van dentro del APK,
que cualquiera puede abrir. El secreto es el del paso 3.

Para iOS falta además la llave de **APNs** (Apple Push Notification service),
que es lo que le da a Firebase permiso para tocarle la puerta a los iPhone:

1. En [developer.apple.com](https://developer.apple.com) > Certificates,
   Identifiers & Profiles > **Keys** > `+`, marcar *Apple Push Notifications
   service (APNs)* y descargar el `.p8`. **Solo se puede descargar una vez.**
2. En Firebase: Configuración del proyecto > **Cloud Messaging** > sección iOS >
   *Subir* la llave APNs. Pide el `.p8`, el **Key ID** (sale en la misma página
   de Apple) y el **Team ID** (arriba a la derecha en developer.apple.com; el de
   este proyecto ya está en Xcode: `WFLZKCYTXB`).

Esto necesita la cuenta de Apple Developer de pago. Sin la llave APNs, Android
recibe avisos y iOS no: la app iOS no falla, simplemente nunca consigue token.

### Paso 3 · Darle la credencial al backend

En la consola de Firebase: **Configuración del proyecto > Cuentas de servicio >
Generar nueva clave privada**. Se descarga un `.json`. Guardalo así:

```bash
mv ~/Downloads/swiftyring-*.json backend/SwiftyRing/keys/fcm-cuenta-servicio.json
```

La variable que lo apunta ya está puesta en `backend/SwiftyRing/.env.development`:

```
FCM_CREDENTIALS_PATH=keys/fcm-cuenta-servicio.json
```

En el servidor hay que agregar esa misma línea a `.env.production` y dejar el
`.json` en `backend/SwiftyRing/keys/`; el `docker-compose.prod.yml` ya monta esa
carpeta dentro del contenedor.

Ese archivo **es un secreto**: quien lo tenga puede mandar notificaciones en
nombre del colegio. Ya está en `.gitignore`, igual que la llave privada RS256.

Al reiniciar el servidor el log tiene que decir
`FCM: credencial cargada para el proyecto …`. Si dice
`sin FCM_CREDENTIALS_PATH`, la ruta está mal.

### Paso 4 · Probar que llega

Con un profesor que tenga clase más tarde hoy, entrá a la app con su usuario
(para que registre el token), y desde el admin tocá **TIMBRAR**. El aviso debe
llegar al teléfono y, en el historial, esa notificación pasa a "enviada: true".

Ojo con dos cosas al probar:

- **El emulador de Android sirve, el simulador de iPhone no.** El simulador no
  tiene APNs; para iOS hace falta un iPhone de verdad conectado.
- Si la app está abierta en pantalla, el aviso no sale como notificación del
  sistema sino como la barra de colores dentro de la app: eso lo hace
  `enganche_push.dart` a propósito, y es señal de que funcionó.

---

## Qué NO tocar

| No toques | Por qué |
|---|---|
| `app/lib/core/` | Es compartido. Cambiarlo afecta al otro equipo |
| El enum de roles | Es contrato con el backend y con el otro módulo |
| Los claims del JWT | El otro backend los lee; quitar uno rompe su módulo |
| `keys/jwt_private.pem` | Es la llave de firma. No se copia, no se sube, no se comparte |
| La carpeta del otro módulo | Ni para leerla en un `import` |

Si necesitás algo de esa lista, se acuerda por escrito entre los dos equipos y se actualiza `Docs/04-Integracion/Contrato_Integracion_Timbre_ControlBanos.md`.

---

## Para el equipo de Control Baños

Lo que ya tenés resuelto y no hay que construir:

- El login. Un docente entra una vez y su identidad les llega en `ref.watch(authProvider).session`.
- El rol. `admin` es coordinador, `profesor` es docente. El `operador` no entra a su módulo y su tarjeta ni aparece en el lanzador.
- El token para llamar a su backend. Va en la cabecera automáticamente.

Su backend es un proyecto Vapor **aparte**, en su propio repositorio. Para validar los tokens que emite el backend del timbre:

```
GET http://127.0.0.1:8080/.well-known/jwks.json
```

o si prefieren pegar la llave en un archivo de configuración:

```
GET http://127.0.0.1:8080/.well-known/jwt-public-key.pem
```

Con esa llave **pueden verificar** tokens, pero no pueden emitirlos. Es a propósito.

En la base de datos les corresponde el schema `banos`, con sus cinco tablas. El modelo está en `Docs/04-Integracion/modelo_datos_completo.dbml`. Sobre el schema del timbre tienen solo lectura, y solo de dos tablas.

Sus requerimientos están en `Docs/03-Control-Banos/`.

---

## Si algo se rompe

| Síntoma | Causa más probable |
|---|---|
| Error de conexión al entrar | El backend no está corriendo. Probá `curl http://127.0.0.1:8080/` |
| La app arranca y se queda en el círculo de carga | El backend no responde, o falta la llave RS256 en `keys/` |
| "Correo o contraseña incorrectos" con datos buenos | La base no tiene el admin sembrado. Corré `migrate` |
| El script de aislamiento falla | Alguien importó el otro módulo. El mensaje dice qué archivo |
| Cambié algo en `core/` y se rompió otra cosa | Por eso `core/` no se toca sin avisar |

---

*Guía de trabajo · Proyecto de grado SENA CDITI · I.E. Santa Sofía · 2026*
