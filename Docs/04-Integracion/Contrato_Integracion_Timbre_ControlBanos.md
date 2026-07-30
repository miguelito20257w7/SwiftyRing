# Contrato de integración — Sistema de Timbre Escolar ↔ Control Baños SS

**Versión 1.0 · Julio de 2026 · I.E. Santa Sofía (Dosquebradas, Risaralda)**

Este documento define la frontera técnica entre los dos módulos del proyecto de grado. Es de cumplimiento obligatorio para ambos equipos: cualquier cambio que cruce la frontera se acuerda aquí primero y se implementa después.

| | Sistema de Timbre Escolar | Control Baños SS |
|---|---|---|
| **Equipo** | Miguel Ángel Salazar García | Jhoan Santiago Chalarca · Isabel Galeano · Juan Esteban Estrada |
| **Repositorio backend** | `timbre-escolar-backend` | `controlbanos-backend` |
| **Schema de PostgreSQL** | `public` | `banos` |
| **Rol de PostgreSQL** | `swiftyring` | `proyectobanos` |
| **Prefijo de API** | `/api` | `/api/banos` |
| **Carpeta en la app Flutter** | `lib/modules/timbre_escolar/` | `lib/modules/proyecto_banos/` |
| **Rol frente a la identidad** | Emisor (Auth Server) | Consumidor |

---

## 1. Principio rector

**Control Baños SS puede desaparecer por completo sin que el Sistema de Timbre Escolar deje de compilar, migrar o funcionar.**

Esto se verifica con dos operaciones que deben poder ejecutarse en cualquier momento sin efectos colaterales:

```sql
DROP SCHEMA banos CASCADE;
DROP ROLE proyectobanos;
```

```bash
rm -rf app/lib/modules/proyecto_banos/
flutter analyze   # debe pasar sin errores
flutter build apk # debe compilar
```

Si alguna de las dos rompe algo, el contrato está violado y hay que corregirlo, no documentarlo.

La relación es **asimétrica y unidireccional**: Control Baños depende del Timbre Escolar, nunca al revés.

---

## 2. Base de datos

### 2.1. Una sola base, dos schemas

Ambos sistemas comparten la misma base de datos PostgreSQL. La separación es por **schema**, no por base de datos:

```
Base de datos: swiftyring
├── schema public   → Timbre Escolar (usuarios, profesores, salones,
│                     materias, horario_timbres, bloques, activaciones...)
└── schema banos    → Control Baños SS (grupos, estudiantes, salidas,
                      alertas, configuracion)
```

El Timbre Escolar se queda en `public` tal como está hoy: no se migra nada, no se toca ninguna migración existente.

### 2.2. Creación del schema y el rol

Lo ejecuta **el dueño de la base (Miguel)**, una sola vez. El equipo de Control Baños no ejecuta DDL fuera de su schema.

```sql
-- 1. Rol de la aplicación Control Baños
CREATE ROLE proyectobanos WITH LOGIN PASSWORD '<password-fuerte>';

-- 2. Su schema, del que es dueño
CREATE SCHEMA banos AUTHORIZATION proyectobanos;

-- 3. Nadie más puede crear objetos en public
REVOKE CREATE ON SCHEMA public FROM PUBLIC;
REVOKE CREATE ON SCHEMA public FROM proyectobanos;

-- 4. Lectura puntual sobre las dos tablas de identidad, nada más
GRANT USAGE ON SCHEMA public TO proyectobanos;
GRANT SELECT ON public.usuarios   TO proyectobanos;
GRANT SELECT ON public.profesores TO proyectobanos;

-- 5. Que las tablas que yo cree en el futuro NO se le concedan solas
ALTER DEFAULT PRIVILEGES IN SCHEMA public
  REVOKE ALL ON TABLES FROM proyectobanos;

-- 6. Yo no tengo nada sobre su schema (y no lo necesito)
REVOKE ALL ON SCHEMA banos FROM swiftyring;
```

Verificación de que quedó bien (debe fallar con *permission denied*):

```sql
SET ROLE proyectobanos;
INSERT INTO public.usuarios (id, nombre, email, password_hash, rol)
  VALUES ('x','x','x@x.co','x','admin');   -- ERROR esperado
CREATE TABLE public.prueba (id int);        -- ERROR esperado
RESET ROLE;
```

### 2.3. Lo que esto protege y lo que no

**Protege de:** que su código borre, altere o corrompa filas y tablas del Timbre Escolar; que una migración suya mal escrita toque `public`; que un `DROP TABLE` accidental se lleve datos míos.

**No protege de:** un `ALTER TABLE` suyo con lock prolongado sobre una tabla grande, o agotar el pool de conexiones de PostgreSQL. Ambos sistemas comparten instancia, así que comparten recursos. Es un riesgo aceptado para el alcance del proyecto de grado; si se vuelve un problema, el siguiente paso es separar en dos bases de datos y comunicar todo por API.

### 2.4. Migraciones de Fluent

Cada backend Vapor lleva su propio registro de migraciones. Con schemas separados esto sale gratis **siempre que la conexión de Control Baños tenga el `search_path` correcto**, porque Fluent crea `_fluent_migrations` en el primer schema del `search_path`:

```sql
ALTER ROLE proyectobanos SET search_path TO banos;
```

Resultado: `public._fluent_migrations` (mío) y `banos._fluent_migrations` (suyo) son tablas distintas. Un `migrate --revert` de ellos jamás puede revertir una migración mía.

> **Esto hay que dejarlo montado antes de la primera migración de Control Baños.** Si su primera migración corre con `search_path = public`, sus tablas nacen en mi schema y desenredar eso después es doloroso.

### 2.5. Prohibición de foreign keys entre schemas

**No existe ninguna FK entre `banos` y `public`, en ninguna de las dos direcciones.**

Las columnas de Control Baños que apuntan a identidad del Timbre Escolar (`autorizado_por_usuario_id`, `director_usuario_id`, `cancelado_por_usuario_id`, `atendida_por_usuario_id`) guardan el UUID de `public.usuarios.id` como texto plano. La validación es de aplicación: el `usuario_id` sale del claim `sub` de un JWT ya verificado, así que no hace falta que la base lo garantice.

Las tres razones:

1. `DROP SCHEMA banos CASCADE` no deja ni un rastro en `public`.
2. Una fila de Control Baños nunca bloquea un `DELETE` sobre `public.usuarios`.
3. Su rol no necesita el privilegio `REFERENCES` sobre mis tablas.

Dentro del schema `banos` las FK sí son normales y obligatorias (`estudiantes.grupo_id → grupos.id`, `salidas.estudiante_id → estudiantes.id`, `alertas.salida_id → salidas.id`).

### 2.6. Snapshots en lugar de joins entre schemas

`salidas` guarda `autorizado_por_nombre` y `grupo_nombre` como copias del valor al momento de la salida. No es redundancia por descuido: es lo que permite que el historial (RF09) y los reportes (RF12) sigan siendo correctos si el estudiante cambia de grupo, si un docente se retira o si el schema `banos` se lee sin acceso a `public`.

Por la misma razón se descartó una tabla `matriculas`: para el alcance del piloto, `estudiantes.grupo_id` más el snapshot en `salidas` resuelve la historia sin una tabla extra.

---

## 3. Identidad y autenticación

### 3.1. Un solo login

El docente abre **una sola app** y escribe **una sola contraseña**. El Timbre Escolar es el único emisor de identidad; Control Baños nunca ve ni almacena contraseñas.

La tabla `banos.docentes` que aparecía en el documento de requerimientos v1.0 —con usuario y contraseña propios— **no se implementa**. Los docentes son filas de `public.usuarios` con `rol = 'profesor'`.

### 3.2. Cambio obligatorio: HS512 → RS256

Hoy el backend del Timbre Escolar firma con HMAC-SHA512 (`configure.swift`, `app.jwt.keys.add(hmac:)`). Con HMAC la llave de firma y la de verificación son la misma: si se la entrego a Control Baños para que valide tokens, también pueden **emitir** tokens, incluyendo uno con `rol: admin`. Con una base de datos compartida eso es inaceptable.

**Migración a RS256:**

| | Timbre Escolar | Control Baños SS |
|---|---|---|
| Llave privada | La tiene, firma con ella | Nunca la ve |
| Llave pública | La publica | La usa para verificar |

**Estado: implementado.** El par de llaves se genera con OpenSSL y se carga desde archivo, no desde una variable de entorno: un PEM es multilínea y meterlo en un `.env` obliga a escapar saltos de línea o a codificarlo en base64, dos formas fáciles de equivocarse al desplegar.

```bash
# desde backend/SwiftyRing/
openssl genrsa -out keys/jwt_private.pem 2048
openssl rsa -in keys/jwt_private.pem -pubout -out keys/jwt_public.pem
chmod 600 keys/jwt_private.pem
```

La privada está en `.gitignore`; **la pública sí se versiona**, porque es justo lo que hay que entregar. Las rutas se configuran con `JWT_PRIVATE_KEY_PATH` y `JWT_PUBLIC_KEY_PATH`.

El código vive en `Sources/SwiftyRing/Core/Auth/JWTConfig.swift`. Si no encuentra la llave, el servidor **no arranca**: es preferible a que levante emitiendo tokens que nadie puede verificar.

La llave pública se expone en dos formatos:

```
GET /.well-known/jwks.json          → JWKS estándar (para clientes de JWT)
GET /.well-known/jwt-public-key.pem → PEM plano (para pegar en configuración)
```

Ambos con `Cache-Control: public, max-age=3600`.

**Verificación hecha sobre el servidor real:**

| Prueba | Resultado |
|---|---|
| Verificar un token emitido, usando solo la llave pública | `Verified OK` |
| Verificar el mismo token con el claim `rol` alterado | `Verification failure` |
| Intentar firmar con la llave pública | `Could not find private key` |

Esa tercera fila es la razón de ser del cambio: con HMAC, entregar la llave de verificación era entregar también la de firma.

### 3.3. Claims del token

El payload actual (`SwiftyRingPayload.swift`) tiene `sub`, `exp` y `rol`. Para servir a los dos módulos hay que agregar `iss`, `aud`, `iat`, `nombre` y `email`:

```json
{
  "sub":    "9f1c…-uuid-de-usuarios.id",
  "nombre": "Andrea Ramírez",
  "email":  "andrea@santasofia.edu.co",
  "rol":    "profesor",
  "iss":    "timbre-escolar",
  "aud":    ["timbre", "banos"],
  "iat":    1785312000,
  "exp":    1785340800
}
```

`nombre` y `email` viajan en el token para que Control Baños pueda llenar `autorizado_por_nombre` sin consultar `public.usuarios` en cada autorización.

**Validaciones obligatorias del lado de Control Baños**, en este orden: firma RS256 contra la llave pública → `exp` no vencido → `iss == "timbre-escolar"` → `"banos"` presente en `aud` → `rol` dentro de los aceptados.

### 3.4. Roles

El enum `rol_usuario` del Timbre Escolar **no cambia**. Sigue siendo `admin | operador | profesor`. El mapeo acordado:

| Rol en Control Baños | Rol real en `public.usuarios` | Puede |
|---|---|---|
| Docente | `profesor` | Autorizar, cancelar y cerrar salidas de cualquier grupo; ver el historial |
| Coordinador | `admin` | Todo lo del docente, más reportes institucionales, alertas y configuración |
| — | `operador` | Sin acceso a Control Baños: el token se rechaza con 403 |

Consecuencia que el equipo debe tener presente: un coordinador entra a Control Baños como `admin`, y ese mismo rol le da permisos de administrador sobre el Timbre Escolar. Es una decisión tomada a conciencia para no tocar el enum compartido. Si más adelante estorba, la salida limpia es una tabla `banos.permisos (usuario_id, rol_banos)` en su propio schema, sin modificar nada mío.

### 3.5. Ciclo de vida de la sesión

- El token vence según `JWT_EXPIRATION_HOURS` del Timbre Escolar. Ambos módulos respetan el mismo `exp`.
- **Un solo login, un solo logout.** Si la sesión expira dentro del módulo de baños, la app entera vuelve a la pantalla de login: no existe una sesión parcial.
- El refresh lo maneja `core/auth`. El módulo de baños nunca llama a `/api/auth/refresh` por su cuenta; recibe el token vigente del `AuthService` compartido.

---

## 4. Contrato de API

### 4.1. Endpoints que el Timbre Escolar expone a Control Baños

| Método | Ruta | Quién | Devuelve |
|---|---|---|---|
| `POST` | `/api/auth/login` | Público | `{ token, usuario }` |
| `POST` | `/api/auth/refresh` | Token vigente | `{ token }` |
| `GET` | `/api/auth/me` | Token vigente | Usuario del token |
| `GET` | `/.well-known/jwks.json` | Público | Llave pública RS256 · **implementado** |
| `GET` | `/.well-known/jwt-public-key.pem` | Público | La misma llave en PEM · **implementado** |
| `GET` | `/api/profesores` | `admin` | Lista de docentes activos · **pendiente** |

Esa es la superficie completa. **No hay endpoints de escritura** hacia el Timbre Escolar desde Control Baños, y no se agregan sin actualizar este documento.

> **`GET /api/profesores` todavía no existe.** Depende de la tabla `profesores`, que aún no está migrada: hoy la única tabla creada es `usuarios`. Mientras tanto, Control Baños obtiene la identidad del docente de los claims `sub`, `nombre`, `email` y `rol` del propio token, que es lo que necesita para registrar una salida. El endpoint hace falta cuando quieran listar docentes que no son el que tiene la sesión abierta.

### 4.2. Endpoints propios de Control Baños

Todos bajo `/api/banos`, todos exigen JWT válido con `"banos"` en `aud`.

| Método | Ruta | RF | Descripción |
|---|---|---|---|
| `GET` | `/grupos` | RF02 | Grupos activos del año lectivo |
| `GET` | `/grupos/:id/estudiantes` | RF02 | Estudiantes del grupo con su estado actual (en salón / fuera) |
| `GET` | `/salidas/activas` | RF03 | Salidas `en_curso` con tiempo transcurrido |
| `POST` | `/salidas` | RF04, RF05, RF06 | Autoriza una salida. Valida el límite diario y responde 409 si se agotó |
| `PATCH` | `/salidas/:id/regreso` | RF08 | Registra el regreso y calcula `duracion_seg` |
| `PATCH` | `/salidas/:id/cancelar` | RF07 | Cancela con motivo obligatorio |
| `GET` | `/salidas` | RF09, RF10 | Historial con filtros de fecha, grupo, estudiante y búsqueda |
| `GET` | `/salidas/export` | RF11 | Exporta el historial en CSV o PDF |
| `GET` | `/reportes/resumen` | RF12 | Total del día, duración promedio, emergencias, salidas por día |
| `GET` | `/alertas` | — | Alertas pendientes (solo `admin`) |
| `GET`/`PUT` | `/configuracion` | — | Parámetros del sistema (solo `admin`) |

### 4.3. Errores acordados

| Código | Cuándo |
|---|---|
| `401` | Token ausente, mal firmado o vencido |
| `403` | Token válido pero `rol = operador`, o `"banos"` no está en `aud` |
| `409` | El estudiante agotó sus salidas normales del día (RF06) o ya tiene una salida `en_curso` |
| `422` | Cancelación sin motivo, regreso sobre una salida ya finalizada |

---

## 5. Aislamiento en la app Flutter

### 5.1. Estructura

```
lib/
├── core/                        ← compartido, propiedad del Timbre Escolar
│   ├── auth/                    ← login, sesión, roles, almacenamiento seguro
│   │   ├── domain/              ← AuthSession, RolUsuario, AuthRepository
│   │   ├── data/                ← datasource, DTOs, SessionStorage
│   │   ├── presentation/pages/  ← bienvenida, login, pantalla de carga
│   │   └── auth_provider.dart   ← estado de sesión de toda la app
│   ├── network/                 ← DioClient, interceptor del Bearer, TokenStore
│   ├── theme/
│   ├── router/                  ← crearRouter() y guardia de sesión
│   └── shared_widgets/
├── modules/
│   ├── timbre_escolar/          ← módulo propio
│   └── proyecto_banos/          ← módulo de Control Baños — 100 % borrable
└── main.dart                    ← raíz de composición: monta los módulos
```

> **Estado:** implementado. La estructura ya existe y está verificada con `flutter analyze`, la suite de pruebas y el script de aislamiento.

### 5.2. Reglas de dependencia

| Desde | Hacia | |
|---|---|---|
| `modules/proyecto_banos/` | `core/` | Permitido |
| `modules/proyecto_banos/` | `modules/timbre_escolar/` | **Prohibido** |
| `core/` | `modules/proyecto_banos/` | **Prohibido** |
| `modules/timbre_escolar/` | `modules/proyecto_banos/` | **Prohibido** |

`core/` no conoce la existencia de los módulos. Nada en `core/` ni en `timbre_escolar/` puede contener la cadena `proyecto_banos`.

### 5.3. Punto de contacto único

El módulo de baños se engancha en **un solo lugar**: `main.dart`, la raíz de composición.

Es deliberado que sea ahí y no en `core/router/`. Si `core/` importara las rutas del módulo, `core/` dependería de `proyecto_banos` y la regla de la sección 5.2 quedaría rota por el propio andamiaje. La solución es que `core/` exponga un constructor de router que **recibe** las rutas y no las conoce:

```dart
// lib/core/router/app_router.dart — core/ no importa ningún módulo
GoRouter crearRouter(Ref ref, {required List<RouteBase> rutasDeModulos}) { … }
```

```dart
// lib/main.dart — el único archivo que conoce a todos los módulos
final List<RouteBase> rutasDeModulos = [
  ...timbreEscolarRoutes,
  ...proyectoBanosRoutes,   // ← única línea a borrar
];
```

`rutasDeModulos` es público para que las pruebas reutilicen la lista real en vez de repetirla: duplicada, borrar un módulo obligaría a acordarse de dos archivos.

Borrar el módulo son dos pasos, ambos fuera de `core/`: eliminar la carpeta y quitar esa línea con su import.

### 5.4. Verificación automática

El script `app/tool/check_module_isolation.sh` falla si alguien cruza la frontera:

```bash
cd app && ./tool/check_module_isolation.sh
```

Comprueba tres reglas: que `core/` no importe ningún módulo, que `timbre_escolar/` no importe `proyecto_banos/` y que `proyecto_banos/` no importe `timbre_escolar/`.

Dos detalles de implementación que importan:

- **Solo inspecciona directivas `import`/`export`**, no el texto del archivo. Un comentario que menciona otro módulo no es una dependencia; una primera versión que hacía `grep` del nombre a secas daba falsos positivos con la propia documentación del código.
- **Cubre imports de paquete y relativos.** `package:swiftyring/modules/…` es el camino obvio, pero `../../otro_modulo/…` es la forma fácil de saltarse la regla sin darse cuenta.

El script sale con código 1 cuando encuentra una violación, así que sirve tal cual en un hook de pre-commit o en CI.

### 5.5. Prueba de borrado

Al cierre de cada entrega, en una rama descartable:

```bash
git checkout -b prueba-borrado
rm -rf app/lib/modules/proyecto_banos/
# quitar la línea de proyectoBanosRoutes en app_router.dart
flutter analyze && flutter test && flutter build apk --debug
git checkout main && git branch -D prueba-borrado
```

Si compila, el aislamiento está sano. Si no, hay una dependencia oculta que corregir.

---

## 6. Qué requiere acuerdo escrito

Cambios que **ningún equipo hace por su cuenta**:

- Modificar el enum `rol_usuario` o la tabla `public.usuarios`.
- Agregar claims al JWT o cambiar el algoritmo de firma.
- Agregar endpoints del Timbre Escolar consumidos por Control Baños.
- Otorgar cualquier privilegio nuevo al rol `proyectobanos`.
- Cualquier FK que cruce la frontera entre `public` y `banos`.

Cambios que cada equipo hace libremente: todo lo que viva exclusivamente dentro de su schema, su repositorio de backend y su carpeta de módulo.

---

*Contrato de integración · Versión 1.0 · Julio de 2026*
