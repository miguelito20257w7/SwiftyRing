#!/usr/bin/env bash
#
# Verifica las reglas de dependencia entre módulos (RNF-12 y RI04 del
# Contrato de integración Timbre Escolar ↔ Control Baños SS).
#
#   modules/proyecto_banos/  ->  core/                    permitido
#   modules/proyecto_banos/  ->  modules/timbre_escolar/  PROHIBIDO
#   core/                    ->  cualquier módulo         PROHIBIDO
#   modules/timbre_escolar/  ->  modules/proyecto_banos/  PROHIBIDO
#
# `main.dart` es la excepción deliberada: es la raíz de composición y el único
# archivo que puede nombrar a todos los módulos.
#
# Solo se inspeccionan directivas `import`/`export`, no el texto del archivo:
# un comentario que menciona otro módulo no es una dependencia. Se cubren tanto
# los imports de paquete (`package:swiftyring/modules/...`) como los relativos
# (`../../otro_modulo/...`), que son la forma fácil de saltarse la regla sin
# darse cuenta.
#
# Uso:  ./tool/check_module_isolation.sh    (desde la carpeta app/)

set -uo pipefail
cd "$(dirname "$0")/.."

fallos=0
DIRECTIVA="^[[:space:]]*(import|export)[[:space:]]+['\"]"

comprobar() {
  local descripcion="$1" fragmento="$2" carpeta="$3"
  if [ ! -d "$carpeta" ]; then
    echo "· $descripcion  (no existe $carpeta, se omite)"
    return
  fi

  local hallazgos
  hallazgos=$(grep -rnE --include='*.dart' "${DIRECTIVA}.*${fragmento}" "$carpeta" 2>/dev/null || true)

  if [ -n "$hallazgos" ]; then
    echo "✗ $descripcion"
    echo "$hallazgos" | sed 's/^/    /'
    fallos=$((fallos + 1))
  else
    echo "✓ $descripcion"
  fi
}

echo "Aislamiento de módulos"
echo "----------------------"

comprobar "core/ no importa ningún módulo" \
  "modules/" lib/core

comprobar "timbre_escolar/ no importa proyecto_banos/" \
  "proyecto_banos/" lib/modules/timbre_escolar

comprobar "proyecto_banos/ no importa timbre_escolar/" \
  "timbre_escolar/" lib/modules/proyecto_banos

echo
if [ "$fallos" -eq 0 ]; then
  echo "Aislamiento correcto: cada módulo puede borrarse sin romper a los demás."
  exit 0
fi

echo "$fallos regla(s) incumplida(s)."
echo "Una dependencia cruzada rompe la promesa de poder borrar un módulo entero."
exit 1
