# Requerimientos del Proyecto — Control Baños SS
**Documento de requerimientos · Versión 1.0 · 2026**
Sistema de gestión inteligente de acceso a servicios sanitarios · Web · Móvil

---

## Índice

- 01 · Identificación y alcance del proyecto
- 02 · Actores del sistema
- 03 · Requerimientos funcionales (RF)
- 04 · Reglas de negocio
- 05 · Requerimientos no funcionales (RNF)
- 06 · Requerimientos de datos
- 07 · Requerimientos técnicos
- 08 · Fuera de alcance

---

## 01 · Identificación y alcance del proyecto

**Nombre del proyecto:** Control Baños SS

**Objetivo general:** desarrollar un sistema que permita a los docentes gestionar y autorizar la salida de estudiantes al baño durante la jornada de clase, dejando un registro digital de cada salida (hora, duración, tipo) y generando reportes de uso.

**Problema que resuelve:** actualmente el control de salidas al baño se lleva de forma manual o no se lleva registro alguno, lo que dificulta identificar abusos, emergencias reales o tiempos excesivos fuera del salón.

**Alcance:** aplicación web/móvil con un panel de control para docentes (autorizar, cancelar, consultar salidas) y un módulo de reportes y estadísticas.

---

## 02 · Actores del sistema

| Actor | Descripción |
|---|---|
| **Docente / Administrador** | Inicia sesión con usuario y contraseña. Autoriza, cancela y consulta salidas. Genera reportes. |
| **Estudiante** | No accede al sistema directamente; es gestionado por el docente. Su información y su historial de salidas quedan registrados. |
| **Sistema** | Aplica automáticamente las reglas de negocio (límite de salidas, cálculo de duración, historial). |

---

## 03 · Requerimientos funcionales (RF)

| # | Requerimiento |
|---|---|
| RF01 | El sistema debe permitir el inicio de sesión de docentes mediante usuario y contraseña. |
| RF02 | El sistema debe mostrar un panel "Control Baños" con la lista de estudiantes de la jornada y su estado (en salón / fuera del salón). |
| RF03 | El sistema debe mostrar en el panel la actividad reciente: estudiantes que han salido, hora y tiempo transcurrido. |
| RF04 | El sistema debe permitir autorizar la **salida 1** de un estudiante, registrando estudiante, fecha y hora. |
| RF05 | El sistema debe permitir autorizar la **salida 2** de un estudiante, validando primero si ya alcanzó el máximo de salidas normales permitidas ese día. |
| RF06 | Si el estudiante ya agotó sus salidas normales, el sistema debe mostrar el mensaje de salida no autorizada e indicar que solo procede una nueva salida si se marca como **emergencia**. |
| RF07 | El sistema debe permitir cancelar una salida ya autorizada, dejando constancia de la cancelación. |
| RF08 | El sistema debe permitir registrar la hora de regreso del estudiante y calcular automáticamente la duración de la salida. |
| RF09 | El sistema debe mostrar un **historial de salidas** con fecha, hora, estudiante y duración. |
| RF10 | El sistema debe permitir **buscar** un estudiante dentro del historial de salidas. |
| RF11 | El sistema debe permitir **exportar** el historial de salidas (ej. a Excel o PDF). |
| RF12 | El sistema debe generar un módulo de **reportes y estadísticas** con: total de salidas del día, duración promedio, número de emergencias y salidas por día. |
| RF13 | Al finalizar cualquier acción (autorizar, cancelar, exportar), el sistema debe permitir volver al panel principal o registrar una nueva salida. |

---

## 04 · Reglas de negocio

- Cada estudiante tiene un máximo de **2 salidas normales por día**.
- Las salidas marcadas como **emergencia** no cuentan dentro de ese límite y siempre pueden autorizarse.
- Una salida solo puede estar en uno de estos estados: **Autorizada**, **Cancelada** o **En curso**.
- La duración de una salida se calcula como la diferencia entre la hora de salida y la hora de regreso; solo existe una vez el estudiante regresa.
- Solo un docente autenticado puede autorizar, cancelar o consultar salidas.

---

## 05 · Requerimientos no funcionales (RNF)

| # | Requerimiento |
|---|---|
| RNF01 | **Usabilidad:** una instrucción clara por pantalla; el docente actúa sin necesidad de adivinar el siguiente paso (tono claro, respetuoso, eficiente y honesto). |
| RNF02 | **Rendimiento:** las acciones de autorizar/cancelar una salida deben reflejarse en el panel en menos de 2 segundos. |
| RNF03 | **Seguridad:** las contraseñas se almacenan cifradas (hash); el acceso a autorizar salidas requiere sesión activa. |
| RNF04 | **Disponibilidad:** el sistema debe estar operativo durante toda la jornada académica. |
| RNF05 | **Identidad visual:** la interfaz debe seguir el manual de marca — colores Azul Marino #1E2545, Verde Acción #2D8C3E y Gris Fondo #F2F2F2; tipografías Bebas Neue (títulos), Inter (cuerpo) y Roboto Mono (datos/códigos). |
| RNF06 | **Compatibilidad:** el sistema debe funcionar correctamente en navegador web y en dispositivos móviles. |
| RNF07 | **Trazabilidad:** toda salida autorizada o cancelada debe quedar registrada de forma permanente en el historial. |

---

## 06 · Requerimientos de datos

El sistema requiere una base de datos con al menos las siguientes entidades (ya modeladas en el archivo `control_banos_ss_bd.xlsx`):

- **Estudiantes**: id, código, nombre completo, ficha, estado.
- **Docentes**: id, nombre completo, usuario, contraseña (hash), rol.
- **Configuración**: parámetros del sistema (máximo de salidas normales por día, duración máxima recomendada, etc.).
- **Salidas**: id, estudiante (FK), docente que autoriza (FK), fecha, hora de salida, hora de regreso, duración calculada, número de salida del día, tipo (Normal/Emergencia), estado (Autorizada/Cancelada/En curso).

---

## 07 · Requerimientos técnicos

- Frontend: HTML, CSS y JavaScript (consistente con el resto de proyectos del estudiante), o framework equivalente.
- Backend/almacenamiento: base de datos relacional (MySQL/MariaDB), siguiendo el mismo patrón de tablas independientes y dependientes usado en los demás proyectos SENA del estudiante.
- Diseño responsive para uso en computador y celular.
- Paleta y tipografía tomadas directamente del manual de marca de Control Baños SS.

---

## 08 · Fuera de alcance

- Integración con hardware físico (sensores de puerta, torniquetes, tarjetas RFID).
- Notificaciones push o por correo electrónico.
- Roles distintos a Docente/Administrador (ej. padres de familia, coordinación externa).
- Aplicación nativa de escritorio.

---

*Control Baños SS · Documento de requerimientos · Versión 1.0 · 2026*
