# Ficha Técnica y Logística de Proyectos Productivos
**Programa:** Técnico en Programación de Software  
**Institución Educativa:** I.E. Santa Sofía · Dosquebradas, Risaralda  
**Centro de Formación:** SENA — CDITI, Regional Risaralda  
**Modalidad:** Articulación con la Media Técnica (Grado 11) · Año 2026  

---

## 1. Resumen Ejecutivo de la Sustentación

En el marco del proceso de etapa productiva del programa **Técnico en Programación de Software**, se presentan dos soluciones tecnológicas de software y hardware desarrolladas para responder a necesidades críticas de la **Institución Educativa Santa Sofía**. Ambos módulos se integran de manera armónica sobre una misma aplicación móvil multiplataforma e infraestructura de servidores compartida, pero mantienen una estricta independencia funcional, de base de datos y de sustentación académica.

| Proyecto | Nombre Oficial | Cantidad de Aprendices | Enfoque Principal |
| :--- | :--- | :---: | :--- |
| **Proyecto 1** | **SwiftyRing — Sistema de Timbre Escolar Inteligente** | **1** | Automatización horaria del timbre, aviso push a docentes y alerta sísmica autónoma (IoT + Cloud + Móvil). |
| **Proyecto 2** | **Control Baños SS — Sistema inteligente de control de salidas al baño** | **3** | Digitalización, cronometraje, trazabilidad y reportes de salidas pedagógicas al baño (Móvil + Cloud). |
| **Total Global** | **Plataforma Institucional Integrada I.E. Santa Sofía** | **4 aprendices** | Ecosistema escolar digital unificado. |

---

## 2. Proyecto 1: SwiftyRing

### 2.1. Nombre Oficial del Proyecto
* **Nombre Oficial:** `SwiftyRing — Sistema de Timbre Escolar Inteligente`
* **Lema Institucional:** *"El timbre inteligente de tu colegio. Suena a tiempo. Protege cuando importa."*
* **Estudio / Sello Desarrollador:** Swifty Devs

### 2.2. Objetivo General
> *"Desarrollar e implementar SwiftyRing, un sistema de timbre escolar inteligente que automatice la operación del timbre según horarios configurables, notifique a cada docente su próxima clase, detecte eventos sísmicos activando la evacuación de forma autónoma, funcione aun sin conexión a internet y deje registro auditable de toda su operación."*

### 2.3. Integrante y Ficha de Contacto
* **Cantidad de Aprendices para Sustentar:** **1 aprendiz** (Desarrollador Full-Stack a cargo de la totalidad de las áreas: liderazgo, backend, frontend, firmware IoT, diseño de marca y aseguramiento de calidad).

| Campo | Información del Aprendiz |
| :--- | :--- |
| **Nombre Completo** | Miguel Ángel Salazar García |
| **Documento de Identidad** | `[Número de T.I. / C.C. — Diligenciar por el aprendiz]` |
| **Correo Electrónico** | `miguelsalazar2801@icloud.com` *(institucional: `@santasofia.edu.co` / `@misena.edu.co`)* |
| **Número de Celular** | `[Número de teléfono móvil — Diligenciar por el aprendiz]` |
| **Rol en el Proyecto** | Líder de Proyecto, Desarrollador Full-Stack (Flutter / Vapor / ESP32 C++), Diseñador UI/UX y QA |

### 2.4. Necesidades de Tecnología
El proyecto se fundamenta en una solución integral que vincula hardware embebido, servicios en la nube y clientes móviles:

1. **Frontend Móvil (App):**
   * **Framework:** Flutter (Lenguaje Dart) bajo arquitectura limpia (*Clean Architecture* - capas data, domain, presentation).
   * **Diseño:** Directrices de diseño *Material Design 3* con tokens de marca propios de SwiftyRing.
   * **Roles de usuario:** Tres perfiles funcionales implementados: Administrador, Operador y Profesor.
2. **Backend y Seguridad (API REST):**
   * **Framework:** Vapor 4 (Lenguaje Swift).
   * **Autenticación e Identidad:** Emisor central de tokens JWT firmados con clave asimétrica **RS256** (RSA 2048-bit); contraseñas cifradas con algoritmo hash seguro **bcrypt**.
   * **Comunicaciones:** Tráfico 100% cifrado sobre HTTPS / TLS y canal WebSocket en tiempo real para sincronización inmediata con el hardware.
3. **Persistencia de Datos:**
   * **Motor:** PostgreSQL (versión 16+).
   * **Esquema:** Esquema principal `public` con 17 tablas relacionales gestionadas mediante el ORM Fluent.
4. **Módulo de Hardware Embebido (IoT):**
   * **Microcontrolador:** ESP32 DevKit (Wi-Fi 2.4 GHz, procesador Dual-Core) programado en C/C++ sobre el framework oficial **ESP-IDF**.
   * **Sensor Sísmico:** Acelerómetro y giroscopio **MPU-6050** con algoritmo de detección sísmica STA/LTA (filtro para descartar vibraciones vehiculares externas).
   * **Visualización Local:** Pantalla gráfica **OLED de 1.3" I2C** (controlador SH1106 / SSD1306) con visualización de hora sincronizada por NTP, estado de conexión Wi-Fi, IP y alertas.
   * **Control de Potencia:** Módulo relé de estado sólido / electromecánico (aislado ópticamente) para conmutación del circuito del timbre institucional (110V AC).
   * **Pulsador y Señalización:** Botón físico para toque manual local, LED indicador de estado RGB y sistema de detección de caída de red eléctrica (modo UPS/batería de respaldo).
   * **Gabinete:** Carcasa de montaje a pared modelada y fabricada en **impresión 3D**.
5. **Servicios de Mensajería y Despliegue en la Nube:**
   * **Notificaciones Push:** Integración con **Firebase Cloud Messaging (FCM)** para la notificación instantánea de materias y salones a los celulares docentes.
   * **Servidor de Producción:** Servidor Linux (AlmaLinux + Nginx como proxy inverso + Docker) bajo el dominio `host.swiftydevs.dev`.

### 2.5. Necesidades de Logística para la Sustentación
1. **Espacio Físico y Mobiliario:**
   * Mesa o mesa técnica para la colocación del computador portátil, el módulo físico ESP32 y el dispositivo de prueba del timbre.
   * Espacio despejado para que el jurado pueda apreciar la pantalla OLED y la activación del mecanismo.
2. **Conectividad Eléctrica y Red:**
   * 1 punto de toma eléctrica de 110V AC (o regleta multilínea) para alimentar la laptop, el cargador del microcontrolador y la maqueta del timbre.
   * Acceso a red Wi-Fi con salida a internet (o zona de anclaje de datos móviles / Hotspot 4G/5G) para la comunicación en vivo entre la app móvil, el servidor y el módulo ESP32.
3. **Equipos Audiovisuales:**
   * 1 Video beam o pantalla de televisión con puerto HDMI para la proyección de diapositivas y demostración del panel administrativo.
4. **Equipos Físicos para Demostración en Vivo:**
   * 1 Computador portátil del aprendiz para control de la exposición y monitoreo del servidor.
   * 1 Módulo físico SwiftyRing (ESP32 montado en caja 3D, sensor sísmico MPU-6050, pantalla OLED y campana/timbre de prueba).
   * 1 o 2 Teléfonos celulares (Android / iOS) con la app SwiftyRing instalada para demostrar el toque remoto y la recepción en vivo de notificaciones push de cambio de clase.

---

## 3. Proyecto 2: Control Baños SS

### 3.1. Nombre Oficial del Proyecto
* **Nombre Oficial:** `Control Baños SS — Sistema inteligente de control de salidas al baño`
* **Lema Institucional:** *"Cada salida, registrada."*
* **Identidad Visual:** Azul Marino (`#1E2545`) y Verde Acción (`#2D8C3E`)

### 3.2. Objetivo General
> *"Desarrollar un sistema móvil que permita autorizar, registrar y analizar las salidas al baño de los estudiantes en tiempo real, dejando constancia digital de cada salida y generando reportes de uso para la coordinación de la institución."*

### 3.3. Integrantes y Ficha de Contacto
* **Cantidad de Aprendices para Sustentar:** **3 aprendices** (Equipo colaborativo con división clara de responsabilidades técnicas y documentales).

| Nombre Completo | Documento de Identidad | Correo Electrónico | Número de Celular | Rol / Responsabilidad en el Proyecto |
| :--- | :--- | :--- | :--- | :--- |
| **Jhoan Santiago Chalarca** | `[Número de T.I. / C.C.]` | `johneduard5555@gmail.com` | `[Número celular]` | Líder de proyecto · Backend Vapor y base de datos |
| **Isabel Galeano** | `[Número de T.I. / C.C.]` | `[Correo electrónico]` | `[Número celular]` | Diseño UI/UX · Documentación y evidencias |
| **Juan Esteban Estrada** | `[Número de T.I. / C.C.]` | `[Correo electrónico]` | `[Número celular]` | Desarrollo Frontend Flutter · Control de pruebas (QA) |

### 3.4. Necesidades de Tecnología
El módulo está diseñado con una arquitectura desacoplada que asegura costo cero en licencias y operación dentro de la infraestructura escolar:

1. **Frontend Móvil (App):**
   * **Framework:** Flutter (Lenguaje Dart), módulo autónomo dentro de la aplicación móvil institucional.
   * **Funcionalidades del Docente:** Panel en vivo que muestra qué estudiantes están en el baño, cronómetro activo por salida, autorización y registro de retorno en máximo 3 toques de pantalla.
   * **Funcionalidades de Coordinación:** Consulta de métricas acumuladas, salidas recurrentes, alertas de tiempo excedido y generación de reportes por grado o fecha.
2. **Backend Propio (API REST):**
   * **Framework:** Vapor 4 (Lenguaje Swift) bajo el prefijo de rutas `/api/banos`.
   * **Lógica de Negocio Automática:** Aplicación estricta de reglas de negocio (límite configurable de 2 salidas diarias por estudiante, cómputo automático de duración, detección y almacenamiento de alertas por demora excesiva).
3. **Persistencia y Aislamiento de Datos:**
   * **Motor:** PostgreSQL (versión 16+).
   * **Esquema Dedicado:** Schema independiente `banos` (5 tablas relacionales: `grupos`, `estudiantes`, `salidas`, `alertas`, `configuracion`).
   * **Aislamiento Arquitectónico:** Aislamiento total que permite desacoplar o eliminar el esquema sin afectar la operatividad del sistema de timbre escolar ni la estructura institucional.
4. **Seguridad y Autenticación Unificada:**
   * Consumo y validación de tokens **JWT RS256** originados en el servidor de identidad institucional. El docente utiliza un único inicio de sesión para acceder a toda la plataforma escolar.
5. **Herramientas de Diseño y Control de Versiones:**
   * **Diseño y Maquetación:** Figma para diagramación de flujos de usuario (UX) y componentes visuales; Canva para material de divulgación.
   * **Control de Versiones:** Git y GitHub para trazabilidad de código y entregables.
   * **Costo de Licencias:** **$0 COP** (100% tecnologías de código abierto o capas gratuitas educativas).

### 3.5. Necesidades de Logística para la Sustentación
1. **Espacio Físico y Mobiliario:**
   * Mesa de exposición para los 3 integrantes del equipo con espacio suficiente para ubicar sus computadores portátiles.
2. **Conectividad Eléctrica y Red:**
   * Regleta eléctrica con mínimo 3 tomas de corriente disponibles para mantener encendidos los computadores y terminales móviles durante toda la sesión.
   * Conexión a internet mediante Wi-Fi o datos móviles para la sincronización fluida entre las apps de los expositores y la base de datos de pruebas.
3. **Equipos Audiovisuales:**
   * 1 Video beam o pantalla de proyección con cable HDMI para proyectar la presentación y visualizar la consola administrativa de reportes de coordinación.
4. **Equipos Físicos para Demostración en Vivo:**
   * 3 Computadores portátiles (propiedad de los aprendices) para la presentación de diapositivas, demostración técnica del backend y exhibición de la base de datos.
   * 3 Dispositivos móviles (smartphones) para simular la interacción simultánea entre el docente autorizando un permiso de salida y el directivo monitoreando el panel en tiempo real.
   * 3 Cuadernos de campo / bitácoras físicas de seguimiento de la etapa productiva SENA.

---

## 4. Matriz Comparativa y Requerimientos Globales de la Sustentación

Para la jornada de sustentación ante el comité evaluador y directivos de la I.E. Santa Sofía, se consolida la siguiente lista de chequeo de logística unificada:

| Elemento Logístico | SwiftyRing | Control Baños SS | Requerimiento Total para el Aula |
| :--- | :---: | :---: | :--- |
| **Aprendices Expositores** | 1 | 3 | **4 aprendices** en total. |
| **Laptops de Exposición** | 1 | 3 | **Mínimo 2 o 3 laptops** activas simultáneamente. |
| **Dispositivos Móviles** | 1 - 2 | 3 | **Mínimo 3 smartphones** (Android / iOS) con la app instalada. |
| **Hardware Externo** | 1 módulo ESP32 + sensores + campana | N/A (módulo 100% software) | **1 kit de demostración física** con su respectivo soporte. |
| **Puntos de Energía (110V)** | 2 tomas | 3 tomas | **1 regleta multilínea de 6 tomas** en la mesa de exposición. |
| **Proyección Audiovisual** | Video beam / TV HDMI | Video beam / TV HDMI | **1 Video beam** en el aula con cable HDMI y sonido. |
| **Conexión a Internet** | Requerida (Wi-Fi / Hotspot) | Requerida (Wi-Fi / Hotspot) | **Red Wi-Fi estable** con salida a internet para el tráfico HTTPS y FCM. |
| **Tiempo de Exposición** | 15 - 20 min | 15 - 20 min | **Aprox. 45 - 60 minutos** (incluyendo sesión de preguntas del jurado). |

---

> [!TIP]
> **Instrucciones para los Aprendices:**
> Para la entrega formal impresa o digital ante la coordinación académica y evaluadores del SENA, completar los campos entre corchetes `[Número de T.I. / C.C.]` y `[Número de celular]` con los datos personales vigentes de cada integrante.
