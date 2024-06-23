#!/bin/bash

# Función para instalar paquetes
install_package() {
    PACKAGE_NAME=$1
    echo "Instalando $PACKAGE_NAME..."
    apt update -y
    apt install -y $PACKAGE_NAME
}

# Función para instalar todos los paquetes
install_all_packages() {
    echo "Instalando todos los paquetes y dependencias..."
    ALL_PACKAGES=(
        "python3" "nmap" "python3-pip" "git" "curl" "nodejs" "npm" "openssh-client" "wget" "unzip" "net-tools" 
        "ruby" "perl" "php" "openssl" "build-essential" "cmake" "subversion" "automake" "autoconf" "htop" 
        "tmux" "ufw" "fail2ban" "iputils-ping" "traceroute" "dnsutils" "tcpdump" "snapd" "flatpak" 
        "openjdk-11-jdk" "golang" "composer" "mysql-server" "mariadb-server" "postgresql" "postgresql-contrib" 
        "redis-server" "mongodb" "docker" "docker-compose"
    )
    
    apt update -y
    for PACKAGE in "${ALL_PACKAGES[@]}"; do
        apt install -y $PACKAGE
    done
}

# Menú de selección de paquetes
echo "Seleccione los paquetes que desea instalar (separados por espacio):"
echo "1) python3"
echo "2) nmap"
echo "3) python3-pip"
echo "4) git"
echo "5) curl"
echo "6) nodejs"
echo "7) npm"
echo "8) openssh-client"
echo "9) wget"
echo "10) unzip"
echo "11) net-tools"
echo "12) ruby"
echo "13) perl"
echo "14) php"
echo "15) openssl"
echo "16) build-essential"
echo "17) cmake"
echo "18) subversion"
echo "19) automake"
echo "20) autoconf"
echo "21) htop"
echo "22) tmux"
echo "23) ufw"
echo "24) fail2ban"
echo "25) iputils-ping"
echo "26) traceroute"
echo "27) dnsutils"
echo "28) tcpdump"
echo "29) snapd"
echo "30) flatpak"
echo "31) openjdk-11-jdk"
echo "32) golang"
echo "33) composer"
echo "34) mysql-server"
echo "35) mariadb-server"
echo "36) postgresql"
echo "37) postgresql-contrib"
echo "38) redis-server"
echo "39) mongodb"
echo "40) docker"
echo "41) docker-compose"
echo "42) Instalar todos los paquetes y dependencias"

read -p "Ingrese los números correspondientes a su elección (separados por espacio): " choices

# Convertir las elecciones de números a nombres de paquetes
for choice in $choices; do
    case $choice in
        1)  install_package "python3" ;;
        2)  install_package "nmap" ;;
        3)  install_package "python3-pip" ;;
        4)  install_package "git" ;;
        5)  install_package "curl" ;;
        6)  install_package "nodejs" ;;
        7)  install_package "npm" ;;
        8)  install_package "openssh-client" ;;
        9)  install_package "wget" ;;
        10) install_package "unzip" ;;
        11) install_package "net-tools" ;;
        12) install_package "ruby" ;;
        13) install_package "perl" ;;
        14) install_package "php" ;;
        15) install_package "openssl" ;;
        16) install_package "build-essential" ;;
        17) install_package "cmake" ;;
        18) install_package "subversion" ;;
        19) install_package "automake" ;;
        20) install_package "autoconf" ;;
        21) install_package "htop" ;;
        22) install_package "tmux" ;;
        23) install_package "ufw" ;;
        24) install_package "fail2ban" ;;
        25) install_package "iputils-ping" ;;
        26) install_package "traceroute" ;;
        27) install_package "dnsutils" ;;
        28) install_package "tcpdump" ;;
        29) install_package "snapd" ;;
        30) install_package "flatpak" ;;
        31) install_package "openjdk-11-jdk" ;;
        32) install_package "golang" ;;
        33) install_package "composer" ;;
        34) install_package "mysql-server" ;;
        35) install_package "mariadb-server" ;;
        36) install_package "postgresql" ;;
        37) install_package "postgresql-contrib" ;;
        38) install_package "redis-server" ;;
        39) install_package "mongodb" ;;
        40) install_package "docker" ;;
        41) install_package "docker-compose" ;;
        42) install_all_packages ;;
        *)  echo "Opción no válida: $choice" ;;
    esac
done

# Actualizar todos los paquetes instalados
echo "Actualizando todos los paquetes instalados..."
apt upgrade -y

echo "¡Instalación y actualización completadas!"
