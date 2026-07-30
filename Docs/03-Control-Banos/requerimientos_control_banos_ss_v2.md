# Requerimientos del Proyecto — Control Baños SS
**Documento de requerimientos · Versión 2.0 · Julio de 2026**
Sistema inteligente de control de salidas al baño · Aplicación móvil
I.E. Santa Sofía — Sede Villa Fanny · Dosquebradas, Risaralda

---

## Cambios frente a la versión 1.0

Esta versión corrige el documento de requerimientos original a partir del stack realmente acordado y de la integración con el Sistema de Timbre Escolar.

| # | Cambio | Motivo |
|---|---|---|
| 01 | Stack: de HTML/CSS/JS + MySQL a **Flutter + Vapor (Swift) + PostgreSQL** | Es el stack acordado y el que ya declara la propuesta de proyecto productivo v2 |
| 02 | Plataforma: de web + móvil a **solo móvil (Android/iOS)** | La v1.0 se contradecía: el resumen prometía web y el objetivo general decía móvil. Se resuelve a favor del objetivo general |
| 03 | Se elimina la tabla **Docentes** con usuario y contraseña propios | Rompía el requisito de login único. Los docentes son usuarios del Sistema de Timbre Escolar |
| 04 | "Ficha" pasa a **grado + grupo** (ej. 11A) | "Ficha" es vocabulario del SENA; en educación básica y media la unidad es el grupo |
| 05 | Se unifica el vocabulario de entidades: `grupos`, `estudiantes`, `salidas`, `alertas`, `configuracion` | La propuesta hablaba de "cursos" y "alertas"; el documento v1.0 de "Configuración" y "Docentes" |
| 06 | Estados de una salida: **En curso / Finalizada / Cancelada** | La v1.0 listaba "Autorizada, Cancelada, En curso", pero "Autorizada" y "En curso" describían el mismo estado y faltaba el estado final |
| 07 | Se agregan RF14–RF20 (alertas, configuración e integración) | Cubren funcionalidad que la propuesta prometía y el documento de requerimientos no recogía |
| 08 | Municipio corregido a **Dosquebradas, Risaralda** | La I.E. Santa Sofía está en Dosquebradas, no en Pereira |

---

## Índice

- 01 · Identificación y alcance del proyecto
- 02 · Actores del sistema
- 03 · Requerimientos funcionales (RF)
- 04 · Reglas de negocio
- 05 · Requerimientos no funcionales (RNF)
- 06 · Requerimientos de datos
- 07 · Requerimientos técnicos
- 08 · Requerimientos de integración y aislamiento
- 09 · Fuera de alcance

---

## 01 · Identificación y alcance del proyecto

**Nombre del proyecto:** Control Baños SS

**Equipo:** Jhoan Santiago Chalarca (líder de proyecto / backend Vapor) · Isabel Galeano (diseño UX / documentación) · Juan Esteban Estrada (frontend Flutter / pruebas)

**Programa de formación:** Técnico en Programación de Software — Articulación con la Media, grado 11

**Institución:** I.E. Santa Sofía — Sede Villa Fanny (Dosquebradas, Risaralda) · SENA — CDITI

**Objetivo general:** desarrollar un sistema móvil que permita a los docentes autorizar, registrar y analizar las salidas al baño de los estudiantes en tiempo real, dejando constancia digital de cada salida (hora, duración, tipo) y generando reportes de uso para coordinación.

**Problema que resuelve:** hoy el control de salidas al baño se lleva de forma verbal o en papel. No hay registro trazable, no se sabe cuánto tardó el estudiante ni cuántas veces sale por semana, y coordinación no tiene datos objetivos para tomar decisiones sobre convivencia y aprovechamiento del tiempo de clase.

**Alcance:** módulo dentro de la aplicación móvil institucional, con panel de control para el docente (autorizar, cancelar, cerrar y consultar salidas), historial exportable, alertas de tiempo excedido y módulo de reportes para coordinación.

**Relación con el Sistema de Timbre Escolar:** Control Baños SS es un módulo del mismo proyecto de grado y de la misma aplicación. Comparte con el Sistema de Timbre Escolar la identidad de los usuarios (un solo login) y la instancia de base de datos, pero mantiene sus datos y su código completamente separados. Las condiciones exactas están en el *Contrato de integración — Sistema de Timbre Escolar ↔ Control Baños SS*.

---

## 02 · Actores del sistema

| Actor | Rol real en el sistema | Descripción |
|---|---|---|
| **Docente** | `profesor` | Inicia sesión con las credenciales institucionales. Autoriza, cancela y cierra salidas. Consulta el historial. |
| **Coordinador** | `admin` | Todo lo del docente, más reportes institucionales, atención de alertas y configuración de parámetros. |
| **Estudiante** | — | No accede al sistema. Es gestionado por el docente; su información y su historial de salidas quedan registrados. |
| **Sistema** | — | Aplica las reglas de negocio: límite de salidas, cálculo de duración, generación de alertas e historial. |

> El rol `operador` del Sistema de Timbre Escolar **no tiene acceso** a Control Baños: su token se rechaza con 403.

---

## 03 · Requerimientos funcionales (RF)

### Acceso

| # | Requerimiento |
|---|---|
| RF01 | El docente debe poder iniciar sesión con las mismas credenciales institucionales que usa para el resto de la aplicación. El módulo no tiene registro de usuarios ni contraseñas propias. |
| RF02 | El sistema debe rechazar el acceso al módulo a los usuarios con rol `operador`, mostrando un mensaje claro en lugar de una pantalla vacía. |

### Panel de control

| # | Requerimiento |
|---|---|
| RF03 | El sistema debe mostrar un panel "Control Baños" con la lista de grupos activos y, dentro de cada grupo, sus estudiantes con el estado actual: **en salón** o **fuera del salón**. |
| RF04 | El sistema debe mostrar en el panel la actividad reciente: estudiantes que están fuera, hora de salida y tiempo transcurrido, actualizado en vivo. |
| RF05 | El sistema debe permitir buscar un estudiante por nombre o código dentro del panel. |

### Gestión de salidas

| # | Requerimiento |
|---|---|
| RF06 | El sistema debe permitir autorizar la salida de un estudiante, registrando estudiante, docente que autoriza, fecha y hora de salida. |
| RF07 | Antes de autorizar, el sistema debe validar cuántas salidas normales lleva el estudiante ese día y bloquear la autorización si ya alcanzó el máximo configurado. |
| RF08 | Si el estudiante agotó sus salidas normales, el sistema debe informarlo con un mensaje explícito e indicar que solo procede una nueva salida marcándola como **emergencia**. |
| RF09 | El sistema debe impedir que un estudiante tenga dos salidas en curso al mismo tiempo. |
| RF10 | El sistema debe permitir registrar el regreso del estudiante y calcular automáticamente la duración de la salida. |
| RF11 | El sistema debe permitir cancelar una salida ya autorizada, exigiendo un motivo y dejando constancia de quién canceló y cuándo. |

### Historial y reportes

| # | Requerimiento |
|---|---|
| RF12 | El sistema debe mostrar un historial de salidas con fecha, hora, estudiante, grupo, docente, tipo, estado y duración. |
| RF13 | El sistema debe permitir filtrar el historial por rango de fechas, grupo, estudiante y tipo de salida. |
| RF14 | El sistema debe permitir exportar el historial filtrado a CSV o PDF y compartirlo desde el dispositivo. |
| RF15 | El sistema debe generar un módulo de reportes con: total de salidas del día, duración promedio, número de emergencias, salidas por día y estudiantes con más salidas en el periodo. |

### Alertas y configuración

| # | Requerimiento |
|---|---|
| RF16 | El sistema debe generar automáticamente una alerta cuando una salida en curso supere la duración configurada como límite. |
| RF17 | El sistema debe registrar una alerta cuando un docente intente autorizar una salida por encima del máximo diario del estudiante. |
| RF18 | El coordinador debe poder consultar las alertas pendientes y marcarlas como atendidas. |
| RF19 | El coordinador debe poder configurar el máximo de salidas normales por día, la duración recomendada y el umbral de alerta, sin necesidad de recompilar la aplicación. |

### Administración de datos

| # | Requerimiento |
|---|---|
| RF20 | El sistema debe permitir registrar, editar y desactivar grupos y estudiantes. Los estudiantes son propiedad de Control Baños SS: ningún otro módulo los administra. |
| RF21 | Al terminar cualquier acción (autorizar, cancelar, cerrar, exportar), el sistema debe permitir volver al panel principal o registrar una nueva salida sin pasos intermedios. |

---

## 04 · Reglas de negocio

- **RN01.** Cada estudiante tiene un máximo de salidas normales por día, configurable, con valor inicial **2**.
- **RN02.** Las salidas marcadas como **emergencia** no cuentan contra ese límite y siempre pueden autorizarse.
- **RN03.** Una salida está en uno de tres estados excluyentes: **En curso** (autorizada, el estudiante sigue fuera), **Finalizada** (regresó, tiene duración) o **Cancelada** (el docente revocó la autorización).
- **RN04.** La duración se calcula como `hora_regreso − hora_salida` y solo existe cuando la salida está finalizada.
- **RN05.** Un estudiante no puede tener dos salidas en curso simultáneamente.
- **RN06.** Solo un usuario autenticado con rol `profesor` o `admin` puede autorizar, cancelar o consultar salidas.
- **RN07.** Cancelar exige motivo. La salida cancelada **no se borra**: queda en el historial con su estado.
- **RN08.** Ninguna salida se elimina de la base de datos. El historial es permanente.
- **RN09.** El límite diario se cuenta sobre el **día escolar** (`fecha`), no sobre ventanas de 24 horas.

---

## 05 · Requerimientos no funcionales (RNF)

| # | Requerimiento |
|---|---|
| RNF01 | **Usabilidad:** una instrucción clara por pantalla; el docente actúa sin adivinar el siguiente paso. Autorizar una salida no debe tomar más de tres toques desde el panel. |
| RNF02 | **Rendimiento:** autorizar, cancelar o cerrar una salida debe reflejarse en el panel en menos de 2 segundos sobre la red del colegio. |
| RNF03 | **Seguridad:** el módulo no almacena contraseñas. Todo acceso exige un token JWT válido y vigente, verificado con la llave pública del Sistema de Timbre Escolar. |
| RNF04 | **Aislamiento:** el backend de Control Baños solo escribe en su propio schema de base de datos. No tiene permiso de escritura sobre ninguna tabla del Sistema de Timbre Escolar. |
| RNF05 | **Disponibilidad:** operativo durante toda la jornada académica, en las jornadas mañana y tarde. |
| RNF06 | **Identidad visual:** la interfaz sigue el manual de marca de Control Baños SS — Azul Marino #1E2545, Verde Acción #2D8C3E, Gris Fondo #F2F2F2; tipografías Bebas Neue (títulos), Inter (cuerpo) y Roboto Mono (datos y códigos). |
| RNF07 | **Compatibilidad:** Android 8.0 o superior e iOS 15 o superior, desde una sola base de código Flutter. |
| RNF08 | **Trazabilidad:** toda salida autorizada, cerrada o cancelada queda registrada de forma permanente, con el usuario responsable y la marca de tiempo. |
| RNF09 | **Mantenibilidad:** el módulo vive completo bajo `lib/modules/proyecto_banos/` y puede eliminarse sin romper la compilación del resto de la aplicación. |
| RNF10 | **Privacidad:** los datos de los estudiantes solo son visibles para docentes y coordinación autenticados. La aplicación no expone listados fuera de sesión. |

---

## 06 · Requerimientos de datos

El sistema requiere las siguientes entidades, todas en el schema `banos` de la base de datos institucional. El modelo completo está en `modelo_datos_control_banos.dbml`.

| Entidad | Contenido | Dueño |
|---|---|---|
| **grupos** | Nombre (11A), grado, jornada, sede, año lectivo, director de grupo | Control Baños SS |
| **estudiantes** | Código institucional, nombre completo, grupo, estado activo | Control Baños SS |
| **salidas** | Estudiante, docente que autoriza, fecha, hora de salida, hora de regreso, duración, número de salida del día, tipo (normal/emergencia), estado (en curso/finalizada/cancelada), motivo y datos de cancelación | Control Baños SS |
| **alertas** | Salida asociada, tipo, umbral, fecha de generación, atendida por quién y cuándo | Control Baños SS |
| **configuracion** | Máximo de salidas normales, duración máxima, umbral de alerta, año lectivo | Control Baños SS |
| **usuarios** | Identidad de docentes y coordinadores | Sistema de Timbre Escolar — **solo lectura** |
| **profesores** | Jornada y dirección de grupo del docente | Sistema de Timbre Escolar — **solo lectura** |

Restricciones de datos:

- No existe ninguna llave foránea entre el schema `banos` y el schema del Sistema de Timbre Escolar. Los identificadores de usuario se guardan como texto y se validan con el JWT.
- `salidas` conserva copias del nombre del docente y del grupo del estudiante al momento de la salida, para que el historial siga siendo correcto si esos datos cambian después.
- La tabla `configuracion` tiene una sola fila, garantizada por restricción en la base de datos.

---

## 07 · Requerimientos técnicos

| Capa | Tecnología |
|---|---|
| Aplicación móvil | Flutter (Dart), Android e iOS desde una sola base de código |
| Cliente HTTP | `dio`, apuntando al backend propio en `/api/banos` |
| Backend | Vapor 4 (Swift), API REST JSON |
| ORM | Fluent con `fluent-postgres-driver` |
| Base de datos | PostgreSQL, schema `banos` |
| Autenticación | JWT RS256 emitido por el Sistema de Timbre Escolar y verificado con su llave pública |
| Versionado | Git · repositorio `controlbanos-backend` para el backend |
| Diseño | Figma para bocetos, siguiendo el manual de marca de Control Baños SS |

Condiciones de despliegue:

- El backend de Control Baños corre como servicio independiente, en su propio puerto y con su propio proceso.
- Se conecta a PostgreSQL con el rol `proyectobanos`, cuyo `search_path` apunta a `banos`.
- Nunca comparte proceso, puerto ni archivo de configuración con el backend del Sistema de Timbre Escolar.

---

## 08 · Requerimientos de integración y aislamiento

| # | Requerimiento |
|---|---|
| RI01 | Control Baños SS no emite tokens. Recibe el JWT que emite el Sistema de Timbre Escolar y lo verifica con la llave pública publicada en `/.well-known/jwks.json`. |
| RI02 | El backend de Control Baños valida, en este orden: firma, expiración, emisor (`iss`), audiencia (`aud` debe incluir `banos`) y rol. |
| RI03 | Control Baños no ejecuta ninguna sentencia de escritura sobre tablas del Sistema de Timbre Escolar. El permiso está revocado a nivel de base de datos, no solo por convención. |
| RI04 | El código del módulo vive completo bajo `lib/modules/proyecto_banos/` y solo puede importar desde `lib/core/`. Importar desde `lib/modules/timbre_escolar/` está prohibido. |
| RI05 | El módulo se engancha a la aplicación en un único punto: el registro de rutas. Eliminar la carpeta y esa línea debe dejar la aplicación compilando. |
| RI06 | Antes de cada entrega se ejecuta la prueba de borrado: eliminar el módulo, correr `flutter analyze` y compilar. Si falla, hay una dependencia que corregir. |
| RI07 | Cualquier cambio en el enum de roles, en los claims del JWT o en los permisos de base de datos requiere acuerdo escrito entre los dos equipos. |

---

## 09 · Fuera de alcance

- Integración con hardware físico: sensores de puerta, torniquetes, tarjetas RFID.
- Notificaciones push o por correo electrónico.
- Versión web o aplicación de escritorio.
- Acceso de estudiantes o padres de familia al sistema.
- Escritura sobre los datos del Sistema de Timbre Escolar (horarios, timbres, salones, materias).
- Sincronización sin conexión: el módulo requiere red para autorizar y registrar salidas.

---

*Control Baños SS · Documento de requerimientos · Versión 2.0 · Julio de 2026*
*I.E. Santa Sofía — Sede Villa Fanny · SENA — CDITI*
