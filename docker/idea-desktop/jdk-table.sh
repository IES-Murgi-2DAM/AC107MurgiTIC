#!/usr/bin/env bash
# Registra el JDK del contenedor en la tabla de SDKs del IDE.
#
# Los proyectos Android referencian el JDK por nombre: .idea/misc.xml guarda
# project-jdk-name="corretto-17" y .idea/gradle.xml puede guardar gradleJvm.
# Si ese nombre no existe en la tabla, el IDE no sincroniza Gradle ("JDK not
# found"). El host no se usa para esto: el JDK vive siempre en la imagen
# (/opt/jdk-17), así que se declara con los nombres que pida el proyecto.
#
# Es idempotente: conserva los SDKs válidos que ya hubiera y solo añade lo que
# falta. Los SDKs cuya ruta ya no existe se descartan.
set -euo pipefail

JDK_HOME="${JDK_HOME:-/opt/jdk-17}"
PROJECT_DIR="${PROJECT_DIR:-/workspace}"
[ -x "$JDK_HOME/bin/java" ] || exit 0

product="${DATA_DIR_NAME:-}"
if [ -z "$product" ]; then
  for dir in "$HOME"/.config/JetBrains/*/; do
    [ -d "$dir" ] || continue
    product="$(basename "${dir%/}")"
    break
  done
fi
[ -n "$product" ] || exit 0

table="$HOME/.config/JetBrains/$product/options/jdk.table.xml"
mkdir -p "$(dirname "$table")"

# Nombres de JDK que pide el proyecto. Los valores con # (por ejemplo
# #JAVA_HOME o #GRADLE_LOCAL_JAVA_HOME) los resuelve el propio IDE.
names=()
add_name() {
  local name="$1" seen
  [ -n "$name" ] || return 0
  case "$name" in \#*) return 0 ;; esac
  for seen in "${names[@]:-}"; do
    [ "$seen" = "$name" ] && return 0
  done
  names+=("$name")
}
if [ -f "$PROJECT_DIR/.idea/misc.xml" ]; then
  while IFS= read -r name; do
    add_name "$name"
  done < <(sed -n 's/.*project-jdk-name="\([^"]*\)".*/\1/p' "$PROJECT_DIR/.idea/misc.xml")
fi
if [ -f "$PROJECT_DIR/.idea/gradle.xml" ]; then
  while IFS= read -r name; do
    add_name "$name"
  done < <(sed -n 's/.*name="gradleJvm" value="\([^"]*\)".*/\1/p' "$PROJECT_DIR/.idea/gradle.xml")
fi
# Proyecto sin JDK declarado: se deja uno disponible por defecto.
[ "${#names[@]}" -gt 0 ] || names=(corretto-17)

modules=()
while IFS= read -r line; do
  [ -n "$line" ] && modules+=("${line%%@*}")
done < <("$JDK_HOME/bin/java" --list-modules 2>/dev/null || true)

version="$("$JDK_HOME/bin/java" -version 2>&1 | sed -n '1s/.*"\([^"]*\)".*/\1/p' || true)"
[ -n "$version" ] || version="17"

jdk_block() {
  local name="$1" esc module
  esc="${name//&/&amp;}"
  esc="${esc//</&lt;}"
  esc="${esc//>/&gt;}"
  esc="${esc//\"/&quot;}"
  printf '    <jdk version="2">\n'
  printf '      <name value="%s" />\n' "$esc"
  printf '      <type value="JavaSDK" />\n'
  printf '      <version value="java version &quot;%s&quot;" />\n' "$version"
  printf '      <homePath value="%s" />\n' "$JDK_HOME"
  printf '      <roots>\n'
  printf '        <annotationsPath>\n'
  printf '          <root type="composite">\n'
  printf '            <root type="simple" url="jar://$APPLICATION_HOME_DIR$/plugins/java/lib/resources/jdkAnnotations.jar!/" />\n'
  printf '          </root>\n'
  printf '        </annotationsPath>\n'
  printf '        <classPath>\n'
  printf '          <root type="composite">\n'
  for module in "${modules[@]:-}"; do
    [ -n "$module" ] || continue
    printf '            <root type="simple" url="jrt://%s!/%s" />\n' "$JDK_HOME" "$module"
  done
  printf '          </root>\n'
  printf '        </classPath>\n'
  printf '        <javadocPath>\n'
  printf '          <root type="composite" />\n'
  printf '        </javadocPath>\n'
  printf '        <sourcePath>\n'
  printf '          <root type="composite">\n'
  if [ -f "$JDK_HOME/lib/src.zip" ]; then
    printf '            <root type="simple" url="jar://%s/lib/src.zip!/" />\n' "$JDK_HOME"
  fi
  printf '          </root>\n'
  printf '        </sourcePath>\n'
  printf '      </roots>\n'
  printf '      <additional />\n'
  printf '    </jdk>\n'
}

# Bloques <jdk> ya existentes que siguen apuntando a un JDK presente.
valid=()
if [ -f "$table" ]; then
  current=""
  while IFS= read -r line; do
    if [ -z "$current" ]; then
      case "$line" in
        *"<jdk version="*) current="$line"$'\n' ;;
      esac
    else
      current+="$line"$'\n'
    fi
    if [ -n "$current" ] && [ "${line##*</jdk>}" != "$line" ]; then
      home="$(printf '%s' "$current" | sed -n 's/.*<homePath value="\([^"]*\)".*/\1/p' | head -n 1)"
      home="${home//\$USER_HOME\$/$HOME}"
      if [ -n "$home" ] && [ -d "$home" ]; then
        valid+=("$current")
      fi
      current=""
    fi
  done < "$table"
fi

has_name() {
  local name="$1" block
  for block in "${valid[@]:-}"; do
    [ -n "$block" ] || continue
    if printf '%s' "$block" | grep -qF "<name value=\"$name\""; then
      return 0
    fi
  done
  return 1
}

missing=0
for name in "${names[@]}"; do
  has_name "$name" || missing=1
done
[ "$missing" = "1" ] || exit 0

tmp="$(mktemp)"
{
  printf '<?xml version="1.0" encoding="UTF-8"?>\n'
  printf '<application>\n'
  printf '  <component name="ProjectJdkTable">\n'
  for block in "${valid[@]:-}"; do
    if [ -n "$block" ]; then
      printf '%s' "$block"
    fi
  done
  for name in "${names[@]}"; do
    has_name "$name" || jdk_block "$name"
  done
  printf '  </component>\n'
  printf '</application>\n'
} > "$tmp"
mv "$tmp" "$table"
