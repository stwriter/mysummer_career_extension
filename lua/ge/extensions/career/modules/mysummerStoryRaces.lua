-- MySummer Story Races
-- Manages chapter-based races with progression
-- Sends player to location, triggers race on arrival

local M = {}
M.moduleName = "career_modules_mysummerStoryRaces"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_branches",
  "career_modules_playerAttributes",
  -- Note: mysummerRaceManager, mysummerMissions, and mysummerChat are checked at runtime
  -- to avoid circular dependencies
}

local logTag = "mysummerStoryRaces"
local saveFile = "mysummer_story_races.json"

-- Forward declarations
local saveState
local loadState
local completeMission

-- ============================================================================
-- LOCALIZATION
-- ============================================================================

local function tr(key, default)
  return translateLanguage(key, default or key)
end

-- ============================================================================
-- RACE DEFINITIONS BY CHAPTER
-- ============================================================================

-- Story contact missions (1 per chapter, mandatory)
-- Each chapter introduces a new mechanic using real missions from mysummerMissions.lua:
-- Prologue: No mission (just races)
-- Ch1: delivery (simple intro) - Basic delivery tutorial
-- Ch2: delivery (with heat) - Delivery under pressure
-- Ch3: surveillance - Stealth mechanic
-- Ch4: chase - Action mechanic
-- Ch5: escort - Combat/survival mechanic
-- Ch6: escort (final) - Ultimate test
local storyMissions = {
  {
    id = "ch1_mission",
    chapter = 1,
    requiredLevel = 1, -- Chapter 1 unlocked at 300 XP
    requiresProjectCar = false,
    missionRef = "ghost_delivery_1", -- Reference to mission in mysummerMissions
    contact = "ghost",
    name = { en = "The Message", es = "El Mensaje" },
    description = {
      en = "A mysterious message from an unknown number. Ghost needs a package moved.",
      es = "Un mensaje misterioso de un numero desconocido. Ghost necesita mover un paquete."
    },
    tutorialHint = {
      en = "Delivery missions: Pick up at one location, deliver to another. Watch the timer.",
      es = "Misiones de entrega: Recoge en un sitio, entrega en otro. Vigila el tiempo."
    },
    xpReward = 100,
    moneyReward = 0,
    introDialogue = {
      { en = "You don't know me. But I know you.", es = "No me conoces. Pero yo a ti si." },
      { en = "That ETK project you're working on... it has potential.", es = "Ese proyecto ETK en el que trabajas... tiene potencial." },
      { en = "I need a favor. Move a package for me. Don't ask questions.", es = "Necesito un favor. Mueve un paquete para mi. No hagas preguntas." },
    },
    duringDialogues = {
      { afterSeconds = 30, messages = {
        { en = "Keep moving. Time is money.", es = "Sigue moviendote. El tiempo es dinero." },
      }},
      { afterSeconds = 90, messages = {
        { en = "You're doing good. Don't slow down.", es = "Lo estas haciendo bien. No reduzcas." },
      }},
    },
    completionDialogue = {
      { en = "Welcome to the scene. I'm Ghost. I'll be in touch.", es = "Bienvenido a la escena. Soy Ghost. Estare en contacto." },
      { en = "There are races happening. Small ones, for now. I'll send you the details.", es = "Hay carreras. Pequenas, por ahora. Te enviare los detalles." },
    },
  },
  {
    id = "ch2_mission",
    chapter = 2,
    requiredLevel = 1,
    requiresProjectCar = false,
    missionRef = "ghost_delivery_2", -- Hot Cargo - delivery with heat
    contact = "ghost",
    name = { en = "Hot Cargo", es = "Carga Caliente" },
    description = {
      en = "This delivery is risky. The heat is real. Don't get stopped.",
      es = "Esta entrega es arriesgada. El calor es real. No te paren."
    },
    tutorialHint = {
      en = "Some deliveries have 'heat' - police will be looking for you.",
      es = "Algunas entregas tienen 'calor' - la policia te buscara."
    },
    xpReward = 150,
    moneyReward = 0,
    introDialogue = {
      { en = "This one's different. The cops are sniffing around.", es = "Esta es diferente. Los polis estan husmeando." },
      { en = "Get the goods from the auto shop, deliver to the lot. Fast.", es = "Recoge la mercancia del taller, entregala en el parking. Rapido." },
    },
    duringDialogues = {
      { afterSeconds = 20, messages = {
        { en = "Eyes on the road. Eyes on the mirrors.", es = "Ojos en la carretera. Ojos en los espejos." },
      }},
      { afterSeconds = 60, messages = {
        { en = "If you see blue lights, lose them. Don't lead them to the drop.", es = "Si ves luces azules, pierdalos. No los lleves a la entrega." },
      }},
      { afterSeconds = 120, messages = {
        { en = "Almost there. Stay calm.", es = "Casi llegas. Mantén la calma." },
      }},
    },
    completionDialogue = {
      { en = "Not bad for a rookie. You can handle pressure.", es = "No esta mal para un novato. Aguantas la presion." },
      { en = "I've got more work coming. Stay ready.", es = "Tengo mas trabajo. Estate listo." },
    },
  },
  {
    id = "ch3_mission",
    chapter = 3,
    requiredLevel = 2,
    requiresProjectCar = false,
    missionRef = "ghost_surveillance_1", -- Eyes On
    contact = "ghost",
    name = { en = "Eyes On", es = "Vigilancia" },
    description = {
      en = "Ghost needs someone followed. Keep your distance, don't get spotted.",
      es = "Ghost necesita que sigas a alguien. Manten la distancia, no te dejes ver."
    },
    tutorialHint = {
      en = "Surveillance: Follow the target. Too close = detected. Too far = lost. Watch the meter.",
      es = "Vigilancia: Sigue al objetivo. Muy cerca = detectado. Muy lejos = perdido. Vigila el indicador."
    },
    xpReward = 200,
    moneyReward = 0,
    introDialogue = {
      { en = "There's someone I need watched. A rat, maybe.", es = "Hay alguien a quien necesito vigilar. Una rata, quizas." },
      { en = "Follow him. Stay back. Report where he goes.", es = "Siguelo. Mantente atras. Dime a donde va." },
    },
    duringDialogues = {
      { afterSeconds = 15, messages = {
        { en = "Not too close. Let him breathe.", es = "No demasiado cerca. Dejale respirar." },
      }},
      { afterSeconds = 45, messages = {
        { en = "He's nervous. Stay in the traffic flow.", es = "Esta nervioso. Mantente en el trafico." },
      }},
      { afterSeconds = 90, messages = {
        { en = "Interesting... he's heading somewhere specific.", es = "Interesante... va a algun sitio especifico." },
      }},
    },
    completionDialogue = {
      { en = "Good intel. Now I know where to find him.", es = "Buena informacion. Ahora se donde encontrarlo." },
      { en = "You've got a steady hand. Techie wants to meet you.", es = "Tienes mano firme. Techie quiere conocerte." },
    },
    unlockContact = "techie",
  },
  {
    id = "ch4_mission",
    chapter = 4,
    requiredLevel = 3,
    requiresProjectCar = false,
    missionRef = "shadow_chase_1", -- First chase mission
    contact = "shadow",
    name = { en = "Dirty Work", es = "Trabajo Sucio" },
    description = {
      en = "Shadow needs someone stopped. No questions, no witnesses.",
      es = "Shadow necesita que detengas a alguien. Sin preguntas, sin testigos."
    },
    tutorialHint = {
      en = "Chase missions: Pursue the target and force them to stop. Ram them if needed.",
      es = "Misiones de persecucion: Persigue al objetivo y obligalo a parar. Embistelo si es necesario."
    },
    xpReward = 300,
    moneyReward = 0,
    introDialogue = {
      { en = "...", es = "..." },
      { en = "Someone's been talking. That stops tonight.", es = "Alguien ha estado hablando. Eso termina esta noche." },
    },
    duringDialogues = {
      { afterSeconds = 10, messages = {
        { en = "Don't let them reach the highway.", es = "No les dejes llegar a la autopista." },
      }},
      { afterSeconds = 40, messages = {
        { en = "Pin them down. Use your car.", es = "Acorraladlos. Usa tu coche." },
      }},
    },
    completionDialogue = {
      { en = "Clean work. You're crossing lines now. No going back.", es = "Trabajo limpio. Estas cruzando lineas. No hay vuelta atras." },
    },
    unlockContact = "shadow",
  },
  {
    id = "ch5_mission",
    chapter = 5,
    requiredLevel = 4,
    requiresProjectCar = true,
    missionRef = "ghost_escort_1", -- Running the Gauntlet
    contact = "ghost",
    name = { en = "The Return", es = "El Retorno" },
    description = {
      en = "Ghost resurfaces with an urgent request. His enemies are closing in.",
      es = "Ghost reaparece con una peticion urgente. Sus enemigos se acercan."
    },
    tutorialHint = {
      en = "Escort missions: Survive enemy waves while reaching the destination.",
      es = "Misiones de escolta: Sobrevive oleadas de enemigos mientras llegas al destino."
    },
    xpReward = 400,
    moneyReward = 0,
    introDialogue = {
      { en = "It's been a while. I went quiet for a reason.", es = "Ha pasado tiempo. Me calle por una razon." },
      { en = "They're hunting me now. I need you to drive my truck through their blockade.", es = "Me estan cazando. Necesito que conduzcas mi camion a traves de su bloqueo." },
    },
    duringDialogues = {
      { afterSeconds = 5, messages = {
        { en = "Here they come. Don't stop!", es = "Aqui vienen. No pares!" },
      }},
      { afterSeconds = 30, messages = {
        { en = "More incoming. Push through!", es = "Vienen mas. Atraviesalos!" },
      }},
      { afterSeconds = 60, messages = {
        { en = "You're doing it. Keep going!", es = "Lo estas logrando. Sigue adelante!" },
      }},
    },
    completionDialogue = {
      { en = "The Big One is real. It's happening. Your grandfather knew about it.", es = "The Big One es real. Esta pasando. Tu abuelo lo sabia." },
      { en = "You need to qualify. Official rallies. Then we'll talk about the race.", es = "Necesitas clasificar. Rallys oficiales. Luego hablaremos de la carrera." },
    },
  },
  {
    id = "ch6_mission",
    chapter = 6,
    requiredLevel = 5,
    requiresProjectCar = true,
    missionRef = "ghost_escort_2", -- Death Race - hardest escort
    contact = "ghost",
    name = { en = "The Legacy", es = "El Legado" },
    description = {
      en = "Everyone wants Ghost dead. You're driving through all of them.",
      es = "Todos quieren a Ghost muerto. Vas a atravesarlos a todos."
    },
    tutorialHint = {
      en = "Final test: Multiple waves, high intensity. Prove you're ready for The Big One.",
      es = "Prueba final: Multiples oleadas, alta intensidad. Demuestra que estas listo para The Big One."
    },
    xpReward = 500,
    moneyReward = 0,
    introDialogue = {
      { en = "Every crew in the city wants my blood tonight.", es = "Cada banda de la ciudad quiere mi sangre esta noche." },
      { en = "You're driving my armored rig through all of them. Don't stop. Don't look back.", es = "Vas a conducir mi camion blindado a traves de todos ellos. No pares. No mires atras." },
    },
    duringDialogues = {
      { afterSeconds = 5, messages = {
        { en = "They're everywhere. MOVE!", es = "Estan por todos lados. MUEVETE!" },
      }},
      { afterSeconds = 25, messages = {
        { en = "That was wave one. More coming.", es = "Esa fue la primera oleada. Vienen mas." },
      }},
      { afterSeconds = 50, messages = {
        { en = "They're throwing everything at us!", es = "Nos estan tirando todo lo que tienen!" },
      }},
      { afterSeconds = 80, messages = {
        { en = "Almost there. Don't give up now!", es = "Casi llegamos. No te rindas ahora!" },
      }},
    },
    completionDialogue = {
      { en = "He never got to race it. An accident, the night before. Some say sabotage.", es = "Nunca pudo correrla. Un accidente, la noche anterior. Algunos dicen sabotaje." },
      { en = "That ETK you're building... it was his dream. Now it's yours.", es = "Ese ETK que estas construyendo... era su sueno. Ahora es tuyo." },
      { en = "Do it for both of you.", es = "Hazlo por los dos." },
    },
  },
}

-- Story races organized by chapter, matching branch level requirements from info.json
-- 8-Phase System (Phase 0-8)
local storyRaces = {
  -- Phase 0 (Level 0): 3 races - Prologue (The Weight of Silence)
  {
    chapter = 0,
    chapterName = "prologue",
    requiredLevel = 0, -- Available from start (0 XP)
    requiresProjectCar = false,
    requiresCovet = false,
    races = {
      {
        id = "prologue_race1",
        missionId = "west_coast_usa/aiRace/001-STREET/info.json",
        name = { en = "Downtown Dash", es = "Carrera Centro" },
        description = { en = "The classic downtown circuit where legends are made", es = "El circuito clasico del centro donde nacen las leyendas" },
        contact = "ghost",
        xpReward = 200,
        moneyReward = 500,
      },
      {
        id = "prologue_race2",
        missionId = "west_coast_usa/aiRace/002-STREET/info.json",
        name = { en = "Industrial Loop", es = "Circuito Industrial" },
        description = { en = "Quick sprint through the industrial district", es = "Sprint rapido por el distrito industrial" },
        contact = "ghost",
        xpReward = 200,
        moneyReward = 500,
      },
      {
        id = "prologue_race3",
        missionId = "west_coast_usa/aiRace/003-STREET/info.json",
        name = { en = "Harbor Run", es = "Carrera del Puerto" },
        description = { en = "Late night race near the docks", es = "Carrera nocturna cerca de los muelles" },
        contact = "ghost",
        xpReward = 220,
        moneyReward = 700,
      },
    },
  },
  -- Phase 1 (Level 1): 3 races - Origins
  {
    chapter = 1,
    chapterName = "chapter1",
    requiredLevel = 1, -- Requires 350 XP
    requiresProjectCar = false,
    requiresCovet = false,
    races = {
      {
        id = "ch1_race1",
        missionId = "west_coast_usa/aiRace/004-STREET/info.json",
        name = { en = "The Dance of Three", es = "La Danza de los Tres" },
        description = { en = "Racing with Rook and Nova - two philosophies clash", es = "Corriendo con Rook y Nova - dos filosofias chocan" },
        contact = "rook",
        xpReward = 250,
        moneyReward = 1000,
      },
      {
        id = "ch1_race2",
        missionId = "west_coast_usa/aiRace/005-STREET/info.json",
        name = { en = "The Rhythm of Asphalt", es = "El Ritmo del Asfalto" },
        description = { en = "Rook's technical challenge - precision over power", es = "Desafio tecnico de Rook - precision sobre potencia" },
        contact = "rook",
        xpReward = 250,
        moneyReward = 1200,
      },
      {
        id = "ch1_race3",
        missionId = "west_coast_usa/aiRace/006-STREET/info.json",
        name = { en = "The Crack", es = "La Grieta" },
        description = { en = "Tensions rise as Ghost warns of danger ahead", es = "Las tensiones aumentan mientras Ghost advierte del peligro" },
        contact = "ghost",
        xpReward = 280,
        moneyReward = 1500,
      },
    },
  },
  -- Phase 2 (Level 2): 3 races - The Split
  {
    chapter = 2,
    chapterName = "chapter2",
    requiredLevel = 2, -- Requires 850 XP
    requiresProjectCar = false,
    requiresCovet = false,
    races = {
      {
        id = "ch2_race1",
        missionId = "west_coast_usa/aiRace/007-STREET/info.json",
        name = { en = "Point of Friction", es = "Punto de Friccion" },
        description = { en = "Nova vs Rook argument intensifies mid-race", es = "La discusion Nova vs Rook se intensifica en plena carrera" },
        contact = "nova",
        xpReward = 300,
        moneyReward = 2000,
      },
      {
        id = "ch2_race2",
        missionId = "west_coast_usa/aiRace/008-STREET/info.json",
        name = { en = "The Weight of Steel", es = "El Peso del Acero" },
        description = { en = "Muscle appears, watching your ETK-I with interest", es = "Muscle aparece, observando tu ETK-I con interes" },
        contact = "muscle",
        xpReward = 320,
        moneyReward = 2500,
      },
      {
        id = "ch2_race3",
        missionId = "west_coast_usa/aiRace/009-STREET/info.json",
        name = { en = "Ultimatum", es = "Ultimatum" },
        description = { en = "Rook begs you to talk sense into Nova", es = "Rook te suplica que hagas entrar en razon a Nova" },
        contact = "rook",
        xpReward = 350,
        moneyReward = 3000,
      },
    },
  },
  -- Phase 3 (Level 3): 3 races - The Crisis
  {
    chapter = 3,
    chapterName = "chapter3",
    requiredLevel = 3, -- Requires 1600 XP
    requiresProjectCar = false,
    requiresCovet = false,
    races = {
      {
        id = "ch3_race1",
        missionId = "west_coast_usa/aiRace/010-STREET/info.json",
        name = { en = "Material Tension", es = "Tension de Materiales" },
        description = { en = "Rook and Nova teach opposite lessons during the race", es = "Rook y Nova enseñan lecciones opuestas durante la carrera" },
        contact = "rook",
        xpReward = 400,
        moneyReward = 3500,
      },
      {
        id = "ch3_race2",
        missionId = "west_coast_usa/aiRace/001-STREET/info.json",
        name = { en = "Viper's Whisper", es = "El Murmullo de Viper" },
        description = { en = "Ghost reminds you of the past - your grandfather and Viper", es = "Ghost te recuerda el pasado - tu abuelo y Viper" },
        contact = "ghost",
        xpReward = 420,
        moneyReward = 3800,
      },
      {
        id = "ch3_race3",
        missionId = "west_coast_usa/aiRace/002-STREET/info.json",
        name = { en = "Nova's Proposal", es = "La Propuesta de Nova" },
        description = { en = "Nova approaches you privately about leaving this town", es = "Nova te aborda en privado sobre dejar este pueblo" },
        contact = "nova",
        xpReward = 450,
        moneyReward = 4000,
      },
    },
  },
  -- Phase 4 (Level 4): 3 races - The Split (Final Rupture)
  {
    chapter = 4,
    chapterName = "chapter4",
    requiredLevel = 4, -- Requires 2400 XP
    requiresProjectCar = false,
    requiresCovet = false,
    races = {
      {
        id = "ch4_race1",
        missionId = "west_coast_usa/aiRace/003-STREET/info.json",
        name = { en = "Ignition Failure", es = "Fallo de Encendido" },
        description = { en = "Nova's car malfunctions - Shadow's parts are risky", es = "El coche de Nova falla - las piezas de Shadow son arriesgadas" },
        contact = "nova",
        xpReward = 480,
        moneyReward = 4500,
      },
      {
        id = "ch4_race2",
        missionId = "west_coast_usa/aiRace/004-STREET/info.json",
        name = { en = "The Interrogation", es = "El Interrogatorio" },
        description = { en = "Rook asks you about Nova's connection to Shadow", es = "Rook te pregunta sobre la conexion de Nova con Shadow" },
        contact = "rook",
        xpReward = 500,
        moneyReward = 5000,
      },
      {
        id = "ch4_race3",
        missionId = "west_coast_usa/aiRace/005-STREET/info.json",
        name = { en = "The Explosion", es = "La Explosion" },
        description = { en = "Public breakup over the radio - the team shatters", es = "Ruptura publica por la radio - el equipo se destruye" },
        contact = "ghost",
        xpReward = 520,
        moneyReward = 5500,
      },
    },
  },
  -- Phase 5 (Level 5): 4 races - Rally Regional (Dust and Betrayal)
  {
    chapter = 5,
    chapterName = "chapter5",
    requiredLevel = 5, -- Requires 3300 XP
    requiresProjectCar = true, -- MUST use ETK-I
    requiresCovet = false,
    races = {
      {
        id = "ch5_rally1",
        missionId = "west_coast_usa/aiRace/007-STREET/info.json",
        name = { en = "Gravel Baptism", es = "Bautismo de Grava" },
        description = { en = "First rally stage - the ETK-I sounds perfect", es = "Primera etapa rally - el ETK-I suena perfecto" },
        contact = "ghost",
        xpReward = 550,
        moneyReward = 6000,
      },
      {
        id = "ch5_rally2",
        missionId = "west_coast_usa/aiRace/008-STREET/info.json",
        name = { en = "Forest Fire", es = "Fuego en el Bosque" },
        description = { en = "Shadow sees profit in your success", es = "Shadow ve ganancia en tu exito" },
        contact = "shadow",
        xpReward = 580,
        moneyReward = 6500,
      },
      {
        id = "ch5_rally3",
        missionId = "west_coast_usa/aiRace/009-STREET/info.json",
        name = { en = "Final Plea", es = "Los Alegatos Finales" },
        description = { en = "CRITICAL: Choose Rook or Nova - this choice is permanent", es = "CRITICO: Elige Rook o Nova - esta eleccion es permanente" },
        contact = "rook",
        xpReward = 600,
        moneyReward = 7000,
      },
      {
        id = "ch5_rally4",
        missionId = "west_coast_usa/aiRace/010-STREET/info.json",
        name = { en = "Last Victory", es = "La Ultima Victoria" },
        description = { en = "You win the rally. Then... darkness. The car is stolen.", es = "Ganas el rally. Luego... oscuridad. El coche es robado." },
        contact = "ghost",
        xpReward = 650,
        moneyReward = 8000,
      },
    },
  },
  -- Phase 6 (Level 6): 4 races - Copa Covet (Rock Bottom)
  {
    chapter = 6,
    chapterName = "chapter6",
    requiredLevel = 6, -- Requires 4500 XP
    requiresProjectCar = false,
    requiresCovet = true, -- MUST use Covet
    races = {
      {
        id = "ch6_covet1",
        missionId = "west_coast_usa/aiRace/001-STREET/info.json",
        name = { en = "Scrap and Humiliation", es = "Chatarra y Humillacion" },
        description = { en = "From rally winner to junkyard Covet driver", es = "De ganador de rally a conductor de Covet de desguace" },
        contact = "ghost",
        xpReward = 150,
        moneyReward = 300,
      },
      {
        id = "ch6_covet2",
        missionId = "west_coast_usa/aiRace/002-STREET/info.json",
        name = { en = "Traitor's Silence", es = "El Silencio del Traidor" },
        description = { en = "Your partner has vanished. Techie shows 'evidence' of betrayal", es = "Tu pareja ha desaparecido. Techie muestra 'evidencia' de traicion" },
        contact = "techie",
        xpReward = 150,
        moneyReward = 300,
      },
      {
        id = "ch6_covet3",
        missionId = "west_coast_usa/aiRace/003-STREET/info.json",
        name = { en = "Other Side of the Coin", es = "La Otra Cara de la Moneda" },
        description = { en = "The one you didn't choose mocks your misfortune", es = "Quien no elegiste se burla de tu desgracia" },
        contact = "nova",
        xpReward = 180,
        moneyReward = 400,
      },
      {
        id = "ch6_covet4",
        missionId = "west_coast_usa/aiRace/004-STREET/info.json",
        name = { en = "End of Covet Cup", es = "Final de la Copa Covet" },
        description = { en = "You win the pass, but the ETK-I is still gone", es = "Ganas el pase, pero el ETK-I sigue perdido" },
        contact = "shadow",
        xpReward = 200,
        moneyReward = 500,
      },
    },
  },
  -- Phase 7 (Level 7): 4 races - Clasificatorias (The Iron Trail)
  {
    chapter = 7,
    chapterName = "chapter7",
    requiredLevel = 7, -- Requires 6000 XP
    requiresProjectCar = false,
    requiresCovet = false,
    races = {
      {
        id = "ch7_qualifier1",
        missionId = "west_coast_usa/aiRace/005-STREET/info.json",
        name = { en = "Puzzle Pieces", es = "Piezas del Puzzle" },
        description = { en = "You see your ETK-I's parts on rival cars", es = "Ves piezas de tu ETK-I en coches rivales" },
        contact = "ghost",
        xpReward = 500,
        moneyReward = 4000,
      },
      {
        id = "ch7_qualifier2",
        missionId = "west_coast_usa/aiRace/006-STREET/info.json",
        name = { en = "Ghost in the Paddock", es = "El Fantasma en el Paddock" },
        description = { en = "Anonymous messages hint Shadow manipulated everything", es = "Mensajes anonimos insinuan que Shadow manipulo todo" },
        contact = "system",
        xpReward = 520,
        moneyReward = 4500,
      },
      {
        id = "ch7_qualifier3",
        missionId = "west_coast_usa/aiRace/007-STREET/info.json",
        name = { en = "The Ambush", es = "La Emboscada" },
        description = { en = "Someone tries to take you out of the race violently", es = "Alguien intenta sacarte de la carrera violentamente" },
        contact = "shadow",
        xpReward = 550,
        moneyReward = 5000,
      },
      {
        id = "ch7_qualifier4",
        missionId = "west_coast_usa/aiRace/008-STREET/info.json",
        name = { en = "The Reunion", es = "El Reencuentro" },
        description = { en = "Your partner returns. The truth is revealed. Shadow challenges you.", es = "Tu pareja regresa. La verdad se revela. Shadow te desafia." },
        contact = "rook",
        xpReward = 600,
        moneyReward = 6000,
      },
    },
  },
  -- Phase 8 (Level 8): 2 races - The Big One (Reclamation and Glory)
  {
    chapter = 8,
    chapterName = "chapter8",
    requiredLevel = 8, -- Requires 7800 XP
    requiresProjectCar = true, -- ETK-I recovered and used
    requiresCovet = false,
    races = {
      {
        id = "ch8_duel_shadow",
        missionId = "west_coast_usa/aiRace/009-STREET/info.json",
        name = { en = "Justice at 200 km/h", es = "Justicia a 200 km/h" },
        description = { en = "1vs1 duel against Shadow - he drives YOUR ETK-I", es = "Duelo 1vs1 contra Shadow - el conduce TU ETK-I" },
        contact = "shadow",
        xpReward = 800,
        moneyReward = 15000,
      },
      {
        id = "ch8_bigone",
        missionId = "west_coast_usa/aiRace/010-STREET/info.json",
        name = { en = "Grandfather's Dream", es = "El Sueno del Abuelo" },
        description = { en = "The Big One. Against Viper. For both of you.", es = "The Big One. Contra Viper. Por ambos." },
        contact = "viper",
        xpReward = 1000,
        moneyReward = 50000,
      },
    },
  },
}

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  completedRaces = {}, -- { raceId = { completed = true, bestTime = 123, wins = 1 } }
  completedMissions = {}, -- { missionId = true }
  activeRace = nil,    -- Currently selected race (waiting for player to arrive, then starts correct version)
  activeMission = nil, -- Currently active story mission
  currentChapter = 0,  -- Current story chapter (0 = prologue)
  -- Story dialogue state
  drivingDialogueTriggered = {}, -- Which dialogues have been shown
  missionElapsedTime = 0, -- Time elapsed since story mission started (for timed dialogues)
  -- Narrative event tracking (per race instance)
  narrativeEvents = {
    raceStartTriggered = false,  -- Has race_start event been triggered?
    raceMidTriggered = false,    -- Has race_mid event been triggered?
    raceEndTriggered = false,    -- Has race_end event been triggered?
    raceStartTime = 0,           -- When did the player start moving?
    playerMovedInRace = false,   -- Has player started moving? (for race_start detection)
    missionEnded = false,        -- Has the race mission ended? (for race_end detection)
  },
  -- Progression tracking (per phase)
  phaseRaceCount = {
    [0] = 0,  -- Prologue: 0 races completed
    [1] = 0,  -- Phase 1: 0 races completed
    [2] = 0,  -- Phase 2: 0 races completed
    [3] = 0,  -- Phase 3: 0 races completed
    [4] = 0,  -- Phase 4: 0 races completed
    [5] = 0,  -- Phase 5: 0 races completed
    [6] = 0,  -- Phase 6: 0 races completed
    [7] = 0,  -- Phase 7: 0 races completed
    [8] = 0,  -- Phase 8: 0 races completed
  },
}

-- ============================================================================
-- NARRATIVE EVENT SYSTEM
-- ============================================================================

local RACE_MID_DELAY = 60  -- Seconds after race_start to trigger race_mid
local PLAYER_SPEED_THRESHOLD = 5.0  -- m/s to consider "moving"

-- Reset narrative events (called when starting/restarting a race)
-- Parameters are optional - if not provided, will try to get from state
local function resetNarrativeEvents(phase, raceCount)
  state.narrativeEvents = {
    raceStartTriggered = false,
    raceMidTriggered = false,
    raceEndTriggered = false,
    raceStartTime = 0,
    playerMovedInRace = false,
    missionEnded = false,
    missionEndTime = 0,
    waitingForResult = false,  -- Waiting for completeRace after mission ended
  }

  -- Also reset narrative content (monologues/calls/SMS) so they can be seen again
  if extensions.career_modules_mysummerNarrative and phase and raceCount then
    extensions.career_modules_mysummerNarrative.resetRaceNarrative(phase, raceCount)
    log("I", logTag, string.format("Narrative events and content reset for Phase %d, Race #%d", phase, raceCount))
  else
    log("I", logTag, "Narrative events reset (no phase/race info)")
  end
end

-- Get player speed
local function getPlayerSpeed()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return 0 end

  local vel = playerVehicle:getVelocity()
  if not vel then return 0 end

  return vel:length()
end

-- Get current phase based on player level
local function getCurrentPhase()
  if not career_branches or not career_modules_playerAttributes then
    return 0
  end

  local skillId = "mysummer-streetracing"
  local totalXP = career_modules_playerAttributes.getAttributeValue(skillId) or 0
  local level = career_branches.calcBranchLevelFromValue(totalXP, skillId)

  return level or 0
end

-- Trigger narrative event based on phase and race count
local function triggerNarrativeEventByCount(phase, raceCount, eventType)
  if not extensions.career_modules_mysummerNarrative then return end

  -- Build event key: "phase0_race1_start", "phase1_race2_mid", etc.
  local eventKey = string.format("phase%d_race%d_%s", phase, raceCount, eventType)

  log("I", logTag, string.format("Triggering narrative event '%s' (Phase %d, Race #%d, Type: %s)",
    eventKey, phase, raceCount, eventType))

  extensions.career_modules_mysummerNarrative.queueEvent(eventKey, 2)  -- 2 second delay
end

-- ============================================================================
-- HELPER FUNCTIONS
-- ============================================================================

-- Get player's current streetracing level
local function getPlayerLevel()
  if career_modules_playerAttributes then
    local attr = career_modules_playerAttributes.getAttributeValue("mysummer-streetracing")
    if attr then
      -- Convert XP to level (8-phase system)
      local xp = attr or 0
      if xp >= 7800 then return 8
      elseif xp >= 6000 then return 7
      elseif xp >= 4500 then return 6
      elseif xp >= 3300 then return 5
      elseif xp >= 2400 then return 4
      elseif xp >= 1600 then return 3
      elseif xp >= 850 then return 2
      elseif xp >= 350 then return 1
      else return 0
      end
    end
  end
  return 0
end

-- Check if player is driving the project car (ETK-I)
local function isPlayerInProjectCar()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return false end

  local model = playerVehicle:getJBeamFilename()
  return model == "etki"
end

-- Check if player is driving a Covet
local function isPlayerInCovet()
  local playerVehicle = be:getPlayerVehicle(0)
  if not playerVehicle then return false end

  local model = playerVehicle:getJBeamFilename()
  return model == "covet"
end

-- Get localized text
local function getLocalizedText(textTable)
  if not textTable then return "" end
  local lang = Lua and Lua.language or "en"
  if lang:find("es") then
    return textTable.es or textTable.en or ""
  end
  return textTable.en or ""
end

-- Get mission start position from info.json
local function getMissionStartPosition(missionPath)
  -- missionPath is like "west_coast_usa/aiRace/001-STREET/info.json"
  local fullPath = "/gameplay/missions/" .. missionPath
  local infoData = jsonReadFile(fullPath)

  if infoData and infoData.startTrigger and infoData.startTrigger.pos then
    local pos = infoData.startTrigger.pos
    if pos[1] and pos[2] and pos[3] then
      return vec3(pos[1], pos[2], pos[3])
    end
  end

  log("W", logTag, "Could not get start position for mission: " .. tostring(missionPath))
  return nil
end

-- Get player vehicle position
local function getPlayerPosition()
  local playerVehicle = be:getPlayerVehicle(0)
  if playerVehicle then
    return playerVehicle:getPosition()
  end
  return nil
end

-- ============================================================================
-- RACE ACCESS
-- ============================================================================

-- Get all races available for a chapter
local function getChapterRaces(chapter)
  for _, chapterData in ipairs(storyRaces) do
    if chapterData.chapter == chapter then
      return chapterData
    end
  end
  return nil
end

-- Find story race ID by BeamNG mission ID
-- The missionId from BeamNG is like "west_coast_usa-aiRace-001-STREET" or similar
local function findRaceIdByMission(beamngMissionId)
  -- First check if there's an active race - that's likely the one that just finished
  if state.activeRace and state.activeRace.raceId then
    return state.activeRace.raceId
  end

  -- Otherwise search through all races to find matching missionId
  -- BeamNG mission IDs are formatted like "west_coast_usa/aiRace/001-STREET"
  -- Our missionId is like "west_coast_usa/aiRace/001-STREET/info.json"
  for _, chapterData in ipairs(storyRaces) do
    for _, race in ipairs(chapterData.races) do
      -- Remove "/info.json" from our path
      local ourPath = race.missionId:gsub("/info%.json$", "")
      -- Also try with REPEAT suffix
      local ourPathRepeat = ourPath .. "-REPEAT"

      if beamngMissionId == ourPath or beamngMissionId == ourPathRepeat then
        return race.id
      end

      -- Also try direct substring match
      if beamngMissionId:find(race.id, 1, true) then
        return race.id
      end
    end
  end

  log("D", logTag, "No story race found for BeamNG mission: " .. tostring(beamngMissionId))
  return nil
end

-- Check if a race is accessible
local function isRaceAccessible(raceId)
  local playerLevel = getPlayerLevel()

  for _, chapterData in ipairs(storyRaces) do
    for _, race in ipairs(chapterData.races) do
      if race.id == raceId then
        -- Check level requirement
        if playerLevel < chapterData.requiredLevel then
          return false, "level", chapterData.requiredLevel
        end
        -- Check project car requirement
        if chapterData.requiresProjectCar and not isPlayerInProjectCar() then
          return false, "projectcar", nil
        end
        -- Check Covet requirement
        if chapterData.requiresCovet and not isPlayerInCovet() then
          return false, "requirescovet", nil
        end
        return true, nil, nil
      end
    end
  end
  return false, "notfound", nil
end

-- Check if race is completed
local function isRaceCompleted(raceId)
  return state.completedRaces[raceId] and state.completedRaces[raceId].completed
end

-- Check if story mission is completed
local function isMissionCompleted(missionId)
  return state.completedMissions[missionId] == true
end

-- Get story mission by ID
local function getStoryMission(missionId)
  for _, mission in ipairs(storyMissions) do
    if mission.id == missionId then
      return mission
    end
  end
  return nil
end

-- Check if story mission is accessible
local function isMissionAccessible(missionId)
  local mission = getStoryMission(missionId)
  if not mission then return false, "notfound" end

  local playerLevel = getPlayerLevel()

  -- Check level requirement
  if playerLevel < mission.requiredLevel then
    return false, "level", mission.requiredLevel
  end

  -- Check project car requirement
  if mission.requiresProjectCar and not isPlayerInProjectCar() then
    return false, "projectcar"
  end

  return true
end

-- ============================================================================
-- STORY DIALOGUE SYSTEM
-- Mission mechanics are handled by mysummerMissions.lua.
-- Story missions add a narrative layer with timed dialogues.
-- ============================================================================

-- Show story dialogue via chat overlay
local function showStoryDialogue(contactId, messageTable)
  local content = getLocalizedText(messageTable)
  if career_modules_mysummerChat then
    career_modules_mysummerChat.showDialogueMessage(contactId, content)
  end
  log("I", logTag, "Story dialogue: " .. content)
end

-- Check and trigger time-based story dialogues during mission
local function checkStoryDialogues(dtSim)
  if not state.activeMission then return end

  local mission = getStoryMission(state.activeMission.missionId)
  if not mission or not mission.duringDialogues then return end

  -- Update mission elapsed time
  state.missionElapsedTime = (state.missionElapsedTime or 0) + dtSim

  -- Check time-based dialogues
  for i, dialogue in ipairs(mission.duringDialogues) do
    local dialogueKey = state.activeMission.missionId .. "_during_" .. i

    -- Skip already triggered
    if state.drivingDialogueTriggered[dialogueKey] then
      goto continue
    end

    -- Trigger based on elapsed time
    if dialogue.afterSeconds and state.missionElapsedTime >= dialogue.afterSeconds then
      state.drivingDialogueTriggered[dialogueKey] = true
      for _, msg in ipairs(dialogue.messages) do
        showStoryDialogue(mission.contact, msg)
      end
    end

    ::continue::
  end
end

-- ============================================================================
-- STORY MISSION MANAGEMENT
-- ============================================================================

-- Start a story mission
local function selectMission(missionId)
  local accessible, reason, value = isMissionAccessible(missionId)
  if not accessible then
    log("W", logTag, "Mission not accessible: " .. missionId .. " reason: " .. tostring(reason))

    -- Show UI feedback based on failure reason
    if reason == "projectcar" then
      local message = {
        en = "This mission requires the ETK-I project car. Switch vehicles and try again.",
        es = "Esta mision requiere el ETK-I del proyecto. Cambia de vehiculo e intenta de nuevo."
      }
      ui_message.addMessage("mysummer_vehicle_requirement", getLocalizedText(message), 5, "warning", "warning")

    elseif reason == "level" then
      local message = {
        en = "You need more reputation to unlock this mission. (Required Level: " .. tostring(value) .. ")",
        es = "Necesitas mas reputacion para desbloquear esta mision. (Nivel Requerido: " .. tostring(value) .. ")"
      }
      ui_message.addMessage("mysummer_level_requirement", getLocalizedText(message), 5, "warning", "info")
    end

    return { success = false, reason = reason, value = value }
  end

  local mission = getStoryMission(missionId)
  if not mission then
    return { success = false, reason = "notfound" }
  end

  -- Check if there's already an active mission in mysummerMissions
  if career_modules_mysummerMissions then
    local activeMission = career_modules_mysummerMissions.getActiveMission()
    if activeMission then
      log("W", logTag, "Cannot start story mission - there's an active mission")
      return { success = false, reason = "active_mission" }
    end
  end

  -- Show intro dialogue if exists
  if mission.introDialogue and career_modules_mysummerChat then
    local messages = {}
    for _, msg in ipairs(mission.introDialogue) do
      table.insert(messages, getLocalizedText(msg))
    end
    career_modules_mysummerChat.showDialogue(mission.contact, messages)
  end

  -- Show tutorial hint
  if mission.tutorialHint and guihooks then
    guihooks.trigger("toastrMsg", {
      type = "info",
      title = getLocalizedText(mission.name),
      msg = getLocalizedText(mission.tutorialHint),
    })
  end

  -- Set tracking state
  state.activeMission = {
    missionId = missionId,
    name = getLocalizedText(mission.name),
    contact = mission.contact,
    xpReward = mission.xpReward,
    moneyReward = mission.moneyReward,
    chapter = mission.chapter,
    startTime = os.time(),
    missionRef = mission.missionRef,
  }

  -- Reset dialogue state for story dialogues
  state.drivingDialogueTriggered = {}
  state.missionElapsedTime = 0

  saveState()

  -- Start the actual mission from mysummerMissions
  if mission.missionRef and career_modules_mysummerMissions then
    -- Extract contact from missionRef (e.g., "ghost_delivery_1" -> "ghost")
    local refContact = mission.missionRef:match("^(%w+)_")
    if refContact then
      local success = career_modules_mysummerMissions.startMissionFromTemplate(refContact, mission.missionRef, missionId)
      if not success then
        log("E", logTag, "Failed to start mission from template: " .. mission.missionRef)
        state.activeMission = nil
        saveState()
        return { success = false, reason = "mission_start_failed" }
      end
    end
  end

  log("I", logTag, "Story mission selected: " .. missionId)

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerStoryMissionSelected", {
      missionId = missionId,
      name = state.activeMission.name,
      contact = state.activeMission.contact,
    })
  end

  -- Trigger narrative event for mission selection (uses mission ID directly)
  if extensions.career_modules_mysummerNarrative then
    local eventId = missionId .. "_selected"
    extensions.career_modules_mysummerNarrative.queueEvent(eventId, 2)
    log("I", logTag, string.format("Triggering narrative event '%s' for mission selection", eventId))
  end

  return { success = true }
end

-- Cancel active mission
local function cancelMission()
  if not state.activeMission then return end

  log("I", logTag, "Story mission cancelled: " .. state.activeMission.missionId)

  state.activeMission = nil
  state.missionPhase = nil
  state.drivingDialogueTriggered = {}

  saveState()

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end
end

-- Called by mysummerMissions when a story mission completes
local function onMissionCompleted(storyMissionId, success)
  if not state.activeMission or state.activeMission.missionId ~= storyMissionId then
    log("W", logTag, "onMissionCompleted called but no matching active story mission")
    return
  end

  local mission = getStoryMission(storyMissionId)
  if not mission then return end

  if success then
    -- Mark as completed
    state.completedMissions[storyMissionId] = true

    -- Mark phase as completed in narrative system
    local phase = mission.chapter
    if phase and extensions.career_modules_mysummerNarrative then
      local flagName = "phase" .. phase .. "_completed"
      extensions.career_modules_mysummerNarrative.setStoryFlag(flagName, true)
      log("I", logTag, string.format("Phase %d completed (mission: %s)", phase, storyMissionId))
    end

    -- Award story XP (additional to mission rewards)
    local xpGained = mission.xpReward or 0

    if career_modules_playerAttributes and xpGained > 0 then
      career_modules_playerAttributes.addAttributes(
        { ["mysummer-streetracing"] = xpGained },
        { label = "Story Mission: " .. getLocalizedText(mission.name), tags = {"gameplay", "mysummer"} }
      )
    end

    log("I", logTag, "Story contact work completed: " .. storyMissionId .. " XP: " .. xpGained)

    -- Notify narrative system (contact works, not to be confused with BeamNG missions/races)
    if extensions.career_modules_mysummerNarrative then
      extensions.career_modules_mysummerNarrative.onContactWorkCompleted(storyMissionId)
    end

    -- Show completion dialogue (after a short delay to let mission toast show first)
    if mission.completionDialogue and career_modules_mysummerChat then
      local messages = {}
      for _, msg in ipairs(mission.completionDialogue) do
        table.insert(messages, getLocalizedText(msg))
      end
      -- Show dialogue directly - mysummerChat will queue messages
      career_modules_mysummerChat.showDialogue(mission.contact, messages)
    end

    -- Unlock contact if specified
    if mission.unlockContact and career_modules_mysummerCareer then
      if career_modules_mysummerCareer.unlockContact then
        career_modules_mysummerCareer.unlockContact(mission.unlockContact)
        log("I", logTag, "Unlocked contact: " .. mission.unlockContact)
      end
    end

    -- Notify UI
    if guihooks then
      guihooks.trigger("mysummerStoryMissionCompleted", {
        missionId = storyMissionId,
        xpGained = xpGained,
        success = true,
      })
    end
  else
    -- Mission failed
    log("I", logTag, "Story mission failed: " .. storyMissionId)

    -- Notify UI
    if guihooks then
      guihooks.trigger("mysummerStoryMissionCompleted", {
        missionId = storyMissionId,
        success = false,
      })
    end
  end

  -- Clear active mission
  state.activeMission = nil
  state.missionPhase = nil
  state.drivingDialogueTriggered = {}

  saveState()
end

-- Legacy function - kept for backwards compatibility
completeMission = function(missionId)
  onMissionCompleted(missionId, true)
end

-- ============================================================================
-- RACE MANAGEMENT
-- ============================================================================

-- Select a story race: navigate to start, auto-start correct version (normal/REPEAT) on arrival
local function selectRace(raceId)
  local accessible, reason, value = isRaceAccessible(raceId)
  if not accessible then
    log("W", logTag, "Race not accessible: " .. raceId .. " reason: " .. tostring(reason))

    -- Show UI feedback based on failure reason
    if reason == "projectcar" then
      local message = {
        en = "Rally Regional races require the ETK-I project car. Switch vehicles and try again.",
        es = "Las carreras del Rally Regional requieren el ETK-I del proyecto. Cambia de vehiculo e intenta de nuevo."
      }
      ui_message.addMessage("mysummer_vehicle_requirement", getLocalizedText(message), 5, "warning", "warning")

    elseif reason == "requirescovet" then
      local message = {
        en = "Copa Covet races require an Ibishu Covet. You must purchase one from the dealership.",
        es = "Las carreras de la Copa Covet requieren un Ibishu Covet. Debes comprar uno en el concesionario."
      }
      ui_message.addMessage("mysummer_vehicle_requirement", getLocalizedText(message), 5, "warning", "warning")

    elseif reason == "level" then
      local message = {
        en = "You need more reputation to unlock this race. (Required Level: " .. tostring(value) .. ")",
        es = "Necesitas mas reputacion para desbloquear esta carrera. (Nivel Requerido: " .. tostring(value) .. ")"
      }
      ui_message.addMessage("mysummer_level_requirement", getLocalizedText(message), 5, "warning", "info")
    end

    return { success = false, reason = reason, value = value }
  end

  -- Find the race
  local race = nil
  local chapterData = nil
  for _, chapter in ipairs(storyRaces) do
    for _, r in ipairs(chapter.races) do
      if r.id == raceId then
        race = r
        chapterData = chapter
        break
      end
    end
    if race then break end
  end

  if not race then
    return { success = false, reason = "notfound" }
  end

  -- Check if race has been won before - use REPEAT version to avoid duplicate XP rewards
  local raceStatus = state.completedRaces[raceId] or {}
  local missionIdToUse = race.missionId
  local isRepeat = false

  if raceStatus.wins and raceStatus.wins > 0 then
    -- Player has won this race before, use REPEAT version (no skill XP, reduced rewards)
    local repeatMissionId = race.missionId:gsub("%-STREET/", "-STREET-REPEAT/")
    if repeatMissionId ~= race.missionId then
      missionIdToUse = repeatMissionId
      isRepeat = true
      log("I", logTag, "Using REPEAT version: " .. repeatMissionId)
    end
  end

  -- Get mission start position for navigation
  local startPos = getMissionStartPosition(missionIdToUse)
  if not startPos then
    log("E", logTag, "Cannot get start position for race: " .. raceId)
    return { success = false, reason = "noposition" }
  end

  -- Determine phase and race count for this race
  -- Use the race's chapter, NOT the player's current level
  local currentPhase = chapterData.chapter

  -- raceCount is based on how many you've COMPLETED, not the race's position
  -- This allows any race to be completed in any order
  local nextRaceCount = (state.phaseRaceCount[currentPhase] or 0) + 1

  log("I", logTag, string.format("selectRace: %s (Phase %d, will be race #%d, completed so far: %d)",
    raceId, currentPhase, nextRaceCount, state.phaseRaceCount[currentPhase] or 0))

  -- Track which race is selected (for controlling mission start and completion tracking)
  state.activeRace = {
    raceId = raceId,
    missionId = missionIdToUse,
    isRepeat = isRepeat,
    name = getLocalizedText(race.name) .. (isRepeat and " (Repeat)" or ""),
    contact = race.contact,
    xpReward = race.xpReward,
    moneyReward = race.moneyReward,
    chapter = chapterData.chapter,
    phase = currentPhase,  -- Store phase for narrative reset
    raceCount = nextRaceCount,  -- Will be the Nth race when completed (based on progress)
    startPos = { x = startPos.x, y = startPos.y, z = startPos.z },
    waitingForArrival = true, -- Player needs to drive there, then we'll start the correct mission
  }

  saveState()

  -- Show dialogue from contact
  if career_modules_mysummerChat and race.contact ~= "system" then
    local messages = {
      tr("mysummer.storyRaces.goToRace." .. race.contact, "Head to the race location. I'll be watching."),
    }
    career_modules_mysummerChat.showDialogueMessage(race.contact, messages[1])
  end

  -- Navigate to the race start using BeamNG's waypoint system
  -- Don't auto-clear on arrival - we control when to start the mission
  if core_groundMarkers then
    core_groundMarkers.setPath(startPos, { clearPathOnReachingTarget = false })
    log("I", logTag, "Navigation set to race: " .. raceId .. " at " .. tostring(startPos))
  end

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerStoryRaceSelected", {
      raceId = raceId,
      name = state.activeRace.name,
      contact = state.activeRace.contact,
    })
  end

  -- Trigger narrative event for race selection using stored phase/raceCount
  if state.activeRace.phase and state.activeRace.raceCount then
    triggerNarrativeEventByCount(state.activeRace.phase, state.activeRace.raceCount, "selected")
  end

  return { success = true }
end

-- Cancel active race
local function cancelRace()
  if not state.activeRace then return end

  log("I", logTag, "Race cancelled: " .. state.activeRace.raceId)

  -- Get phase info before clearing activeRace
  -- Handle legacy saves where phase/raceCount might not be stored
  local racePhase = state.activeRace.phase or state.activeRace.chapter
  local raceCount = state.activeRace.raceCount

  if not raceCount and racePhase then
    -- Fallback: calculate based on completion count
    raceCount = (state.phaseRaceCount[racePhase] or 0) + 1
    log("W", logTag, string.format("Legacy save: calculated raceCount=%d from phaseRaceCount", raceCount))
  end

  if not racePhase or not raceCount then
    log("W", logTag, string.format("Cannot determine phase/count for race %s, skipping narrative reset",
      state.activeRace.raceId))
    state.activeRace = nil
    saveState()
    if core_groundMarkers then
      core_groundMarkers.setPath(nil)
    end
    return
  end

  log("I", logTag, string.format("cancelRace: Resetting Phase %d, Race #%d", racePhase, raceCount))

  state.activeRace = nil

  -- Reset narrative events so they can trigger again
  resetNarrativeEvents(racePhase, raceCount)

  saveState()

  -- Clear waypoint
  if core_groundMarkers then
    core_groundMarkers.setPath(nil)
  end
end

-- ============================================================================
-- PHASE PROGRESSION
-- ============================================================================

-- Get chapter data by phase number
local function getChapterData(phase)
  for _, chapterData in ipairs(storyRaces) do
    if chapterData.chapter == phase then
      return chapterData
    end
  end
  return nil
end

-- Mapeo de fases a misiones y contactos
local phaseMissionMap = {
  [0] = { missionId = nil, contact = nil },  -- Phase 0 has no mission (tutorial)
  [1] = { missionId = "ch1_mission", contact = "ghost" },
  [2] = { missionId = "ch2_mission", contact = "ghost" },
  [3] = { missionId = "ch3_mission", contact = "ghost" },
  [4] = { missionId = "ch4_mission", contact = "shadow" },
  [5] = { missionId = "ch5_mission", contact = "ghost" },
  [6] = { missionId = "ch6_mission", contact = "ghost" },
}

-- Notify player when all races for a phase are completed
local function notifyPhaseRacesCompleted(phase)
  log("I", logTag, string.format("Phase %d: All races completed!", phase))

  local phaseInfo = phaseMissionMap[phase]
  if not phaseInfo or not phaseInfo.missionId then
    log("I", logTag, "Phase " .. phase .. " has no contact mission")
    return
  end

  -- Send SMS from contact
  if career_modules_mysummerChat then
    local messages = {
      [1] = { -- Ghost ch1_mission
        es = "Has demostrado tu valor en las calles, Miller. Tengo un trabajo que requiere... discreción. Revisa el mapa.",
        en = "You've proven yourself on the streets, Miller. I have a job that requires... discretion. Check the map."
      },
      [2] = { -- Ghost ch2_mission
        es = "Tienes manos firmes. Necesito que muevas algo caliente. La policía estará atenta. ¿Interesado?",
        en = "You've got steady hands. I need you to move something hot. Police will be watching. Interested?"
      },
      [3] = { -- Ghost ch3_mission
        es = "Hay una rata en mi operación. Necesito que la sigas sin que se dé cuenta. Nueva misión disponible.",
        en = "There's a rat in my operation. I need you to tail them without being spotted. New mission available."
      },
      [4] = { -- Shadow ch4_mission
        es = "Alguien está hablando demasiado. Encárgate. No quiero preguntas. Solo resultados.",
        en = "Someone's been talking too much. Handle it. I don't want questions. Just results."
      },
      [5] = { -- Ghost ch5_mission
        es = "El rally se acerca. Pero primero, un último trabajo. Revisa el mapa.",
        en = "The rally is coming. But first, one last job. Check the map."
      },
      [6] = { -- Ghost ch6_mission
        es = "Copa Covet. Es humillante, lo sé. Pero es el único camino de vuelta. Revisa el mapa.",
        en = "Covet Cup. It's humiliating, I know. But it's the only way back. Check the map."
      },
    }

    local message = messages[phase]
    if message then
      career_modules_mysummerChat.sendContactMessage(phaseInfo.contact, message, { silent = false })
      log("I", logTag, string.format("Sent mission notification SMS from %s for phase %d", phaseInfo.contact, phase))
    end
  end

  -- Trigger mission unlock notification in UI
  if guihooks then
    guihooks.trigger("mysummerMissionUnlocked", {
      phase = phase,
      missionId = phaseInfo.missionId,
      contact = phaseInfo.contact,
    })
  end
end

-- ============================================================================
-- RACE COMPLETION
-- ============================================================================

-- Complete a race (called from race manager when race finishes)
local function completeRace(raceId, position, time)
  if not state.activeRace or state.activeRace.raceId ~= raceId then
    -- Check if any story race matches
    local found = false
    for _, chapter in ipairs(storyRaces) do
      for _, race in ipairs(chapter.races) do
        if race.id == raceId then
          found = true
          -- Calculate what race number this will be (based on completion count)
          local nextRaceCount = (state.phaseRaceCount[chapter.chapter] or 0) + 1
          state.activeRace = {
            raceId = raceId,
            xpReward = race.xpReward,
            moneyReward = race.moneyReward,
            contact = race.contact,
            chapter = chapter.chapter,
            phase = chapter.chapter,  -- Add phase for narrative
            raceCount = nextRaceCount,  -- Based on completion count, not position
          }
          break
        end
      end
      if found then break end
    end
    if not found then return end
  end

  local raceData = state.completedRaces[raceId] or { completed = false, bestTime = nil, wins = 0 }

  -- Clear the waiting flag (completeRace has been called)
  state.narrativeEvents.waitingForResult = false

  -- Check if this is first victory (before updating flags)
  local isFirstVictory = position == 1 and not raceData.countedForPhase

  -- Update completion status (only mark as completed if player won)
  if position and position == 1 then
    raceData.completed = true
    raceData.wins = (raceData.wins or 0) + 1

    -- Increment phase race counter (only on first win)
    if not raceData.countedForPhase then
      local phase = state.activeRace.chapter or getCurrentPhase()
      local previousCount = state.phaseRaceCount[phase] or 0
      state.phaseRaceCount[phase] = previousCount + 1
      raceData.countedForPhase = true
      log("I", logTag, string.format("Phase %d race count: %d (won race: %s)", phase, state.phaseRaceCount[phase], raceId))

      -- Check if all races for this phase are completed
      local chapterData = getChapterData(phase)
      if chapterData and state.phaseRaceCount[phase] >= #chapterData.races then
        notifyPhaseRacesCompleted(phase)
      end
    end

    -- Mark that mission ended successfully - race_end listener will trigger when player moves
    state.narrativeEvents.missionEnded = true
    log("I", logTag, "Race WON - race_end listener activated (waiting for player movement)")
  else
    -- Lost or DNF - reset narrative so player can experience it again
    log("I", logTag, "Race NOT won (position: " .. tostring(position) .. ") - resetting narrative")
    local racePhase = state.activeRace.phase or state.activeRace.chapter
    local raceCount = state.activeRace.raceCount

    if not raceCount and racePhase then
      -- Fallback: calculate based on completion count
      raceCount = (state.phaseRaceCount[racePhase] or 0) + 1
    end

    if racePhase and raceCount then
      resetNarrativeEvents(racePhase, raceCount)
    end
  end

  -- Always track best time, even if didn't win
  if time and (not raceData.bestTime or time < raceData.bestTime) then
    raceData.bestTime = time
  end

  state.completedRaces[raceId] = raceData

  -- Rewards are handled by BeamNG's native star system (info.json starRewards)
  -- BeamNG automatically prevents duplicate rewards (only first time unlocking a star)
  local xpGained = state.activeRace.xpReward or 0
  local moneyGained = state.activeRace.moneyReward or 0

  log("I", logTag, "Rewards handled by BeamNG native system (first victory only)")

  log("I", logTag, "Race completed: " .. raceId .. " position: " .. tostring(position))

  -- Narrative events are triggered during the race (start/mid/end) by onUpdate()
  -- No need to call narrative system here

  -- Send completion dialogue
  if career_modules_mysummerChat and state.activeRace.contact ~= "system" then
    local message = (position and position == 1) and
      tr("mysummer.storyRaces.win", "Nice work! You're getting better.") or
      tr("mysummer.storyRaces.finish", "You finished. Keep practicing.")
    career_modules_mysummerChat.sendContactMessage(state.activeRace.contact, message, { silent = true })
  end

  -- Don't clear activeRace if won - the race_end listener needs it
  -- If not won, clear it now (narrative already reset)
  if not (position and position == 1) then
    state.activeRace = nil
  end

  saveState()

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerStoryRaceCompleted", {
      raceId = raceId,
      position = position,
      xpGained = xpGained,
      moneyGained = moneyGained,
    })
  end
end

-- ============================================================================
-- API FOR UI
-- ============================================================================

-- Get all story races with status for UI
local function getStoryRacesForUI()
  local result = {
    currentLevel = getPlayerLevel(),
    isInProjectCar = isPlayerInProjectCar(),
    chapters = setmetatable({}, {__jsontype = "array"}), -- Force JSON array serialization
    activeRace = state.activeRace,
    activeMission = state.activeMission,
  }

  for _, chapterData in ipairs(storyRaces) do
    local chapterResult = {
      chapter = chapterData.chapter,
      chapterName = chapterData.chapterName,
      requiredLevel = chapterData.requiredLevel,
      requiresProjectCar = chapterData.requiresProjectCar,
      isAccessible = result.currentLevel >= chapterData.requiredLevel,
      races = setmetatable({}, {__jsontype = "array"}), -- Force JSON array serialization even when empty
      mission = nil, -- Story mission for this chapter
    }

    -- Add races
    for _, race in ipairs(chapterData.races) do
      local raceStatus = state.completedRaces[race.id] or {}
      local accessible, reason, _ = isRaceAccessible(race.id)

      local hasWon = (raceStatus.wins or 0) > 0
      table.insert(chapterResult.races, {
        id = race.id,
        name = getLocalizedText(race.name),
        description = getLocalizedText(race.description),
        contact = race.contact,
        xpReward = race.xpReward,
        moneyReward = race.moneyReward,
        completed = raceStatus.completed or false,
        wins = raceStatus.wins or 0,
        bestTime = raceStatus.bestTime,
        isAccessible = accessible,
        lockedReason = not accessible and reason or nil,
        willBeRepeat = hasWon, -- True if race has been won before (BeamNG handles reduced rewards automatically)
      })
    end

    -- Add story mission for this chapter
    for _, mission in ipairs(storyMissions) do
      if mission.chapter == chapterData.chapter then
        local accessible, reason = isMissionAccessible(mission.id)
        chapterResult.mission = {
          id = mission.id,
          name = getLocalizedText(mission.name),
          description = getLocalizedText(mission.description),
          contact = mission.contact,
          type = mission.type,
          xpReward = mission.xpReward,
          moneyReward = mission.moneyReward,
          completed = isMissionCompleted(mission.id),
          isAccessible = accessible,
          lockedReason = not accessible and reason or nil,
          requiresProjectCar = mission.requiresProjectCar,
        }
        break
      end
    end

    table.insert(result.chapters, chapterResult)
  end

  return result
end

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

loadState = function()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath) or {}

  state.completedRaces = data.completedRaces or {}
  state.completedMissions = data.completedMissions or {}
  state.currentChapter = data.currentChapter or 0
  state.activeMission = data.activeMission
  state.activeRace = data.activeRace -- Restore active race (may be waiting for arrival)
  state.drivingDialogueTriggered = data.drivingDialogueTriggered or {}
  state.missionElapsedTime = 0 -- Reset on load, will be tracked during gameplay

  -- Restore phase race counts (critical for narrative event reset logic)
  if data.phaseRaceCount then
    for phase, count in pairs(data.phaseRaceCount) do
      state.phaseRaceCount[tonumber(phase)] = count
    end
    log("I", logTag, string.format("Restored phaseRaceCount: Phase0=%d, Phase1=%d",
      state.phaseRaceCount[0] or 0, state.phaseRaceCount[1] or 0))
  end

  -- DISABLED: Restore waypoint (no longer needed since we don't auto-start)
  -- if state.activeRace and state.activeRace.waitingForArrival and state.activeRace.startPos then
  --   local startPos = vec3(state.activeRace.startPos.x, state.activeRace.startPos.y, state.activeRace.startPos.z)
  --   if core_groundMarkers then
  --     core_groundMarkers.setPath(startPos, { clearPathOnReachingTarget = false })
  --     log("I", logTag, "Restored waypoint to race start")
  --   end
  -- end

  log("I", logTag, "Loaded story races state")
end

saveState = function(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  savePath = currentSavePath or savePath
  if not savePath then return end

  local dirPath = savePath .. "/career/mysummer"
  if not FS:directoryExists(dirPath) then
    FS:directoryCreate(dirPath, true)
  end

  local filePath = dirPath .. "/" .. saveFile
  local data = {
    completedRaces = state.completedRaces,
    completedMissions = state.completedMissions,
    currentChapter = state.currentChapter,
    activeMission = state.activeMission,
    activeRace = state.activeRace, -- Save active race (may be waiting for arrival)
    drivingDialogueTriggered = state.drivingDialogueTriggered,
    phaseRaceCount = state.phaseRaceCount, -- Track completed races per phase (for narrative reset)
    -- missionElapsedTime not saved - resets each mission
  }
  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onCareerActive(active)
  if active then
    loadState()
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

local function onExtensionLoaded()
  log("I", logTag, "MySummer Story Races loaded")
end

-- Update hook for story dialogues during missions AND race arrival detection
local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then return end

  -- DISABLED: Auto-start race on arrival
  -- Now the menu just navigates to the race location, player must manually start the mission
  -- if state.activeRace and state.activeRace.waitingForArrival then
  --   local playerPos = getPlayerPosition()
  --   if playerPos and state.activeRace.startPos then
  --     local startPos = vec3(state.activeRace.startPos.x, state.activeRace.startPos.y, state.activeRace.startPos.z)
  --     local distance = playerPos:distance(startPos)
  --
  --     -- Close enough to start race (15 meters)
  --     if distance <= 15 then
  --       log("I", logTag, "Player arrived at race start. Starting: " .. state.activeRace.missionId)
  --
  --       -- Reset narrative events using stored phase/raceCount (for new race instance)
  --       -- Handle legacy saves where phase/raceCount might not be stored
  --       local racePhase = state.activeRace.phase or state.activeRace.chapter
  --       local raceCount = state.activeRace.raceCount
  --
  --       if not raceCount and racePhase then
  --         -- Fallback: calculate based on completion count
  --         raceCount = (state.phaseRaceCount[racePhase] or 0) + 1
  --       end
  --
  --       if racePhase and raceCount then
  --         resetNarrativeEvents(racePhase, raceCount)
  --       end
  --
  --       -- Clear waiting flag
  --       state.activeRace.waitingForArrival = false
  --       saveState()
  --
  --       -- Clear waypoint
  --       if core_groundMarkers then
  --         core_groundMarkers.setPath(nil)
  --       end
  --
  --       -- Start the correct mission version (normal or REPEAT)
  --       local missionToStart = state.activeRace.missionId:gsub("/info.json", "")
  --       if career_modules_mysummerRaceManager then
  --         career_modules_mysummerRaceManager.startNativeMission(missionToStart)
  --       end
  --
  --       -- Notify UI
  --       if guihooks then
  --         guihooks.trigger("mysummerStoryRaceStarted", {
  --           raceId = state.activeRace.raceId,
  --           name = state.activeRace.name,
  --         })
  --       end
  --     end
  --   end
  -- end

  -- Check story dialogues (for active missions)
  if state.activeMission then
    checkStoryDialogues(dtSim)
  end

  -- ========================================================================
  -- NARRATIVE EVENT DETECTION (for active races)
  -- ========================================================================
  if state.activeRace and not state.activeRace.waitingForArrival then
    local currentSpeed = getPlayerSpeed()
    local currentTime = os.time()

    -- Use stored phase and race count from activeRace
    -- Handle legacy saves where phase/raceCount might not be stored
    local currentPhase = state.activeRace.phase or state.activeRace.chapter
    local currentRaceCount = state.activeRace.raceCount

    if not currentRaceCount then
      if currentPhase then
        -- Fallback: calculate based on completion count
        currentRaceCount = (state.phaseRaceCount[currentPhase] or 0) + 1
      else
        -- Cannot determine, skip narrative triggers
        return
      end
    end

    -- RACE_START: Player starts moving after spawn
    if not state.narrativeEvents.raceStartTriggered and
       currentSpeed > PLAYER_SPEED_THRESHOLD and
       not state.narrativeEvents.playerMovedInRace then

      state.narrativeEvents.playerMovedInRace = true
      state.narrativeEvents.raceStartTriggered = true
      state.narrativeEvents.raceStartTime = currentTime

      triggerNarrativeEventByCount(currentPhase, currentRaceCount, "start")
      log("I", logTag, string.format("race_start: Player started moving (speed: %.1f m/s) - Phase %d, Race #%d",
        currentSpeed, currentPhase, currentRaceCount))
    end

    -- RACE_MID: 60 seconds after race_start (only if mission hasn't ended yet)
    if state.narrativeEvents.playerMovedInRace and
       not state.narrativeEvents.raceMidTriggered and
       not state.narrativeEvents.missionEnded and
       state.narrativeEvents.raceStartTime > 0 then

      local elapsed = currentTime - state.narrativeEvents.raceStartTime
      if elapsed >= RACE_MID_DELAY then
        state.narrativeEvents.raceMidTriggered = true

        triggerNarrativeEventByCount(currentPhase, currentRaceCount, "mid")
        log("I", logTag, string.format("race_mid: %d seconds elapsed - Phase %d, Race #%d",
          elapsed, currentPhase, currentRaceCount))
      end
    end

    -- RACE_END LISTENER: Activated by completeRace(win), triggers when back in freeroam
    -- Check if mission is no longer active (player spawned back in freeroam)
    local missionActive = gameplay_missions_missionManager and
                          gameplay_missions_missionManager.getForegroundMissionId() ~= nil

    if state.narrativeEvents.missionEnded and
       not state.narrativeEvents.raceEndTriggered and
       not missionActive then

      state.narrativeEvents.raceEndTriggered = true

      triggerNarrativeEventByCount(currentPhase, currentRaceCount, "end")
      log("I", logTag, string.format("race_end: Player returned to freeroam after winning - Phase %d, Race #%d",
        currentPhase, currentRaceCount))

      -- Clear activeRace now that race_end has been triggered
      state.activeRace = nil
      saveState()
    end

    -- TIMEOUT DETECTOR: If mission ended but completeRace not called after 2 seconds → cancelled/quit
    if state.narrativeEvents.waitingForResult and
       state.narrativeEvents.missionEndTime > 0 then

      local elapsed = currentTime - state.narrativeEvents.missionEndTime
      if elapsed >= 2 then
        log("I", logTag, "Race quit/cancelled detected (completeRace not called) - resetting narrative")
        if currentPhase and currentRaceCount then
          resetNarrativeEvents(currentPhase, currentRaceCount)
        end
        state.activeRace = nil
        saveState()
      end
    end
  end
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

-- Race API
M.getStoryRacesForUI = getStoryRacesForUI
M.selectRace = selectRace
M.cancelRace = cancelRace
M.completeRace = completeRace
M.findRaceIdByMission = findRaceIdByMission
M.isRaceAccessible = isRaceAccessible
M.isRaceCompleted = isRaceCompleted
M.getPlayerLevel = getPlayerLevel
M.isPlayerInProjectCar = isPlayerInProjectCar

-- Mission API
M.selectMission = selectMission
M.cancelMission = cancelMission
M.completeMission = completeMission
M.onMissionCompleted = onMissionCompleted -- Called by mysummerMissions when mission ends
M.isMissionAccessible = isMissionAccessible
M.isMissionCompleted = isMissionCompleted
M.getStoryMission = getStoryMission

-- Lifecycle
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onExtensionLoaded = onExtensionLoaded
M.onUpdate = onUpdate -- For story dialogues during missions

-- Mission lifecycle callback (called when any mission state changes)
M.onAnyMissionChanged = function(state_change, mission)
  if not mission or not mission.id then return end

  local missionId = mission.id

  -- Filter: only process actual race missions, not levels or other stuff
  if not missionId:find("/aiRace/") then
    return
  end

  if state_change == "started" then
    log("I", logTag, "onAnyMissionChanged: Race started - " .. tostring(missionId))

    -- Handle race started from map (without going through selectRace menu)
    if not state.activeRace then
      log("I", logTag, "No activeRace state found, attempting auto-detection...")
      -- Try to find this race in our story races
      local raceId = findRaceIdByMission(missionId)
      if raceId then
        log("I", logTag, "Race started from map (not from menu): " .. raceId)

        -- Find race data
        local race = nil
        local chapterData = nil
        for _, chapter in ipairs(storyRaces) do
          for _, r in ipairs(chapter.races) do
            if r.id == raceId then
              race = r
              chapterData = chapter
              break
            end
          end
          if race then break end
        end

        if race and chapterData then
          -- Create activeRace state automatically
          local currentPhase = chapterData.chapter
          local nextRaceCount = (state.phaseRaceCount[currentPhase] or 0) + 1

          state.activeRace = {
            raceId = raceId,
            missionId = missionId,
            isRepeat = false,
            name = getLocalizedText(race.name),
            contact = race.contact,
            xpReward = race.xpReward,
            moneyReward = race.moneyReward,
            chapter = chapterData.chapter,
            phase = currentPhase,
            raceCount = nextRaceCount,
            waitingForArrival = false,  -- Already started, not waiting
          }

          log("I", logTag, string.format("Auto-created activeRace state: Phase %d, Race #%d",
            currentPhase, nextRaceCount))
          saveState()
        end
      end
    end

    -- Reset narrative events when a race mission starts/restarts
    if state.activeRace and state.activeRace.missionId == missionId then
      log("I", logTag, "Race mission started/restarted: " .. missionId)

      -- Mark that player has arrived and started the race (narrative system needs this)
      state.activeRace.waitingForArrival = false
      saveState()

      -- Use stored phase and race count from activeRace
      -- Handle legacy saves where phase/raceCount might not be stored
      local racePhase = state.activeRace.phase or state.activeRace.chapter
      local raceCount = state.activeRace.raceCount

      if not raceCount and racePhase then
        -- Fallback: calculate based on completion count
        raceCount = (state.phaseRaceCount[racePhase] or 0) + 1
      end

      -- Only reset narrative if this race hasn't been completed before
      -- This allows events to replay only for cancelled/failed races, not completed ones
      if racePhase and raceCount then
        local completedCount = state.phaseRaceCount[racePhase] or 0
        if raceCount > completedCount then
          -- This is a new race (not yet completed) - allow narrative events
          log("D", logTag, string.format("New race (Phase %d, Race #%d) - narrative events ready", racePhase, raceCount))
          resetNarrativeEvents(racePhase, raceCount)
        else
          -- This race was already completed - don't reset narrative
          log("D", logTag, string.format("Already completed race (Phase %d, Race #%d) - narrative events preserved", racePhase, raceCount))
        end
      end

      -- Trigger "selected" event now that race has actually started
      if racePhase and raceCount then
        triggerNarrativeEventByCount(racePhase, raceCount, "selected")
      end
    end

  elseif state_change == "stopped" then
    log("I", logTag, "onAnyMissionChanged: Race stopped - " .. tostring(missionId))

    -- Mission ended - this is the event that triggers the "wait for movement" listener
    if state.activeRace and state.activeRace.missionId == missionId then
      -- Mark that mission ended - completeRace() will be called shortly with the result
      state.narrativeEvents.missionEndTime = os.time()
      state.narrativeEvents.waitingForResult = true  -- Flag to indicate we're waiting for completeRace
      log("I", logTag, "Race mission ended: " .. missionId .. " (listener activated, waiting for result)")
    end
  end
end

return M
