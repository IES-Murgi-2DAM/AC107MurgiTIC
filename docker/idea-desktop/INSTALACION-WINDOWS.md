# Preparar el equipo (Windows 10/11)

Requisitos previos para poder abrir el proyecto con el IDE del contenedor.

Los permisos de administrador solo hacen falta en la instalación inicial
(secciones 1 y 2). Para usar el IDE se arranca con doble clic y sin elevar.

Si trabajas en **Linux nativo** (Ubuntu, Debian, Fedora…), no necesitas WSL ni
Docker Desktop: mira la **sección 9**.

## 1. WSL2 con Ubuntu

En PowerShell **como administrador**:

```powershell
wsl --install -d Ubuntu
```

Reinicia el equipo y, cuando se abra la ventana de Ubuntu, crea el usuario y la
contraseña de Linux (pueden ser distintos de los de Windows; apúntalos).

Comprueba que la distro es de tipo 2:

```powershell
wsl -l -v
```

Debe aparecer `VERSION 2` en la fila de Ubuntu. Si pone `1`:

```powershell
wsl --set-version Ubuntu 2
```

Y actualiza WSL, que hace falta para WSLg y para `wsl --cd`:

```powershell
wsl --update
```

## 2. Docker Desktop

1. Descarga e instala **Docker Desktop** desde <https://www.docker.com/products/docker-desktop/>.
2. En la primera configuración deja marcado **Use WSL 2 based engine**.
3. En *Settings → Resources → WSL integration* activa la integración con **Ubuntu**.
4. Comprueba desde la ventana de Ubuntu:

```bash
docker run --rm hello-world
```

Si responde `Hello from Docker!`, está listo.

## 3. Dependencias de Ubuntu en WSL (`socat`) y WSLg

WSL2 ya incluye WSLg, no hace falta instalar ningún servidor X en Windows.

`socat` es **obligatorio**: es el puente entre el IDE del contenedor y el adb
del host. Sin él el IDE arranca, pero el Device Manager sale vacío aunque el
emulador esté en marcha. Se instala **en Ubuntu (WSL)**, no en Windows, porque
el lanzador y el puente se ejecutan en la distro:

```bash
sudo apt update
sudo apt install -y socat git curl x11-apps
xeyes
```

Debe aparecer una ventana con unos ojos. Si no aparece, actualiza Windows
(`wsl --update`) antes de continuar.

Si usas **Linux nativo** en lugar de Windows, `socat` también es obligatorio
(ver la sección 9).

## 4. IntelliJ IDEA Ultimate (no hace falta Android Studio)

En Windows solo necesitas **IntelliJ IDEA Ultimate** con dos plugins
instalados y activados (*Settings → Plugins*):

- **Android**
- **Android Design Tools**

Con esos dos plugins el IDE instala el SDK de Android, crea los AVD y arranca
el emulador, igual que Android Studio. Comprueba en
*Settings → Languages & Frameworks → Android SDK* que hay un SDK instalado y
que **platform-tools** está marcado (lo necesita el lanzador para el adb).

El lanzador toma del IDE de Windows la versión del IDE, la licencia, la
configuración, los plugins y la ruta del SDK (por defecto
`%LOCALAPPDATA%\Android\Sdk`; si lo instalaste en otra carpeta lo lee de
`config/options/jdk.table.xml`). No hace falta `local.properties`.

> El IDE de Windows y el del contenedor tienen que ser la **misma versión**:
> el lanzador lo comprueba y descarga la versión de Linux equivalente.

> **El JDK lo pone el contenedor, no el equipo**: la imagen incluye un
> **JDK 17** (OpenJDK) en `/opt/jdk-17` y lo registra automáticamente en
> IntelliJ con el nombre que pida el proyecto (en este proyecto,
> `corretto-17`). No hace falta instalar ningún JDK en Windows ni en Ubuntu, y
> el JDK del host no se monta para compilar.

## 5. Dónde tiene que estar el proyecto

El proyecto **tiene que estar en el disco de Windows**. Cada alumno lo tendrá
donde suela clonar; las ubicaciones habituales son:

| Sitio | Ruta real |
|---|---|
| IdeaProjects (al clonar desde IntelliJ) | `C:\Users\<tu-usuario>\IdeaProjects\<carpeta-proyecto>` |
| Escritorio | `C:\Users\<tu-usuario>\Desktop\<carpeta-proyecto>` |
| Descargas | `C:\Users\<tu-usuario>\Downloads\<carpeta-proyecto>` |
| Documentos | `C:\Users\<tu-usuario>\Documents\<carpeta-proyecto>` |

Las carpetas se llaman así aunque Windows las muestre en español
(*Escritorio*, *Descargas*, *Documentos*). Todas las ubicaciones valen: lo que
importa es abrir `Abrir-IDE.bat` **desde la carpeta donde está el proyecto**. La
ventana muestra la ruta completa antes de arrancar, así que se comprueba de un
vistazo.

> **Cuidado con Escritorio y Documentos si están sincronizados con OneDrive**
> (`C:\Users\<tu-usuario>\OneDrive\...`). Gradle genera miles de ficheros y la
> sincronización puede bloquearlos o dejar el proyecto a medias. En ese caso, es
> mejor mover el proyecto a `IdeaProjects`.

> **No lo clones en el home de Ubuntu** (`/home/...`). Vive en el disco virtual
> de WSL (`ext4.vhdx`) y se pierde si la distro se corrompe o se reinstala. El
> lanzador se niega a arrancar ahí. Si clonas desde una terminal de WSL, hazlo en
> `/mnt/c/Users/<tu-usuario>/IdeaProjects/...`.

## 6. Arrancar el IDE

**Doble clic en `Abrir-IDE.bat`**, en la raíz del proyecto (Explorador de
Windows, sin consola y sin permisos de administrador).

Se abre una ventana de consola que dice `Abriendo IntelliJ IDEA en el
contenedor...` y, encima, la ventana del IDE. **Esa consola es el IDE**: no se
cierra hasta que salgas de IntelliJ.

Para tenerlo a mano: clic derecho en `Abrir-IDE.bat` → *Enviar a* → *Escritorio
(crear acceso directo)*.

> No lo ejecutes **como administrador**. Docker Desktop y WSL trabajan en tu
> sesión de usuario; elevado, Docker no ve el contexto ni las unidades. Los
> permisos de administrador solo hacen falta en la instalación inicial
> (secciones 1 y 2).

Si prefieres hacerlo desde Ubuntu en WSL:

```bash
cd /mnt/c/Users/<tu-usuario>/IdeaProjects/<carpeta-proyecto>
bash docker/idea-desktop/run-idea.sh
```

La primera vez descarga el IDE de Linux de la misma versión que el de Windows
(~1,6 GB) y lo guarda en `~/.local/share/idea-container/idea-linux/`. Las
siguientes veces arranca en segundos.

## 7. Emulador o móvil por USB

El emulador se ejecuta **en el host** —en Windows, o en Linux nativo—, nunca
dentro del contenedor: el IDE del contenedor solo lo ve como un dispositivo
conectado por adb.

1. Abre IntelliJ IDEA en Windows y crea el AVD en el **Device Manager**
   (solo hace falta la primera vez).
2. Arranca el emulador **antes** de abrir el IDE del contenedor, mejor desde una
   terminal (ver el aviso de abajo).
3. Comprueba en PowerShell: `adb devices` debe listar el emulador.
4. Arranca el IDE con el lanzador: él mismo ejecuta `adb -a start-server` y crea
   el puente para que el IDE del contenedor vea el dispositivo.

> **Arranca el AVD desde la terminal, no desde el Device Manager del IDE del
> host.** Si lo lanza ese IDE, el emulador arranca **sin ventana**
> (`-qt-hide-window`) y se muestra **incrustado** en su tool window de
> dispositivos. Si luego cierras ese IDE, el emulador sigue vivo pero **ya no se
> ve en ningún sitio**: no basta con cerrar el IDE, hay que matar el proceso y
> volver a arrancarlo.
>
> ```bash
> # Linux nativo, WSL o macOS
> "$ANDROID_HOME/emulator/emulator" -avd Pixel_6a
> ```
>
> ```powershell
> # Windows (PowerShell)
> & "$env:LOCALAPPDATA\Android\Sdk\emulator\emulator.exe" -avd Pixel_6a
> ```

En **Linux nativo** los pasos son los mismos cambiando «IntelliJ IDEA en
Windows» por el IDE del host y PowerShell por la terminal; allí el lanzador
ejecuta `adb start-server` (sin `-a`) porque adb escucha ya en `127.0.0.1`.

Dentro del IDE del contenedor el Device Manager mostrará el emulador ya
arrancado, pero **no podrá crearlo ni iniciarlo** (el emulador es del host).

Si el IDE no muestra el dispositivo, en PowerShell:

```powershell
adb kill-server
adb -a start-server
adb devices
```

y vuelve a lanzar el IDE.

Para un móvil físico, activa *Depuración USB* y acepta el aviso de la huella RSA
en el teléfono (el diálogo aparece en Windows).

## 8. Para quien prefiera la consola (WSL)

Formas de abrir una terminal de Ubuntu, de la más cómoda a la más rápida:

- **Windows Terminal** (ya viene en Windows 11): flecha del menú → **Ubuntu**.
- **Menú Inicio** → escribe `Ubuntu`.
- Desde el **Explorador**, en la carpeta del proyecto, escribe `wsl` en la barra
  de direcciones y pulsa Intro: abre Ubuntu ya situado en esa carpeta.
- Desde PowerShell, dentro de la carpeta del proyecto: `wsl`.

Dentro de Ubuntu:

```bash
cd /mnt/c/Users/<tu-usuario>/IdeaProjects/<carpeta-proyecto>
bash docker/idea-desktop/run-idea.sh
```

Atajo para no repetir el `cd`: añade al final de `~/.bashrc`

```bash
alias ide='bash /mnt/c/Users/<tu-usuario>/<carpeta-proyecto>/docker/idea-desktop/run-idea.sh'
```

y ábrelo con `ide` desde cualquier carpeta.

Variables que acepta el lanzador, por si quieres tocar algo:

| Variable | Para qué |
|---|---|
| `DRY_RUN=1` | Imprime el comando `docker run` sin arrancar nada |
| `NETWORK=none` | Arranca sin red (modo examen aislado) |
| `AUTO_BACKUP=0` | No hace la copia de seguridad del proyecto |
| `ADB_HOST=...` | IP del servidor adb (por defecto la puerta de enlace de WSL) |
| `SDK_DIR=/ruta` | Fuerza la ruta del SDK de Android |
| `CONTAINER_ENGINE=docker` | Fuerza el motor de contenedores |
| `CONTAINER_NAME=...` | Nombre del contenedor (por defecto `idea-desktop-test`) |
| `ALLOW_WSL_FS=1` | Permite arrancar con el proyecto dentro de WSL (bajo tu riesgo) |
| `KEEP_SELINUX=1` | En Fedora/RHEL conserva el etiquetado SELinux (por defecto se desactiva para el contenedor) |

`Ctrl+C` en esa terminal para el contenedor y cierra el IDE. Si la terminal se
cierra de golpe, puede quedar el contenedor ocupando el nombre; el lanzador lo
detecta y te dice qué ejecutar:

```bash
docker rm -f idea-desktop-test
```

Para ver qué hay corriendo: `docker ps`.

## 9. Linux nativo (Ubuntu/Debian o Fedora/RHEL)

No hace falta WSL ni Docker Desktop: con Podman (recomendado) o Docker y
`socat`, el lanzador funciona igual. `socat` es obligatorio por lo mismo que en
WSL: sin él no hay puente con el adb del host y el Device Manager sale vacío.

```bash
# Debian / Ubuntu
sudo apt update && sudo apt install -y socat

# Fedora / RHEL
sudo dnf install -y socat
```

El resto de la guía aplica igual, salvo todo lo específico de WSL y de Docker
Desktop. Desde la carpeta del proyecto:

```bash
bash docker/idea-desktop/run-idea.sh
```

## Problemas frecuentes

| Síntoma | Solución |
|---|---|
| `docker: command not found` en Ubuntu | Falta activar la integración WSL en Docker Desktop |
| No aparece ninguna ventana del IDE | `wsl --update` y comprobar `xeyes` |
| `instala socat en el host` | `sudo apt install -y socat` (Debian/Ubuntu) o `sudo dnf install -y socat` (Fedora/RHEL), y relanza el IDE |
| `no alcanzo el servidor adb` | `adb kill-server && adb -a start-server` en PowerShell |
| El IDE no ve el emulador | Arranca el AVD **antes** que el IDE y comprueba que `socat` está instalado (secciones 3 y 9) |
| Pide login de JetBrains | Abre una vez IntelliJ IDEA en Windows y valida la licencia |
| `Ya hay un IDE abierto en el contenedor` | Ya hay una ventana del IDE abierta, o quedó un contenedor suelto: `docker rm -f idea-desktop-test` |
| El IDE avisa de que falta un componente del SDK y no puede instalarlo | El SDK se monta de solo lectura: instálalo en el IDEA de Windows y vuelve a abrir |
