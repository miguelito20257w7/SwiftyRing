# Documentación del proyecto

Proyecto de grado SENA — CDITI · Articulación con la media, grado 11
I.E. Santa Sofía · Dosquebradas, Risaralda · 2026

Dos módulos independientes que se entregan sobre una misma aplicación e infraestructura:

| Módulo | Autor | Carpeta |
|---|---|---|
| Sistema de Timbre Escolar (SwiftyRing) | Miguel Ángel Salazar García | [`02-Timbre-Escolar/`](02-Timbre-Escolar/) |
| Control Baños SS | Jhoan Santiago Chalarca · Isabel Galeano · Juan Esteban Estrada | [`03-Control-Banos/`](03-Control-Banos/) |

La frontera entre los dos está en [`04-Integracion/`](04-Integracion/). **Empezá por ahí** si vas a tocar base de datos, autenticación o la estructura de carpetas de la app.

---

## Estructura

```
Docs/
├── 00-SENA/            Material oficial del centro de formación
├── 01-Marca/           Identidad visual de las dos marcas
├── 02-Timbre-Escolar/  Entregables del Sistema de Timbre Escolar
├── 03-Control-Banos/   Entregables de Control Baños SS
└── 04-Integracion/     Frontera entre los dos módulos
```

### 00-SENA

| Archivo | Qué es |
|---|---|
| `MATERIAL ETAPA PRODUCTIVA AcMe CDITI.pdf` | Guía oficial del CDITI. Define la estructura obligatoria de la propuesta de proyecto productivo (11 secciones) y los formatos de bitácora 165, 023 y 147 |

### 01-Marca

| Carpeta | Contenido |
|---|---|
| `Swifty-Devs/` | Marca del estudio desarrollador. Manual de marca v1.0, logos SVG y PNG, archivo fuente de Affinity |
| `SwiftyRing/` | Marca del producto Timbre Escolar. Logo con y sin texto (SVG), ícono de app, logo con retícula de construcción, archivo fuente |

**Swifty Devs** es el estudio; **SwiftyRing** es el producto respaldado, con su propia paleta. No confundir las dos paletas.

Control Baños SS no tiene carpeta aquí: su identidad visual (Azul Marino `#1E2545`, Verde Acción `#2D8C3E`, Bebas Neue · Inter · Roboto Mono) está declarada en su RNF06 y aplicada directamente en el CSS de sus documentos. Si el equipo entrega un manual de marca o un logo propio, va en `01-Marca/Control-Banos/`.

> Los HTML de `02-Timbre-Escolar/` referencian los logos de SwiftyRing por ruta relativa (`../01-Marca/SwiftyRing/...`). Si movés esa carpeta, se rompen las portadas.

### 02-Timbre-Escolar

| Archivo | Qué es |
|---|---|
| `Documento Final.md` | Análisis, diseño y marca. Cliente, problema, requerimientos, flujogramas AS-IS/TO-BE, modelo relacional y diccionario de datos campo por campo |
| `Requerimientos_TimbreEscolar_SwiftyRing_v5.html` / `.pdf` | Documento de requerimientos vigente: 48 RF y 13 RNF. La v5.0 agrega el rol de servidor de identidad y los requerimientos de aislamiento |
| `Propuesta_Proyecto_Productivo_SwiftyRing.html` / `.pdf` | Propuesta SENA con las 11 secciones del CDITI. Cronograma julio–diciembre 2026, aprendiz único |
| `SketchBD.dbml` | **Fuente de verdad del schema `public`.** 17 tablas, v5 |
| `SketchBD.dbdiagram` | Posiciones guardadas del diagrama en dbdiagram.io |
| `_archivo/` | Requerimientos v3.0 (FastAPI) y v4.0 (previo a la convivencia de módulos). Historial, no se usan |

### 03-Control-Banos

| Archivo | Qué es |
|---|---|
| `requerimientos_control_banos_ss_v2.md` | Documento de requerimientos vigente: 21 RF, 10 RNF, 9 reglas de negocio, 7 de integración |
| `Requerimientos_ControlBanos_v2.html` / `.pdf` | El mismo documento maquetado, 14 páginas |
| `Documento Final Control Baños.md` | Análisis, diseño y marca, en paralelo al del Timbre Escolar |
| `Propuesta_Proyecto_Productivo_ControlBanos.html` / `.pdf` | Propuesta SENA, 15 páginas. Cronograma de 13 semanas, tres integrantes |
| `_archivo/` | Documentos originales del equipo: requerimientos v1.0 (decía HTML/JS + MySQL) y su primera propuesta. Superados, se conservan como historial |

### 04-Integracion

| Archivo | Qué es |
|---|---|
| `Contrato_Integracion_Timbre_ControlBanos.md` | **El documento que manda.** Schemas y permisos de PostgreSQL, contrato de JWT, endpoints, reglas de aislamiento en Flutter y procedimiento de prueba de borrado |
| `modelo_datos_completo.dbml` | Modelo de las 22 tablas: 17 en `public` y 5 en `banos`, con los vínculos lógicos entre schemas documentados |
| `modelo_datos_completo.dbdiagram` | Posiciones guardadas del diagrama completo |

---

## Reglas de mantenimiento

**El modelo de datos vive en dos archivos.** `02-Timbre-Escolar/SketchBD.dbml` es la fuente de verdad del schema `public`; `04-Integracion/modelo_datos_completo.dbml` es la vista integrada de los dos schemas. Si cambiás una tabla de `public`, hay que tocar los dos. Es el único costo de mantener el diagrama del Timbre por separado; si algún día molesta, la salida es quedarse solo con el modelo completo.

**Los PDF no se generan con el print del navegador.** Se generan con Chrome headless, que respeta el CSS de impresión y las sangrías de portada:

```bash
"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" --headless=old --disable-gpu --print-to-pdf=salida.pdf --no-pdf-header-footer --virtual-time-budget=20000 --user-data-dir=$(mktemp -d) --allow-file-access-from-files "file://$PWD/entrada.html"
```

Usar un perfil nuevo en cada render: reutilizarlo bloquea el proceso. Chrome a veces no termina solo, aunque el PDF ya esté escrito completo — verificá que el archivo cierre con `%%EOF` antes de asumir que falló.

**Los HTML cargan tipografías de Google Fonts**, así que necesitan internet para renderizar con la tipografía correcta. Sin conexión el documento se ve, pero con fuentes de sistema.

**Los documentos marcados `_archivo/` no se actualizan.** Están ahí para poder mostrar la evolución del proyecto en la sustentación, no para consultarlos como referencia vigente.
