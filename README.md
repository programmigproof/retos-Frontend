# Proyecto base con Tailwind CSS 4

Plantilla mínima para empezar proyectos web con Tailwind CSS ya configurado.

## Requisitos

- Node.js y npm
- Visual Studio Code con Live Server, o cualquier servidor local para archivos estáticos

## Empezar

1. Abre esta carpeta en Visual Studio Code.
2. En la terminal, instala las dependencias de la plantilla:

   ```bash
   npm install
   ```

3. Inicia la compilación automática de Tailwind:

   ```bash
   npm run dev
   ```

4. Abre `index.html` con Live Server. Deja `npm run dev` activo mientras trabajas.

Para generar el CSS una sola vez, usa `npm run build`.

## Incorporar archivos de la plantilla a un proyecto existente

Desde la carpeta del proyecto, ejecuta en PowerShell:

```powershell
.\actualizar-con-plantilla.ps1
```

El script crea un respaldo junto a la carpeta del proyecto, incorpora los
archivos que falten desde la rama `main` de la plantilla y conserva los archivos
existentes. Despues ejecuta `npm install` y `npm run dev`. Requiere Git, Node.js
y npm.

## Publicar una vez en GitHub como plantilla

1. Instala GitHub CLI y autentícate con `gh auth login`.
2. Desde la carpeta de este proyecto, publica el repositorio:

   ```bash
   git init
   git add .
   git commit -m "Proyecto base Tailwind"
   gh repo create TU_USUARIO/proyecto-base-tailwind --public --source=. --remote=origin --push
   ```

3. En GitHub, abre el repositorio, ve a **Settings** y activa **Template repository**.

## Crear un proyecto nuevo desde la plantilla

Con GitHub CLI autenticado, ejecuta desde la carpeta donde quieras crear el proyecto:

```bash
gh repo create mi-proyecto --template TU_USUARIO/proyecto-base-tailwind --public --clone
cd mi-proyecto
code .
```

La plantilla ya trae la configuración, los scripts y el CSS inicial. Cada proyecto
clonado necesita `npm install` una vez para restaurar sus dependencias; después,
`npm run dev` recompila Tailwind automáticamente mientras trabajas. No subas
`node_modules` a GitHub.

El CSS de entrada está en `src/input.css` y el CSS generado se guarda en
`src/output.css`.

## Sincronizar cambios con retos-Frontend

Ejecuta `.\auto-subir-a-retos.ps1` desde la raíz del repositorio. El script usa
el nombre de la carpeta como rama (convierte espacios en guiones), prepara un
commit inicial con los archivos existentes y publica los cambios posteriores
tras unos segundos sin guardados. Mantén la ventana de PowerShell abierta para
que el monitor siga activo; usa `Ctrl+C` para detenerlo.

No incluye `.vscode`, `node_modules` ni `.git`. Cada grupo de cambios genera un
commit automático y se sube a la rama del proyecto en `retos-Frontend`.

## Usar esta carpeta directamente

En esta carpeta, ejecuta `npm install` una vez y luego `npm run dev`. Abre
`index.html` con Live Server y deja el proceso de desarrollo activo.

Para generar el CSS una sola vez, usa `npm run build`.
