# My Summer Career Extension (RLS) - Documentacion

**Resumen**
- Extension de carrera inspirada en My Summer Car que agrega un Parts Market, un auto proyecto ETK y progresion guiada.
- Depende de `rls_career_overhaul` y asume que ambos mods estan en la misma carpeta base.

**Requisitos**
- `rls_career_overhaul` habilitado.
- Node.js instalado para compilar la UI con `build_ui.bat`.

**Estructura**
- `build_ui.bat`: build de UI (copia baseUI de RLS, mezcla fuentes, corre `npm run build`, copia a `ui/vue-dist`).
- `lua/ge/extensions/career/modules/mysummerParts.lua`: modulo principal de gameplay (mercado de partes, pickups, spawns, seguro).
- `ui-vue-src/`: overlay de UI con vistas/tiendas nuevas y ajustes.
- `ui/`: salida compilada (`vue-dist`) y carpetas sincronizadas desde RLS (`modules`, `modModules`, `startScreen`).
- `vehicles/etki/`: configuracion del chasis proyecto ETK.
- `mod_info/MYSUMCAR/info.json`: metadata del mod (tag, version, descripcion, dependencia).

**Lua (mysummerParts.lua)**
- Estado persistente en `career/rls_career/mysummerMarket.json` (listings, leads, activePickup, ids, flags).
- Genera `listings` legales y `leads` ilegales para partes del modelo `etki` (objetivo: 6 listings + 2 leads).
- Selecciona ubicaciones usando `freeroam_facilities`; fallback cerca del jugador si no hay datos.
- Crea rutas con `core_groundMarkers` y completa pickups al acercarse (6-8 unidades).
- Compras legales: cobra dinero, agrega parte a inventario; ilegales: disparan persecucion policial y pueden ser confiscadas en arresto.
- Sincroniza entradas de seguro si faltan (`career_modules_insurance_insurance`) y siembra inventario de partes.
- Spawns iniciales: compra garage por defecto, spawnea Miramar (starter) y ETK chassis proyecto.
- Integra el menu de computadora: agrega `Parts Market` en funciones generales y renombra `partShop` a `Install Parts`.
- Emite updates UI con `guihooks.trigger("mysummerMarketUpdated", data)`.

**UI (ui-vue-src)**
- `modules/career/routes.js`: agrega rutas `phone-parts-market` y `mysummer-market`.
- `views/PhoneMain.vue`: agrega app "Parts Market" al telefono y ajusta layout para que entren todas.
- `views/PhoneMySummerMarket.vue`: wrapper de telefono para el mercado (modo compact).
- `views/MySummerMarketMain.vue`: wrapper de computadora para el mercado.
- `components/mysummer/MySummerPartsMarket.vue`: UI completa (tabs de listings/leads/active, refresh, reservar, cancelar).
- `stores/mysummerPartsStore.js`: store Pinia que llama a Lua y escucha `mysummerMarketUpdated`.
- `stores/partShoppingStore.js`: deshabilita partes sin `partId` y muestra mensaje "Find this part in the Parts Market."
- `views/ComputerMain.vue`: agrega icono `mysummerParts` para la app del ordenador.
- `bridge/LuaFunctionSignatures.js`: expone llamadas de `career_modules_mysummerParts`.

**Vehiculos**
- `vehicles/etki/mysummer_2400ti_ttsport_chassis.pc`: chasis proyecto con piezas faltantes (base para progresion).
- `vehicles/etki/info_mysummer_2400ti_ttsport_chassis.json`: metadata del config (valor, peso, descripcion).

**Build de UI**
- Script: `build_ui.bat`.
- Origenes de build: `../rls_career_overhaul/baseUI` (base), `../rls_career_overhaul/ui-vue-src` (fuentes RLS), `ui-vue-src` (override extension).
- Salida: `ui/vue-dist` + sincronizacion de `ui/modules`, `ui/modModules`, `ui/startScreen` desde RLS.
- `ui-build-temp` es temporal (no editar; se puede borrar si se requiere rebuild limpio).

**Notas**
- Warnings de Sass `@import` y lightningcss `:deep`/`:has-text` vienen del UI base de RLS; no bloquean el build.
- Si la UI del telefono no aparece, revalidar build y que `ui/vue-dist` se haya actualizado.
