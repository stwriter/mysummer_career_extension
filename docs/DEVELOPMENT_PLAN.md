# MySummer - Plan de Desarrollo Detallado

## Estado Actual del Proyecto

### Implementado
- [x] Sistema de Progresion Nativo (domain `mysummer`, skill `streetracing` con 7 niveles v4)
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
- [x] **Sprint 18**: Sistema de capitulos basado en carreras (2 wins = 1 capitulo)
- [x] **Sprint 19**: Desbloqueo de Ghost tras primera compra
- [x] **Sprint 20**: Restriccion de piezas por capitulo (solo upgrades bloqueados)
- [x] **Sprint 21**: Sistema de mensajeria/email con UI en navegador
- [x] **Sprint 22**: App de email en movil (PhoneEmail.vue)
- [x] **Sprint 15**: Sistema de misiones de contactos (delivery + chase missions)
- [x] **Sprint 24**: Sistema de Chat Unificado (WhatsApp-style, reemplaza email, integra DeepWeb V3)
- [x] **Sprint 25**: Sistema de Capitulos v4 (6 capitulos, 18 carreras + 6 misiones de contacto, dialogos de conduccion)

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
**Prioridad: ALTA** | **Estado: EN PROGRESO**

### Objetivo
Los contactos pueden ofrecer misiones segun nivel de confianza.

### Tipos de Mision
- **Delivery**: Llevar item de A a B con limite de tiempo
- **Chase**: Perseguir y detener vehiculo objetivo (IA en modo flee)
- **Find Part**: Conseguir pieza especifica para el contacto
- **Surveillance**: Seguir vehiculo sin ser detectado
- **Escort**: Proteger vehiculo del contacto durante transporte

### Tareas Completadas
- [x] Framework base de misiones (`mysummerMissions.lua`)
- [x] Sistema de templates por contacto
- [x] Cooldowns entre misiones (30min base, reduce con nivel)
- [x] XP/reputacion segun dificultad (25-100 XP)
- [x] Timer UI con avisos de tiempo
- [x] Implementar Delivery missions con cargo real
- [x] Implementar Chase missions con IA flee
- [x] Spawn de objetivos chase en carreteras (traffic utils)
- [x] Deteccion de objetivo detenido (distancia + velocidad + tiempo)
- [x] Vehiculos chase por dificultad (easy/medium/hard)
- [x] Misiones chase para Ghost y Muscle

### Tareas Pendientes
- [ ] Implementar Surveillance missions
- [ ] Implementar Escort missions
- [ ] Implementar Find Part missions
- [ ] Misiones chase para Techie, Import, Shadow
- [ ] UI de progreso de chase (distancia al objetivo)
- [ ] Integracion policia en misiones high-heat

### Archivos
- `lua/ge/extensions/career/modules/mysummerMissions.lua` - Sistema completo
- `lua/ge/extensions/career/modules/mysummerCargo.lua` - Integracion cargo

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
| ~~24~~ | ~~Chat Unificado~~ | ~~ALTA~~ | COMPLETADO |
| **25** | **Capitulos v4 + Carreras** | **ALTA** | **EN PROGRESO** |
| 14 | Multiples Fuentes XP | ALTA | Pendiente |
| 15 | Misiones Contactos | ALTA | EN PROGRESO (Delivery+Chase OK, faltan Surveillance/Escort/FindPart) |
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

## SPRINT 25: Sistema de Capitulos v4 con Carreras y Narrativa
**Prioridad: ALTA** | **Estado: EN PROGRESO**

### Objetivo
Implementar la estructura de 6 capitulos (v4) con carreras PLACEHOLDER y sistema narrativo completo.

### Documentacion Narrativa
Ver `/docs/narrative_v4/` para:
- `v4_hilo_narrativo.md` - Biblia narrativa completa
- `rook_full.json` - Dialogos de Rook (piloto ansioso)
- `nova_full.json` - Dialogos de Nova (ambiciosa)
- `ghost_full.json` - Dialogos de Ghost (fixer misterioso)
- `techie_full.json`, `muscle_full.json`, `import_full.json`, `shadow_full.json`, `viper_full.json`

### Sistema de Fases Narrativas

| Fase | Nombre | Trigger | Personajes Activos |
|------|--------|---------|-------------------|
| 0 | Legacy | Carta abuelo | Sistema |
| 1 | Origins | Primeras carreras | Rook, Nova |
| 2 | The Contact | Primera compra performance | Ghost |
| 3 | The Split | Conflicto Rook/Nova | Todos |
| 4 | The Fall | Sabotaje del coche | Ghost, Shadow |
| 5 | The Climb | Recuperar coche | Todos |
| 6 | The Legend | The Big One | Viper |

### Estructura v4 (6 Capitulos)

| Cap | Nombre | Contacto | Coche | Carreras |
|-----|--------|----------|-------|----------|
| 0 | Prologo - El Garaje | Sistema | Miramar | - |
| 1 | Carreras entre conocidos | Rook, Nova | Cualquiera | 3 |
| 2 | Underground bajo | Ghost | Cualquiera | 3 |
| 3 | Rallys regionales | Techie/Muscle/Import | Cualquiera | 3 |
| 4 | Underground alto | Shadow | Cualquiera | 3 |
| 5 | Rallys oficiales | Ghost | **Proyecto** | 3 |
| 6 | Camino a The Big One | Todos | **Proyecto** | 3 |

### Sistema de Carreras (PLACEHOLDER)

Las carreras son PLACEHOLDERS que:
1. **Waypoint**: Al aceptar, se crea waypoint al punto de inicio
2. **Activacion**: Al llegar al punto, se activa la mision nativa de BeamNG
3. **Misiones**: Usar carreras existentes de BeamNG/IROK (`race.race.json` original)
4. **Vehiculos rivales**: Usar configs que terminan en `_race1.pc`
5. **Recompensas**: Dar las recompensas ya definidas (dinero + XP)
6. **Repeticion**: OK que se repitan carreras entre capitulos

### Nuevos Personajes

**Rook** (Piloto ansioso/leal)
- Pareja de Nova
- Mecanico del grupo
- Inseguro, siempre "un paso detras"
- Teme perder a Nova y quedarse atras

**Nova** (Piloto ambiciosa)
- Pareja de Rook
- Directa, observadora
- Quiere salir del circuito pequenio
- No traiciona por maldad, sino por conviccion

### Sistema de Personalidad del Jugador

Traits (0-100):
- `ambition`: Deseo de ganar, voluntad de riesgo
- `loyalty`: Dedicacion a companieros
- `caution`: Planificacion vs velocidad imprudente

Relaciones dinamicas:
- `rook_confidence`: Confianza de Rook en si mismo
- `rook_trust`: Confianza de Rook en el jugador
- `rook_affinity`: Afinidad con Rook
- `nova_respect`: Respeto de Nova hacia el jugador
- `nova_affinity`: Afinidad con Nova

### Contenido por Capitulo
- **3 carreras** placeholder (de existentes)
- **1 mision de contacto** obligatoria
- **Dialogos en pantalla** durante conduccion
- **Mensajes de chat** dinamicos segun fase

### Tareas

#### Sistema de Carreras Placeholder
- [x] Actualizar skill streetracing a 7 niveles (0-6)
- [x] Crear `mysummerStoryRaces.lua` con estructura
- [ ] Simplificar sistema: waypoint -> llegar -> mision nativa
- [ ] Definir 18 carreras usando misiones existentes de BeamNG
- [ ] Configurar vehiculos rivales con `_race1.pc`
- [ ] Sistema de recompensas por carrera

#### Sistema Narrativo V4
- [x] Crear `mysummerNarrative.lua` (Story Orchestrator) - Eventos narrativos por fase
- [x] Anadir Rook y Nova como contactos en chat (rook_v3.json, nova_v3.json)
- [x] Sistema de personality tracking (affinityEffects en mysummerChat.lua)
- [x] Sistema de relaciones (rook_affinity, nova_affinity, getTeammateAlignment)
- [x] Triggers de conversacion por fase (mysummerNarrative events)
- [x] Extender `mysummerChat.lua` con formato V3/V4 (queueDialogue, queueMessage)
- [x] Fix plantillas {{contextReaction}} y {{contextTransition}}
- [x] Fix queueDialogue para enviar mensajes al chat del telefono
- [x] Actualizar Ghost V3 para nuevo contexto narrativo (Ghost te contacta primero)
- [ ] Completar level2 y level3 de Ghost V3
- [ ] Testing completo del sistema narrativo

#### Misiones de Contacto
- [ ] 6 misiones obligatorias (1 por capitulo)
- [ ] Tipos: delivery, chase (ya implementados)
- [ ] Integracion con progresion de fase

#### UI
- [ ] Actualizar selector de carreras
- [ ] Mostrar Rook/Nova en lista de contactos
- [ ] Dialogos overlay durante conduccion
- [ ] Testing completo

### Archivos

Existentes a modificar:
- `gameplay/domains/mysummer/skills/streetracing/info.json` - Ya tiene 7 niveles
- `lua/ge/extensions/career/modules/mysummerStoryRaces.lua` - Simplificar
- `lua/ge/extensions/career/modules/mysummerMissions.lua` - Extender
- `lua/ge/extensions/career/modules/mysummerChat.lua` - Formato V4

Ya creados:
- `lua/ge/extensions/career/modules/mysummerNarrative.lua` - Story Orchestrator con eventos por fase
- `lua/ge/extensions/career/modules/deepweb_contacts/rook_v3.json` - Dialogos de Rook (mecanico ansioso)
- `lua/ge/extensions/career/modules/deepweb_contacts/nova_v3.json` - Dialogos de Nova (copiloto ambiciosa)
- `lua/ge/extensions/career/modules/deepweb_contacts/ghost_v3.json` - Ghost (misterioso, conoce al abuelo)
- `gameplay/domains/mysummer/skills/rook/info.json` - Skill de relacion con Rook
- `gameplay/domains/mysummer/skills/nova/info.json` - Skill de relacion con Nova
- `docs/narrative_test_guide.md` - Guia de prueba del sistema narrativo

Documentacion (ya existe):
- `/docs/narrative_v4/` - Todos los JSONs narrativos
- `/docs/V4_SYSTEM_DESIGN.md` - Diseno tecnico

---

## Archivos Clave del Proyecto

### Lua (Backend)
- `lua/ge/extensions/career/modules/mysummerParts.lua` - Mercado de piezas
- `lua/ge/extensions/career/modules/mysummerPartShops.lua` - Tiendas oficiales
- `lua/ge/extensions/career/modules/mysummerRaceManager.lua` - Carreras antiguas
- `lua/ge/extensions/career/modules/mysummerStoryRaces.lua` - Sistema de carreras v4
- `lua/ge/extensions/career/modules/mysummerCareer.lua` - Progresion de capitulos
- `lua/ge/extensions/career/modules/mysummerChat.lua` - Sistema de chat/contactos
- `lua/ge/extensions/career/modules/mysummerMissions.lua` - Misiones de contactos
- `lua/ge/extensions/career/modules/mysummerStory.lua` - Story Orchestrator (CREAR)

### Vue (Frontend)
- `ui-vue-src/modules/career/components/mysummer/browser/` - Paginas del navegador
- `ui-vue-src/modules/career/components/mysummer/MySummerBrowser.vue` - Router
- `ui-vue-src/modules/career/stores/mysummerPartsStore.js` - Estado de mercado

### Configuraciones
- `vehicles/etki/mysummer_2400ti_ttsport_chassis.pc` - Config actual ETK-I
- `vehicles/*/*.pc` terminados en `_race1.pc` - Configs de rivales para carreras
- `gameplay/domains/mysummer/` - Domain y skills
- `gameplay/missions/west_coast_usa/aiRace/` - Misiones de carreras BeamNG

### Documentacion Narrativa
- `/docs/narrative_v4/v4_hilo_narrativo.md` - Biblia narrativa
- `/docs/narrative_v4/*_full.json` - Dialogos por personaje
- `/docs/V4_SYSTEM_DESIGN.md` - Arquitectura tecnica V4

---

## Tono Narrativo (Reglas de Oro)

Del documento `v4_hilo_narrativo.md`:

1. **Mundo realista**, no heroico
2. Nadie es completamente bueno ni malo
3. Las decisiones tienen **consecuencias lentas**, no inmediatas
4. El pasado pesa mas que el presente
5. El coche no es solo un objeto: es **identidad**

**Mensaje central:**
> No heredas los errores de otros. Los repites... o no.

**Regla de oro para contenido:**
Si un dialogo, mision o evento:
- no refuerza una personalidad
- no empuja un conflicto
- no deja una duda
-> **no pertenece a esta historia**

---

---

## SPRINT 26: Sistemas Narrativos Expandidos
**Prioridad: ALTA** | **Estado: EN PROGRESO**

### Objetivo
Expandir la narrativa más allá del chat con múltiples canales de comunicación y un sistema de debug completo.

### Documentación
Ver `/docs/narrative_v4/narrative_systems_design.md` para diseño completo.

### Nuevos Sistemas

#### 26.1 Monólogos Internos
Pensamientos del protagonista en pantalla mientras conduce.

**Triggers:**
- Al iniciar una misión/carrera
- Después de eventos narrativos
- Al pasar cerca de lugares significativos
- Aleatorios según fase narrativa

**UI:**
- Texto en cursiva, centro-inferior
- Fade in/out suave (5s visible)
- Sin interacción del jugador

**Contenido por fase:**
- Fase 0-1: Primeros pasos, dudas sobre el coche
- Fase 2: Preguntas sobre Ghost y el abuelo
- Fase 3: Tensión Rook/Nova
- Fase 4: Conflicto y desconfianza
- Fase 5: Advertencias, cercanía a The Big One
- Fase 6: Post-robo, búsqueda de respuestas

**Archivos:**
- `lua/ge/extensions/career/modules/mysummerMonologues.lua`
- `deepweb_contacts/monologues/phase*.json`

#### 26.2 Sistema de Llamadas
Conversaciones telefónicas durante la conducción.

**Características:**
- Más inmersivas que el chat
- Pueden interrumpir al jugador
- Opción de contestar o ignorar
- Diálogo con opciones de respuesta

**UI:**
- Notificación de llamada entrante
- Overlay durante llamada con texto
- Opciones de respuesta numeradas
- Timer de duración

**Llamadas principales:**
- Fase 2: Primera llamada de Ghost (críptica)
- Fase 4: Llamada de Rook (nervioso, pide consejo)
- Fase 4: Llamada de Nova (frustrada, planes)
- Fase 5: Advertencia urgente de Ghost
- Fase 6: Llamada de revelación

**Archivos:**
- `lua/ge/extensions/career/modules/mysummerCalls.lua`
- `deepweb_contacts/calls/ghost_calls.json`
- `deepweb_contacts/calls/rook_calls.json`
- `deepweb_contacts/calls/nova_calls.json`

#### 26.3 Sistema de Debug Narrativo
Herramientas para probar toda la historia sin jugar.

**Comandos de consola:**
```lua
-- Estado actual
career_modules_mysummerNarrative.debugStatus()

-- Avanzar a fase
career_modules_mysummerNarrative.debugSetPhase(3)

-- Disparar evento
career_modules_mysummerNarrative.forceTriggerEvent("ghost_first_message")

-- Listar eventos
career_modules_mysummerNarrative.debugListEvents()

-- Reproducir historia completa
career_modules_mysummerNarrative.debugPlayFullStory()

-- Reproducir fase específica
career_modules_mysummerNarrative.debugPlayPhase(2)

-- Desbloquear documentos
career_modules_mysummerNarrative.debugUnlockAllDocuments()

-- Reset completo
career_modules_mysummerNarrative.debugReset()

-- Modo teatro (speedMultiplier: 1=normal, 5=5x, 0=instantáneo)
career_modules_mysummerNarrative.debugTheaterMode(5)
```

**Modo Teatro:**
- Reproduce toda la historia en secuencia
- Muestra monólogos, mensajes, llamadas, documentos
- Controles: ESPACIO (pausa), FLECHA (saltar), ESC (salir)
- Velocidad configurable

**Archivos:**
- `lua/ge/extensions/career/modules/mysummerNarrativeDebug.lua`

### Arquitectura de Módulos

```
mysummerNarrative.lua          -- Eventos y lógica principal (existente)
       │
       ├── mysummerMonologues.lua     -- Sistema de monólogos
       ├── mysummerCalls.lua          -- Sistema de llamadas
       └── mysummerNarrativeDebug.lua -- Herramientas de debug
```

### Tareas

#### Implementación Base
- [ ] Crear `mysummerMonologues.lua` con sistema básico
- [ ] Crear `mysummerCalls.lua` con sistema de llamadas
- [ ] Crear `mysummerNarrativeDebug.lua` con comandos de debug

#### UI
- [ ] Overlay de monólogos (texto fade in/out)
- [ ] UI de llamada entrante
- [ ] UI de llamada activa con opciones
- [ ] Panel de debug (opcional, para desarrollo)

#### Contenido
- [ ] Escribir monólogos para cada fase (6 fases × 5-10 monólogos)
- [ ] Escribir diálogos de llamadas para Ghost, Rook, Nova
- [ ] Integrar con eventos narrativos existentes

#### Testing
- [ ] Probar modo teatro completo
- [ ] Verificar triggers de monólogos
- [ ] Testear sistema de llamadas

### Prioridad de Implementación

1. **Debug básico** - Para poder probar todo rápido
2. **Monólogos** - El más fácil de implementar
3. **Llamadas** - El más complejo, requiere UI interactiva

---

## Orden de Prioridades (Actualizado)

| Sprint | Nombre | Prioridad | Estado |
|--------|--------|-----------|--------|
| ~~7~~ | ~~ETK-I Basico~~ | ~~ALTA~~ | COMPLETADO |
| ~~8.2~~ | ~~Kilometraje inicial~~ | ~~MEDIA~~ | COMPLETADO |
| ~~13~~ | ~~Traits y Cooldowns~~ | ~~ALTA~~ | COMPLETADO |
| ~~24~~ | ~~Chat Unificado~~ | ~~ALTA~~ | COMPLETADO |
| **25** | **Capitulos v4 + Narrativa** | **ALTA** | **EN PROGRESO** |
| **26** | **Narrativa Expandida + Debug** | **ALTA** | **EN PROGRESO** |
| 14 | Multiples Fuentes XP | ALTA | Pendiente |
| 15 | Misiones Contactos | ALTA | EN PROGRESO |
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

*Documento creado: Enero 2025*
*Ultima actualizacion: Sprint 26 - Sistemas Narrativos Expandidos*
