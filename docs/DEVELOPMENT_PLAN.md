# MySummer - Plan de Desarrollo Detallado

## Estado Actual del Proyecto

### Implementado
- [x] Sistema de Progresion Nativo (domain `mysummer`, skill `streetracing` con 5 niveles)
- [x] 10 carreras street racing con recompensas
- [x] Mercado de Piezas basico (PartsBay, SpeedParts, SilkRoad)
- [x] Vehiculos iniciales (Miramar + ETK-I chasis)
- [x] UI base (telefono, ordenador, mercado)
- [x] Sistema de leads/soplos para piezas ilegales
- [x] Integracion policia para piezas calientes
- [x] Filtrado de categorias en tiendas (excluye ruedas, neumaticos, pintura, cargo de segunda mano e ilegal)
- [x] Sistema jerarquico de categorias para ruedas/neumaticos (4 niveles)
- [x] **Sprint 7**: Configuracion ETK-I basico (chasis vacio con partsTree)
- [x] **Sprint 8.2**: Kilometraje inicial de vehiculos (Miramar 800k-1M km, ETK-I 500k-800k km)

---

## SPRINT 1: Sistema de Cargo para Recogida de Piezas
**Prioridad: ALTA**

### Objetivo
Las piezas compradas en el mercado de segunda mano deben usar el sistema de cargo nativo de BeamNG.

### Tareas

#### 1.1 Investigar sistema de cargo de BeamNG
- [ ] Localizar modulos de cargo en BeamNG (`freeroam_cargo`, `career_modules_cargo`, etc.)
- [ ] Entender como funcionan las propiedades de peso y tamanio
- [ ] Documentar API disponible para crear/gestionar cargo

#### 1.2 Definir propiedades de peso para piezas
- [ ] Crear tabla de pesos realistas por tipo de pieza:
  - Motor: ~150-250 kg
  - Transmision: ~50-80 kg
  - Escape: ~15-30 kg
  - Radiador: ~10-15 kg
  - Asientos: ~15-25 kg cada uno
  - Puertas: ~20-35 kg cada una
  - Parachoques: ~10-20 kg
  - Capo/maletero: ~15-25 kg
  - Piezas pequenias (ECU, sensores): ~1-5 kg
- [ ] Almacenar pesos en metadata de partes o tabla de lookup

#### 1.3 Implementar validacion de espacio
- [ ] Al confirmar recogida, verificar espacio disponible en vehiculo actual
- [ ] Verificar capacidad de remolque si existe
- [ ] Mostrar mensaje de error si no hay espacio suficiente
- [ ] Opcion de seleccionar que piezas recoger si hay varias pendientes

#### 1.4 Integrar con pickup actual
- [ ] Modificar `mysummerParts.lua` para crear cargo al recoger
- [ ] La pieza ocupa espacio fisico en el vehiculo
- [ ] Al llegar al garaje, transferir cargo a inventario de piezas

#### Archivos a modificar
- `lua/ge/extensions/career/modules/mysummerParts.lua`
- Posiblemente crear nuevo modulo `mysummerCargo.lua`

---

## SPRINT 2: Stock Unico en Tienda Oficial (SpeedParts)
**Prioridad: ALTA**

### Objetivo
Las piezas de SpeedParts deben tacharse al comprarlas y no poder comprarse de nuevo.

### Tareas

#### 2.1 Sistema de tracking de compras
- [ ] Crear estructura de estado para piezas compradas por vehiculo
- [ ] Persistir en save del jugador
- [ ] Cargar al iniciar carrera

#### 2.2 UI de piezas compradas
- [ ] Mostrar piezas compradas con estilo "tachado" o "agotado"
- [ ] Deshabilitar boton de compra para piezas ya adquiridas
- [ ] Indicador visual claro (gris, tachado, icono de check)

#### 2.3 Logica de tienda
- [ ] Modificar endpoint de compra para validar no-recompra
- [ ] Actualizar estado al completar compra
- [ ] Manejar caso de multiples piezas del mismo tipo (ej: 4 ruedas)

#### Archivos a modificar
- `lua/ge/extensions/career/modules/mysummerPartShops.lua`
- `ui-vue-src/modules/career/components/mysummer/browser/OfficialStorePage.vue`

---

## SPRINT 3: Sistema de Carreras con Listener
**Prioridad: ALTA**

### Objetivo
Al seleccionar una carrera desde el movil, se crea waypoint. Al llegar, se activa la carrera. NO debe activarse al pasar casualmente.

### Tareas

#### 3.1 Investigar sistema de carreras nativo
- [ ] Revisar `gameplay_missions_missions.lua`
- [ ] Entender como se activan las carreras
- [ ] Documentar hooks disponibles (`onRaceStart`, `onPlayerReachLocation`, etc.)

#### 3.2 Sistema de "carrera solicitada"
- [ ] Estado que indica que el jugador ha seleccionado una carrera
- [ ] Flag `activeRaceRequest = { missionId, startPos }`
- [ ] Timeout o cancelacion si el jugador no llega en X minutos

#### 3.3 Listener de llegada
- [ ] Detectar cuando el jugador llega a la zona de inicio
- [ ] Solo activar si hay `activeRaceRequest` activo
- [ ] Limpiar request al iniciar carrera o al cancelar

#### 3.4 Waypoint de navegacion
- [ ] Al seleccionar carrera: `core_groundMarkers.setPath(startPos)`
- [ ] Mostrar en minimapa la ubicacion
- [ ] Opcion de cancelar desde el movil

#### Archivos a modificar
- `lua/ge/extensions/career/modules/mysummerRaceManager.lua`
- Posiblemente crear `mysummerRaceListener.lua`

---

## SPRINT 4: Desbloqueo de Carreras por Nivel
**Prioridad: MEDIA**

### Objetivo
Las carreras se desbloquean segun el nivel de `streetracing` del jugador.

### Tareas

#### 4.1 Definir requisitos por carrera
- [ ] Asignar nivel minimo a cada mision existente
- [ ] Actualizar `info.json` de cada mision con campo `requiredLevel`
- [ ] Niveles sugeridos:
  - Nivel 1: Carreras entre amigos (5 carreras)
  - Nivel 2-3: Rallys locales (3 carreras)
  - Nivel 3-4: Carreras ilegales (2 carreras)
  - Nivel 5: The Big One

#### 4.2 Filtrado en UI
- [ ] Mostrar carreras bloqueadas con icono de candado
- [ ] Tooltip indicando nivel requerido
- [ ] Separar visualmente por categoria/acto

#### 4.3 Validacion en backend
- [ ] Rechazar intento de iniciar carrera si nivel insuficiente
- [ ] Mensaje explicativo al jugador

#### Archivos a modificar
- `gameplay/missions/*/aiRace/*/info.json` (multiples)
- `lua/ge/extensions/career/modules/mysummerRaceManager.lua`
- `ui-vue-src/modules/apps/mysummerRace/`

---

## SPRINT 5: Sistema de Rivales
**Prioridad: MEDIA**

### Objetivo
Disenar rivales con dificultad progresiva y personalidades.

### Tareas

#### 5.1 Definir rivales fijos
- [ ] Crear 3 rivales principales con nombres y backstory:
  - **Rival 1** (Acto 1-2): Amigo competitivo, ETK-I basico
  - **Rival 2** (Acto 2-3): Corredor local arrogante, Pessima tuneado
  - **Rival 3** (Acto 3-5): Leyenda local, ETK-I full race
- [ ] Configuraciones de vehiculo progresivas por rival

#### 5.2 Pool de rivales secundarios
- [ ] 5-8 rivales secundarios que rotan
- [ ] Pueden reaparecer con mejores coches
- [ ] Variedad de vehiculos (Miramar, Pessima, ETK-I, etc.)

#### 5.3 Configuraciones de IA
- [ ] Crear configs de vehiculo para cada rival/nivel
- [ ] Ajustar agresividad/skill de IA segun acto
- [ ] Vehiculos almacenados en `vehicles/*/rivals/`

#### Archivos a crear/modificar
- `vehicles/etki/rivals/*.pc`
- `vehicles/pessima/rivals/*.pc`
- `lua/ge/extensions/career/modules/mysummerRivals.lua`

---

## SPRINT 6: DeepWeb con Domains Nativos
**Prioridad: MEDIA**

### Objetivo
Usar el sistema nativo de domains de BeamNG para la deepweb y contactos.

### Tareas

#### 6.1 Investigar sistema de domains
- [ ] Revisar como funciona el domain `mysummer` actual
- [ ] Entender sistema de skills y niveles
- [ ] Ver si se pueden crear "sub-skills" para contactos

#### 6.2 Disenar estructura de contactos
- [ ] 3-5 contactos con diferentes especializaciones:
  - **Contacto 1**: Piezas de motor (turbo, intake, ECU)
  - **Contacto 2**: Suspension y frenos
  - **Contacto 3**: Electronica y tunning
  - **Contacto 4**: Piezas "calientes" (robadas)
- [ ] Niveles de confianza que desbloquean mejores piezas

#### 6.3 Sistema de conversaciones
- [ ] UI estilo chat/mensaje para hablar con contactos
- [ ] Dialogo que sube nivel de confianza
- [ ] Desbloqueo de soplos basado en nivel de contacto

#### 6.4 Integracion con soplos
- [ ] Los soplos disponibles dependen del nivel de contactos
- [ ] Mejores contactos = mejores piezas ilegales
- [ ] Riesgo (heat) proporcional a la calidad

#### Archivos a crear/modificar
- `gameplay/domains/mysummer/skills/contacts/` (nuevo)
- `lua/ge/extensions/career/modules/mysummerContacts.lua` (nuevo)
- `ui-vue-src/modules/career/components/mysummer/browser/DeepWebPage.vue`

---

## ~~SPRINT 7: Configuracion ETK-I Basico~~ COMPLETADO
**Estado: IMPLEMENTADO**

El ETK-I inicial ya spawna como chasis vacio con partsTree configurado.

---

## SPRINT 8: Kilometraje Inicial de Vehiculos
**Prioridad: MEDIA** | **Parcialmente completado**

### Objetivo
Los vehiculos iniciales deben tener el kilometraje correcto.

### Tareas

#### 8.1 Investigar sistema de odometro
- [ ] Revisar como BeamNG maneja el odometro
- [ ] Verificar si es por vehiculo o por parte
- [ ] Documentar API para modificar km

#### ~~8.2 Implementar km iniciales~~ COMPLETADO
- [x] Miramar: 800.000 - 1.000.000 km (random)
- [x] ETK-I chasis: 500.000 - 800.000 km (random)
- [x] Aplicar al spawn inicial

#### 8.3 Impacto en gameplay
- [ ] Mayor km = mayor probabilidad de fallos (futuro)
- [ ] Indicador visible en UI del vehiculo

#### Archivos a modificar
- `lua/ge/extensions/career/modules/mysummerParts.lua`

---

## SPRINT 9: Sistema de Fallos por Kilometraje
**Prioridad: BAJA**

### Objetivo
Las piezas con muchos km deben tener mayor probabilidad de fallo.

### Tareas

#### 9.1 Investigar sistema de dano de BeamNG
- [ ] Ver como funciona `integrityValue` y otros parametros
- [ ] Buscar si hay sistema de fallos aleatorios existente
- [ ] Documentar eventos de rotura/fallo

#### 9.2 Disenar sistema de probabilidades
- [ ] Tabla de probabilidad de fallo segun km:
  - 0-50k km: 0% probabilidad
  - 50k-100k: 1% por carrera
  - 100k-200k: 5% por carrera
  - 200k+: 10% por carrera
- [ ] Tipos de fallo segun pieza (motor: perdida potencia, suspension: handling malo, etc.)

#### 9.3 Implementar sistema
- [ ] Check de probabilidad al iniciar carrera
- [ ] Aplicar efecto de fallo durante carrera
- [ ] Notificar al jugador del problema
- [ ] Opcion de reparar/reemplazar pieza

#### Archivos a crear
- `lua/ge/extensions/career/modules/mysummerWear.lua`

---

## SPRINT 10: Eventos Dinamicos en Carreras (Opcional)
**Prioridad: BAJA**

### Objetivo
Anadir persecuciones policiales o de bandas durante algunas carreras.

### Tareas

#### 10.1 Sistema de eventos random
- [ ] Probabilidad de evento segun tipo de carrera:
  - Carreras legales: 0%
  - Carreras ilegales: 10-20%
  - Carreras nocturnas: 25%
- [ ] Pool de eventos posibles

#### 10.2 Persecucion policial
- [ ] Spawn de vehiculo policial durante carrera
- [ ] IA de persecucion
- [ ] Escapar o ser atrapado
- [ ] Consecuencias (multa, perder carrera, etc.)

#### 10.3 Persecucion de banda
- [ ] Spawn de vehiculos hostiles
- [ ] IA agresiva (choque intencional)
- [ ] Sobrevivir hasta meta

---

## SPRINT 11: UI de Catalogo (Opcional)
**Prioridad: BAJA**

### Objetivo
Crear UI estilo revista vintage para la tienda oficial de piezas.

### Tareas

#### 11.1 Disenar layout de revista
- [ ] Paginas con fotos del ETK-I
- [ ] Estetica retro/vintage
- [ ] Secciones: Ofertas, Motor, Suspension, Interior, etc.

#### 11.2 Implementar componente
- [ ] Navegacion por paginas
- [ ] Destacados y ofertas
- [ ] Descripciones detalladas de piezas

---

## SPRINT 12: Checklist del Proyecto (Mejora)
**Prioridad: MEDIA**

### Objetivo
Conectar el checklist existente con datos reales del ETK-I.

### Tareas

#### 12.1 Backend de checklist
- [ ] Crear `mysummerChecklist.lua` con logica real
- [ ] Leer estado de piezas del ETK-I desde inventario
- [ ] Categorizar piezas por sistema (motor, suspension, carroceria, interior)

#### 12.2 Sincronizar con UI
- [ ] `ProjectChecklistPage.vue` debe consumir datos reales
- [ ] Actualizar estado al instalar/desinstalar piezas
- [ ] Progreso real vs mock actual

#### Archivos a modificar
- `lua/ge/extensions/career/modules/mysummerChecklist.lua`
- `ui-vue-src/modules/career/components/mysummer/browser/ProjectChecklistPage.vue`

---

## SPRINT 13: Sistema de Traits y Cooldowns en Contactos
**Prioridad: ALTA** | **Estado: IMPLEMENTADO**

### Objetivo
Hacer el sistema de contactos menos predecible y mas dinamico con traits de personalidad y cooldowns.

### Implementado
- [x] Sistema de traits por contacto (valores y deslikes)
- [x] Scoring basado en traits en lugar de respuestas "correctas" obvias
- [x] Cooldowns entre conversaciones (5min base, reduce con nivel)
- [x] Eventos de confrontacion aleatorios
- [x] Contacto Oracle (AI pilot) siempre desbloqueado
- [x] UI actualizada con indicadores de cooldown y traits

### Archivos Modificados
- `lua/ge/extensions/career/modules/mysummerDeepWeb.lua`
- `lua/ge/extensions/career/modules/deepweb_contacts/*.json`
- `ui-build-temp/src/modules/career/components/mysummer/browser/DeepWebPage.vue`

---

## SPRINT 14: Multiples Fuentes de XP
**Prioridad: ALTA** | **Estado: Pendiente**

### Objetivo
Permitir ganar XP con contactos de multiples formas, no solo conversaciones.

### Tareas
- [ ] XP por comprar piezas del contacto (5-15 XP segun valor)
- [ ] XP pasivo por tiempo (1 XP/hora, max 5/dia por contacto)
- [ ] Sistema de referidos (contactos presentan a otros)
- [ ] XP por completar misiones del contacto

---

## SPRINT 15: Sistema de Misiones de Contactos
**Prioridad: ALTA** | **Estado: Pendiente**

### Objetivo
Los contactos pueden ofrecer misiones segun nivel de confianza.

### Tipos de Mision
- **Delivery**: Llevar item de A a B con limite de tiempo
- **Find Part**: Conseguir pieza especifica para el contacto
- **Race**: Carreras contra contacto o asociado (parcialmente implementado)
- **Surveillance**: Seguir vehiculo sin ser detectado
- **Escort**: Proteger vehiculo del contacto durante transporte

### Tareas
- [ ] Framework base de misiones
- [ ] Implementar Delivery missions
- [ ] Implementar Find Part missions
- [ ] Cooldown entre misiones (30min - 2h)
- [ ] XP segun dificultad (25-100 XP)

---

## SPRINT 16: Sistema de Consecuencias
**Prioridad: MEDIA** | **Estado: Pendiente**

### Objetivo
Las acciones tienen consecuencias reales en las relaciones.

### Tareas
- [ ] Perdida de XP por malas respuestas (-5 a -20 XP)
- [ ] Perdida de XP por misiones fallidas (-25 a -50 XP)
- [ ] Bloqueo temporal por errores graves (24-72h)
- [ ] Efectos ripple entre contactos (rivales/aliados)
- [ ] Decaimiento de confianza por inactividad (1 XP/semana)

### Relaciones Entre Contactos
- Ghost <-> Shadow: Rivales
- Techie <-> Muscle: Mundos diferentes
- Import: Neutral con todos

---

## SPRINT 17: Integracion IA para Conversaciones
**Prioridad: MEDIA** | **Estado: Pendiente**

### Objetivo
Conversaciones dinamicas generadas por IA usando APIs gratuitas.

### Proveedores a Investigar
- **Groq**: 14,400 requests/dia gratis
- **Mistral**: 1B tokens/mes gratis
- **OpenRouter**: 30+ modelos gratuitos

### Tareas
- [ ] Capa de abstraccion para multiples proveedores
- [ ] Sistema de prompts basado en personalidad del contacto
- [ ] Fallback a conversaciones scripteadas si API falla
- [ ] Cache de respuestas para uso offline
- [ ] Contacto Oracle usa IA siempre

---

## Orden de Prioridades

| Sprint | Nombre | Prioridad | Estado |
|--------|--------|-----------|--------|
| ~~7~~ | ~~ETK-I Basico~~ | ~~ALTA~~ | COMPLETADO |
| ~~8.2~~ | ~~Kilometraje inicial~~ | ~~MEDIA~~ | COMPLETADO |
| ~~13~~ | ~~Traits y Cooldowns~~ | ~~ALTA~~ | COMPLETADO |
| 14 | Multiples Fuentes XP | ALTA | Pendiente |
| 15 | Misiones Contactos | ALTA | Pendiente |
| 1 | Sistema Cargo | ALTA | Pendiente |
| 2 | Stock Unico | ALTA | Pendiente |
| 3 | Carreras Listener | ALTA | Pendiente |
| 16 | Consecuencias | MEDIA | Pendiente |
| 17 | IA Conversaciones | MEDIA | Pendiente |
| 4 | Desbloqueo Carreras | MEDIA | Pendiente |
| 5 | Rivales | MEDIA | Pendiente |
| 12 | Checklist | MEDIA | Pendiente |
| 6 | DeepWeb | MEDIA | Pendiente |
| 9 | Fallos por KM | BAJA | Pendiente |
| 10 | Eventos Dinamicos | BAJA | Pendiente |
| 11 | UI Catalogo | BAJA | Pendiente |

---

## Archivos Clave del Proyecto

### Lua (Backend)
- `lua/ge/extensions/career/modules/mysummerParts.lua` - Mercado de piezas
- `lua/ge/extensions/career/modules/mysummerPartShops.lua` - Tiendas oficiales
- `lua/ge/extensions/career/modules/mysummerRaceManager.lua` - Carreras
- `lua/ge/extensions/career/modules/mysummerCore.lua` - Core del mod
- `lua/ge/extensions/career/modules/mysummerChecklist.lua` - Checklist (crear)

### Vue (Frontend)
- `ui-vue-src/modules/career/components/mysummer/browser/` - Paginas del navegador
- `ui-vue-src/modules/career/components/mysummer/MySummerBrowser.vue` - Router
- `ui-vue-src/modules/career/stores/mysummerPartsStore.js` - Estado de mercado

### Configuraciones
- `vehicles/etki/mysummer_2400ti_ttsport_chassis.pc` - Config actual ETK-I
- `gameplay/domains/mysummer/` - Domain y skills
- `gameplay/missions/west_coast_usa/aiRace/` - Misiones de carreras

---

*Documento creado: Enero 2025*
*Actualizar segun avance del desarrollo*
