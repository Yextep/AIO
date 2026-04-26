# Instalador de Paquetes y Dependencias Todo En Uno

Scripts para flojos como yo que les da pereza estar instalando cada paquete o dependencia de forma manual al momento de tener un entorno de trabajo nuevo.

<img align="center" height="480" width="1000" alt="GIF" src="https://github.com/Yextep/AIO/assets/114537444/9346f947-3f16-4d68-bcba-33c74a7d0d23"/>

## Instalación

Clonamos el repositorio

```bash
git clone https://github.com/Yextep/AIO
```
Accedemos a la carpeta
```bash
cd aio
```
Damos los Permisos
```bash
chmod +x aio.sh
```
Ejecutamos
```bash
./aio.sh
```
Tambien puedes pasar selecciones directamente:

```bash
./aio.sh python npm
./aio.sh 1 7
./aio.sh all --upgrade
```

Opciones utiles:

```bash
./aio.sh --dry-run 1 7      # muestra lo que haria sin instalar
./aio.sh --verify-only      # verifica Python, Chromium, Puppeteer y Playwright
```

La opcion `python` instala `python3`, `pip3`, `venv`, `virtualenv`, `python3-dev` y herramientas de compilacion. La opcion `npm` instala Node.js, npm, Chromium, Puppeteer y Playwright, y configura Chromium para entornos tipo proot usando `--no-sandbox` en las verificaciones.
