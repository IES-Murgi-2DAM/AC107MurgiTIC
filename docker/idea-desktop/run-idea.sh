#!/usr/bin/env bash
# Runs IntelliJ IDEA inside a container, showing its window on the host X
# display (plain X11, XWayland and WSLg all work).
#
# Usage:
#   ./docker/idea-desktop/run-idea.sh
#   NETWORK=none ./docker/idea-desktop/run-idea.sh   # offline / exam mode
#   CONTAINER_ENGINE=docker ./docker/idea-desktop/run-idea.sh
#   DRY_RUN=1 ./docker/idea-desktop/run-idea.sh      # only print the command
#
# En Windows se ejecuta desde Ubuntu en WSL2 (WSLg pone la ventana). Allí el
# IDE del host es de Windows y no se puede montar en un contenedor Linux, así
# que se descarga en el directorio de estado la misma versión (IDEA_VERSION)
# que el alumno tiene instalada, para que configuración y licencia encajen.
#
# Overridable variables: IDE_HOME, IDEA_VERSION, DATA_DIR_NAME, IMAGE,
# CONTAINER_NAME, STATE_DIR, GRADLE_CACHE, NETWORK, CONTAINER_ENGINE,
# ADB_HOST, IMPORT_HOST_LICENSE, AUTO_BACKUP, DRY_RUN, KEEP_SELINUX.
# En Linux nativo IDE_HOME se detecta solo; solo hace falta fijarla si el IDE
# está en una ubicación poco habitual.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"

# En WSL el proyecto y el IDE viven en el disco de Windows, accesibles por /mnt.
IS_WSL=0
if [ "${FORCE_WSL:-0}" = "1" ] || [ -n "${WSL_DISTRO_NAME:-}" ] \
   || grep -qi microsoft /proc/version 2>/dev/null; then
  IS_WSL=1
fi

# Ejecuta un comando que puede tardar sin dejar la terminal muda: va mostrando
# los segundos transcurridos en la misma línea. La salida del comando se guarda
# y solo se muestra si falla, para no llenar la pantalla con el ruido de tar,
# cp o adb. Sin terminal (por ejemplo desde Abrir-IDE.bat) no dibuja nada.
# PASO_QUIETO=1 delante de la llamada oculta también el aviso de fallo, para
# los pasos en los que fallar es normal (por ejemplo, si no hay nada que
# importar). PASO_SALIDA=<fichero> guarda la salida del comando, para los pasos
# que devuelven datos en vez de ejecutar algo.
paso() {
  local msg="$1"; shift
  local log status=0 pid secs=0 quieto="${PASO_QUIETO:-0}"
  log="$(mktemp "${TMPDIR:-/tmp}/idea-paso.XXXXXX")" || { "$@"; return; }
  if [ ! -t 1 ]; then
    "$@" >"$log" 2>&1 || status=$?
    if [ "$status" -ne 0 ] && [ "$quieto" != "1" ]; then
      echo "  $msg: ha fallado." >&2
      sed 's/^/    /' "$log" >&2
    fi
    [ -z "${PASO_SALIDA:-}" ] || cp -f "$log" "$PASO_SALIDA" 2>/dev/null || true
    rm -f "$log"
    return "$status"
  fi
  "$@" >"$log" 2>&1 &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    printf '\r  %s... %ds ' "$msg" "$secs"
    sleep 1
    secs=$((secs + 1))
  done
  wait "$pid" || status=$?
  printf '\r\033[K'
  if [ "$status" -ne 0 ] && [ "$quieto" != "1" ]; then
    echo "  $msg: ha fallado." >&2
    sed 's/^/    /' "$log" >&2
  fi
  [ -z "${PASO_SALIDA:-}" ] || cp -f "$log" "$PASO_SALIDA" 2>/dev/null || true
  rm -f "$log"
  return "$status"
}

# C:\Users\x\AppData -> /mnt/c/Users/x/AppData
# local.properties escapa los dos puntos de la unidad (sdk.dir=C\:\\Users\\...),
# así que se normaliza primero ese escape y después las barras.
win_path() {
  local p="$1"
  p="${p//\\:/:}"
  p="${p//\\//}"
  p="$(printf '%s' "$p" | tr -s '/')"
  case "$p" in
    [A-Za-z]:/*) printf '/mnt/%s%s\n' "$(printf '%s' "${p%%:*}" | tr 'A-Z' 'a-z')" "${p#*:}" ;;
    *) printf '%s\n' "$p" ;;
  esac
}

# Pide a Windows su entorno. Cada cmd.exe lanzado desde WSL tarda casi un
# segundo, así que se vuelca todo con un solo `set` en vez de preguntar una
# variable por llamada. Las rutas estándar no sirven siempre: hay perfiles con
# el usuario en otra unidad y administradores que han redirigido AppData, y
# entonces C:\Users\<usuario>\AppData no existe.
win_env_dump() {
  [ "$IS_WSL" = "1" ] || return 1
  command -v cmd.exe >/dev/null 2>&1 || return 1
  cmd.exe /c set 2>/dev/null | tr -d '\r'
}

# Valor de una variable dentro del volcado anterior, ya convertido a /mnt/...
win_env_get() {
  local dump="$1" name="$2" line value=""
  while IFS= read -r line; do
    case "$line" in
      "$name="*) value="${line#*=}"; break ;;
    esac
  done <<< "$dump"
  [ -n "$value" ] || return 0
  win_path "$value"
}

if [ "$IS_WSL" = "1" ]; then
  WIN_ENV_FILE="$(mktemp "${TMPDIR:-/tmp}/idea-winenv.XXXXXX")"
  PASO_QUIETO=1 PASO_SALIDA="$WIN_ENV_FILE" \
    paso "Leyendo la configuración de Windows" win_env_dump || true
  WIN_ENV_DUMP="$(cat "$WIN_ENV_FILE" 2>/dev/null || true)"
  rm -f "$WIN_ENV_FILE"
  WIN_HOME="${WIN_HOME:-$(win_env_get "$WIN_ENV_DUMP" USERPROFILE)}"
  WIN_APPDATA="${WIN_APPDATA:-$(win_env_get "$WIN_ENV_DUMP" APPDATA)}"
  WIN_LOCALAPPDATA="${WIN_LOCALAPPDATA:-$(win_env_get "$WIN_ENV_DUMP" LOCALAPPDATA)}"
  WIN_PROGRAMFILES="${WIN_PROGRAMFILES:-$(win_env_get "$WIN_ENV_DUMP" ProgramFiles)}"
  unset WIN_ENV_DUMP
  [ -n "${WIN_APPDATA:-}" ] || WIN_APPDATA="${WIN_HOME:-}/AppData/Roaming"
  [ -n "${WIN_LOCALAPPDATA:-}" ] || WIN_LOCALAPPDATA="${WIN_HOME:-}/AppData/Local"
fi
if [ "$IS_WSL" = "1" ] && [ -z "${WIN_HOME:-}" ]; then
  echo "Aviso: no localizo tu carpeta de usuario de Windows, así que no se" >&2
  echo "importarán licencia ni ajustes del IDE del host. Define WIN_HOME" >&2
  echo "(por ejemplo /mnt/c/Users/tuUsuario)." >&2
fi

# Un proyecto dentro del sistema de ficheros de WSL vive en un disco virtual:
# un `wsl --unregister` o un ext4.vhdx corrupto se lo lleva entero. El proyecto
# tiene que estar en el disco de Windows, montado como /mnt/c, /mnt/d...
if [ "$IS_WSL" = "1" ] && [ "${ALLOW_WSL_FS:-0}" != "1" ]; then
  case "$PROJECT_DIR" in
    /mnt/*) ;;
    *)
      echo "El proyecto está en $PROJECT_DIR, dentro del disco virtual de WSL." >&2
      echo "Tiene que estar en el disco de Windows: muévelo, por ejemplo, a" >&2
      echo "C:\\Users\\<usuario>\\IdeaProjects\\ y abre Abrir-IDE.bat desde ahí." >&2
      echo "Si WSL se corrompe o se reinstala, ese disco virtual se pierde" >&2
      echo "entero, y con él el proyecto." >&2
      echo "ALLOW_WSL_FS=1 lo permite bajo tu responsabilidad." >&2
      exit 1
      ;;
  esac
fi

# Busca la instalación de IntelliJ IDEA de Windows y devuelve la ruta de su
# product-info.json. Hay tres formas habituales de instalarlo (Toolbox, el
# instalador clásico en Program Files y el ZIP descomprimido), y puede haber
# varias versiones a la vez; se usa la más reciente, que es la que el alumno
# tiene abierta y licenciada.
find_windows_product_info() {
  [ "$IS_WSL" = "1" ] || return 1
  local root candidate found
  local roots=()
  [ -n "${WIN_LOCALAPPDATA:-}" ] \
    && roots+=("$WIN_LOCALAPPDATA/JetBrains/Toolbox/apps" "$WIN_LOCALAPPDATA/Programs")
  [ -n "${WIN_PROGRAMFILES:-}" ] && roots+=("$WIN_PROGRAMFILES/JetBrains")
  [ -n "${WIN_HOME:-}" ] \
    && roots+=("$WIN_HOME/AppData/Local/JetBrains/Toolbox/apps" "$WIN_HOME/AppData/Local/Programs")
  for root in "${roots[@]:-}"; do
    [ -d "$root" ] || continue
    while IFS= read -r candidate; do
      if python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); sys.exit(0 if str(d.get("dataDirectoryName","")).startswith("IntelliJIdea") else 1)' "$candidate" 2>/dev/null; then
        printf '%s\n' "$candidate"
        return 0
      fi
    done < <(find "$root" -maxdepth 4 -name product-info.json -printf '%T@ %p\n' 2>/dev/null \
               | sort -rn | cut -d' ' -f2-)
  done
  return 1
}

first_existing() {
  local p
  for p in "$@"; do
    if [ -e "$p" ]; then
      printf '%s\n' "$p"
      return 0
    fi
  done
  return 1
}

# El mismo script sirve para Podman y Docker. Se prefiere Podman (no necesita
# demonio) y se puede forzar el motor con CONTAINER_ENGINE=docker.
if [ -z "${CONTAINER_ENGINE:-}" ]; then
  if command -v podman >/dev/null 2>&1; then
    CONTAINER_ENGINE=podman
  elif command -v docker >/dev/null 2>&1; then
    CONTAINER_ENGINE=docker
  else
    echo "No encuentro Podman ni Docker. Instala uno de los dos o define" >&2
    echo "CONTAINER_ENGINE con el comando a usar." >&2
    exit 1
  fi
fi
if ! command -v "$CONTAINER_ENGINE" >/dev/null 2>&1; then
  echo "CONTAINER_ENGINE=$CONTAINER_ENGINE no está instalado." >&2
  exit 1
fi

# Mapeo de usuario: Podman rootless usa keep-id para que el usuario del
# contenedor sea el del host. Docker no tiene esa opción, así que en Linux se
# pasan UID/GID explícitos. En Docker Desktop (macOS/Windows) no hace falta:
# la máquina virtual ya traduce los permisos de los volúmenes.
USER_ARGS=()
if [ "$CONTAINER_ENGINE" = "podman" ]; then
  USER_ARGS=(--userns=keep-id)
elif [ "$(uname -s)" = "Linux" ]; then
  USER_ARGS=(--user "$(id -u):$(id -g)")
fi

# En Fedora/RHEL con SELinux en enforcing, container_t no puede ejecutar el
# IDE montado del host ni escribir en /workspace: los bind mounts conservan la
# etiqueta del home (data_home_t, cache_home_t) y "ro" no la cambia. La opción
# :z reetiquetaría el origen (los ~2 GB de Toolbox, y Toolbox lo revierte al
# actualizar), así que se desactiva el etiquetado solo para este contenedor,
# que sigue aislado por namespaces. En Ubuntu nativo y en WSL2 no hay SELinux y
# no se añade nada. KEEP_SELINUX=1 conserva el etiquetado (hará falta :z).
SELINUX_ARGS=()
if [ "${KEEP_SELINUX:-0}" != "1" ]; then
  if { [ -r /sys/fs/selinux/enforce ] \
       && [ "$(cat /sys/fs/selinux/enforce 2>/dev/null)" = "1" ]; } \
     || [ "$(getenforce 2>/dev/null || true)" = "Enforcing" ]; then
    SELINUX_ARGS=(--security-opt label=disable)
  fi
fi

STATE_DIR="${STATE_DIR:-$HOME/.local/share/idea-container}"
GRADLE_CACHE="${GRADLE_CACHE:-$STATE_DIR/gradle}"
CONTAINER_NAME="${CONTAINER_NAME:-idea-desktop-test}"
NETWORK="${NETWORK:-bridge}"
ADB_HOST="${ADB_HOST:-127.0.0.1}"
DRY_RUN="${DRY_RUN:-0}"

# Devuelve la ruta de un IDE Linux utilizable dentro del directorio dado. Toolbox
# instala cada build en ch-<n>/<build>/ y deja un enlace "current", pero otras
# instalaciones (ZIP descomprimido, paquete) tienen bin/idea.sh directamente.
ide_dir_if_valid() {
  local dir="$1" sub
  [ -d "$dir" ] || return 1
  if [ -x "$dir/bin/idea.sh" ]; then
    printf '%s\n' "$dir"
    return 0
  fi
  for sub in "$dir"/ch-*/current "$dir"/ch-*/*; do
    if [ -x "$sub/bin/idea.sh" ]; then
      printf '%s\n' "$sub"
      return 0
    fi
  done
  return 1
}

# Cada alumno instala el IDE donde quiere, así que no basta con una ruta fija:
# el nombre del producto cambia (intellij-idea-ultimate, intellij-idea, IDEA-U)
# y quien no usa Toolbox lo deja en el home o en /opt. Se prueban todas las
# ubicaciones habituales en orden; la primera que tenga bin/idea.sh vale.
detect_ide_home() {
  local candidate
  for candidate in \
    "$HOME/.local/share/JetBrains/Toolbox/apps/intellij-idea-ultimate" \
    "$HOME/.local/share/JetBrains/Toolbox/apps/intellij-idea" \
    "$HOME/.local/share/JetBrains/Toolbox/apps/IDEA-U" \
    "$HOME"/.local/share/JetBrains/Toolbox/apps/intellij-idea* \
    "$HOME"/.local/share/JetBrains/Toolbox/apps/IDEA-U \
    "$HOME"/idea-IU-* \
    "$HOME"/idea-* \
    "$HOME"/opt/idea* \
    "$HOME"/.local/opt/idea* \
    "$HOME"/snap/intellij-idea-ultimate/current \
    /snap/intellij-idea-ultimate/current \
    /opt/idea* \
    /usr/local/idea* \
    /usr/share/idea*; do
    if ide_dir_if_valid "$candidate"; then
      return 0
    fi
  done
  return 1
}

# En Linux se reutiliza el IDE ya instalado en el host: misma versión y cero
# descargas. En WSL ese IDE es de Windows y no sirve dentro del contenedor, así
# que se toma la versión del IDE de Windows y se descarga el Linux en la imagen.
# Por eso la detección solo se hace fuera de WSL: allí un IDE Linux dentro de la
# distro llevaría a mezclar su configuración con la del IDE de Windows.
if [ -z "${IDE_HOME:-}" ] && [ "$IS_WSL" != "1" ]; then
  if IDE_HOME="$(detect_ide_home)"; then
    echo "IDE del host detectado: $IDE_HOME"
  else
    IDE_HOME=""
  fi
fi

product_info_field() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$1" "$2"
}

if [ -n "${IDE_HOME:-}" ]; then
  if [ ! -x "$IDE_HOME/bin/idea.sh" ]; then
    echo "No encuentro la instalación de IntelliJ IDEA en: $IDE_HOME" >&2
    echo "La ruta de IDE_HOME tiene que ser la carpeta que contiene bin/idea.sh." >&2
    echo "Para ver las instalaciones que tienes:" >&2
    echo "  ls ~/.local/share/JetBrains/Toolbox/apps/" >&2
    echo "Y luego:" >&2
    echo "  export IDE_HOME=\"\$HOME/.local/share/JetBrains/Toolbox/apps/intellij-idea\"" >&2
    echo "Si lo dejas vacío en WSL se usa el IDE incluido en la imagen." >&2
    exit 1
  fi
  PRODUCT_INFO="$IDE_HOME/product-info.json"
elif [ "$IS_WSL" = "1" ]; then
  PRODUCT_INFO="$(find_windows_product_info || true)"
else
  echo "No encuentro la instalación de IntelliJ IDEA en el host." >&2
  echo "He buscado en las rutas habituales de Toolbox, en el home y en /opt." >&2
  echo "Para ver las instalaciones que tienes:" >&2
  echo "  ls ~/.local/share/JetBrains/Toolbox/apps/" >&2
  echo "Y luego:" >&2
  echo "  export IDE_HOME=\"\$HOME/.local/share/JetBrains/Toolbox/apps/intellij-idea\"" >&2
  exit 1
fi

if [ -n "${PRODUCT_INFO:-}" ] && [ -f "$PRODUCT_INFO" ]; then
  DATA_DIR_NAME="${DATA_DIR_NAME:-$(product_info_field "$PRODUCT_INFO" dataDirectoryName)}"
  IDEA_VERSION="${IDEA_VERSION:-$(product_info_field "$PRODUCT_INFO" version)}"
fi
if [ -z "${DATA_DIR_NAME:-}" ]; then
  echo "No sé qué versión de IntelliJ IDEA usar." >&2
  echo "Indica DATA_DIR_NAME (por ejemplo IntelliJIdea2026.2) e IDEA_VERSION" >&2
  echo "(por ejemplo 2026.2)." >&2
  exit 1
fi
if [ "$IS_WSL" = "1" ] && [ -z "${IDE_HOME:-}" ] && [ -z "${IDEA_VERSION:-}" ]; then
  echo "Falta IDEA_VERSION para descargar el IDE Linux dentro de la imagen." >&2
  exit 1
fi

IMAGE="${IMAGE:-localhost/idea-desktop:$DATA_DIR_NAME}"

# En Windows no hay IDE Linux que montar, así que se descarga el mismo número
# de versión que el alumno tiene instalado (no se puede usar un IDE de otra
# versión con una configuración y una licencia de otra). Se guarda en el
# directorio de estado, no en la imagen: la imagen sigue siendo pequeña y el
# IDE sobrevive a reconstrucciones. Son ~1,6 GB, solo la primera vez.
if [ "$IS_WSL" = "1" ] && [ -z "${IDE_HOME:-}" ]; then
  LINUX_IDE_DIR="$STATE_DIR/idea-linux/$IDEA_VERSION"
  if [ ! -x "$LINUX_IDE_DIR/bin/idea.sh" ]; then
    echo "Descargando IntelliJ IDEA $IDEA_VERSION para Linux (~1,6 GB)..."
    echo "Solo ocurre la primera vez; se guarda en $LINUX_IDE_DIR"
    mkdir -p "$STATE_DIR/idea-linux"
    DL_DIR="$STATE_DIR/idea-linux/.download"
    rm -rf "$DL_DIR"
    mkdir -p "$DL_DIR"
    if ! curl -fL --progress-bar -o "$DL_DIR/idea.tar.gz" \
           "https://download.jetbrains.com/idea/ideaIU-$IDEA_VERSION.tar.gz"; then
      rm -rf "$DL_DIR"
      echo "No he podido descargar IntelliJ IDEA $IDEA_VERSION." >&2
      echo "Comprueba la conexión o define IDE_HOME con un IDE Linux ya" >&2
      echo "instalado." >&2
      exit 1
    fi
    descomprimir_ide() { tar -xzf "$DL_DIR/idea.tar.gz" -C "$DL_DIR" --strip-components=1; }
    paso "Descomprimiendo IntelliJ IDEA" descomprimir_ide
    rm -f "$DL_DIR/idea.tar.gz"
    rm -rf "$LINUX_IDE_DIR"
    mv "$DL_DIR" "$LINUX_IDE_DIR"
  fi
  IDE_HOME="$LINUX_IDE_DIR"
fi

# El IDE del host solo se puede montar si es un binario Linux.
IDE_MOUNT_ARGS=()
if [ -n "${IDE_HOME:-}" ]; then
  IDE_MOUNT_ARGS=(-v "$IDE_HOME:/opt/idea:ro")
fi

# Directorios del IDE del host. En Windows (visto desde WSL) la configuración,
# los plugins y el consentimiento están bajo %APPDATA%\JetBrains, y las
# preferencias de Java bajo %USERPROFILE%\.java.
if [ "$IS_WSL" = "1" ]; then
  HOST_COMMON_DATA="${HOST_COMMON_DATA:-${WIN_APPDATA:-}/JetBrains}"
  HOST_CONFIG_ROOT="${HOST_CONFIG_ROOT:-${WIN_APPDATA:-}/JetBrains}"
  HOST_CONFIG="${HOST_CONFIG:-$HOST_COMMON_DATA/$DATA_DIR_NAME}"
  HOST_PREFS="${HOST_PREFS:-${WIN_HOME:-}/.java/.userPrefs/jetbrains}"
  HOST_PLUGIN_DIR="${HOST_PLUGIN_DIR:-$HOST_CONFIG/plugins}"
else
  HOST_COMMON_DATA="${HOST_COMMON_DATA:-$HOME/.local/share/JetBrains}"
  HOST_CONFIG_ROOT="${HOST_CONFIG_ROOT:-$HOME/.config/JetBrains}"
  HOST_CONFIG="${HOST_CONFIG:-$HOME/.config/JetBrains/$DATA_DIR_NAME}"
  HOST_PREFS="${HOST_PREFS:-$HOME/.java/.userPrefs/jetbrains}"
  HOST_PLUGIN_DIR="${HOST_PLUGIN_DIR:-$HOST_COMMON_DATA/$DATA_DIR_NAME}"
fi

ANDROID_HOME_STATE="${ANDROID_HOME_STATE:-$STATE_DIR/android-home}"
JAVA_STATE="${JAVA_STATE:-$STATE_DIR/java}"
RUNTIME_DIR_STATE="${RUNTIME_DIR_STATE:-$STATE_DIR/run}"
ADB_BRIDGE="${ADB_BRIDGE:-1}"
ADB_BRIDGE_DIR="$STATE_DIR/adb"
ADB_BRIDGE_SOCKET="$ADB_BRIDGE_DIR/adb.sock"

if [ -z "${DISPLAY:-}" ]; then
  echo "DISPLAY no está definido: no hay servidor X al que conectar la ventana." >&2
  if [ "$IS_WSL" = "1" ]; then
    echo "En WSL debería venir definido por WSLg. Comprueba con 'wsl -l -v'" >&2
    echo "que la distro es versión 2 y que Windows está actualizado." >&2
  fi
  exit 1
fi

mkdir -p "$STATE_DIR/config" "$STATE_DIR/cache" "$STATE_DIR/data" "$GRADLE_CACHE" \
         "$ANDROID_HOME_STATE" "$ADB_BRIDGE_DIR" "$JAVA_STATE" "$RUNTIME_DIR_STATE"

# El IDE guarda el consentimiento de términos, la cuenta JetBrains y la
# licencia fuera del directorio del producto (por ejemplo consentOptions es
# hermano de él). Se persiste el árbol completo de configuración y datos para
# no repetir la aceptación de términos ni el login en cada arranque.
# La aceptación del EULA no está aquí: Java Preferences la guarda en
# ~/.java/.userPrefs (clave eua_accepted_version), de ahí el montaje de $JAVA_STATE.
PRODUCT_CONFIG="$STATE_DIR/config/$DATA_DIR_NAME"
PRODUCT_DATA="$STATE_DIR/data/$DATA_DIR_NAME"
mkdir -p "$PRODUCT_CONFIG" "$PRODUCT_DATA"

# Migración desde el diseño anterior, que montaba solo el directorio del producto.
for entry in "$STATE_DIR/config"/*; do
  [ -e "$entry" ] || continue
  [ "$entry" = "$PRODUCT_CONFIG" ] && continue
  mv "$entry" "$PRODUCT_CONFIG/" 2>/dev/null || true
done
for entry in "$STATE_DIR/data"/*; do
  [ -e "$entry" ] || continue
  case "$(basename "$entry")" in
    "$DATA_DIR_NAME"|consentOptions) continue ;;
  esac
  mv "$entry" "$PRODUCT_DATA/" 2>/dev/null || true
done

# Do not share ~/.gradle with the host: its Gradle daemon keeps the journal
# cache locked. Seed a private cache once so the container can work offline.
# En WSL no se siembra: la caché de Windows trae artefactos y wrappers de
# Windows que dentro del contenedor no sirven.
# La copia puede ser de varios GB (la caché de Android es grande), así que
# tarda lo suyo y por eso se muestra el latido. --reflink=auto no cuesta nada
# donde no hay soporte y en btrfs/XFS la copia es instantánea y no ocupa.
# SEED_GRADLE_CACHE=0 se la salta y Gradle descarga lo que necesite.
if [ ! -f "$GRADLE_CACHE/.seeded-from-host" ] && [ "$IS_WSL" != "1" ] \
   && [ "${SEED_GRADLE_CACHE:-1}" = "1" ] && [ -d "$HOME/.gradle/wrapper" ]; then
  seed_size="$(mktemp "${TMPDIR:-/tmp}/idea-seed.XXXXXX")"
  sembrar_cache_gradle() {
    cp -a --reflink=auto "$HOME/.gradle/wrapper" "$HOME/.gradle/caches" "$GRADLE_CACHE/"
    du -sh "$GRADLE_CACHE" 2>/dev/null | cut -f1
  }
  if PASO_SALIDA="$seed_size" \
     paso "Copiando la caché de Gradle del host (solo la primera vez)" sembrar_cache_gradle; then
    touch "$GRADLE_CACHE/.seeded-from-host"
    echo "Caché de Gradle copiada en $GRADLE_CACHE ($(tail -n 1 "$seed_size" 2>/dev/null))."
  else
    echo "Aviso: no he podido copiar la caché de Gradle; se descargará al compilar." >&2
  fi
  rm -f "$seed_size"
fi

# Si la ventana anterior se cerró de golpe (Ctrl+C, terminal cerrada) puede
# quedar el contenedor con el mismo nombre y el nuevo `run` fallaría. Se
# comprueba antes de la copia de seguridad para no gastar copias en balde.
if [ "$DRY_RUN" != "1" ] \
   && "$CONTAINER_ENGINE" inspect --type container "$CONTAINER_NAME" >/dev/null 2>&1; then
  if [ "$("$CONTAINER_ENGINE" inspect -f '{{.State.Running}}' "$CONTAINER_NAME" 2>/dev/null)" = "true" ]; then
    echo "Ya hay un IDE abierto en el contenedor $CONTAINER_NAME." >&2
    echo "Cierra esa ventana antes de abrir otra, o límpialo con:" >&2
    echo "  $CONTAINER_ENGINE rm -f $CONTAINER_NAME" >&2
    exit 1
  fi
  echo "Quitando el contenedor anterior, que quedó a medias..."
  "$CONTAINER_ENGINE" rm -f "$CONTAINER_NAME" >/dev/null 2>&1 || true
fi

# Copia de seguridad del árbol de fuentes antes de arrancar. El proyecto vive
# en el disco del host, así que esto es una red de seguridad extra y no un
# sustituto de git: cubre un guardado corrupto o un borrado accidental desde
# el IDE. Se conservan las tres copias más recientes de cada proyecto (el
# directorio de estado es común a todos los exámenes). AUTO_BACKUP=0 la anula.
#
# Solo se copia lo que el alumno escribe. Todo lo demás lo regeneran Gradle y
# el IDE y es lo que hace que la copia tarde y ocupe: build/ de cada módulo,
# .gradle/, .idea/, .kotlin/, los restos del NDK (.cxx, .externalNativeBuild)
# y los binarios empaquetados. Con esas exclusiones un proyecto de examen
# ocupa unos cientos de KB en vez de varios GB.
if [ "${AUTO_BACKUP:-1}" = "1" ]; then
  BACKUP_DIR="$STATE_DIR/backups/$(basename "$PROJECT_DIR")"
  mkdir -p "$BACKUP_DIR"
  backup_target="$BACKUP_DIR/$(date +%Y%m%d-%H%M%S)"
  BACKUP_EXCLUDES=(--exclude-vcs --exclude=.git --exclude=build
                   --exclude=.gradle --exclude=.idea --exclude=.kotlin
                   --exclude=.cxx --exclude=.externalNativeBuild
                   --exclude=captures --exclude='*.apk' --exclude='*.aab'
                   --exclude='*.hprof')
  if mkdir "$backup_target" 2>/dev/null; then
    hacer_copia() {
      # timeout: si el árbol vive en /mnt/c (WSL) o tiene algo raro, la copia
      # no puede dejar el arranque esperando para siempre.
      timeout 180 tar -C "$PROJECT_DIR" -cf - "${BACKUP_EXCLUDES[@]}" . \
        | tar -C "$backup_target" -xf -
    }
    if paso "Copia de seguridad del proyecto" hacer_copia; then
      echo "Copia de seguridad del proyecto en $backup_target ($(du -sh "$backup_target" 2>/dev/null | cut -f1))"
    else
      rm -rf "$backup_target"
      echo "Aviso: no he podido hacer la copia de seguridad; sigo adelante." >&2
    fi
    borrar_copias_viejas() {
      find "$BACKUP_DIR" -mindepth 1 -maxdepth 1 -type d -printf '%T@ %p\n' 2>/dev/null \
        | sort -rn | tail -n +4 | cut -d' ' -f2- \
        | while IFS= read -r old; do rm -rf "$old"; done
    }
    paso "Borrando las copias de seguridad antiguas" borrar_copias_viejas || true
  fi
fi

# El alumno puede tener el IDE en el directorio de producto de otra versión
# (Toolbox deja varias instaladas) o haber instalado otra copia, así que no se
# exige una ruta exacta: se busca el idea.key más reciente en todo el árbol de
# configuración de JetBrains. Devuelve la ruta del que se vaya a usar.
find_host_license() {
  local root="$1"
  [ -d "$root" ] || return 1
  find "$root" -maxdepth 3 -type f -name idea.key -printf '%T@ %p\n' 2>/dev/null \
    | sort -rn | head -n 1 | cut -d' ' -f2-
}

xml_escape() {
  local s="$1"
  s="${s//&/&amp;}"
  s="${s//</&lt;}"
  s="${s//>/&gt;}"
  s="${s//\"/&quot;}"
  printf '%s' "$s"
}

# Deshace el escapado que java.util.prefs aplica al guardar en el registro:
# "\" es un "/" y "//" es un "\" literal ("//r", "//n" y "//t" son los saltos).
prefs_decode() {
  local s="$1" out="" i=0 c n
  while [ "$i" -lt "${#s}" ]; do
    c="${s:i:1}"
    if [ "$c" = "/" ] && [ "${s:i+1:1}" = "/" ]; then
      n="${s:i+2:1}"
      case "$n" in
        r) out+=$'\r'; i=$((i + 3)) ;;
        n) out+=$'\n'; i=$((i + 3)) ;;
        t) out+=$'\t'; i=$((i + 3)) ;;
        *) out+='\'; i=$((i + 2)) ;;
      esac
    elif [ "$c" = '\' ]; then
      out+="/"; i=$((i + 1))
    else
      out+="$c"; i=$((i + 1))
    fi
  done
  printf '%s' "$out"
}

# En Windows java.util.prefs no usa ficheros: guarda los nodos en el registro
# (HKCU\Software\JavaSoft\Prefs), así que ~/.java/.userPrefs no existe y la
# cuenta JetBrains no se puede copiar como fichero. Se exporta esa rama y se
# reconstruye el árbol de prefs.xml que espera el IDE de Linux: un directorio
# por nodo, con sus entradas en prefs.xml.
import_windows_prefs() {
  local dest="$1" dump line cur="" rel rest name tail type value
  [ "$IS_WSL" = "1" ] || return 1
  command -v reg.exe >/dev/null 2>&1 || return 1
  dump="$(reg.exe query 'HKCU\Software\JavaSoft\Prefs\jetbrains' /s 2>/dev/null | tr -d '\r')" || true
  [ -n "$dump" ] || return 1
  while IFS= read -r line; do
    case "$line" in
      HKEY_*)
        # Cierra el nodo anterior y abre el nuevo con la cabecera del formato.
        [ -z "$cur" ] || printf '</map>\n' >> "$cur"
        rel="${line#HKEY_CURRENT_USER\\Software\\JavaSoft\\Prefs\\jetbrains}"
        rel="${rel#\\}"
        rel="${rel//\\//}"
        mkdir -p "$dest/$rel"
        cur="$dest/$rel/prefs.xml"
        {
          printf '<?xml version="1.0" encoding="UTF-8" standalone="no"?>\n'
          printf '<!DOCTYPE map SYSTEM "http://java.sun.com/dtd/preferences.dtd">\n'
          printf '<map MAP_XML_VERSION="1.0">\n'
        } > "$cur"
        ;;
      " "*)
        [ -n "$cur" ] || continue
        rest="${line#"${line%%[![:space:]]*}"}"
        case "$rest" in *"    REG_"*) ;; *) continue ;; esac
        name="${rest%%    REG_*}"
        # reg query alinea las columnas: el nombre lleva espacios de relleno
        # detrás y el valor puede llevarlos delante.
        name="${name%"${name##*[![:space:]]}"}"
        tail="${rest#*    REG_}"
        type="${tail%%    *}"
        case "$tail" in *"    "*) value="${tail#*    }" ;; *) value="" ;; esac
        value="${value#"${value%%[![:space:]]*}"}"
        # Solo los valores de texto: los binarios del registro no los usa el IDE.
        [ "$type" = "SZ" ] || continue
        printf '  <entry key="%s" value="%s" />\n' \
          "$(xml_escape "$(prefs_decode "$name")")" \
          "$(xml_escape "$(prefs_decode "$value")")" >> "$cur"
        ;;
    esac
  done <<< "$dump"
  [ -z "$cur" ] || printf '</map>\n' >> "$cur"
  return 0
}

# La licencia es siempre la del alumno que ejecuta el script: nunca se copia
# una licencia ajena dentro del estado del contenedor. Lo que se reutiliza es
# la activación que ese mismo usuario ya tiene en su IDE del host, para que no
# tenga que volver a iniciar sesión dentro del contenedor.
# Son tres piezas distintas: el ticket de licencia (idea.key), los datos de
# cuenta y aceptación de términos (java.util.prefs) y la respuesta al diálogo
# de envío de estadísticas (consentOptions/accepted, que vive en el directorio
# común de datos, hermano del del producto).
# Solo se copian si el contenedor aún no tiene nada, para no pisar nunca una
# sesión iniciada dentro del propio contenedor. IMPORT_HOST_LICENSE=0 lo anula.
HOST_CONSENT="$HOST_COMMON_DATA/consentOptions/accepted"
CONSENT_FILE="$STATE_DIR/data/consentOptions/accepted"
LICENSE_IMPORTED=0
if [ "${IMPORT_HOST_LICENSE:-1}" = "1" ]; then
  if [ ! -f "$PRODUCT_CONFIG/idea.key" ]; then
    # En Linux el idea.key vive en ~/.config/JetBrains/<producto>/, mientras que
    # en Windows todo cuelga de %APPDATA%\JetBrains. Se buscan los dos árboles
    # porque en cada plataforma solo uno de ellos lo contiene.
    for root in "$HOST_CONFIG_ROOT" "$HOST_COMMON_DATA"; do
      host_key="$(find_host_license "$root")"
      [ -n "$host_key" ] && break
    done
    if [ -n "${host_key:-}" ]; then
      cp -f "$host_key" "$PRODUCT_CONFIG/idea.key"
      echo "Licencia del IDE del host importada en el contenedor ($host_key)."
      LICENSE_IMPORTED=1
    fi
  else
    LICENSE_IMPORTED=1
  fi
  if [ ! -d "$JAVA_STATE/.userPrefs/jetbrains/auth-tokens" ]; then
    if [ -d "$HOST_PREFS" ]; then
      mkdir -p "$JAVA_STATE/.userPrefs"
      cp -a "$HOST_PREFS" "$JAVA_STATE/.userPrefs/jetbrains"
      echo "Cuenta y términos del IDE del host importados en el contenedor."
      LICENSE_IMPORTED=1
    elif PASO_QUIETO=1 paso "Importando la cuenta de JetBrains del registro de Windows" \
           import_windows_prefs "$JAVA_STATE/.userPrefs/jetbrains"; then
      echo "Cuenta de JetBrains del IDE de Windows importada en el contenedor."
      LICENSE_IMPORTED=1
    fi
  else
    LICENSE_IMPORTED=1
  fi
  if [ ! -f "$CONSENT_FILE" ] && [ -f "$HOST_CONSENT" ]; then
    mkdir -p "$(dirname "$CONSENT_FILE")"
    cp -f "$HOST_CONSENT" "$CONSENT_FILE"
    echo "Consentimiento de envío de datos del IDE del host heredado."
  fi
fi

if [ "$LICENSE_IMPORTED" = "0" ]; then
  echo "Aviso: no he encontrado la licencia en el IDE del host, así que el" >&2
  echo "contenedor pedirá iniciar sesión la primera vez (quedará guardada en" >&2
  echo "$PRODUCT_CONFIG). He buscado en:" >&2
  echo "  $HOST_CONFIG_ROOT" >&2
  echo "  $HOST_COMMON_DATA" >&2
  [ "$IS_WSL" != "1" ] || echo "  HKCU\\Software\\JavaSoft\\Prefs\\jetbrains (registro de Windows)" >&2
  echo "Comprueba que has abierto IntelliJ IDEA en el host y has validado la" >&2
  echo "licencia al menos una vez." >&2
fi

# Si el IDE no se cerró limpiamente (contenedor detenido a la fuerza) queda un
# fichero .lock con el socket del arranque anterior y el nuevo proceso se niega
# a iniciar. Como este estado es de un único contenedor, se elimina aquí.
if [ "$DRY_RUN" != "1" ] \
   && ! "$CONTAINER_ENGINE" inspect --type container "$CONTAINER_NAME" >/dev/null 2>&1; then
  rm -f "$PRODUCT_CONFIG/.lock"
fi

if command -v xhost >/dev/null 2>&1; then
  xhost +si:localuser:"$(id -un)" >/dev/null 2>&1 || true
fi

# Android plugins live in the host's user plugin directory. Mount only the
# Android ones: GitHub Copilot and the rest of the host plugins stay out.
PLUGIN_ARGS=()
if [ -d "$HOST_PLUGIN_DIR" ]; then
  for plugin in android design-tools android-compose-ide-plugin; do
    if [ -d "$HOST_PLUGIN_DIR/$plugin" ]; then
      PLUGIN_ARGS+=(-v "$HOST_PLUGIN_DIR/$plugin:/home/developer/.local/share/JetBrains/$DATA_DIR_NAME/$plugin:ro")
    fi
  done
fi

# Keep Copilot (and the AI helpers) disabled even if a plugin is installed
# later. The file is mounted read-only inside the container.
# org.jetbrains.completion.full.line no es el autocompletado del IDE: es el
# plugin "Full Line Code Completion", que completa líneas enteras con un modelo
# de IA y además trae dentro el módulo llmInstaller (ventana de promo y
# autoinstalación de AI Assistant). El autocompletado normal, las plantillas y
# los generadores de código (constructores, getters, setters) son del núcleo del
# IDE y no dependen de ningún plugin.
DISABLED_PLUGINS_FILE="$PRODUCT_CONFIG/disabled_plugins.txt"
touch "$DISABLED_PLUGINS_FILE"
for plugin_id in com.github.copilot com.github.copilot.provider.helper \
                 com.intellij.ml.llm com.intellij.ml.local.models \
                 org.jetbrains.completion.full.line; do
  grep -qxF "$plugin_id" "$DISABLED_PLUGINS_FILE" || echo "$plugin_id" >> "$DISABLED_PLUGINS_FILE"
done

# Segundo cerrojo: con el plugin anterior deshabilitado la ventana que ofrece
# instalar AI Assistant ya no puede cargarse, pero si algún día se reactiva el
# plugin o el módulo llega por otra vía, el estado que escribe el propio IDE al
# descartarla (shouldShowNextTime="NO") evita que vuelva a salir.
PROMO_STATE_FILE="$PRODUCT_CONFIG/options/AIOnboardingPromoWindowAdvisor.xml"
mkdir -p "$(dirname "$PROMO_STATE_FILE")"
if ! grep -qs 'name="shouldShowNextTime" value="NO"' "$PROMO_STATE_FILE"; then
  cat > "$PROMO_STATE_FILE" <<'PROMO_EOF'
<application>
  <component name="AIOnboardingPromoWindowAdvisor">
    <option name="attempts" value="8" />
    <option name="shouldShowNextTime" value="NO" />
  </component>
</application>
PROMO_EOF
fi

# Disabling Copilot is not enough: it could be reinstalled from the plugin
# marketplace. Point the marketplace hosts to localhost inside the container
# so no plugin can be downloaded during the session (BLOCK_PLUGIN_MARKETPLACE=0
# to allow it again).
MARKETPLACE_ARGS=()
if [ "${BLOCK_PLUGIN_MARKETPLACE:-1}" = "1" ]; then
  for host in plugins.jetbrains.com download.jetbrains.com; do
    MARKETPLACE_ARGS+=(--add-host "$host:127.0.0.1")
  done
fi

# La imagen tiene que traer el JDK del contenedor. Comprobar solo si existe no
# basta: quien ya la tuviera construida no la reconstruiría y seguiría sin JDK,
# así que se mira el label con el que se marca la versión que lo incluye.
IMAGE_JDK="$("$CONTAINER_ENGINE" image inspect -f '{{ index .Config.Labels "idea-desktop.jdk" }}' "$IMAGE" 2>/dev/null || true)"
if [ "$DRY_RUN" != "1" ] && [ "$IMAGE_JDK" != "17" ]; then
  echo "Construyendo imagen $IMAGE con $CONTAINER_ENGINE ..."
  "$CONTAINER_ENGINE" build -t "$IMAGE" -f "$SCRIPT_DIR/Dockerfile" "$SCRIPT_DIR"
fi

# El SDK no tiene por qué venir de Android Studio: con los plugins de Android
# e Android Design Tools, el propio IDEA instala el SDK (por defecto en
# %LOCALAPPDATA%\Android\Sdk) y lo registra en config/options/jdk.table.xml.
# local.properties no siempre existe, porque suele estar en .gitignore.
sdk_from_jdk_table() {
  local table="$HOST_CONFIG/options/jdk.table.xml" path
  [ -f "$table" ] || return 1
  path="$(tr -d '\r' < "$table" | awk '
    /<jdk /            { es_sdk = 0 }
    /type value="Android SDK"/ { es_sdk = 1 }
    es_sdk && /<homePath value=/ {
      sub(/.*<homePath value="/, ""); sub(/".*/, ""); print; exit
    }')"
  [ -n "$path" ] || return 1
  [ "$IS_WSL" = "1" ] && path="$(win_path "$path")"
  [ -d "$path" ] || return 1
  printf '%s\n' "$path"
}

detect_sdk_dir() {
  local p
  p="$(sed -n 's/^sdk\.dir=//p' "$PROJECT_DIR/local.properties" 2>/dev/null | tail -n 1)"
  if [ -n "$p" ]; then
    [ "$IS_WSL" = "1" ] && p="$(win_path "$p")"
    [ -d "$p" ] && { printf '%s\n' "$p"; return 0; }
  fi
  for p in "${WIN_HOME:-/nonexistent}/AppData/Local/Android/Sdk" \
           "$HOME/Android/Sdk" "$HOME/Library/Android/sdk"; do
    [ -d "$p" ] && { printf '%s\n' "$p"; return 0; }
  done
  sdk_from_jdk_table
}

# El SDK se monta en una ruta fija del contenedor y se genera un
# local.properties que apunta ahí. Así funciona aunque el proyecto no tenga
# local.properties (está en .gitignore, así que un clon nuevo no lo trae) o
# aunque el del alumno apunte a la ruta de otro equipo. En WSL además el SDK es
# de Windows (ruta C:\... y binarios .exe) y no puede montarse en su ruta.
SDK_DIR="${SDK_DIR:-$(detect_sdk_dir || true)}"
SDK_ARGS=()
LOCAL_PROPS_ARGS=()
CONTAINER_SDK=/opt/android-sdk
if [ -n "$SDK_DIR" ] && [ -d "$SDK_DIR" ]; then
  SDK_ARGS=(-v "$SDK_DIR:$CONTAINER_SDK:ro" \
            -e "ANDROID_HOME=$CONTAINER_SDK" -e "ANDROID_SDK_ROOT=$CONTAINER_SDK")
  CONTAINER_PROPS="$STATE_DIR/local.properties"
  printf 'sdk.dir=%s\n' "$CONTAINER_SDK" > "$CONTAINER_PROPS"
  LOCAL_PROPS_ARGS=(-v "$CONTAINER_PROPS:/workspace/local.properties:ro")
else
  echo "Aviso: no encuentro el SDK de Android." >&2
  if [ "$IS_WSL" = "1" ]; then
    echo "En IntelliJ IDEA de Windows: Settings > Languages & Frameworks >" >&2
    echo "Android SDK, instala el SDK y comprueba que platform-tools está" >&2
    echo "marcado. Sin SDK el proyecto no compilará dentro del contenedor." >&2
  else
    echo "Instálalo desde IntelliJ IDEA (Settings > Languages & Frameworks >" >&2
    echo "Android SDK) o define SDK_DIR con su ruta. Sin SDK el proyecto no" >&2
    echo "compilará dentro del contenedor." >&2
  fi
fi

# The IDE (ddmlib) always connects to localhost:5037, but the adb server runs
# on the host. Bridge the host adb Unix socket into the container so both the
# emulator and a USB device managed by the host adb are visible to the IDE.
ADB_ARGS=()
SOCAT_PID=""
cleanup_adb_bridge() {
  [ -n "$SOCAT_PID" ] && kill "$SOCAT_PID" 2>/dev/null || true
  rm -f "$ADB_BRIDGE_SOCKET"
}
ADB_BIN=""
if [ -n "$SDK_DIR" ]; then
  ADB_BIN="$(first_existing "$SDK_DIR/platform-tools/adb" "$SDK_DIR/platform-tools/adb.exe" || true)"
fi
if [ "$ADB_BRIDGE" = "1" ] && [ -n "$ADB_BIN" ]; then
  if command -v socat >/dev/null 2>&1; then
    # En WSL el servidor adb es un proceso de Windows: tiene que escuchar en
    # todas las interfaces para que el contenedor lo alcance.
    if [ "$IS_WSL" = "1" ]; then
      if [ "$ADB_HOST" = "127.0.0.1" ]; then
        ADB_HOST="$(ip route show default 2>/dev/null | awk '/^default/ {print $3; exit}')"
        ADB_HOST="${ADB_HOST:-127.0.0.1}"
      fi
      PASO_QUIETO=1 paso "Arrancando el servidor adb del host" "$ADB_BIN" -a start-server || true
    else
      PASO_QUIETO=1 paso "Arrancando el servidor adb del host" "$ADB_BIN" start-server || true
    fi
    # timeout: si la IP no es la correcta (o el firewall de Windows descarta
    # los paquetes) un connect a pelo se queda esperando minutos sin decir nada.
    if ! PASO_QUIETO=1 paso "Comprobando el servidor adb en $ADB_HOST:5037" \
           timeout 5 bash -c "exec 3<>/dev/tcp/$ADB_HOST/5037"; then
      echo "Aviso: no alcanzo el servidor adb en $ADB_HOST:5037." >&2
      if [ "$IS_WSL" = "1" ]; then
        echo "En Windows ejecuta: adb kill-server && adb -a start-server" >&2
        echo "Si tu WSL usa redes en modo espejo, prueba ADB_HOST=127.0.0.1." >&2
      fi
    fi
    rm -f "$ADB_BRIDGE_SOCKET"
    socat UNIX-LISTEN:"$ADB_BRIDGE_SOCKET",fork,reuseaddr "TCP:$ADB_HOST:5037" &
    SOCAT_PID=$!
    for _ in $(seq 1 20); do
      [ -S "$ADB_BRIDGE_SOCKET" ] && break
      sleep 0.1
    done
    if [ -S "$ADB_BRIDGE_SOCKET" ]; then
      ADB_ARGS=(-v "$ADB_BRIDGE_DIR:/home/developer/.adb-bridge" \
                -e "ADB_BRIDGE_SOCKET=/home/developer/.adb-bridge/adb.sock")
      trap cleanup_adb_bridge EXIT
    else
      echo "Aviso: no se pudo crear el puente ADB; el IDE no verá dispositivos." >&2
    fi
  else
    echo "Aviso: instala socat en el host para que el IDE vea el emulador." >&2
  fi
fi

# The project's Gradle JVM points to a host path; mount it at the same path.
JDKS_DIR="$(first_existing "$HOME/.jdks" "${WIN_HOME:-/nonexistent}/.jdks" || true)"
JDKS_ARGS=()
if [ -d "$JDKS_DIR" ]; then
  JDKS_ARGS=(-v "$JDKS_DIR:$JDKS_DIR:ro")
fi

# En WSL las claves, la configuración de git y el keystore están en la carpeta
# del usuario de Windows, no en la del usuario de Linux.
GITCONFIG_ARGS=()
gitconfig="$(first_existing "$HOME/.gitconfig" "${WIN_HOME:-/nonexistent}/.gitconfig" || true)"
if [ -n "$gitconfig" ]; then
  GITCONFIG_ARGS+=(-v "$gitconfig:/home/developer/.gitconfig:ro")
fi
gitcredentials="$(first_existing "$HOME/.git-credentials" "${WIN_HOME:-/nonexistent}/.git-credentials" || true)"
if [ -n "$gitcredentials" ]; then
  GITCONFIG_ARGS+=(-v "$gitcredentials:/home/developer/.git-credentials:ro")
fi

# Claves SSH del alumno y reenvío del agente para poder hacer `git push`
# a GitHub sin configurar nada dentro del contenedor. En WSL las claves están
# en la carpeta del usuario de Windows y no hay agente SSH que reenviar.
SSH_ARGS=()
ssh_dir="$(first_existing "$HOME/.ssh" "${WIN_HOME:-/nonexistent}/.ssh" || true)"
if [ -n "$ssh_dir" ] && [ -d "$ssh_dir" ]; then
  SSH_ARGS+=(-v "$ssh_dir:/home/developer/.ssh:ro")
fi
if [ "$IS_WSL" != "1" ] && [ -n "${SSH_AUTH_SOCK:-}" ] && [ -S "${SSH_AUTH_SOCK:-}" ]; then
  SSH_ARGS+=(-v "$SSH_AUTH_SOCK:/tmp/ssh-agent.sock" -e SSH_AUTH_SOCK=/tmp/ssh-agent.sock)
fi

# La imagen no trae tzdata: se reutiliza la base de zonas del host para que el
# reloj del contenedor coincida con el de fuera (afecta a la validez de la
# licencia y a las marcas de tiempo de los logs).
TZ_ARGS=()
if [ -d /usr/share/zoneinfo ]; then
  TZ_ARGS=(-v /usr/share/zoneinfo:/usr/share/zoneinfo:ro)
fi

# Reuse the host debug keystore so APKs built inside the container have the
# same signature as the ones already installed on the emulator/device.
ANDROID_KEYSTORE_ARGS=()
keystore="$(first_existing "$HOME/.android/debug.keystore" "${WIN_HOME:-/nonexistent}/.android/debug.keystore" || true)"
if [ -n "$keystore" ] && [ -f "$keystore" ]; then
  ANDROID_KEYSTORE_ARGS=(-v "$keystore:/home/developer/.android/debug.keystore:ro")
fi

RUN_ARGS=(
  run --rm -it
  --name "$CONTAINER_NAME"
  --init
  "${USER_ARGS[@]}"
  "${SELINUX_ARGS[@]}"
  --network "$NETWORK"
  --shm-size=1g
  -e "DISPLAY=$DISPLAY"
  -e HOME=/home/developer
  -e LANG=C.UTF-8
  -e "TZ=${TZ:-$(cat /etc/timezone 2>/dev/null || echo UTC)}"
  -e XDG_RUNTIME_DIR=/home/developer/.run
  -e NO_AT_BRIDGE=1
  -e GRADLE_USER_HOME=/home/developer/.gradle
  -e ANDROID_USER_HOME=/home/developer/.android
  -e JDK_HOME=/opt/jdk-17
  -e "DATA_DIR_NAME=$DATA_DIR_NAME"
  -e PROJECT_DIR=/workspace
  -e REMOTE_CONTAINERS=1
  -e ADB_SERVER_SOCKET=tcp:127.0.0.1:5037
  -e _JAVA_AWT_WM_NONREPARENTING=1
  -v /tmp/.X11-unix:/tmp/.X11-unix:ro
  "${IDE_MOUNT_ARGS[@]}"
  -v "$PROJECT_DIR:/workspace"
  "${LOCAL_PROPS_ARGS[@]}"
  -v "$STATE_DIR/config:/home/developer/.config/JetBrains"
  -v "$DISABLED_PLUGINS_FILE:/home/developer/.config/JetBrains/$DATA_DIR_NAME/disabled_plugins.txt:ro"
  -v "$STATE_DIR/cache:/home/developer/.cache/JetBrains/$DATA_DIR_NAME"
  -v "$STATE_DIR/data:/home/developer/.local/share/JetBrains"
  -v "$ANDROID_HOME_STATE:/home/developer/.android"
  -v "$JAVA_STATE:/home/developer/.java"
  -v "$RUNTIME_DIR_STATE:/home/developer/.run"
  "${ANDROID_KEYSTORE_ARGS[@]}"
  -v "$GRADLE_CACHE:/home/developer/.gradle"
  "${PLUGIN_ARGS[@]}"
  "${SDK_ARGS[@]}"
  "${JDKS_ARGS[@]}"
  "${GITCONFIG_ARGS[@]}"
  "${SSH_ARGS[@]}"
  "${ADB_ARGS[@]}"
  "${TZ_ARGS[@]}"
  "${MARKETPLACE_ARGS[@]}"
  "$IMAGE"
  /opt/idea/bin/idea.sh /workspace
)

# DRY_RUN=1 imprime el comando sin arrancar nada: sirve para revisar los
# montajes en una máquina nueva antes de gastar tiempo en la descarga.
if [ "${DRY_RUN:-0}" = "1" ]; then
  echo "Comando que se ejecutaría:"
  printf ' %q' "$CONTAINER_ENGINE" "${RUN_ARGS[@]}"
  echo
  exit 0
fi

echo "Abriendo IntelliJ IDEA en contenedor ($CONTAINER_ENGINE, red: $NETWORK)..."
"$CONTAINER_ENGINE" "${RUN_ARGS[@]}"
