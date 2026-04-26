#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_NAME="${0##*/}"
DRY_RUN=0
RUN_UPGRADE=0
VERIFY_ONLY=0
APT_UPDATED=0
APT_PREPARED=0

declare -a REQUESTED=()
declare -a WARNINGS=()
declare -a VERIFY_ERRORS=()
declare -A DONE=()
declare -a SUDO=()

trap 'error "Fallo en la linea ${LINENO}: ${BASH_COMMAND}"; exit 1' ERR

log() {
    printf '[INFO] %s\n' "$*"
}

ok() {
    printf '[OK] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*" >&2
    WARNINGS+=("$*")
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

die() {
    error "$*"
    exit 1
}

print_command() {
    printf '+'
    printf ' %q' "$@"
    printf '\n'
}

run_cmd() {
    print_command "$@"
    if (( DRY_RUN )); then
        return 0
    fi

    "$@"
}

run_cmd_status() {
    local status

    print_command "$@"
    if (( DRY_RUN )); then
        return 0
    fi

    set +e
    "$@"
    status=$?
    set -e
    return "$status"
}

root_run() {
    if ((${#SUDO[@]})); then
        run_cmd "${SUDO[@]}" "$@"
    else
        run_cmd "$@"
    fi
}

root_env_run() {
    local env_vars=(
        "DEBIAN_FRONTEND=${DEBIAN_FRONTEND:-noninteractive}"
        "APT_LISTCHANGES_FRONTEND=${APT_LISTCHANGES_FRONTEND:-none}"
        "NEEDRESTART_MODE=${NEEDRESTART_MODE:-a}"
    )

    if ((${#SUDO[@]})); then
        run_cmd "${SUDO[@]}" env "${env_vars[@]}" "$@"
    else
        run_cmd env "${env_vars[@]}" "$@"
    fi
}

usage() {
    cat <<USAGE
Uso:
  ./${SCRIPT_NAME} [opciones] [selecciones...]

Opciones:
  -n, --dry-run       Muestra lo que haria sin instalar nada.
  --upgrade          Ejecuta apt-get upgrade al final.
  --verify-only      Ejecuta verificaciones sin instalar paquetes.
  -h, --help         Muestra esta ayuda.

Selecciones:
  Puedes usar numeros del menu o alias como python, npm, playwright, all.

Variables utiles:
  AIO_NO_RECOMMENDS=1            Instala paquetes apt sin recomendados.
  AIO_DOWNLOAD_NODE_BROWSERS=1   Permite que npm descargue navegadores propios.

Ejemplos:
  ./${SCRIPT_NAME} python npm
  ./${SCRIPT_NAME} --dry-run 1 7
  ./${SCRIPT_NAME} all --upgrade
USAGE
}

show_menu() {
    cat <<'MENU'
Seleccione los paquetes o grupos que desea instalar (separados por espacio):
 1) python3 completo (python3, pip3, venv, virtualenv, python3-dev)
 2) nmap
 3) python3-pip / venv / virtualenv (instala el grupo Python completo)
 4) git
 5) curl
 6) nodejs + npm
 7) npm + Puppeteer + Chromium + Playwright (configurado para --no-sandbox)
 8) openssh-client
 9) wget
10) unzip
11) net-tools
12) ruby
13) perl
14) php
15) openssl
16) build-essential
17) cmake
18) subversion
19) automake
20) autoconf
21) htop
22) tmux
23) ufw
24) fail2ban
25) iputils-ping
26) traceroute
27) dnsutils
28) tcpdump
29) snapd
30) flatpak
31) Java JDK
32) golang
33) composer
34) MySQL/MariaDB server
35) mariadb-server
36) postgresql
37) postgresql-contrib
38) redis-server
39) mongodb (solo si existe en los repos configurados)
40) docker
41) docker-compose
42) instalar todo lo disponible
43) actualizar sistema con apt-get upgrade
 0) salir
MENU
}

setup_sudo() {
    if (( EUID == 0 )); then
        return 0
    fi

    if command -v sudo >/dev/null 2>&1; then
        SUDO=(sudo)
        return 0
    fi

    die "Ejecuta este script como root o instala sudo."
}

require_apt() {
    command -v apt-get >/dev/null 2>&1 || die "apt-get no esta disponible. Este script esta pensado para Debian/Ubuntu."
    command -v apt-cache >/dev/null 2>&1 || die "apt-cache no esta disponible."
    command -v dpkg-query >/dev/null 2>&1 || die "dpkg-query no esta disponible."
}

mark_once() {
    local key="$1"

    if [[ -n "${DONE[$key]+x}" ]]; then
        log "Saltando '${key}': ya fue procesado."
        return 1
    fi

    DONE[$key]=1
    return 0
}

apt_update_once() {
    if (( APT_UPDATED )); then
        return 0
    fi

    log "Actualizando indice de paquetes apt..."
    root_env_run apt-get update
    APT_UPDATED=1
}

prepare_apt_once() {
    if (( APT_PREPARED )); then
        return 0
    fi

    log "Comprobando estado de dpkg/apt..."
    root_env_run dpkg --configure -a
    apt_update_once
    root_env_run apt-get -f install -y
    APT_PREPARED=1
}

apt_package_available() {
    local package="$1"
    local candidate

    candidate="$(apt-cache policy "$package" 2>/dev/null | awk '/Candidate:/ {print $2; exit}')"
    [[ -n "$candidate" && "$candidate" != "(none)" ]]
}

select_first_available() {
    local result_var="$1"
    shift

    local package
    prepare_apt_once

    for package in "$@"; do
        if apt_package_available "$package"; then
            printf -v "$result_var" '%s' "$package"
            return 0
        fi
    done

    printf -v "$result_var" ''
    return 1
}

install_apt_packages() {
    local label="$1"
    shift

    local package
    local -a packages=()
    local -a install_args=(-y)

    prepare_apt_once

    if [[ "${AIO_NO_RECOMMENDS:-0}" == "1" ]]; then
        install_args+=(--no-install-recommends)
    fi

    for package in "$@"; do
        if apt_package_available "$package"; then
            packages+=("$package")
        else
            warn "Paquete apt no disponible, se omite: ${package} (${label})"
        fi
    done

    if ((${#packages[@]} == 0)); then
        warn "No hay paquetes apt disponibles para: ${label}"
        return 0
    fi

    log "Instalando ${label}: ${packages[*]}"
    root_env_run apt-get install "${install_args[@]}" "${packages[@]}"
}

verify_error() {
    printf '[VERIFY] %s\n' "$*" >&2
    VERIFY_ERRORS+=("$*")
}

verify_command() {
    local command_name="$1"

    if (( DRY_RUN )); then
        log "[dry-run] verificaria comando: ${command_name}"
        return 0
    fi

    if command -v "$command_name" >/dev/null 2>&1; then
        ok "Comando disponible: ${command_name}"
    else
        verify_error "No se encontro el comando: ${command_name}"
    fi
}

verify_dpkg_package() {
    local package="$1"

    if (( DRY_RUN )); then
        log "[dry-run] verificaria paquete dpkg: ${package}"
        return 0
    fi

    if dpkg-query -W -f='${Status}' "$package" 2>/dev/null | grep -q 'install ok installed'; then
        ok "Paquete instalado: ${package}"
    else
        verify_error "El paquete no quedo instalado: ${package}"
    fi
}

install_tool() {
    local key="$1"
    local label="$2"
    local package="$3"
    shift 3

    mark_once "$key" || return 0
    install_apt_packages "$label" "$package"

    if (($#)); then
        local command_name
        for command_name in "$@"; do
            verify_command "$command_name"
        done
    else
        verify_dpkg_package "$package"
    fi
}

install_python() {
    mark_once python || return 0

    install_apt_packages "Python 3 completo" \
        python3 \
        python3-pip \
        python3-venv \
        python3-virtualenv \
        python3-dev \
        python-is-python3 \
        build-essential

    verify_python
}

verify_python() {
    verify_command python3
    verify_command pip3
    verify_command virtualenv

    if (( DRY_RUN )); then
        return 0
    fi

    local tmpdir
    tmpdir="$(mktemp -d)"

    if python3 -m pip --version >/dev/null 2>&1; then
        ok "python3 -m pip funciona."
    else
        verify_error "python3 -m pip no funciona."
    fi

    if python3 -m venv "${tmpdir}/venv" >/dev/null 2>&1 && "${tmpdir}/venv/bin/python" -m pip --version >/dev/null 2>&1; then
        ok "python3 -m venv crea entornos con pip."
    else
        verify_error "python3 -m venv fallo o creo un entorno sin pip."
    fi

    if virtualenv "${tmpdir}/virtualenv" >/dev/null 2>&1; then
        ok "virtualenv crea entornos correctamente."
    else
        verify_error "virtualenv no pudo crear un entorno."
    fi

    rm -rf "$tmpdir"
}

install_node_base() {
    mark_once node-base || return 0

    install_apt_packages "Node.js y npm" \
        ca-certificates \
        nodejs \
        npm

    verify_command node
    verify_command npm
}

npm_executable() {
    if [[ -x /usr/bin/npm ]]; then
        printf '%s\n' /usr/bin/npm
        return 0
    fi

    command -v npm
}

node_executable() {
    if [[ -x /usr/bin/node ]]; then
        printf '%s\n' /usr/bin/node
        return 0
    fi

    command -v node
}

detect_chromium_bin() {
    local candidate
    local -a candidates=(
        "${AIO_CHROMIUM_BIN:-}"
        /usr/bin/chromium
        /usr/bin/chromium-browser
        /snap/bin/chromium
    )

    for candidate in "${candidates[@]}"; do
        if [[ -n "$candidate" && -x "$candidate" ]]; then
            printf '%s\n' "$candidate"
            return 0
        fi
    done

    command -v chromium 2>/dev/null || command -v chromium-browser 2>/dev/null
}

write_browser_profile() {
    local chromium_bin="$1"
    local profile_file="/etc/profile.d/aio-browser-env.sh"
    local tmpfile

    if [[ -z "$chromium_bin" && (( DRY_RUN )) ]]; then
        log "[dry-run] omitiria perfil de Chromium porque el binario aun no existe."
        return 0
    fi

    if [[ -z "$chromium_bin" ]]; then
        warn "No se pudo crear perfil de Chromium: binario no encontrado."
        return 0
    fi

    tmpfile="$(mktemp)"
    cat >"$tmpfile" <<EOF
# Generated by ${SCRIPT_NAME}. Useful in proot/container environments.
export AIO_CHROMIUM_BIN="${chromium_bin}"
export PUPPETEER_EXECUTABLE_PATH="${chromium_bin}"
export PUPPETEER_SKIP_DOWNLOAD="true"
export PUPPETEER_SKIP_CHROMIUM_DOWNLOAD="true"
export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD="1"
export AIO_BROWSER_ARGS="--no-sandbox --disable-setuid-sandbox --disable-dev-shm-usage"
EOF

    log "Escribiendo variables de entorno para Chromium/Puppeteer/Playwright en ${profile_file}"
    root_run install -m 0644 "$tmpfile" "$profile_file"
    rm -f "$tmpfile"
}

install_npm_browser_packages() {
    local npm_cmd
    local npm_cache_dir
    local remove_npm_cache=0
    local -a npm_env=(
        npm_config_audit=false
        npm_config_fund=false
        npm_config_prefer_online=true
        npm_config_fetch_retries=5
        npm_config_fetch_retry_factor=2
        npm_config_fetch_retry_mintimeout=20000
        npm_config_fetch_retry_maxtimeout=120000
        npm_config_maxsockets=1
        npm_config_progress=false
        PUPPETEER_SKIP_DOWNLOAD=true
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
    )
    local -a npm_install_args=(install -g puppeteer playwright)
    local -a prefix=(env)

    npm_cmd="$(npm_executable)" || die "npm no esta disponible despues de instalar nodejs/npm."
    npm_cache_dir="${AIO_NPM_CACHE_DIR:-}"
    if [[ -z "$npm_cache_dir" ]]; then
        npm_cache_dir="$(mktemp -d)"
        remove_npm_cache=1
    fi

    if [[ "${AIO_DOWNLOAD_NODE_BROWSERS:-0}" == "1" ]]; then
        npm_env=(
            npm_config_audit=false
            npm_config_fund=false
            npm_config_prefer_online=true
            npm_config_fetch_retries=5
            npm_config_fetch_retry_factor=2
            npm_config_fetch_retry_mintimeout=20000
            npm_config_fetch_retry_maxtimeout=120000
            npm_config_maxsockets=1
            npm_config_progress=false
        )
        log "AIO_DOWNLOAD_NODE_BROWSERS=1: npm podra descargar navegadores propios."
    else
        log "Instalando Puppeteer/Playwright usando Chromium del sistema para evitar descargas pesadas."
    fi

    npm_env+=(npm_config_cache="$npm_cache_dir")

    if ((${#SUDO[@]})) && [[ "$npm_cmd" == /usr/* ]]; then
        prefix=("${SUDO[@]}" env)
    fi

    if ! run_cmd_status "${prefix[@]}" "${npm_env[@]}" "$npm_cmd" "${npm_install_args[@]}"; then
        warn "npm fallo instalando Puppeteer/Playwright. Limpiando cache y reintentando una vez con cache nueva."
        run_cmd_status "${prefix[@]}" "${npm_env[@]}" "$npm_cmd" cache clean --force >/dev/null 2>&1 || true

        if (( remove_npm_cache )); then
            rm -rf "$npm_cache_dir"
            npm_cache_dir="$(mktemp -d)"
            local index
            for index in "${!npm_env[@]}"; do
                if [[ "${npm_env[$index]}" == npm_config_cache=* ]]; then
                    npm_env[$index]="npm_config_cache=${npm_cache_dir}"
                    break
                fi
            done
        fi

        if ! run_cmd_status "${prefix[@]}" "${npm_env[@]}" "$npm_cmd" "${npm_install_args[@]}"; then
            if (( remove_npm_cache )); then
                rm -rf "$npm_cache_dir"
            fi
            die "npm no pudo instalar puppeteer/playwright despues del reintento."
        fi
    fi

    if [[ "${AIO_DOWNLOAD_NODE_BROWSERS:-0}" == "1" ]] && (( ! DRY_RUN )); then
        local playwright_cmd
        playwright_cmd="$(command -v playwright || true)"
        if [[ -n "$playwright_cmd" ]]; then
            run_cmd "${prefix[@]}" PLAYWRIGHT_BROWSERS_PATH="${AIO_PLAYWRIGHT_BROWSERS_PATH:-/usr/local/share/ms-playwright}" "$playwright_cmd" install chromium
        else
            warn "No se encontro el comando playwright para descargar Chromium administrado por Playwright."
        fi
    fi

    if (( remove_npm_cache )); then
        rm -rf "$npm_cache_dir"
    fi
}

install_node_browser_stack() {
    mark_once node-browser || return 0

    local chromium_package=""
    select_first_available chromium_package chromium chromium-browser || true

    if [[ -n "$chromium_package" ]]; then
        install_apt_packages "Node.js, npm y Chromium" \
            ca-certificates \
            nodejs \
            npm \
            "$chromium_package" \
            fonts-liberation \
            xdg-utils
    else
        warn "No se encontro paquete Chromium en apt. Se instalaran Node.js/npm y los paquetes npm igualmente."
        install_apt_packages "Node.js y npm" ca-certificates nodejs npm
    fi

    install_npm_browser_packages

    local chromium_bin=""
    chromium_bin="$(detect_chromium_bin || true)"
    write_browser_profile "$chromium_bin"
    verify_node_browser_stack
}

verify_node_browser_stack() {
    verify_command node
    verify_command npm

    if (( DRY_RUN )); then
        log "[dry-run] verificaria Chromium, Puppeteer y Playwright con --no-sandbox."
        return 0
    fi

    local node_cmd npm_cmd chromium_bin npm_root
    node_cmd="$(node_executable)" || {
        verify_error "node no esta disponible."
        return 0
    }
    npm_cmd="$(npm_executable)" || {
        verify_error "npm no esta disponible."
        return 0
    }
    chromium_bin="$(detect_chromium_bin || true)"

    if [[ -z "$chromium_bin" ]]; then
        verify_error "Chromium no esta disponible."
        return 0
    fi

    if "$chromium_bin" --version >/dev/null 2>&1; then
        ok "Chromium disponible: $("$chromium_bin" --version)"
    else
        verify_error "Chromium existe pero no responde a --version: ${chromium_bin}"
        return 0
    fi

    local user_data_dir
    local -a chromium_runner=("$chromium_bin")
    user_data_dir="$(mktemp -d)"

    if command -v timeout >/dev/null 2>&1; then
        chromium_runner=(timeout 45 "$chromium_bin")
    fi

    if "${chromium_runner[@]}" \
        --headless \
        --no-sandbox \
        --disable-setuid-sandbox \
        --disable-dev-shm-usage \
        --disable-gpu \
        --user-data-dir="$user_data_dir" \
        --dump-dom 'data:text/html,<title>AIO</title><h1>AIO</h1>' >/dev/null 2>&1; then
        ok "Chromium ejecuta en modo headless con --no-sandbox."
    else
        verify_error "Chromium no pudo ejecutar headless con --no-sandbox."
    fi

    rm -rf "$user_data_dir"

    npm_root="$("$npm_cmd" root -g 2>/dev/null || true)"
    if [[ -z "$npm_root" ]]; then
        verify_error "No se pudo resolver npm root -g."
        return 0
    fi

    local -a node_runner=("$node_cmd")
    if command -v timeout >/dev/null 2>&1; then
        node_runner=(timeout 90 "$node_cmd")
    fi

    if NODE_PATH="$npm_root" AIO_CHROMIUM_BIN="$chromium_bin" "${node_runner[@]}" <<'NODE' >/dev/null 2>&1
const executablePath = process.env.AIO_CHROMIUM_BIN;
const launchArgs = ['--no-sandbox', '--disable-setuid-sandbox', '--disable-dev-shm-usage'];

(async () => {
  const puppeteer = require('puppeteer');
  const puppeteerBrowser = await puppeteer.launch({
    executablePath,
    headless: true,
    args: launchArgs,
  });
  const puppeteerPage = await puppeteerBrowser.newPage();
  await puppeteerPage.setContent('<title>AIO Puppeteer</title>');
  const puppeteerTitle = await puppeteerPage.title();
  await puppeteerBrowser.close();
  if (puppeteerTitle !== 'AIO Puppeteer') {
    throw new Error('Puppeteer title check failed');
  }

  const { chromium } = require('playwright');
  const playwrightBrowser = await chromium.launch({
    executablePath,
    headless: true,
    args: launchArgs,
  });
  const playwrightPage = await playwrightBrowser.newPage();
  await playwrightPage.setContent('<title>AIO Playwright</title>');
  const playwrightTitle = await playwrightPage.title();
  await playwrightBrowser.close();
  if (playwrightTitle !== 'AIO Playwright') {
    throw new Error('Playwright title check failed');
  }
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
NODE
    then
        ok "Puppeteer y Playwright cargan Chromium del sistema con --no-sandbox."
    else
        verify_error "Puppeteer/Playwright no pudieron lanzar Chromium del sistema con --no-sandbox."
    fi
}

install_java() {
    mark_once java || return 0

    local package=""
    select_first_available package default-jdk openjdk-21-jdk openjdk-17-jdk openjdk-11-jdk || true
    if [[ -z "$package" ]]; then
        warn "No se encontro ningun paquete JDK disponible."
        return 0
    fi

    install_apt_packages "Java JDK" "$package"
    verify_command java
    verify_command javac
}

install_mysql_server() {
    mark_once mysql || return 0

    local package=""
    select_first_available package default-mysql-server mysql-server mariadb-server || true
    if [[ -z "$package" ]]; then
        warn "No se encontro mysql-server/default-mysql-server/mariadb-server disponible."
        return 0
    fi

    install_apt_packages "MySQL/MariaDB server" "$package"
    if command -v mysql >/dev/null 2>&1 || command -v mariadb >/dev/null 2>&1 || (( DRY_RUN )); then
        ok "Cliente MySQL/MariaDB disponible o pendiente de verificar en dry-run."
    else
        verify_error "No se encontro cliente mysql/mariadb despues de instalar ${package}."
    fi
}

install_dnsutils() {
    mark_once dnsutils || return 0

    local package=""
    select_first_available package dnsutils bind9-dnsutils bind9-host || true
    if [[ -z "$package" ]]; then
        warn "No se encontro dnsutils/bind9-dnsutils/bind9-host disponible."
        return 0
    fi

    install_apt_packages "DNS tools" "$package"
    verify_command dig
    verify_command nslookup
}

install_postgresql_contrib() {
    mark_once postgresql-contrib || return 0

    local package=""
    select_first_available package postgresql-contrib postgresql-contrib-17 postgresql || true
    if [[ -z "$package" ]]; then
        warn "No se encontro postgresql-contrib ni alternativa disponible."
        return 0
    fi

    if [[ "$package" == "postgresql" ]]; then
        log "postgresql-contrib no esta separado en estos repos; usando postgresql como alternativa disponible."
    fi

    install_apt_packages "PostgreSQL contrib" "$package"
    verify_dpkg_package "$package"
}

install_mongodb() {
    mark_once mongodb || return 0

    local package=""
    select_first_available package mongodb-org mongodb mongodb-server || true
    if [[ -z "$package" ]]; then
        warn "MongoDB no esta en los repositorios apt configurados. En Debian suele requerir el repositorio oficial de MongoDB."
        return 0
    fi

    install_apt_packages "MongoDB" "$package"
    verify_command mongod
}

install_docker() {
    mark_once docker || return 0

    local package=""
    select_first_available package docker.io docker-ce docker || true
    if [[ -z "$package" ]]; then
        warn "No se encontro paquete Docker disponible."
        return 0
    fi

    install_apt_packages "Docker" "$package"
    verify_command docker
}

install_docker_compose() {
    mark_once docker-compose || return 0

    local package=""
    select_first_available package docker-compose docker-compose-plugin || true
    if [[ -z "$package" ]]; then
        warn "No se encontro docker-compose/docker-compose-plugin disponible."
        return 0
    fi

    install_apt_packages "Docker Compose" "$package"

    if (( DRY_RUN )); then
        log "[dry-run] verificaria docker-compose o 'docker compose'."
        return 0
    fi

    if command -v docker-compose >/dev/null 2>&1; then
        ok "Comando disponible: docker-compose"
    elif command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
        ok "Comando disponible: docker compose"
    else
        verify_error "No se encontro docker-compose ni 'docker compose'."
    fi
}

install_all() {
    mark_once all || return 0

    install_python
    install_tool nmap "nmap" nmap nmap
    install_tool git "git" git git
    install_tool curl "curl" curl curl
    install_node_browser_stack
    install_tool openssh-client "openssh-client" openssh-client ssh
    install_tool wget "wget" wget wget
    install_tool unzip "unzip" unzip unzip
    install_tool net-tools "net-tools" net-tools ifconfig netstat
    install_tool ruby "ruby" ruby ruby
    install_tool perl "perl" perl perl
    install_tool php "php" php php
    install_tool openssl "openssl" openssl openssl
    install_tool build-essential "build-essential" build-essential gcc make
    install_tool cmake "cmake" cmake cmake
    install_tool subversion "subversion" subversion svn
    install_tool automake "automake" automake automake
    install_tool autoconf "autoconf" autoconf autoconf
    install_tool htop "htop" htop htop
    install_tool tmux "tmux" tmux tmux
    install_tool ufw "ufw" ufw ufw
    install_tool fail2ban "fail2ban" fail2ban fail2ban-client
    install_tool iputils-ping "iputils-ping" iputils-ping ping
    install_tool traceroute "traceroute" traceroute traceroute
    install_dnsutils
    install_tool tcpdump "tcpdump" tcpdump tcpdump
    install_tool snapd "snapd" snapd snap
    install_tool flatpak "flatpak" flatpak flatpak
    install_java
    install_tool golang "golang" golang go
    install_tool composer "composer" composer composer
    install_mysql_server
    install_tool mariadb "mariadb-server" mariadb-server mariadb
    install_tool postgresql "postgresql" postgresql psql
    install_postgresql_contrib
    install_tool redis "redis-server" redis-server redis-server redis-cli
    install_mongodb
    install_docker
    install_docker_compose
}

upgrade_system() {
    mark_once upgrade || return 0
    prepare_apt_once
    log "Actualizando paquetes instalados con apt-get upgrade..."
    root_env_run apt-get upgrade -y
}

dispatch_selection() {
    local choice="$1"

    case "$choice" in
        0|salir|exit|quit)
            log "Saliendo sin instalar."
            exit 0
            ;;
        1|python|python3)
            install_python
            ;;
        2|nmap)
            install_tool nmap "nmap" nmap nmap
            ;;
        3|pip|pip3|venv|virtualenv|python-pip)
            install_python
            ;;
        4|git)
            install_tool git "git" git git
            ;;
        5|curl)
            install_tool curl "curl" curl curl
            ;;
        6|node|nodejs)
            install_node_base
            ;;
        7|npm|puppeteer|playwright|chromium|browser|node-browser)
            install_node_browser_stack
            ;;
        8|ssh|openssh|openssh-client)
            install_tool openssh-client "openssh-client" openssh-client ssh
            ;;
        9|wget)
            install_tool wget "wget" wget wget
            ;;
        10|unzip)
            install_tool unzip "unzip" unzip unzip
            ;;
        11|net-tools)
            install_tool net-tools "net-tools" net-tools ifconfig netstat
            ;;
        12|ruby)
            install_tool ruby "ruby" ruby ruby
            ;;
        13|perl)
            install_tool perl "perl" perl perl
            ;;
        14|php)
            install_tool php "php" php php
            ;;
        15|openssl)
            install_tool openssl "openssl" openssl openssl
            ;;
        16|build|build-essential)
            install_tool build-essential "build-essential" build-essential gcc make
            ;;
        17|cmake)
            install_tool cmake "cmake" cmake cmake
            ;;
        18|svn|subversion)
            install_tool subversion "subversion" subversion svn
            ;;
        19|automake)
            install_tool automake "automake" automake automake
            ;;
        20|autoconf)
            install_tool autoconf "autoconf" autoconf autoconf
            ;;
        21|htop)
            install_tool htop "htop" htop htop
            ;;
        22|tmux)
            install_tool tmux "tmux" tmux tmux
            ;;
        23|ufw)
            install_tool ufw "ufw" ufw ufw
            ;;
        24|fail2ban)
            install_tool fail2ban "fail2ban" fail2ban fail2ban-client
            ;;
        25|ping|iputils-ping)
            install_tool iputils-ping "iputils-ping" iputils-ping ping
            ;;
        26|traceroute)
            install_tool traceroute "traceroute" traceroute traceroute
            ;;
        27|dns|dnsutils|bind9-dnsutils)
            install_dnsutils
            ;;
        28|tcpdump)
            install_tool tcpdump "tcpdump" tcpdump tcpdump
            ;;
        29|snap|snapd)
            install_tool snapd "snapd" snapd snap
            ;;
        30|flatpak)
            install_tool flatpak "flatpak" flatpak flatpak
            ;;
        31|java|jdk)
            install_java
            ;;
        32|go|golang)
            install_tool golang "golang" golang go
            ;;
        33|composer)
            install_tool composer "composer" composer composer
            ;;
        34|mysql|mysql-server|default-mysql-server)
            install_mysql_server
            ;;
        35|mariadb|mariadb-server)
            install_tool mariadb "mariadb-server" mariadb-server mariadb
            ;;
        36|postgres|postgresql)
            install_tool postgresql "postgresql" postgresql psql
            ;;
        37|postgresql-contrib|postgres-contrib)
            install_postgresql_contrib
            ;;
        38|redis|redis-server)
            install_tool redis "redis-server" redis-server redis-server redis-cli
            ;;
        39|mongodb|mongo)
            install_mongodb
            ;;
        40|docker)
            install_docker
            ;;
        41|compose|docker-compose)
            install_docker_compose
            ;;
        42|all|todo|todos)
            install_all
            ;;
        43|upgrade|actualizar)
            RUN_UPGRADE=1
            ;;
        *)
            verify_error "Opcion no valida: ${choice}"
            ;;
    esac
}

parse_args() {
    while (($#)); do
        case "$1" in
            -n|--dry-run)
                DRY_RUN=1
                ;;
            --upgrade)
                RUN_UPGRADE=1
                ;;
            --verify-only)
                VERIFY_ONLY=1
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            --)
                shift
                while (($#)); do
                    REQUESTED+=("$1")
                    shift
                done
                return 0
                ;;
            -*)
                die "Opcion no reconocida: $1"
                ;;
            *)
                REQUESTED+=("$1")
                ;;
        esac
        shift
    done
}

read_interactive_choices() {
    local choices_line

    show_menu
    printf '\n'
    read -r -p "Ingrese los numeros o alias correspondientes: " choices_line

    if [[ -z "${choices_line//[[:space:]]/}" ]]; then
        die "No se ingreso ninguna seleccion."
    fi

    read -r -a REQUESTED <<<"$choices_line"
}

finish() {
    local item

    if ((${#WARNINGS[@]})); then
        printf '\nAdvertencias:\n' >&2
        for item in "${WARNINGS[@]}"; do
            printf ' - %s\n' "$item" >&2
        done
    fi

    if ((${#VERIFY_ERRORS[@]})); then
        printf '\nVerificaciones fallidas:\n' >&2
        for item in "${VERIFY_ERRORS[@]}"; do
            printf ' - %s\n' "$item" >&2
        done
        exit 1
    fi

    ok "Proceso completado."
}

main() {
    parse_args "$@"
    setup_sudo
    require_apt

    if (( VERIFY_ONLY )); then
        verify_python
        verify_node_browser_stack
        finish
        return 0
    fi

    if ((${#REQUESTED[@]} == 0)); then
        if [[ ! -t 0 ]]; then
            die "No hay entrada interactiva. Pasa selecciones como argumentos; ejemplo: ./${SCRIPT_NAME} python npm"
        fi
        read_interactive_choices
    fi

    local choice
    for choice in "${REQUESTED[@]}"; do
        dispatch_selection "$choice"
    done

    if (( RUN_UPGRADE )); then
        upgrade_system
    fi

    finish
}

main "$@"
