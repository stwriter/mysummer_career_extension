-- This Source Code Form is subject to the terms of the bCDDL, v. 1.1.
-- If a copy of the bCDDL was not distributed with this file, You can obtain one at http://beamng.com/bCDDL-1.1.txt

local M = {}
M.moduleName = "career_modules_mysummerCareer"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerCore",
  -- Note: mysummerParts and mysummerChecklist are checked at runtime to avoid circular deps
  "career_modules_inventory",
  "career_modules_garageManager",
  "career_modules_vehicleShopping",
}

local logTag = "mysummerCareer"
local cachedParkingSites = nil  -- Cache for parking sites
local state  -- Forward declaration (initialized later)
local saveState  -- Forward declaration (defined later)

-- Helper function to check if a table contains a value
local function tableContains(tbl, value)
  if not tbl then return false end
  for _, v in ipairs(tbl) do
    if v == value then return true end
  end
  return false
end

-- ============================================================================
-- PHASE DEFINITIONS
-- ============================================================================

local phaseDefinitions = {
  [1] = {
    name = { en = "Street Rookie", es = "Novato Callejero" },
    description = { en = "Prove yourself in basic street races", es = "Demuestra tu valor en carreras callejeras basicas" },
    requiredRaces = { "street_circuit_01", "industrial_loop_01" },
    requiredWins = 2,
    reputationReward = 500,
    partRewards = {},
    cashReward = 2000,
    storyText = {
      intro = {
        en = "The Miramar is yours now. Time to see what you're made of.",
        es = "El Miramar es tuyo ahora. Es hora de ver de que pasta estas hecho.",
      },
      completion = {
        en = "Not bad for a beginner. People are starting to notice you.",
        es = "Nada mal para ser un novato. La gente empieza a fijarse en ti.",
      },
    },
  },
  [2] = {
    name = { en = "Rally Initiate", es = "Iniciado en Rally" },
    description = { en = "Take on dirt and gravel courses", es = "Enfrentate a circuitos de tierra y grava" },
    prerequisites = { phase = 1, reputationLevel = 5 },
    requiredRaces = { "rally_forest_01", "rally_mountain_01", "rally_stage_01" },
    requiredWins = 2,
    reputationReward = 750,
    partRewards = {},
    cashReward = 3500,
    storyText = {
      intro = {
        en = "Asphalt is easy. Let's see how you handle when the ground fights back.",
        es = "El asfalto es facil. Veamos que tal se te da cuando el suelo te devuelve los golpes.",
      },
      completion = {
        en = "You're not just a street racer anymore. The dirt suits you.",
        es = "Ya no eres solo un corredor callejero. La tierra te sienta bien.",
      },
    },
  },
  [3] = {
    name = { en = "Circuit Contender", es = "Aspirante a Circuito" },
    description = { en = "Master technical circuit racing", es = "Domina las carreras tecnicas en circuito" },
    prerequisites = { phase = 2, reputationLevel = 15 },
    requiredRaces = { "circuit_technical_01", "circuit_fast_01" },
    requiredWins = 3,
    reputationReward = 1000,
    partRewards = {},
    cashReward = 5000,
    storyText = {
      intro = {
        en = "Time for the real tracks. No more backroads - this is where skill matters.",
        es = "Es hora de los circuitos de verdad. Se acabaron los caminos secundarios - aqui es donde importa la habilidad.",
      },
      completion = {
        en = "You're getting faster. But there's still a long road ahead.",
        es = "Cada vez eres mas rapido. Pero aun queda mucho camino por delante.",
      },
    },
  },
  [4] = {
    name = { en = "Performance Specialist", es = "Especialista en Rendimiento" },
    description = { en = "Win races with specific performance requirements", es = "Gana carreras con requisitos de rendimiento especificos" },
    prerequisites = { phase = 3, reputationLevel = 25 },
    requiredRaces = { "performance_challenge_01", "performance_challenge_02" },
    requiredWins = 4,
    reputationReward = 1500,
    partRewards = {},
    cashReward = 7500,
    storyText = {
      intro = {
        en = "Your driving is solid. Now let's see if you can build a car to match.",
        es = "Tu conduccion es solida. Veamos si puedes preparar un coche a la altura.",
      },
      completion = {
        en = "You understand what makes a car fast. That's a rare gift.",
        es = "Entiendes lo que hace rapido a un coche. Eso es un don.",
      },
    },
  },
  [5] = {
    name = { en = "Underground Legend", es = "Leyenda del Underground" },
    description = { en = "Dominate the underground racing scene", es = "Domina la escena de carreras clandestinas" },
    prerequisites = { phase = 4, reputationLevel = 40 },
    requiredRaces = { "underground_01", "underground_02", "underground_03" },
    requiredWins = 5,
    reputationReward = 2000,
    partRewards = {},
    cashReward = 10000,
    storyText = {
      intro = {
        en = "The underground calls. No rules, no safety nets. This is where legends are born.",
        es = "El underground te llama. Sin reglas, sin red de seguridad. Aquí es donde nacen las leyendas.",
      },
      completion = {
        en = "They whisper your name in every garage and back alley. You've made it.",
        es = "Susurran tu nombre en cada garaje y callejón. Lo has conseguido.",
      },
    },
  },
  [6] = {
    name = { en = "Endurance Racer", es = "Corredor de Resistencia" },
    description = { en = "Prove your consistency over long races", es = "Demuestra tu consistencia en carreras largas" },
    prerequisites = { phase = 5, reputationLevel = 50 },
    requiredRaces = { "endurance_01", "endurance_02" },
    requiredWins = 2,
    reputationReward = 2500,
    partRewards = {},
    cashReward = 15000,
    storyText = {
      intro = {
        en = "Speed is one thing. Maintaining it for hours is another.",
        es = "La velocidad es una cosa. Mantenerla durante horas es otra muy distinta.",
      },
      completion = {
        en = "Your consistency is unmatched. The car is an extension of yourself now.",
        es = "Tu consistencia es inigualable. El coche ya es una extension de ti mismo.",
      },
    },
  },
  [7] = {
    name = { en = "International Challenge", es = "Desafio Internacional" },
    description = { en = "Compete against international drivers", es = "Compite contra pilotos internacionales" },
    prerequisites = { phase = 6, reputationLevel = 60 },
    requiredRaces = { "international_01", "international_02", "international_03" },
    requiredWins = 5,
    reputationReward = 3000,
    partRewards = {},
    cashReward = 20000,
    storyText = {
      intro = {
        en = "Word has spread beyond borders. They're flying in just to race you.",
        es = "Tu fama ha cruzado fronteras. Vienen en avion solo para correr contra ti.",
      },
      completion = {
        en = "You've beaten the best from around the world. 'Impressive' doesn't cover it.",
        es = "Has vencido a los mejores del mundo. 'Impresionante' se queda corto.",
      },
    },
  },
  [8] = {
    name = { en = "Championship Qualifier", es = "Clasificatorio del Campeonato" },
    description = { en = "Qualify for the final championship", es = "Clasificate para el campeonato final" },
    prerequisites = { phase = 7, reputationLevel = 70 },
    requiredRaces = { "qualifier_01", "qualifier_02", "qualifier_03" },
    requiredWins = 6,
    reputationReward = 4000,
    partRewards = {},
    cashReward = 30000,
    storyText = {
      intro = {
        en = "This is it. Win these qualifiers and you're in the championship.",
        es = "Este es el momento. Gana estos clasificatorios y entraras en el campeonato.",
      },
      completion = {
        en = "You're in. The championship awaits.",
        es = "Estas dentro. El campeonato te espera.",
      },
    },
  },
  [9] = {
    name = { en = "Semi-Finals", es = "Semifinales" },
    description = { en = "The penultimate challenge", es = "El penultimo desafio" },
    prerequisites = { phase = 8, reputationLevel = 80 },
    requiredRaces = { "semifinal_01", "semifinal_02" },
    requiredWins = 2,
    reputationReward = 5000,
    partRewards = {},
    cashReward = 50000,
    storyText = {
      intro = {
        en = "Two races stand between you and the final. Everything you've built leads to this.",
        es = "Dos carreras te separan de la final. Todo lo que has construido te ha traido hasta aqui.",
      },
      completion = {
        en = "One race left. One chance at greatness.",
        es = "Una carrera mas. Una oportunidad para la gloria.",
      },
    },
  },
  [10] = {
    name = { en = "The Big One", es = "The Big One" },
    description = { en = "The legendary race your grandfather never got to run", es = "La carrera legendaria que tu abuelo nunca pudo correr" },
    prerequisites = {
      phase = 9,
      reputationLevel = 90,
      checklistCompletion = 90,
    },
    requiredRaces = { "championship_final" },
    requiredWins = 1,
    reputationReward = 10000,
    partRewards = {},
    cashReward = 100000,
    unlocksFreePlay = true,
    storyText = {
      intro = {
        en = "This is it. The Big One. The race your grandfather dreamed of. Win this, and the legend is complete.",
        es = "Es el momento. The Big One. La carrera con la que tu abuelo siempre soñó. Gánala, y la leyenda estará completa.",
      },
      completion = {
        en = "CHAMPION. You did it - for yourself, and for him. The car, the build, the journey... it was all worth it. He would be proud.",
        es = "CAMPEON. Lo has conseguido - por ti, y por el. El coche, la preparacion, el viaje... todo ha merecido la pena. Estaria orgulloso.",
      },
    },
  },
}

-- ============================================================================
-- LOCALIZATION HELPERS
-- ============================================================================

-- Get current language (returns "es" for Spanish, "en" for everything else)
local function getCurrentLang()
  local lang = settings.getValue("uiLanguage") or "en-US"
  if lang:find("^es") or lang:find("^spanish") then
    return "es"
  end
  return "en"
end

-- Get localized text from a { en = "...", es = "..." } table
local function getLocalizedText(textTable)
  if type(textTable) == "string" then
    return textTable  -- Already a plain string
  end
  if type(textTable) ~= "table" then
    return ""
  end
  local lang = getCurrentLang()
  return textTable[lang] or textTable.en or ""
end

local function getLocalizedTextList(textList)
  if type(textList) == "string" then
    return { textList }
  end
  if type(textList) ~= "table" then
    return {}
  end
  if textList.en or textList.es then
    return { getLocalizedText(textList) }
  end
  local resolved = {}
  for _, entry in ipairs(textList) do
    if type(entry) == "table" and entry.content then
      table.insert(resolved, {
        text = getLocalizedText(entry.content),
        emotion = entry.emotion,
      })
    else
      table.insert(resolved, getLocalizedText(entry))
    end
  end
  return resolved
end

-- ============================================================================
-- STORY SCENE SYSTEM
-- ============================================================================

local sceneDefinitions = {
  chapter1_first_race = {
    id = "chapter1_first_race",
    scenes = {
      {
        id = "c1_first_rook",
        contactId = "rook",
        name = { en = "Rook", es = "Rook" },
        emotion = "content",
        text = {
          {
            content = { en = "You are not just the new kid.", es = "No eres solo el nuevo." },
            emotion = "content",
          },
          {
            content = {
              en = "You drive like you already know the exits, like you have been here before.",
              es = "Conduces como si ya conocieras las salidas, como si ya hubieras estado aqui antes.",
            },
            emotion = "content",
          },
          {
            content = {
              en = "That is rare.",
              es = "Eso es raro.",
            },
            emotion = "content",
          },
          {
            content = {
              en = "Most chase noise; you chase the line, and the line keeps you alive.",
              es = "La mayoria persigue ruido; tu persigues la linea, y la linea te mantiene vivo.",
            },
            emotion = "sad",
          },
          {
            content = { en = "Keep the car honest and keep yourself honest, or the street will do it for you.", es = "Manten el coche honesto y mantente honesto, o la calle lo hara por ti." },
            emotion = "standard",
          },
          {
            content = { en = "Do not waste it.", es = "No lo desperdicies." },
            emotion = "content",
          },
        },
      },
      {
        id = "c1_first_nova",
        contactId = "nova",
        name = { en = "Nova", es = "Nova" },
        emotion = "content",
        text = {
          {
            content = { en = "Good start.", es = "Buen arranque." },
            emotion = "content",
          },
          {
            content = {
              en = "Keep this pace and people will say your name without looking, like it has always been there.",
              es = "Si mantienes el ritmo, la gente dira tu nombre sin mirarte, como si siempre hubiera estado ahi.",
            },
            emotion = "content",
          },
          {
            content = { en = "You are not invisible anymore.", es = "Ya no eres invisible." },
            emotion = "happy",
          },
          {
            content = {
              en = "So does money, and money changes the rules faster than any race.",
              es = "Y el dinero tambien, y el dinero cambia las reglas mas rapido que cualquier carrera.",
            },
            emotion = "standard",
          },
          {
            content = { en = "We can go further if you want it, but it will not be polite.", es = "Podemos ir mas lejos si lo quieres, pero no sera educado." },
            emotion = "content",
          },
          {
            content = { en = "Do not slow down now.", es = "No bajes el ritmo ahora." },
            emotion = "content",
          },
        },
      },
    },
  },
  chapter1_end = {
    id = "chapter1_end",
    scenes = {
      {
        id = "c1_end_nova",
        contactId = "nova",
        name = { en = "Nova", es = "Nova" },
        emotion = "standard",
        text = {
          {
            content = { en = "This is not a game anymore.", es = "Esto ya no es un juego." },
            emotion = "standard",
          },
          {
            content = { en = "Hesitation is loud; it tells everyone you are waiting to be saved.", es = "La duda se escucha; le dice a todos que esperas que te salven." },
            emotion = "angry",
          },
          {
            content = { en = "Risk means moving before the door closes, while you still have both hands on it.", es = "Arriesgar es moverte antes de que la puerta cierre, mientras aun la tienes en las manos." },
            emotion = "content",
          },
          {
            content = { en = "Say the word, and we go.", es = "Di la palabra y arrancamos." },
            emotion = "content",
          },
          {
            content = { en = "Not today. Not later. Now.", es = "No hoy. No despues. Ahora." },
            emotion = "angry",
          },
          {
            content = { en = "Choose.", es = "Elige." },
            emotion = "standard",
          },
        },
        choices = {
          { value = "push", label = { en = "Push harder", es = "Aceleremos esto" } },
          { value = "steady", label = { en = "Step by step", es = "Paso a paso" } },
        },
      },
      {
        id = "c1_end_rook",
        contactId = "rook",
        name = { en = "Rook", es = "Rook" },
        emotion = "sad",
        text = {
          {
            content = { en = "Do not get cocky.", es = "No te confies." },
            emotion = "sad",
          },
          {
            content = { en = "The circuit is watching, and it bites.", es = "El circuito te mira, y cuando muerde, no avisa." },
            emotion = "sad",
          },
          {
            content = { en = "I have seen nights go bad in one corner, one mistake, one glance at the wrong time.", es = "He visto noches romperse en una sola curva, un error, un vistazo en el peor momento." },
            emotion = "sad",
          },
          {
            content = { en = "Keep your head colder than the asphalt, even when they cheer your name.", es = "Manten la cabeza mas fria que el asfalto, incluso cuando griten tu nombre." },
            emotion = "standard",
          },
          {
            content = { en = "Breathe.", es = "Respira." },
            emotion = "content",
          },
          {
            content = { en = "Then keep going.", es = "Y sigue." },
            emotion = "content",
          },
        },
      },
      {
        id = "c1_end_ghost",
        contactId = "ghost",
        name = { en = "Ghost", es = "Ghost" },
        emotion = "standard",
        text = {
          {
            content = { en = "I saw you.", es = "Te vi." },
            emotion = "standard",
          },
          {
            content = { en = "It was not luck.", es = "No fue suerte." },
            emotion = "standard",
          },
          {
            content = { en = "Luck dies early around here, and careless drivers die with it.", es = "La suerte muere temprano por aqui, y los imprudentes mueren con ella." },
            emotion = "sad",
          },
          {
            content = { en = "Every move leaves a trail, and someone always follows it.", es = "Cada movimiento deja un rastro, y alguien siempre lo sigue." },
            emotion = "standard",
          },
          {
            content = { en = "Do not get comfortable.", es = "No te acomodes." },
            emotion = "angry",
          },
          {
            content = { en = "You will be offered a shortcut; remember this night when it happens.", es = "Te van a ofrecer un atajo; recuerda esta noche cuando ocurra." },
            emotion = "standard",
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 0: Rook & Nova Introduction (after Race 1)
  -- ========================================================================
  rook_nova_introduction = {
    id = "rook_nova_introduction",
    scenes = {
      {
        id = "intro_ghost_presents",
        contactId = "ghost",
        name = { en = "Ghost", es = "Ghost" },
        emotion = "standard",
        text = {
          { content = { en = "One more thing, Miller.", es = "Una cosa mas, Miller." }, emotion = "standard" },
          { content = { en = "There are two racers you should know. They are a couple and they have been racing these circuits for a while.", es = "Hay dos corredores que deberias conocer. Son pareja y llevan tiempo corriendo en estos circuitos." }, emotion = "standard" },
          { content = { en = "Rook is technical, cautious. Nova is the complete opposite: aggressive, hungry.", es = "Rook es tecnico, prudente. Nova es todo lo contrario: agresiva, hambrienta." }, emotion = "content" },
          { content = { en = "They both have talent. They will both be watching you.", es = "Los dos tienen talento. Los dos te estaran mirando." }, emotion = "standard" },
        },
      },
      {
        id = "intro_rook",
        contactId = "rook",
        name = { en = "Rook", es = "Rook" },
        emotion = "content",
        text = {
          { content = { en = "Hi, Miller. Ghost told me about you.", es = "Hola, Miller. Ghost me ha hablado de ti." }, emotion = "content" },
          { content = { en = "Be careful out there. This is not a stroll. The track does not forgive mistakes and old cars are unpredictable.", es = "Ten cuidado ahi fuera. Esto no es un paseo. La pista no perdona errores y los coches viejos son imprevisibles." }, emotion = "standard" },
          { content = { en = "If you need advice on mechanics, you know where to find me.", es = "Si necesitas consejo sobre mecanica, ya sabes donde encontrarme." }, emotion = "content" },
        },
      },
      {
        id = "intro_nova",
        contactId = "nova",
        name = { en = "Nova", es = "Nova" },
        emotion = "happy",
        text = {
          { content = { en = "So you are Miller's grandson.", es = "Asi que tu eres el nieto de Miller." }, emotion = "happy" },
          { content = { en = "I like how you handle that junker. You have got potential.", es = "Me gusta como llevas ese cacharro. Tienes potencial." }, emotion = "content" },
          { content = { en = "Do not let Rook scare you with his safety talks. Races are won by taking risks, not reading manuals.", es = "No dejes que Rook te asuste con sus charlas de seguridad. La carrera se gana arriesgando, no leyendo manuales." }, emotion = "happy" },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 0: "El Legado del Mecanico" - Ghost Contact Mission
  -- ========================================================================
  ghost_legacy_mechanic = {
    id = "ghost_legacy_mechanic",
    scenes = {
      {
        id = "ghost_legacy",
        contactId = "ghost",
        name = { en = "Ghost", es = "Ghost" },
        emotion = "standard",
        text = {
          { content = { en = "I have seen enough.", es = "He visto suficiente." }, emotion = "standard" },
          { content = { en = "You drive with the same regret as Old Miller, but with more hunger.", es = "Conduces con el mismo arrepentimiento que el Viejo Miller, pero con mas hambre." }, emotion = "content" },
          { content = { en = "That ETK-I you have in the garage... your grandfather designed it for Viper.", es = "Ese ETK-I que tienes en el garaje... tu abuelo lo diseno para Viper." }, emotion = "standard" },
          { content = { en = "But when Muscle's father died in that accident, the old man broke. He stopped racing before he even started.", es = "Pero cuando el padre de Muscle murio en aquel accidente, el viejo se rompio. Dejo de correr antes de empezar." }, emotion = "sad" },
        },
        choices = {
          {
            value = "loyalty",
            label = { en = "My grandfather built cars for Viper?", es = "Mi abuelo preparaba coches para Viper?" },
          },
          {
            value = "ambition",
            label = { en = "I am not my grandfather. I will not brake.", es = "No soy mi abuelo. Yo no voy a frenar." },
          },
        },
      },
      -- Response scene based on choice (shown after choice)
      {
        id = "ghost_legacy_response_loyalty",
        contactId = "ghost",
        name = { en = "Ghost", es = "Ghost" },
        emotion = "content",
        text = {
          { content = { en = "He was Viper's right hand. The best.", es = "Era su mano derecha. El mejor." }, emotion = "content" },
          { content = { en = "If you want to finish that car, you are going to need parts they do not sell in normal shops.", es = "Si quieres terminar ese coche, vas a necesitar piezas que no venden en las tiendas normales." }, emotion = "standard" },
          { content = { en = "I can get them, if you prove you will not chicken out like he did.", es = "Yo puedo conseguirlas, si me demuestras que no te vas a acobardar como el." }, emotion = "standard" },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 1: "Hardware y Almas" - Techie Contact Mission
  -- ========================================================================
  techie_hardware_souls = {
    id = "techie_hardware_souls",
    scenes = {
      {
        id = "techie_intro",
        contactId = "techie",
        name = { en = "Techie", es = "Techie" },
        emotion = "standard",
        text = {
          { content = { en = "Miller. The grandson of the man who tuned engines by ear. How archaic.", es = "Miller. El nieto del hombre que afinaba motores de oido. Que arcaico." }, emotion = "standard" },
          { content = { en = "I have been monitoring your radio frequencies and the telemetry data from your last races.", es = "He estado monitorizando tus frecuencias de radio y los datos de telemetria de tus ultimas carreras." }, emotion = "standard" },
          { content = { en = "You have a line efficiency of 84 percent, not bad for someone who still uses manual gears.", es = "Tienes una eficiencia de trazada del 84 por ciento, nada mal para alguien que aun usa cambios manuales." }, emotion = "content" },
          { content = { en = "Rook says you can be trusted, and Nova... well, Nova says you are the only one here with some ambition.", es = "Rook dice que eres de confianza, y Nova... bueno, Nova dice que eres el unico aqui con algo de ambicion." }, emotion = "standard" },
        },
        choices = {
          {
            value = "loyalty",
            label = { en = "Rook is a good racer, he knows what he is doing.", es = "Rook es un buen piloto, sabe lo que hace." },
          },
          {
            value = "ambition",
            label = { en = "Nova is right, we need to aim higher than this town.", es = "Nova tiene razon, hay que aspirar a mas que a este pueblo." },
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 2: "Viejas Heridas" - Muscle Contact Mission
  -- ========================================================================
  muscle_old_wounds = {
    id = "muscle_old_wounds",
    scenes = {
      {
        id = "muscle_intro",
        contactId = "muscle",
        name = { en = "Muscle", es = "Muscle" },
        emotion = "standard",
        text = {
          { content = { en = "So this is the famous grandson.", es = "Asi que este es el famoso nieto." }, emotion = "standard" },
          { content = { en = "Ghost says you have talent, but I only see a kid with a surname too big for his shoulders.", es = "Ghost dice que tienes talento, pero yo solo veo a un chico con un apellido demasiado grande para sus hombros." }, emotion = "standard" },
          { content = { en = "My father died on a night like this, in a car that was not your grandfather's. But he sank with the ship anyway.", es = "Mi padre murio en una noche como esta, en un coche que no era de tu abuelo. Pero el se hundio con el barco de todas formas." }, emotion = "sad" },
          { content = { en = "Miller was the best mechanic in the world, but a coward behind the wheel.", es = "Miller era el mejor mecanico del mundo, pero un cobarde detras del volante." }, emotion = "angry" },
        },
        choices = {
          {
            value = "loyalty",
            label = { en = "My grandfather was not a coward, he just had heart.", es = "Mi abuelo no fue un cobarde, solo tenia corazon." },
          },
          {
            value = "ambition",
            label = { en = "I did not come to talk about him. I came for parts.", es = "No he venido a hablar de el. He venido a por piezas." },
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 3: "El Umbral del Mercado Negro" - Shadow Contact Mission
  -- ========================================================================
  shadow_black_market = {
    id = "shadow_black_market",
    scenes = {
      {
        id = "shadow_intro",
        contactId = "shadow",
        name = { en = "Shadow", es = "Shadow" },
        emotion = "standard",
        text = {
          { content = { en = "So this is the famous grandson.", es = "Asi que este es el famoso nieto." }, emotion = "standard" },
          { content = { en = "Nova says you are tired of Muscle's scrapyard parts and Techie's boring graphs.", es = "Nova dice que estas cansado de las piezas de desguace de Muscle y de los graficos aburridos de Techie." }, emotion = "standard" },
          { content = { en = "My merchandise is not legal, nor pretty, but it will make your ETK-I fly.", es = "Mi mercancia no es legal, ni bonita, pero hara que tu ETK-I vuele." }, emotion = "content" },
          { content = { en = "Old man Miller hated me because my parts do not understand 'safety', only results.", es = "Miller padre me odiaba porque mis piezas no entienden de 'seguridad', solo de resultados." }, emotion = "standard" },
          { content = { en = "Will you follow grandfather's rules or will you win?", es = "Vas a seguir las reglas del abuelo o vas a ganar?" }, emotion = "angry" },
        },
        choices = {
          {
            value = "caution",
            label = { en = "I do not want trouble with police. Legal parts only.", es = "No quiero problemas con la policia. Solo piezas legales." },
          },
          {
            value = "ambition",
            label = { en = "Give me the fastest you have. I will handle the consequences.", es = "Dame lo mas rapido que tengas. Yo me encargo de las consecuencias." },
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 4: "El Precio de la Ambicion" - Debt Mission
  -- ========================================================================
  debt_price_of_ambition = {
    id = "debt_price_of_ambition",
    scenes = {
      {
        id = "ghost_warns_debt",
        contactId = "ghost",
        name = { en = "Ghost", es = "Ghost" },
        emotion = "angry",
        text = {
          { content = { en = "I warned you, Miller.", es = "Te lo adverti, Miller." }, emotion = "angry" },
          { content = { en = "Playing with Shadow is playing with fire.", es = "Jugar con Shadow es jugar con fuego." }, emotion = "angry" },
          { content = { en = "Now Rook is out of the team and Nova has a debt she cannot pay with neighborhood victories.", es = "Ahora Rook esta fuera del equipo y Nova tiene una deuda que no puede pagar con victorias de barrio." }, emotion = "sad" },
          { content = { en = "Shadow wants you to do a 'special delivery' to settle the experimental parts account.", es = "Shadow quiere que hagais un 'encargo' especial para saldar la cuenta de las piezas experimentales." }, emotion = "standard" },
        },
      },
      {
        id = "shadow_debt_offer",
        contactId = "shadow",
        name = { en = "Shadow", es = "Shadow" },
        emotion = "standard",
        text = {
          { content = { en = "Do not be dramatic, Ghost. It is just a quick transport.", es = "No seas dramatico, Ghost. Solo es un transporte rapido." }, emotion = "standard" },
          { content = { en = "Miller, you will drive a solid car and you have the best hands.", es = "Miller, te daremos un coche robusto y tienes las mejores manos." }, emotion = "content" },
          { content = { en = "Help Nova with this job and your debts will be settled.", es = "Ayuda a Nova con este trabajo y vuestras deudas quedaran saldadas." }, emotion = "standard" },
          { content = { en = "Or you can refuse and watch your cars 'disappear' from the garage.", es = "O podeis negaros y ver como vuestros coches 'desaparecen' del garaje." }, emotion = "angry" },
        },
        choices = {
          {
            value = "accept",
            label = { en = "I will do it, but this is the last time.", es = "Lo hare, pero esta es la ultima vez." },
          },
          {
            value = "refuse",
            label = { en = "I am not a delivery boy. Find someone else.", es = "No soy un repartidor. Buscate a otro." },
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 5: "Los Alegatos Finales" - Romance Choice
  -- ========================================================================
  romance_choice = {
    id = "romance_choice",
    scenes = {
      {
        id = "rook_plea",
        contactId = "rook",
        name = { en = "Rook", es = "Rook" },
        emotion = "sad",
        text = {
          { content = { en = "Miller, listen to me. This is ending.", es = "Miller, escuchame. Esto se acaba." }, emotion = "sad" },
          { content = { en = "I can not keep watching how Nova pushes you into Shadow's abyss.", es = "No puedo seguir viendo como Nova te empuja al abismo de Shadow." }, emotion = "sad" },
          { content = { en = "Stay with me. We will finish the ETK-I with Muscle's parts, with honor.", es = "Quedate conmigo. Terminaremos el ETK-I con las piezas de Muscle, con honor." }, emotion = "content" },
          { content = { en = "I promise you loyalty, but you have to cut ties with her now.", es = "Te prometo lealtad, pero tienes que cortar con ella ahora." }, emotion = "standard" },
        },
      },
      {
        id = "nova_plea",
        contactId = "nova",
        name = { en = "Nova", es = "Nova" },
        emotion = "angry",
        text = {
          { content = { en = "Do not listen to him, Miller.", es = "No le escuches, Miller." }, emotion = "angry" },
          { content = { en = "Rook is afraid of his own shadow.", es = "Rook tiene miedo de su propia sombra." }, emotion = "angry" },
          { content = { en = "With me you will reach the Big One with the best engine Shadow can get.", es = "Conmigo llegaras a la Big One con el mejor motor que Shadow pueda conseguir." }, emotion = "content" },
          { content = { en = "I offer you the world, not a dusty workshop.", es = "Te ofrezco el mundo, no un taller polvoriento." }, emotion = "happy" },
          { content = { en = "Choose: the loser's safety or the glory of the fearless?", es = "Elige: la seguridad del perdedor o la gloria de los que no tienen miedo?" }, emotion = "standard" },
        },
        choices = {
          {
            value = "rook",
            label = { en = "Nova, I am sorry. Rook is right about the legacy.", es = "Nova, lo siento. Rook tiene razon sobre el legado." },
          },
          {
            value = "nova",
            label = { en = "Rook, you are too slow for this journey. I am going with her.", es = "Rook, eres demasiado lento para este viaje. Me voy con ella." },
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 5: "El Golpe" - Car Theft Cutscene
  -- ========================================================================
  etki_theft = {
    id = "etki_theft",
    scenes = {
      {
        id = "theft_scene",
        contactId = "shadow",
        name = { en = "???", es = "???" },
        emotion = "standard",
        text = {
          { content = { en = "You are closing the trailer when a reflection in the mirror alerts you.", es = "Estas cerrando el remolque cuando un reflejo en el retrovisor te alerta." }, emotion = "standard" },
          { content = { en = "You do not have time to turn around.", es = "No tienes tiempo de girarte." }, emotion = "standard" },
          { content = { en = "A sharp pain in the back of your neck shuts out the lights.", es = "Un dolor punzante en la nuca te apaga las luces." }, emotion = "angry" },
          { content = { en = "The last thing you hear is the ETK-I engine starting...", es = "Lo ultimo que oyes es el motor del ETK-I arrancando..." }, emotion = "sad" },
          { content = { en = "...and a voice you do not recognize saying: 'Viper will love the gift.'", es = "...y una voz que no reconoces diciendo: 'Viper estara encantada con el regalo'." }, emotion = "angry" },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 7: "El Reencuentro" - Partner Returns + Shadow Challenge
  -- ========================================================================
  partner_truth_reveal = {
    id = "partner_truth_reveal",
    scenes = {
      -- Note: contactId will be set dynamically based on chosen_partner
      {
        id = "partner_returns",
        contactId = "rook",  -- Default, overridden at runtime
        name = { en = "???", es = "???" },  -- Set dynamically
        emotion = "sad",
        text = {
          { content = { en = "Miller! Do not listen to Shadow.", es = "Miller! No escuches a Shadow." }, emotion = "sad" },
          { content = { en = "I never sold the car.", es = "Nunca vendi el coche." }, emotion = "sad" },
          { content = { en = "They set me up. Shadow locked me away so you would think I betrayed you and stop searching.", es = "Me tendieron una trampa. Shadow me encerro para que creyeras que te habia traicionado y dejaras de buscar." }, emotion = "angry" },
          { content = { en = "The ETK-I is whole. Shadow has it in his private garage.", es = "El ETK-I esta entero. Lo tiene Shadow en su garaje privado." }, emotion = "standard" },
          { content = { en = "He is going to use it against you in the Big One!", es = "Lo va a usar contra ti en la Big One!" }, emotion = "angry" },
        },
      },
      {
        id = "shadow_challenge",
        contactId = "shadow",
        name = { en = "Shadow", es = "Shadow" },
        emotion = "standard",
        text = {
          { content = { en = "Enough drama for today.", es = "Suficiente drama por hoy." }, emotion = "standard" },
          { content = { en = "Miller, you have earned your pass.", es = "Miller, has ganado tu pase." }, emotion = "standard" },
          { content = { en = "But if you want to see your ETK-I again... and your partner... you will have to beat me in the Big One.", es = "Pero si quieres volver a ver tu ETK-I... y a tu pareja... tendras que ganarme en la Big One." }, emotion = "content" },
          { content = { en = "I will drive your grandfather's car.", es = "Yo conducire el coche de tu abuelo." }, emotion = "angry" },
          { content = { en = "If you win, I give you everything back. If you lose... the Miller legacy disappears forever.", es = "Si ganas, te lo devuelvo todo. Si pierdes... el legado de Miller desaparece para siempre." }, emotion = "angry" },
        },
        choices = {
          {
            value = "confident",
            label = { en = "Deal. Get ready to lose with a car you do not deserve.", es = "Acepto. Preparate para perder con un coche que no mereces." },
          },
          {
            value = "determined",
            label = { en = "I am coming for you, Shadow. With or without the ETK.", es = "Voy a por ti, Shadow. Con ETK o sin el." },
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 8: "Viper Recognition" - Pre Big One
  -- ========================================================================
  viper_recognition = {
    id = "viper_recognition",
    scenes = {
      {
        id = "viper_intro",
        contactId = "viper",
        name = { en = "Viper", es = "Viper" },
        emotion = "standard",
        text = {
          { content = { en = "So it is true. Miller's car has come back to life.", es = "Asi que es cierto. El coche de Miller ha vuelto a la vida." }, emotion = "standard" },
          { content = { en = "I am Viper.", es = "Soy Viper." }, emotion = "standard" },
          { content = { en = "Your grandfather was the man who made me win everything, but he was also the man who could not look me in the eye after my husband died on that track.", es = "Tu abuelo fue el hombre que me hizo ganar todo, pero tambien fue el hombre que no pudo mirarme a la cara despues de que mi marido muriera en aquella pista." }, emotion = "sad" },
          { content = { en = "I do not blame him... I blame fear.", es = "No lo culpo a el... culpo al miedo." }, emotion = "standard" },
          { content = { en = "Today I will see if you are Miller, or just another ghost in an old car.", es = "Hoy vere si tu eres Miller, o solo otro fantasma en un coche viejo." }, emotion = "standard" },
        },
        choices = {
          {
            value = "ambition",
            label = { en = "I am not a ghost. I am the man who will beat you.", es = "No soy un fantasma. Soy el hombre que va a ganarte." },
          },
          {
            value = "loyalty",
            label = { en = "I race for him, but also for myself. Time to close the circle.", es = "Corro por el, pero tambien por mi. Es hora de cerrar el circulo." },
          },
        },
      },
    },
  },

  -- ========================================================================
  -- PHASE 8: Epilogue - "El Garaje en Paz"
  -- ========================================================================
  epilogue_garage_peace = {
    id = "epilogue_garage_peace",
    scenes = {
      {
        id = "epilogue_viper",
        contactId = "viper",
        name = { en = "Viper", es = "Viper" },
        emotion = "content",
        text = {
          { content = { en = "Miller would have been proud. Or terrified.", es = "Miller habria estado orgulloso. O aterrorizado." }, emotion = "content" },
          { content = { en = "But finally that car has done what it should: roar.", es = "Pero por fin ese coche ha hecho lo que debia: rugir." }, emotion = "happy" },
          { content = { en = "You have done more than him, kid. You have finished the story.", es = "Has hecho mas que el, chico. Has terminado la historia." }, emotion = "happy" },
        },
      },
      {
        id = "epilogue_muscle",
        contactId = "muscle",
        name = { en = "Muscle", es = "Muscle" },
        emotion = "content",
        text = {
          { content = { en = "My father used to say Miller was the best.", es = "Mi padre solia decir que Miller era el mejor." }, emotion = "content" },
          { content = { en = "Now I know he meant the surname, not just the man.", es = "Ahora se que se referia al apellido, no solo al hombre." }, emotion = "happy" },
          { content = { en = "Keep the car. Enjoy it. It is no longer a shadow, now it is yours.", es = "Quedate el coche. Disfrutalo. Ya no es una sombra, ahora es tuyo." }, emotion = "content" },
        },
      },
    },
  },

  -- ========================================================================
  -- EXTRA DRAMATIC SCENES (not in NARRATIVA_REEDIT but enhance key moments)
  -- ========================================================================

  -- Phase 4: Public breakup scene (Rook discovers Shadow connection)
  public_breakup = {
    id = "public_breakup",
    scenes = {
      {
        id = "breakup_rook",
        contactId = "rook",
        name = { en = "Rook", es = "Rook" },
        emotion = "angry",
        text = {
          { content = { en = "I have seen it, Miller! I saw Shadow's name on Nova's phone.", es = "Lo he visto, Miller! He visto el nombre de Shadow en el movil de Nova." }, emotion = "angry" },
          { content = { en = "Nova, you are an idiot! Do you know what they do to people who can not pay for those parts?", es = "Nova, eres una idiota! Sabes lo que le hacen a los que no pueden pagar esas piezas?" }, emotion = "angry" },
          { content = { en = "What are you doing?", es = "Que estas haciendo?" }, emotion = "sad" },
        },
      },
      {
        id = "breakup_nova",
        contactId = "nova",
        name = { en = "Nova", es = "Nova" },
        emotion = "angry",
        text = {
          { content = { en = "Whatever I want, Rook!", es = "Lo que me da la gana, Rook!" }, emotion = "angry" },
          { content = { en = "I am sick of your cheap protectionism!", es = "Estoy harta de tu proteccionismo barato!" }, emotion = "angry" },
          { content = { en = "Miller and I want to get out of here, we want to be more than gas station legends.", es = "Miller y yo queremos salir de aqui, queremos ser algo mas que leyendas de gasolinera." }, emotion = "standard" },
          { content = { en = "If you can not follow us, get out of our line!", es = "Si no puedes seguirnos, apartate de nuestra trazada!" }, emotion = "angry" },
        },
      },
      {
        id = "breakup_rook_final",
        contactId = "rook",
        name = { en = "Rook", es = "Rook" },
        emotion = "sad",
        text = {
          { content = { en = "Fine! Do whatever you want!", es = "Bien! Haz lo que quieras!" }, emotion = "angry" },
          { content = { en = "Miller, if you go with her, forget I ever had your back!", es = "Miller, si te vas con ella, olvida que alguna vez te cubri las espaldas!" }, emotion = "angry" },
          { content = { en = "From now on, you are just two more cars in my rearview.", es = "A partir de ahora, solo sois dos coches mas en mi retrovisor." }, emotion = "sad" },
        },
      },
    },
  },

  -- Phase 8: Shadow Duel pre-race taunt
  shadow_duel = {
    id = "shadow_duel",
    scenes = {
      {
        id = "shadow_taunts",
        contactId = "shadow",
        name = { en = "Shadow", es = "Shadow" },
        emotion = "content",
        text = {
          { content = { en = "Can you feel it, Miller?", es = "Lo sientes, Miller?" }, emotion = "content" },
          { content = { en = "This car has the soul of a coward but the lungs of a monster.", es = "Este coche tiene el alma de un cobarde pero los pulmones de un monstruo." }, emotion = "standard" },
          { content = { en = "Your grandfather built it to win, but he did not have the nerve to handle it.", es = "Tu abuelo lo construyo para ganar, pero no tenia el pulso para manejarlo." }, emotion = "standard" },
          { content = { en = "I do. Try to follow me if you can!", es = "Yo si. Intenta seguirme si puedes!" }, emotion = "angry" },
        },
      },
    },
  },
}

local function buildScenePayload(scene)
  local resolvedTexts = getLocalizedTextList(scene.text)
  local payload = {
    id = scene.id,
    contactId = scene.contactId,
    contactName = getLocalizedText(scene.name),
    emotion = scene.emotion or "standard",
    title = scene.title and getLocalizedText(scene.title) or nil,
    text = resolvedTexts[1] or "",
    texts = resolvedTexts,
  }

  if scene.choices then
    payload.choices = {}
    for _, choice in ipairs(scene.choices) do
      table.insert(payload.choices, {
        value = choice.value,
        label = getLocalizedText(choice.label),
      })
    end
  end

  return payload
end

local function showSceneSequence(sequenceId)
  if not guihooks then return end
  local def = sceneDefinitions[sequenceId]
  if not def or not def.scenes then return end

  local scenesPayload = {}
  for _, scene in ipairs(def.scenes) do
    table.insert(scenesPayload, buildScenePayload(scene))
  end

  guihooks.trigger("mysummerShowSceneSequence", {
    sequenceId = sequenceId,
    scenes = scenesPayload,
    language = getCurrentLang(),
  })
end

local function queueSceneSequence(sequenceId, delaySeconds)
  if not sequenceId or state.sceneFlags[sequenceId] then return end
  if not sceneDefinitions[sequenceId] then return end

  -- Avoid duplicate queue entries
  for _, pending in ipairs(state.pendingSceneSequences) do
    if pending.id == sequenceId then
      return
    end
  end

  table.insert(state.pendingSceneSequences, {
    id = sequenceId,
    delayRemaining = delaySeconds or 0,
  })
  state.sceneFlags[sequenceId] = true
  saveState()
end

local function handleSceneChoice(sequenceId, sceneId, choiceValue)
  if not sequenceId or not sceneId then return end
  if not state.sceneChoices[sequenceId] then
    state.sceneChoices[sequenceId] = {}
  end
  state.sceneChoices[sequenceId][sceneId] = choiceValue
  saveState()
  log("I", logTag, string.format("Scene choice recorded: %s / %s = %s",
    tostring(sequenceId), tostring(sceneId), tostring(choiceValue)))
end

-- Debug helpers (console use)
-- Example: career_modules_mysummerCareer.debugShowSceneSequence("chapter1_end")
local function debugShowSceneSequence(sequenceId)
  if not sequenceId then
    log("W", logTag, "debugShowSceneSequence called without sequenceId")
    return
  end
  log("I", logTag, "DEBUG: Showing scene sequence " .. tostring(sequenceId))
  showSceneSequence(sequenceId)
end

-- Example: career_modules_mysummerCareer.debugQueueSceneSequence("chapter1_first_race", 0)
local function debugQueueSceneSequence(sequenceId, delaySeconds)
  queueSceneSequence(sequenceId, delaySeconds or 0)
  log("I", logTag, "DEBUG: Queued scene sequence " .. tostring(sequenceId))
end

-- Example: career_modules_mysummerCareer.debugResetSceneFlags()
local function debugResetSceneFlags()
  state.sceneFlags = {}
  state.sceneChoices = {}
  state.pendingSceneSequences = {}
  saveState()
  log("I", logTag, "DEBUG: Scene flags, choices, and queues reset")
end

-- ============================================================================
-- RACE LOCATIONS
-- ============================================================================

-- Race locations mapped to RLS freeroam events
-- rlsRace = name of the race in RLS race_data.json (trigger: fre_staging_<rlsRace>)
local raceLocations = {
  -- Phase 1: Street Rookie (easy street races)
  street_circuit_01 = { name = "Beach Circuit", description = "Offroad circuit by the beach", rlsRace = "beachCircuit" },
  industrial_loop_01 = { name = "Quarry Circuit", description = "Race through the quarry", rlsRace = "quarryCircuit" },

  -- Phase 2: Rally Initiate (dirt/offroad)
  rally_forest_01 = { name = "Dirt Circuit", description = "Dirt rally circuit", rlsRace = "dirtCircuit" },
  rally_mountain_01 = { name = "Dirt Oval", description = "Fast dirt oval track", rlsRace = "dirtOval" },
  rally_stage_01 = { name = "Rally Stage 1", description = "Rally stage through countryside", rlsRace = "rally1" },

  -- Phase 3: Circuit Contender (track racing)
  circuit_technical_01 = { name = "Race Track", description = "Professional race track", rlsRace = "track" },
  circuit_fast_01 = { name = "Rubber Band", description = "High speed circuit", rlsRace = "rubberBand" },

  -- Phase 4: Performance Specialist (drag/speed)
  performance_challenge_01 = { name = "Drag Strip", description = "Quarter mile drag race", rlsRace = "drag" },
  performance_challenge_02 = { name = "Highway Drag", description = "Highway drag racing", rlsRace = "dragHighway" },

  -- Phase 5: Underground Legend (drift/touge)
  underground_01 = { name = "Island Touge", description = "Mountain pass racing", rlsRace = "islandTouge" },
  underground_02 = { name = "Drift Loop", description = "Drift competition", rlsRace = "driftLoopRemaster" },
  underground_03 = { name = "Hot Rolled Drift", description = "Industrial drift zone", rlsRace = "hotrolledDrift" },

  -- Phase 6: Endurance (longer races)
  endurance_01 = { name = "Redwood Drift", description = "Forest drift run", rlsRace = "redwoodDrift" },
  endurance_02 = { name = "Sealbrik Drift", description = "Technical drift course", rlsRace = "sealbrikDrift" },

  -- Phase 7: International (track variants)
  international_01 = { name = "Race Track Alt", description = "Alternative track layout", rlsRace = "track" },
  international_02 = { name = "Rock Climb Long", description = "Long rock climb", rlsRace = "rockClimbL" },
  international_03 = { name = "Rock Climb Short", description = "Short rock climb sprint", rlsRace = "rockClimbS" },

  -- Phase 8: Championship Qualifier
  qualifier_01 = { name = "Track Qualifier", description = "Track qualification", rlsRace = "track" },
  qualifier_02 = { name = "Drag Qualifier", description = "Drag qualification", rlsRace = "drag" },
  qualifier_03 = { name = "Drift Qualifier", description = "Drift qualification", rlsRace = "raceTrackDrift" },

  -- Phase 9: Semi-Finals
  semifinal_01 = { name = "Semi-Final Circuit", description = "Circuit semi-final", rlsRace = "track" },
  semifinal_02 = { name = "Semi-Final Touge", description = "Touge semi-final", rlsRace = "islandTouge" },

  -- Phase 10: Championship Final
  championship_final = { name = "CHAMPIONSHIP FINAL", description = "The ultimate race at the track", rlsRace = "track" },
}

-- ============================================================================
-- RLS RACE MAPPING (for reputation rewards when completing RLS freeroam events)
-- ============================================================================

local rlsRaceMapping = {
  -- Offroad/Circuit races
  beachCircuit = { reputationReward = 150, type = "circuit", label = "Beach Circuit" },
  quarryCircuit = { reputationReward = 150, type = "circuit", label = "Quarry Circuit" },
  dirtCircuit = { reputationReward = 200, type = "rally", label = "Dirt Circuit" },
  dirtOval = { reputationReward = 180, type = "rally", label = "Dirt Oval" },

  -- Rally stages (from RLS race_data.json)
  rally1 = { reputationReward = 250, type = "rally", label = "Rally Stage 1" },
  rally2 = { reputationReward = 300, type = "rally", label = "Rally Stage 2" },
  rally3 = { reputationReward = 300, type = "rally", label = "Rally Stage 3" },
  rally4 = { reputationReward = 300, type = "rally", label = "Rally Stage 4 - Final" },

  -- Drag races
  drag = { reputationReward = 100, type = "drag", label = "Drag Strip" },
  dragHighway = { reputationReward = 120, type = "drag", label = "Highway Drag" },

  -- Drift races
  driftLoopRemaster = { reputationReward = 250, type = "drift", label = "Drift Loop" },
  hotrolledDrift = { reputationReward = 220, type = "drift", label = "Hot Rolled Drift" },
  redwoodDrift = { reputationReward = 230, type = "drift", label = "Redwood Drift" },
  sealbrikDrift = { reputationReward = 240, type = "drift", label = "Sealbrik Drift" },
  raceTrackDrift = { reputationReward = 260, type = "drift", label = "Race Track Drift" },

  -- Touge/Mountain races
  islandTouge = { reputationReward = 300, type = "touge", label = "Island Touge" },

  -- Track races
  track = { reputationReward = 350, type = "circuit", label = "Race Track" },
  rubberBand = { reputationReward = 280, type = "circuit", label = "Rubber Band" },

  -- Rock climb
  rockClimbL = { reputationReward = 200, type = "offroad", label = "Rock Climb Long" },
  rockClimbS = { reputationReward = 150, type = "offroad", label = "Rock Climb Short" },
}

-- ============================================================================
-- STATE
-- ============================================================================

state = {  -- Using forward declaration from top of file
  -- Story/Narrative flags
  hasSeenIntro = false,  -- First time intro (grandfather's letter)
  currentChapter = 1,    -- Current story chapter (1-6)
  seenChapterIntros = {}, -- { [chapterId] = true }

  -- Reputation system (separate from RLS)
  reputation = {
    level = 0,        -- 0-100 scale
    tier = 1,         -- 1-5 (derived from level)
    points = 0,       -- Raw points (100 points = 1 level)
    tierThresholds = { 0, 20, 40, 60, 80 },  -- Level thresholds for tiers
  },

  -- Phase progression
  currentPhase = 0,   -- 0-10 (0 = not started)
  phaseProgress = {}, -- { [phaseId] = { wins, completedRaces = {}, completed, completedAt } }

  -- Race tracking
  raceHistory = {},   -- { [raceId] = { wins, attempts, bestTime, lastAttempt } }

  -- Initial vehicles
  hasInitialVehicles = false,
  projectInventoryId = nil,  -- ETK-I project car
  starterInventoryId = nil,  -- Miramar starter

  -- Custom race tracking
  activeCustomRace = nil,  -- { raceId, startTime, checkpointsHit, splitTimes, aiVehicleId, triggers }

  -- Pending AI configurations (processed in onUpdate)
  pendingAIConfigs = {},  -- { { vehId, config, delay } }

  -- Pending phase transition (shown after native UI closes)
  pendingPhaseTransition = nil,  -- { data, delayRemaining }

  -- Pending intro (grandfather's letter, shown after delay)
  pendingIntro = nil,  -- { data, delayRemaining }

  -- Pending story scene sequences (shown after delay)
  pendingSceneSequences = {},  -- { { id, delayRemaining } }

  -- Chapter progression (2 races won = 1 chapter completed)
  chapterProgress = {
    racesWonTotal = 0,
    currentChapter = 1,  -- 1-5 (derived from racesWonTotal)
  },

  -- Story scene flags and choices
  sceneFlags = {},   -- { [sequenceId] = true }
  sceneChoices = {}, -- { [sequenceId] = { [sceneId] = choiceValue } }
}

-- Custom race definitions (MySummer original races with AI)
local customRaces = {
  -- Will be populated with custom race configurations
  -- Example structure:
  -- my_circuit = {
  --   name = "My Circuit",
  --   checkpoints = { { pos = {x, y, z}, radius = 30 }, ... },
  --   startPos = { pos = {x, y, z}, rot = {0, 0, 1, 0} },
  --   aiOpponent = { model = "etki", config = "sport", aggression = 0.7 },
  --   targetTime = 60,
  --   reputationReward = 200
  -- }
}

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

local saveFile = "mysummer_career.json"

local function loadState()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then
    log("W", logTag, "Cannot load - no save path available")
    return
  end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  log("I", logTag, "Looking for save file at: " .. tostring(filePath))

  if not FS:fileExists(filePath) then
    log("I", logTag, "No save file found at " .. tostring(filePath) .. ", using defaults (hasSeenIntro will be FALSE)")
    return
  end

  log("I", logTag, "Save file EXISTS, loading...")

  local data = jsonReadFile(filePath)
  if not data then
    log("E", logTag, "Failed to load save file")
    return
  end

  log("I", logTag, "Loaded data.hasSeenIntro = " .. tostring(data.hasSeenIntro))

  -- Restore state
  state.reputation = data.reputation or state.reputation
  state.currentPhase = data.currentPhase or 0
  state.phaseProgress = data.phaseProgress or {}
  state.raceHistory = data.raceHistory or {}
  state.hasInitialVehicles = data.hasInitialVehicles or false
  state.projectInventoryId = data.projectInventoryId
  state.starterInventoryId = data.starterInventoryId

  -- Restore chapter progress
  if data.chapterProgress then
    state.chapterProgress.racesWonTotal = data.chapterProgress.racesWonTotal or 0
    state.chapterProgress.currentChapter = data.chapterProgress.currentChapter or 1
  end

  -- Restore story/intro flags
  state.hasSeenIntro = data.hasSeenIntro or false
  state.currentChapter = data.currentChapter or 1
  state.seenChapterIntros = data.seenChapterIntros or {}
  state.sceneFlags = data.sceneFlags or {}
  state.sceneChoices = data.sceneChoices or {}

  -- SAFETY CHECK REMOVED: The previous check was too aggressive and would reset
  -- hasSeenIntro even after the player had legitimately seen it.
  -- The flag is now trusted from the save file.
  --
  -- Original logic was:
  -- If (phase 0-1, level 0, no races won, no initial vehicles) AND hasSeenIntro=true
  -- then reset hasSeenIntro to false
  --
  -- This caused problems because:
  -- 1. Player closes intro letter -> hasSeenIntro saved as true
  -- 2. But hasInitialVehicles might still be false (vehicles spawn async)
  -- 3. Next load -> safety check triggers -> intro resets -> always shows intro
  --
  -- Solution: Trust the save file. If player wants to reset, they can use
  -- career_modules_mysummerCareer.resetIntro() console command

  log("I", logTag, "State loaded - Phase: " .. state.currentPhase .. ", Chapter: " .. state.chapterProgress.currentChapter .. ", Level: " .. state.reputation.level .. ", IntroSeen: " .. tostring(state.hasSeenIntro))
end

saveState = function(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  savePath = currentSavePath or savePath
  if not savePath then
    log("W", logTag, "Cannot save - no save path available")
    return
  end

  local dirPath = savePath .. "/career/mysummer"
  FS:directoryCreate(dirPath, true)

  local filePath = dirPath .. "/" .. saveFile
  career_saveSystem.jsonWriteFileSafe(filePath, state, true)
  log("I", logTag, "State saved to " .. filePath)
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

-- ============================================================================
-- UI COMMUNICATION (defined early because it's called by reputation/phase functions)
-- ============================================================================

local function sendCareerUpdate()
  if not guihooks then
    return
  end

  local data = {
    reputation = state.reputation,
    currentPhase = state.currentPhase,
    phaseProgress = state.phaseProgress,
    phases = phaseDefinitions,
    projectInventoryId = state.projectInventoryId,
  }

  guihooks.trigger("mysummerCareerUpdated", data)
end

-- ============================================================================
-- REPUTATION SYSTEM
-- ============================================================================

-- Calculate tier from level
local function calculateTier(level)
  local thresholds = state.reputation.tierThresholds
  for tier = #thresholds, 1, -1 do
    if level >= thresholds[tier] then
      return tier
    end
  end
  return 1
end

-- Update reputation after tier calculation
local function updateReputationTier()
  local oldTier = state.reputation.tier
  state.reputation.tier = calculateTier(state.reputation.level)

  if state.reputation.tier > oldTier then
    log("I", logTag, "TIER UP! Now tier " .. state.reputation.tier)
    -- TODO: Show UI notification
  end
end

-- Add reputation points
-- @param points: Points to add
-- @param reason: Why points were awarded (for logging)
local function addReputationPoints(points, reason)
  local oldLevel = state.reputation.level

  state.reputation.points = state.reputation.points + points

  -- Convert points to levels (100 points = 1 level)
  local newLevels = math.floor(state.reputation.points / 100)
  state.reputation.level = math.min(100, newLevels)  -- Cap at 100
  state.reputation.points = state.reputation.points % 100  -- Keep remainder

  updateReputationTier()

  if state.reputation.level > oldLevel then
    log("I", logTag, string.format("LEVEL UP! %d -> %d (%s)", oldLevel, state.reputation.level, reason))
    -- TODO: Show UI notification
  end

  log("I", logTag, string.format("Reputation +%d (%s) - Level: %d, Tier: %d", points, reason, state.reputation.level, state.reputation.tier))

  saveState()
  sendCareerUpdate()
end

-- Get current reputation data
local function getReputation()
  return state.reputation
end

-- ============================================================================
-- CHAPTER PROGRESSION SYSTEM (Parts unlock gating)
-- ============================================================================

-- Chapter requirements: 2 race wins per chapter
local RACES_PER_CHAPTER = 2
local MAX_CHAPTER = 5

-- Chapter definitions with unlock info
local chapterDefinitions = {
  [1] = { name = { en = "Street Rookie", es = "Novato Callejero" }, racesRequired = 0 },
  [2] = { name = { en = "Rising Driver", es = "Piloto en Ascenso" }, racesRequired = 2 },
  [3] = { name = { en = "Local Racer", es = "Corredor Local" }, racesRequired = 4 },
  [4] = { name = { en = "Street Legend", es = "Leyenda Callejera" }, racesRequired = 6 },
  [5] = { name = { en = "The Big One", es = "The Big One" }, racesRequired = 8 },
}

-- Calculate chapter from total races won
local function calculateChapter(racesWon)
  for chapter = MAX_CHAPTER, 1, -1 do
    local def = chapterDefinitions[chapter]
    if def and racesWon >= def.racesRequired then
      return chapter
    end
  end
  return 1
end

-- Record a race win and update chapter
local function recordRaceWin(raceId)
  state.chapterProgress.racesWonTotal = state.chapterProgress.racesWonTotal + 1
  local oldChapter = state.chapterProgress.currentChapter
  state.chapterProgress.currentChapter = calculateChapter(state.chapterProgress.racesWonTotal)

  log("I", logTag, string.format("Race win recorded. Total wins: %d, Chapter: %d",
    state.chapterProgress.racesWonTotal, state.chapterProgress.currentChapter))

  -- Check for chapter advancement
  if state.chapterProgress.currentChapter > oldChapter then
    log("I", logTag, "CHAPTER UP! Now chapter " .. state.chapterProgress.currentChapter)
    local chapterDef = chapterDefinitions[state.chapterProgress.currentChapter]
    if guihooks and chapterDef then
      guihooks.trigger("mysummerChapterCompleted", {
        oldChapter = oldChapter,
        newChapter = state.chapterProgress.currentChapter,
        chapterName = chapterDef.name,
      })
      guihooks.trigger("toastrMsg", {
        type = "success",
        title = "Chapter Unlocked!",
        msg = "New parts are now available in shops."
      })
    end
  end

  -- Story scenes for Chapter 1 milestones - DISABLED (now using narrative system)
  -- These are mutually exclusive - either it's the first win OR chapter completion, not both at once
  -- if oldChapter == 1 and state.chapterProgress.currentChapter == 2 then
  --   -- Chapter completed - show end sequence
  --   queueSceneSequence("chapter1_end", 4.0)
  -- elseif state.chapterProgress.racesWonTotal == 1 and state.chapterProgress.currentChapter == 1 then
  --   -- First win but still in chapter 1 - show first race sequence
  --   -- Only show if teammates have been met (narrative progression)
  --   local narrative = career_modules_mysummerNarrative
  --   if narrative and narrative.getStoryFlag and narrative.getStoryFlag("teammates_met") then
  --     queueSceneSequence("chapter1_first_race", 4.0)
  --   end
  -- end

  saveState()
  sendCareerUpdate()
end

-- Get current chapter number
local function getCurrentChapter()
  return state.chapterProgress.currentChapter or 1
end

-- Get total races won
local function getTotalRacesWon()
  return state.chapterProgress.racesWonTotal or 0
end

-- Get chapter progress data for UI
local function getChapterProgress()
  local current = state.chapterProgress.currentChapter or 1
  local racesWon = state.chapterProgress.racesWonTotal or 0
  local nextChapter = chapterDefinitions[current + 1]
  local racesToNextChapter = nextChapter and (nextChapter.racesRequired - racesWon) or 0

  return {
    currentChapter = current,
    racesWonTotal = racesWon,
    racesToNextChapter = math.max(0, racesToNextChapter),
    chapterName = chapterDefinitions[current] and chapterDefinitions[current].name or "Unknown",
    maxChapter = MAX_CHAPTER,
  }
end

-- ============================================================================
-- PHASE PROGRESSION
-- ============================================================================

-- Check if prerequisites are met for a phase
-- @param phaseId: Phase number (1-10)
-- @return: canStart (boolean), reason (string if false)
local function checkPhasePrerequisites(phaseId)
  local phaseDef = phaseDefinitions[phaseId]
  if not phaseDef then
    return false, "Invalid phase"
  end

  -- Phase 1 has no prerequisites
  if phaseId == 1 then
    return true
  end

  local prereqs = phaseDef.prerequisites
  if not prereqs then
    return true
  end

  -- Check previous phase completion
  if prereqs.phase then
    local prevPhase = state.phaseProgress[prereqs.phase]
    if not prevPhase or not prevPhase.completed then
      return false, "Must complete Phase " .. prereqs.phase .. " first"
    end
  end

  -- Check reputation level
  if prereqs.reputationLevel and state.reputation.level < prereqs.reputationLevel then
    return false, "Requires Reputation Level " .. prereqs.reputationLevel
  end

  -- Check checklist completion (for final phase)
  if prereqs.checklistCompletion and career_modules_mysummerChecklist then
    local stats = career_modules_mysummerChecklist.getStats()
    if stats.completionPercent < prereqs.checklistCompletion then
      return false, string.format("Requires %d%% checklist completion", prereqs.checklistCompletion)
    end
  end

  return true
end

-- Start a new phase
-- @param phaseId: Phase number to start
local function startPhase(phaseId)
  local canStart, reason = checkPhasePrerequisites(phaseId)
  if not canStart then
    log("W", logTag, "Cannot start phase " .. phaseId .. ": " .. reason)
    return false, reason
  end

  -- Initialize phase progress
  if not state.phaseProgress[phaseId] then
    state.phaseProgress[phaseId] = {
      wins = 0,
      completedRaces = {},
      completed = false,
      completedAt = nil,
    }
  end

  state.currentPhase = phaseId
  saveState()
  sendCareerUpdate()

  log("I", logTag, "Started Phase " .. phaseId .. ": " .. getLocalizedText(phaseDefinitions[phaseId].name))
  return true
end

-- Check if a phase is completed
-- @param phaseId: Phase number
local function checkPhaseCompletion(phaseId)
  local phaseDef = phaseDefinitions[phaseId]
  local progress = state.phaseProgress[phaseId]

  if not phaseDef or not progress then
    return false
  end

  if progress.wins >= phaseDef.requiredWins then
    return true
  end

  return false
end

-- Complete a phase and award rewards
-- @param phaseId: Phase number
local function completePhase(phaseId)
  local phaseDef = phaseDefinitions[phaseId]
  if not phaseDef then
    return
  end

  local progress = state.phaseProgress[phaseId]
  if progress.completed then
    return  -- Already completed
  end

  -- Mark as completed
  progress.completed = true
  progress.completedAt = os.time()

  -- Award reputation
  if phaseDef.reputationReward and phaseDef.reputationReward > 0 then
    addReputationPoints(phaseDef.reputationReward, "Phase " .. phaseId .. " completion")
  end

  -- Award cash
  if phaseDef.cashReward and phaseDef.cashReward > 0 and career_modules_payment then
    career_modules_payment.reward(
      { money = { amount = phaseDef.cashReward } },
      { label = "Phase " .. phaseId .. " completion: " .. getLocalizedText(phaseDef.name), tags = { "gameplay", "reward", "phase" } },
      true
    )
  end

  -- TODO: Award part rewards

  -- Check if this unlocks free play
  local isFinalPhase = phaseDef.unlocksFreePlay
  if isFinalPhase then
    log("I", logTag, "FREE PLAY UNLOCKED! All restrictions removed.")
    -- TODO: Remove part tier restrictions
  end

  log("I", logTag, "PHASE COMPLETED: " .. getLocalizedText(phaseDef.name))

  saveState()
  sendCareerUpdate()

  -- Trigger phase transition UI
  local nextPhaseDef = phaseDefinitions[phaseId + 1]
  guihooks.trigger("mysummerPhaseTransition", {
    completedPhase = phaseId,
    completedPhaseName = getLocalizedText(phaseDef.name),
    completionText = getLocalizedText(phaseDef.storyText.completion),
    cashReward = phaseDef.cashReward or 0,
    reputationReward = phaseDef.reputationReward or 0,
    isFinalPhase = isFinalPhase,
    -- Next phase info (if available)
    nextPhase = nextPhaseDef and (phaseId + 1) or nil,
    nextPhaseName = nextPhaseDef and getLocalizedText(nextPhaseDef.name) or nil,
    nextPhaseDescription = nextPhaseDef and getLocalizedText(nextPhaseDef.description) or nil,
    nextPhaseIntro = nextPhaseDef and getLocalizedText(nextPhaseDef.storyText.intro) or nil,
  })

  -- Auto-start next phase if available
  if nextPhaseDef then
    startPhase(phaseId + 1)
  end
end

-- ============================================================================
-- RACE INTEGRATION
-- ============================================================================

-- Called when a freeroam event (race) is completed
local function onFreeroamEventCompleted(eventData)
  if not eventData or eventData.eventType ~= "race" then
    return
  end

  local raceId = eventData.raceId or eventData.eventId
  local position = eventData.position or 999
  local time = eventData.time

  -- Update race history
  if not state.raceHistory[raceId] then
    state.raceHistory[raceId] = {
      wins = 0,
      attempts = 0,
      bestTime = nil,
      lastAttempt = nil,
    }
  end

  local history = state.raceHistory[raceId]
  history.attempts = history.attempts + 1
  history.lastAttempt = os.time()

  if time and (not history.bestTime or time < history.bestTime) then
    history.bestTime = time
  end

  -- Check if won (position 1)
  if position == 1 then
    history.wins = history.wins + 1

    -- Award reputation for win
    addReputationPoints(200, "Race win: " .. raceId)

    -- Check if this race is part of current phase
    if state.currentPhase > 0 and state.currentPhase <= 10 then
      local phaseDef = phaseDefinitions[state.currentPhase]
      local progress = state.phaseProgress[state.currentPhase]

      if phaseDef and progress and tableContains(phaseDef.requiredRaces, raceId) then
        -- This race counts toward phase progress
        if not tableContains(progress.completedRaces, raceId) then
          table.insert(progress.completedRaces, raceId)
          progress.wins = progress.wins + 1

          log("I", logTag, string.format("Phase %d progress: %d/%d wins",
            state.currentPhase, progress.wins, phaseDef.requiredWins))

          -- Check if phase is now complete
          if checkPhaseCompletion(state.currentPhase) then
            completePhase(state.currentPhase)
          end
        end
      end
    end
  end

  saveState()
end

-- ============================================================================
-- RLS RACE COMPLETION DETECTION
-- ============================================================================

-- Find which of our phase races maps to an RLS race
local function findMappedPhaseRace(rlsRaceName)
  for raceId, raceConfig in pairs(raceLocations) do
    if raceConfig.rlsRace == rlsRaceName then
      return raceId, raceConfig
    end
  end
  return nil, nil
end

-- Calculate reputation reward for completing an RLS race
local function calculateRLSRaceReward(rlsRaceName, isNewBest)
  local mapping = rlsRaceMapping[rlsRaceName]
  if mapping then
    local reward = mapping.reputationReward
    -- Bonus for new personal best time
    if isNewBest then
      reward = math.floor(reward * 1.25)
    end
    return reward
  end
  -- Base reward for unmapped races
  return 50
end

-- Called when player finishes an RLS freeroam race (detected via trigger)
local function onRLSRaceFinished(rlsRaceName, vehicleId)
  log("I", logTag, "RLS race finished detected: " .. tostring(rlsRaceName))

  -- Verify it's the player's vehicle (use same method as RLS freeroamEvents)
  local playerVehicleId = be:getPlayerVehicleID(0)
  if not playerVehicleId then
    log("W", logTag, "No player vehicle found")
    return
  end

  log("I", logTag, "Comparing vehicleId: " .. tostring(vehicleId) .. " vs playerVehicleId: " .. tostring(playerVehicleId))

  if playerVehicleId ~= vehicleId then
    log("I", logTag, "Race finished by non-player vehicle, ignoring")
    return
  end

  -- Get RLS race data if available
  local rlsRaceData = nil
  if gameplay_events_freeroam and gameplay_events_freeroam.getRace then
    rlsRaceData = gameplay_events_freeroam.getRace(rlsRaceName)
  end

  local raceLabel = rlsRaceName
  if rlsRaceMapping[rlsRaceName] then
    raceLabel = rlsRaceMapping[rlsRaceName].label or rlsRaceName
  elseif rlsRaceData and rlsRaceData.label then
    raceLabel = rlsRaceData.label
  end

  -- Award reputation points
  local reward = calculateRLSRaceReward(rlsRaceName, false)  -- TODO: detect new best time
  addReputationPoints(reward, "Carrera completada: " .. raceLabel)

  -- Show notification
  if ui_message then
    ui_message(string.format("+%d Reputation - %s", reward, raceLabel), 4, "Career", "success")
  end

  -- Check if this RLS race is mapped to one of our phase races
  local phaseRaceId, phaseRaceConfig = findMappedPhaseRace(rlsRaceName)
  if phaseRaceId and state.currentPhase > 0 then
    log("I", logTag, "Race maps to phase race: " .. phaseRaceId)

    -- Treat as a win for phase progress (RLS time trials = completion = win)
    local eventData = {
      eventType = "race",
      raceId = phaseRaceId,
      position = 1,  -- Completed = win
      time = nil,    -- Time not tracked here
    }
    onFreeroamEventCompleted(eventData)
  end

  -- Update race history
  if not state.raceHistory[rlsRaceName] then
    state.raceHistory[rlsRaceName] = {
      wins = 0,
      attempts = 0,
      bestTime = nil,
      lastAttempt = nil,
    }
  end
  local history = state.raceHistory[rlsRaceName]
  history.wins = history.wins + 1
  history.attempts = history.attempts + 1
  history.lastAttempt = os.time()

  saveState()
  sendCareerUpdate()
end

-- Listen for BeamNG trigger events (used by RLS freeroam races)
local function onBeamNGTrigger(data)
  if not career_career or not career_career.isActive() then
    return
  end

  -- IMPORTANT: Filter by player vehicle ID first (same as RLS does)
  local playerVehicleId = be:getPlayerVehicleID(0)
  if not playerVehicleId or playerVehicleId ~= data.subjectID then
    return  -- Ignore triggers from AI vehicles
  end

  local triggerName = data.triggerName or ""
  local event = data.event

  -- Detect RLS race finish triggers (only for player vehicle now)
  if event == "enter" and triggerName:match("^fre_finish_") then
    local rlsRaceName = triggerName:sub(12)  -- Remove "fre_finish_" prefix
    log("I", logTag, "Detected RLS finish trigger: " .. rlsRaceName .. " (player vehicle)")
    onRLSRaceFinished(rlsRaceName, data.subjectID)
  end

  -- Detect custom MySummer race checkpoints
  if event == "enter" and triggerName:match("^mysummer_cp_") then
    local parts = triggerName:sub(13)  -- Remove "mysummer_cp_" prefix
    local raceId, cpIndex = parts:match("^(.+)_(%d+)$")
    if raceId and cpIndex then
      onCustomRaceCheckpoint(raceId, tonumber(cpIndex))
    end
  end

  -- Detect custom MySummer race start
  if event == "enter" and triggerName:match("^mysummer_start_") then
    local raceId = triggerName:sub(16)  -- Remove "mysummer_start_" prefix
    onCustomRaceStart(raceId)
  end

  -- Detect custom MySummer race finish
  if event == "enter" and triggerName:match("^mysummer_finish_") then
    local raceId = triggerName:sub(17)  -- Remove "mysummer_finish_" prefix
    onCustomRaceFinish(raceId)
  end
end

-- ============================================================================
-- CUSTOM RACE SYSTEM (MySummer original races with AI opponents)
-- ============================================================================

-- Forward declarations for functions that have circular dependencies
local endCustomRace
local onCustomRaceStart
local onCustomRaceCheckpoint
local onCustomRaceFinish

-- Create checkpoint triggers for a custom race
local function createRaceCheckpoints(raceId)
  local race = customRaces[raceId]
  if not race or not race.checkpoints then
    log("W", logTag, "Cannot create checkpoints - race not found: " .. tostring(raceId))
    return nil
  end

  local triggers = {}
  log("I", logTag, "Creating " .. #race.checkpoints .. " checkpoints for race: " .. raceId)

  for i, cp in ipairs(race.checkpoints) do
    local trigger = createObject('BeamNGTrigger')
    if trigger then
      trigger:setPosition(vec3(cp.pos[1], cp.pos[2], cp.pos[3]))
      local radius = cp.radius or 30
      trigger:setScale(vec3(radius, radius, radius))
      trigger.triggerType = 0  -- Sphere type

      local triggerName = "mysummer_cp_" .. raceId .. "_" .. i
      trigger:registerObject(triggerName)
      triggers[i] = trigger
      log("I", logTag, "Created checkpoint " .. i .. " at: " .. cp.pos[1] .. ", " .. cp.pos[2] .. ", " .. cp.pos[3])
    end
  end

  -- Create start trigger
  if race.startPos then
    local startTrigger = createObject('BeamNGTrigger')
    if startTrigger then
      startTrigger:setPosition(vec3(race.startPos.pos[1], race.startPos.pos[2], race.startPos.pos[3]))
      startTrigger:setScale(vec3(20, 20, 20))
      startTrigger.triggerType = 0
      startTrigger:registerObject("mysummer_start_" .. raceId)
      triggers.start = startTrigger
    end
  end

  -- Create finish trigger (last checkpoint position or explicit finish)
  local finishPos = race.finishPos or race.checkpoints[#race.checkpoints]
  if finishPos then
    local finishTrigger = createObject('BeamNGTrigger')
    if finishTrigger then
      local pos = finishPos.pos or finishPos
      finishTrigger:setPosition(vec3(pos[1], pos[2], pos[3]))
      finishTrigger:setScale(vec3(30, 30, 30))
      finishTrigger.triggerType = 0
      finishTrigger:registerObject("mysummer_finish_" .. raceId)
      triggers.finish = finishTrigger
    end
  end

  return triggers
end

-- Cleanup race triggers
local function cleanupRaceTriggers(triggers)
  if not triggers then return end

  for key, trigger in pairs(triggers) do
    if trigger and trigger.delete then
      trigger:delete()
    end
  end
end

-- Spawn AI opponent for a race
local function spawnAIOpponent(raceConfig, raceId)
  if not raceConfig.aiOpponent then
    return nil
  end

  local ai = raceConfig.aiOpponent
  log("I", logTag, "Spawning AI opponent: " .. ai.model .. "/" .. (ai.config or "default"))

  -- Build spawn options
  local spawnPos = raceConfig.startPos and raceConfig.startPos.pos or { 0, 0, 0 }
  local spawnOptions = {
    model = ai.model,
    config = ai.config,
    pos = vec3(spawnPos[1] - 5, spawnPos[2], spawnPos[3]),  -- Offset slightly from start
    rot = raceConfig.startPos and raceConfig.startPos.rot or quat(0, 0, 1, 0),
  }

  -- Spawn vehicle
  local vehId = nil
  if core_vehicles and core_vehicles.spawnNewVehicle then
    vehId = core_vehicles.spawnNewVehicle(spawnOptions.model, spawnOptions)
  end

  if not vehId then
    log("W", logTag, "Failed to spawn AI vehicle")
    return nil
  end

  -- Queue AI configuration (processed in onUpdate after delay)
  table.insert(state.pendingAIConfigs, {
    vehId = vehId,
    config = {
      aggression = ai.aggression or 0.7,
      aiPath = raceConfig.aiPath
    },
    delay = 1.0  -- Wait 1 second before configuring
  })

  return vehId
end

-- Remove AI opponent vehicle
local function removeAIOpponent(vehId)
  if not vehId then return end

  local veh = be:getObjectByID(vehId)
  if veh then
    if core_vehicles and core_vehicles.removeVehicle then
      core_vehicles.removeVehicle(vehId)
    end
    log("I", logTag, "AI opponent removed: " .. vehId)
  end
end

-- Start a custom race
local function startCustomRace(raceId)
  local race = customRaces[raceId]
  if not race then
    log("W", logTag, "Cannot start race - not found: " .. tostring(raceId))
    return false
  end

  -- Cleanup any existing race
  if state.activeCustomRace then
    endCustomRace(false)
  end

  log("I", logTag, "Starting custom race: " .. raceId)

  -- Create triggers
  local triggers = createRaceCheckpoints(raceId)

  -- Spawn AI if configured
  local aiVehId = spawnAIOpponent(race, raceId)

  -- Initialize race state
  state.activeCustomRace = {
    raceId = raceId,
    startTime = 0,  -- Will be set when crossing start line
    checkpointsHit = 0,
    totalCheckpoints = #race.checkpoints,
    splitTimes = {},
    aiVehicleId = aiVehId,
    triggers = triggers,
    timerActive = false,
  }

  -- Show UI message
  if ui_message then
    ui_message("Race ready: " .. race.name .. " - Drive to start line!", 5, "Career")
  end

  -- Set waypoint to start
  if race.startPos and core_groundMarkers then
    core_groundMarkers.setPath(vec3(race.startPos.pos[1], race.startPos.pos[2], race.startPos.pos[3]))
  end

  return true
end

-- Called when player crosses start line
onCustomRaceStart = function(raceId)
  if not state.activeCustomRace or state.activeCustomRace.raceId ~= raceId then
    return
  end

  if state.activeCustomRace.timerActive then
    return  -- Already started
  end

  log("I", logTag, "Custom race started: " .. raceId)
  state.activeCustomRace.startTime = os.clock()
  state.activeCustomRace.timerActive = true

  -- Start AI if present
  if state.activeCustomRace.aiVehicleId then
    local veh = be:getObjectByID(state.activeCustomRace.aiVehicleId)
    if veh then
      veh:queueLuaCommand("ai.setMode('manual')")
    end
  end

  if ui_message then
    ui_message("GO!", 2, "Career")
  end
end

-- Called when player hits a checkpoint
onCustomRaceCheckpoint = function(raceId, checkpointIndex)
  if not state.activeCustomRace or state.activeCustomRace.raceId ~= raceId then
    return
  end

  if not state.activeCustomRace.timerActive then
    return  -- Race not started yet
  end

  -- Check if this is the expected next checkpoint
  local expectedIndex = state.activeCustomRace.checkpointsHit + 1
  if checkpointIndex ~= expectedIndex then
    log("W", logTag, "Wrong checkpoint order: expected " .. expectedIndex .. ", got " .. checkpointIndex)
    return
  end

  local elapsed = os.clock() - state.activeCustomRace.startTime
  state.activeCustomRace.splitTimes[checkpointIndex] = elapsed
  state.activeCustomRace.checkpointsHit = checkpointIndex

  log("I", logTag, string.format("Checkpoint %d/%d - Time: %.2fs",
    checkpointIndex, state.activeCustomRace.totalCheckpoints, elapsed))

  -- Show split time
  if ui_message then
    ui_message(string.format("Checkpoint %d - %.2fs", checkpointIndex, elapsed), 2, "Career")
  end
end

-- Called when player crosses finish line
onCustomRaceFinish = function(raceId)
  if not state.activeCustomRace or state.activeCustomRace.raceId ~= raceId then
    return
  end

  if not state.activeCustomRace.timerActive then
    return
  end

  -- Check all checkpoints were hit
  if state.activeCustomRace.checkpointsHit < state.activeCustomRace.totalCheckpoints then
    log("W", logTag, "Finish crossed but not all checkpoints hit: " ..
      state.activeCustomRace.checkpointsHit .. "/" .. state.activeCustomRace.totalCheckpoints)
    if ui_message then
      ui_message("Missed checkpoints! Race invalid.", 3, "Career", "error")
    end
    return
  end

  local finishTime = os.clock() - state.activeCustomRace.startTime
  log("I", logTag, string.format("Custom race finished: %s - Time: %.2fs", raceId, finishTime))

  local race = customRaces[raceId]

  -- Determine position (vs AI or target time)
  local position = 1
  local aiTime = nil

  -- TODO: Get AI finish time if applicable

  -- Calculate reward
  local reward = race.reputationReward or 150
  if race.targetTime and finishTime <= race.targetTime then
    reward = math.floor(reward * 1.5)  -- Bonus for beating target time
  end

  addReputationPoints(reward, "Custom race: " .. race.name)

  -- Show result
  if ui_message then
    ui_message(string.format("FINISHED! Time: %.2fs - +%d Reputation", finishTime, reward), 5, "Career", "success")
  end

  -- Update race history
  if not state.raceHistory[raceId] then
    state.raceHistory[raceId] = { wins = 0, attempts = 0, bestTime = nil, lastAttempt = nil }
  end
  local history = state.raceHistory[raceId]
  history.wins = history.wins + 1
  history.attempts = history.attempts + 1
  history.lastAttempt = os.time()
  if not history.bestTime or finishTime < history.bestTime then
    history.bestTime = finishTime
    if ui_message then
      ui_message("NEW PERSONAL BEST!", 3, "Career", "success")
    end
  end

  endCustomRace(true)
  saveState()
  sendCareerUpdate()
end

-- End/cleanup a custom race
endCustomRace = function(completed)
  if not state.activeCustomRace then
    return
  end

  local raceId = state.activeCustomRace.raceId
  log("I", logTag, "Ending custom race: " .. raceId .. " (completed: " .. tostring(completed) .. ")")

  -- Cleanup triggers
  cleanupRaceTriggers(state.activeCustomRace.triggers)

  -- Remove AI opponent
  removeAIOpponent(state.activeCustomRace.aiVehicleId)

  -- Clear waypoint
  if core_groundMarkers and core_groundMarkers.setPath then
    core_groundMarkers.setPath(nil)
  end

  state.activeCustomRace = nil
end

-- Cancel active custom race
local function cancelCustomRace()
  if state.activeCustomRace then
    if ui_message then
      ui_message("Race cancelled", 3, "Career")
    end
    endCustomRace(false)
  end
end

-- ============================================================================
-- INITIAL VEHICLES (MOVED FROM mysummerParts)
-- ============================================================================

-- Spawn the initial vehicles (Miramar starter + ETK-I project)
local function spawnInitialVehicles()
  if state.hasInitialVehicles then
    log("I", logTag, "Initial vehicles already spawned")
    return
  end

  log("I", logTag, "Spawning initial vehicles...")

  -- Check if vehicles already exist in inventory
  local existing = career_modules_inventory and career_modules_inventory.getVehicles() or {}
  for invId, veh in pairs(existing) do
    if veh and veh.model == "etki" and veh.config and veh.config.partConfigFilename and
       veh.config.partConfigFilename:find("mysummer_2400ti_ttsport_chassis") then
      state.projectInventoryId = invId
      state.hasInitialVehicles = true
      log("I", logTag, "Found existing ETK-I project car: " .. tostring(invId))
      saveState()
      return
    end
  end

  -- Note: Starting garage is handled by MySummer challenge (Sealbrick1058Garage)
  -- If no challenge is active, RLS will use its default starter garage

  local garageId = career_modules_garageManager and career_modules_garageManager.getNextAvailableSpace() or nil
  if not garageId then
    log("W", logTag, "No garage space available, skipping vehicle spawn")
    state.hasInitialVehicles = true
    saveState()
    return
  end

  -- For now, just mark as done - vehicles can be added manually or via parts market
  -- Full vehicle spawn requires more complex API calls that may not be available
  log("I", logTag, "Garage space available: " .. tostring(garageId))
  log("I", logTag, "Vehicle spawn deferred - use Parts Market to get project car")

  state.hasInitialVehicles = true
  saveState()

  log("I", logTag, "Initial setup complete")
end

-- Called after inventory is set up
local function onSetupInventoryFinished()
  -- Vehicle spawning is handled by mysummerParts module
  -- Here we just check for existing project vehicle and start phase 1

  -- Teleport to MySummer starting garage (Sealbrick) if this is a new career
  -- This overrides RLS's spawn location which would use Chinatown
  if not state.hasSeenIntro and freeroam_facilities and freeroam_facilities.teleportToGarage then
    local mysummerGarageId = "Sealbrick1058Garage"
    local playerVeh = getPlayerVehicle(0)
    if playerVeh then
      -- Small delay to ensure RLS has finished its spawn logic
      extensions.core_jobsystem.create(function(job)
        job.sleep(0.5)
        log("I", logTag, "New career - teleporting to MySummer garage: " .. mysummerGarageId)
        freeroam_facilities.teleportToGarage(mysummerGarageId, playerVeh)
      end)
    end
  end

  -- Check if project vehicle exists
  if not state.projectInventoryId then
    local existing = career_modules_inventory and career_modules_inventory.getVehicles() or {}
    for invId, veh in pairs(existing) do
      if veh and veh.model == "etki" and veh.config and veh.config.partConfigFilename and
         veh.config.partConfigFilename:find("mysummer_2400ti_ttsport_chassis") then
        state.projectInventoryId = invId
        log("I", logTag, "Found project vehicle: " .. tostring(invId))
        break
      end
    end
  end

  -- DISABLED: Don't auto-start Phase 1
  -- Phase 0 (narrative) happens before any formal phase starts
  -- Phase 1 will start after completing the first 3 races + Ghost's contact mission
  --[[
  if state.currentPhase == 0 then
    local phaseSuccess, phaseErr = pcall(startPhase, 1)
    if not phaseSuccess then
      log("E", logTag, "Failed to start Phase 1: " .. tostring(phaseErr))
    end
  end
  ]]--

  saveState()
end

-- ============================================================================
-- RACE NAVIGATION
-- ============================================================================

-- Get parking sites for race locations (uses gameplay_sites_sitesManager like taxi.lua)
local function getParkingSites()
  if cachedParkingSites then
    return cachedParkingSites
  end

  log("I", logTag, "getParkingSites: Searching for parking sites...")

  -- Method 1: Use sites manager like taxi.lua does
  if gameplay_sites_sitesManager then
    local sitePath = gameplay_sites_sitesManager.getCurrentLevelSitesFileByName('city')
    if sitePath then
      log("I", logTag, "Found city sites file: " .. tostring(sitePath))
      local siteData = gameplay_sites_sitesManager.loadSites(sitePath, true, true)
      if siteData and siteData.parkingSpots and siteData.parkingSpots.objects then
        local parkingList = {}
        for _, spot in pairs(siteData.parkingSpots.objects) do
          if spot.pos then
            table.insert(parkingList, { pos = spot.pos, name = spot.name or "parking" })
          end
        end
        if #parkingList > 0 then
          cachedParkingSites = parkingList
          log("I", logTag, "Found " .. #parkingList .. " parking spots from city sites")
          return cachedParkingSites
        end
      end
    else
      log("W", logTag, "No city sites file found for current level")
    end
  end

  -- Method 2: Fallback to freeroam_facilities
  if freeroam_facilities then
    local facilities = freeroam_facilities.getFacilities()
    if facilities then
      local parkingList = {}
      for facilityId, facility in pairs(facilities) do
        if facility.parkingSpots and facility.parkingSpots.general then
          for spotId, spot in pairs(facility.parkingSpots.general) do
            if spot.pos then
              table.insert(parkingList, { pos = spot.pos, name = spotId })
            end
          end
        end
      end
      if #parkingList > 0 then
        cachedParkingSites = parkingList
        log("I", logTag, "Found " .. #parkingList .. " parking spots from freeroam_facilities")
        return cachedParkingSites
      end
    end
  end

  log("W", logTag, "No parking sites found for current level")
  cachedParkingSites = {}
  return cachedParkingSites
end

-- Get the position for a race by finding the RLS staging trigger
local function getRacePosition(raceId)
  log("I", logTag, "getRacePosition called for: " .. tostring(raceId))

  local raceConfig = raceLocations[raceId]
  if not raceConfig then
    log("W", logTag, "Unknown race ID: " .. tostring(raceId))
    return nil
  end

  -- Try to find the RLS staging trigger for this race
  if raceConfig.rlsRace then
    local triggerName = "fre_staging_" .. raceConfig.rlsRace
    log("I", logTag, "Looking for trigger: " .. triggerName)

    local trigger = scenetree.findObject(triggerName)
    if trigger then
      local pos = trigger:getPosition()
      log("I", logTag, "Found trigger at: " .. tostring(pos.x) .. ", " .. tostring(pos.y) .. ", " .. tostring(pos.z))
      return pos
    else
      log("W", logTag, "Trigger not found: " .. triggerName)
    end
  end

  -- Fallback to predefined coordinates if available
  if raceConfig.pos then
    local pos = raceConfig.pos
    log("I", logTag, "Using fallback position: " .. pos[1] .. ", " .. pos[2] .. ", " .. pos[3])
    return vec3(pos[1], pos[2], pos[3])
  end

  log("W", logTag, "Race has no position defined: " .. tostring(raceId))
  return nil
end

-- Navigate to a race location
local function navigateToRace(raceId)
  log("I", logTag, "navigateToRace called with: " .. tostring(raceId))

  if not raceId then
    log("W", logTag, "No race ID provided")
    return { success = false, message = "No race ID provided" }
  end

  local raceConfig = raceLocations[raceId]
  if not raceConfig then
    log("W", logTag, "Unknown race: " .. tostring(raceId))
    return { success = false, message = "Unknown race" }
  end

  log("I", logTag, "Found race config: " .. raceConfig.name)

  local position = getRacePosition(raceId)
  if not position then
    log("W", logTag, "Could not find location for race: " .. tostring(raceId))
    return { success = false, message = "Race location not available" }
  end

  log("I", logTag, "Got position: " .. tostring(position.x) .. ", " .. tostring(position.y) .. ", " .. tostring(position.z))

  -- Set waypoint using core_groundMarkers (require lazily)
  local groundMarkers = core_groundMarkers or extensions.core_groundMarkers
  if not groundMarkers then
    -- Try to load it
    local success, gm = pcall(require, 'core/groundMarkers')
    if success then
      groundMarkers = gm
    end
  end

  if groundMarkers and groundMarkers.setPath then
    groundMarkers.setPath(position, { clearPathOnReachingTarget = true })
    log("I", logTag, "Set waypoint to race: " .. raceConfig.name)

    -- Show UI message
    if ui_message then
      ui_message("Navigate to: " .. raceConfig.name, 3, "Career")
    end

    return {
      success = true,
      message = "Navigate to " .. raceConfig.name,
      raceName = raceConfig.name,
      position = { x = position.x, y = position.y, z = position.z },
    }
  else
    log("W", logTag, "core_groundMarkers not available")
    return { success = false, message = "Navigation system not available" }
  end
end

-- Get available races for current phase
local function getAvailableRaces()
  local races = {}

  if state.currentPhase <= 0 then
    return races
  end

  local phaseDef = phaseDefinitions[state.currentPhase]
  if not phaseDef or not phaseDef.requiredRaces then
    return races
  end

  local progress = state.phaseProgress[state.currentPhase] or { completedRaces = {} }
  local completedRaces = progress.completedRaces or {}

  for _, raceId in ipairs(phaseDef.requiredRaces) do
    local raceConfig = raceLocations[raceId] or {}
    local isCompleted = false
    for _, completed in ipairs(completedRaces) do
      if completed == raceId then
        isCompleted = true
        break
      end
    end

    table.insert(races, {
      id = raceId,
      name = raceConfig.name or raceId,
      description = raceConfig.description or "",
      completed = isCompleted,
    })
  end

  return races
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Level names for street racing progression (matches info.json levels)
local levelNames = {
  [1] = "Rookie Racer",
  [2] = "Known Driver",
  [3] = "Street Regular",
  [4] = "Underground Star",
  [5] = "Street Legend",
}

-- Get native street racing progression from BeamNG's career_branches system
local function getNativeStreetRacingProgress()
  local result = {
    level = 1,
    levelName = "Rookie Racer",
    currentXP = 0,
    minXP = 0,
    maxXP = 250,
    totalXP = 0,
    isMaxLevel = false,
  }

  -- Try to get data from native career_branches system
  if not career_branches then
    log("W", logTag, "career_branches not available")
    return result
  end

  -- Get the streetracing skill data
  local skillId = "mysummer-streetracing"
  local skill = career_branches.getBranchById(skillId)

  if not skill then
    log("W", logTag, "Skill not found: " .. skillId)
    return result
  end

  -- Get current XP value
  local attKey = skill.attributeKey or skillId
  local totalXP = 0
  if career_modules_playerAttributes and career_modules_playerAttributes.getAttributeValue then
    totalXP = career_modules_playerAttributes.getAttributeValue(attKey) or 0
  end

  -- Calculate level from XP
  local level, _, _, minXP, maxXP = career_branches.calcBranchLevelFromValue(totalXP, skillId)

  result.level = level or 1
  result.levelName = levelNames[result.level] or ("Level " .. result.level)
  result.totalXP = totalXP
  result.minXP = minXP or 0
  result.maxXP = maxXP or 250
  result.currentXP = totalXP - result.minXP
  result.isMaxLevel = result.level >= 5

  log("I", logTag, string.format("Native progress: Level %d (%s), XP: %d/%d",
    result.level, result.levelName, result.currentXP, result.maxXP - result.minXP))

  return result
end

-- Get career data for UI (formatted for Vue)
local function getCareerData()
  log("I", logTag, "getCareerData called")

  -- Get native street racing progression
  local nativeProgress = getNativeStreetRacingProgress()

  -- Get current phase object (from local state)
  local currentPhaseData = nil
  if state.currentPhase > 0 and phaseDefinitions[state.currentPhase] then
    local phaseDef = phaseDefinitions[state.currentPhase]
    local progress = state.phaseProgress[state.currentPhase] or { wins = 0, completedRaces = {} }
    currentPhaseData = {
      id = state.currentPhase,
      name = phaseDef.name,
      description = phaseDef.description,
      objectives = {
        { text = string.format("Win %d races", phaseDef.requiredWins), completed = progress.wins >= phaseDef.requiredWins },
      },
    }
  end

  -- Format phases as array for Vue
  local phasesArray = {}
  for phaseId, phaseDef in pairs(phaseDefinitions) do
    local progress = state.phaseProgress[phaseId] or {}
    local prereqs = phaseDef.prerequisites or {}

    table.insert(phasesArray, {
      id = phaseId,
      name = phaseDef.name,
      description = phaseDef.description,
      reputationRequired = prereqs.reputationLevel or 0,
      completed = progress.completed == true,
      locked = prereqs.phase and state.currentPhase < prereqs.phase,
    })
  end

  -- Sort by phase ID
  table.sort(phasesArray, function(a, b) return a.id < b.id end)

  -- Get available races for current phase
  local availableRaces = getAvailableRaces()

  return {
    -- Native progression data (from BeamNG's career_branches)
    nativeProgress = nativeProgress,
    -- Legacy reputation data (for backwards compatibility)
    reputation = {
      total = nativeProgress.totalXP,
      tier = nativeProgress.levelName:lower():gsub(" ", "_"),
      level = nativeProgress.level,
      points = nativeProgress.currentXP,
      breakdown = {},
    },
    currentPhase = currentPhaseData,
    phases = phasesArray,
    projectVehicle = state.projectInventoryId,
    availableRaces = availableRaces,
  }
end

-- Get project vehicle inventory ID
local function getProjectVehicleId()
  return state.projectInventoryId
end

-- ============================================================================
-- MODULE LIFECYCLE
-- ============================================================================

local function onExtensionLoaded()
  log("I", logTag, "MySummer Career module loaded")

  -- Override RLS's purchaseDefaultGarage to use Sealbrick instead of Chinatown
  if career_modules_garageManager then
    local originalPurchaseDefaultGarage = career_modules_garageManager.purchaseDefaultGarage
    career_modules_garageManager.purchaseDefaultGarage = function()
      -- Purchase Sealbrick garage instead of the default starter garage
      if career_modules_garageManager.addPurchasedGarage then
        log("I", logTag, "MySummer: Purchasing Sealbrick1058Garage as starting garage")
        career_modules_garageManager.addPurchasedGarage("Sealbrick1058Garage")
      end
    end
    log("I", logTag, "Overrode purchaseDefaultGarage to use Sealbrick1058Garage")
  end
end

local function onCareerActive(enabled)
  if not enabled then
    return
  end

  log("I", logTag, "Initializing MySummer Career...")

  loadState()

  -- Show intro letter on first time
  if not state.hasSeenIntro then
    log("I", logTag, "First time player - showing grandfather's letter intro")

    -- Get current language setting
    local lang = settings.getValue("uiLanguage") or "en-US"
    local isSpanish = lang:find("^es") or lang:find("^spanish")

    local introText, signText, signName, postscript

    if isSpanish then
      -- Spanish version
      introText = "Si estás leyendo esto, es porque hay cosas que ya no puedo decirte mirándote a los ojos.\n\n"
      introText = introText .. "No te pongas triste, chaval. Me voy tranquilo. He vivido una buena vida, llena de errores, grasa bajo las uñas y algún que otro acierto. Y tú has sido la mejor parte de todo eso.\n\n"
      introText = introText .. "¿Te acuerdas del garaje? Tú sentado en aquel taburete de madera que siempre cojeaba, mirándome mientras trasteaba con los coches. Te contaba historias de cuando era joven. Algunas eran verdad. Otras me las inventaba un poco para hacerte reír.\n\n"
      introText = introText .. "El Miramar que hay ahí fuera es tuyo ahora. Tiene muchos kilómetros, sí, pero siempre estuvo bien cuidado. Nunca me dejó tirado. No es rápido ni bonito, pero es un coche honesto. Si lo cuidas, te llevará más lejos de lo que imaginas.\n\n"
      introText = introText .. "En el fondo del garaje, bajo una lona vieja, está el ETK-I. Lo empecé con ilusión, pero nunca tuve tiempo de terminarlo. Siempre había algo más importante. Me gustaría pensar que tú sí lo acabarás. Ese coche está esperando a alguien que crea en él.\n\n"
      introText = introText .. "Hay algo que nunca te conté. Hace muchos años, hojeando el periódico del taller, leí sobre una carrera. La llamaban 'The Big One'. Apenas hablaban de ella, sólo una columna pequeña y un par de nombres. No era segura, ni inteligente... ni siquiera sé si era del todo legal.\n\n"
      introText = introText .. "Iba a correrla. Tenía el coche, tenía las ganas... pero la vida se metió por medio. El trabajo, tu abuela, las responsabilidades. Siempre pensé que habría otra oportunidad. No la hubo.\n\n"
      introText = introText .. "No cometas mi error. No dejes que la vida decida por ti. Si vas a correr, corre de verdad. Si vas a construir algo, hazlo pieza a pieza, aunque tardes.\n\n"
      introText = introText .. "Hazlo por ti.\nY si alguna vez dudas, hazlo también por mí."
      signText = "Te quiere,"
      signName = "El abuelo"
      postscript = "P.D. El dinero que hay en el banco es para ti. No es mucho, pero te servirá para empezar. Gástalo con cabeza... aunque sé que no siempre lo harás."
    else
      -- English version (default)
      introText = "If you're reading this, it's because there are things I can no longer tell you face to face.\n\n"
      introText = introText .. "Don't be sad, kid. I'm leaving in peace. I've lived a good life, full of mistakes, grease under my fingernails, and a few things done right. And you were the best part of all of it.\n\n"
      introText = introText .. "Do you remember the garage? You sitting on that old wooden stool that always wobbled, watching me work on the cars. I used to tell you stories from when I was young. Some were true. Others... I may have exaggerated a bit just to make you laugh.\n\n"
      introText = introText .. "The Miramar outside is yours now. It's got a lot of miles on it, sure, but it was always taken care of. It never let me down. It's not fast or pretty, but it's an honest car. Treat it right, and it'll take you farther than you'd expect.\n\n"
      introText = introText .. "In the back of the garage, under an old tarp, there's an ETK-I. I started it with big plans, but never had the time to finish it. There was always something more important. I'd like to think you will finish it. That car is waiting for someone who believes in it.\n\n"
      introText = introText .. "There's something I never told you. Many years ago, while flipping through an old newspaper at the shop, I read about a race. They called it 'The Big One.' It was barely mentioned, just a small column and a few names. It wasn't safe, it wasn't smart... and I'm not even sure it was completely legal.\n\n"
      introText = introText .. "I was going to race it. I had the car, I had the drive... but life got in the way. Work, your grandmother, responsibilities. I always thought there would be another chance. There wasn't.\n\n"
      introText = introText .. "Don't make the same mistake I did. Don't let life decide for you. If you're going to race, race for real. If you're going to build something, do it piece by piece, even if it takes years.\n\n"
      introText = introText .. "Do it for yourself.\nAnd if you ever hesitate... do it for me too."
      signText = "With all my love,"
      signName = "Grandpa"
      postscript = "P.S. The money in the bank is yours. It's not much, but it'll get you started. Spend it wisely... though I know you won't always."
    end

    -- Get Chapter 1 data from the skill
    local chapter1Data = nil
    local branch = career_branches and career_branches.getBranchById("mysummer-streetracing")
    if branch and branch.levels and branch.levels[1] and branch.levels[1].storyText then
      local lang = getCurrentLang()
      local langData = branch.levels[1].storyText[lang] or branch.levels[1].storyText.en
      if langData then
        chapter1Data = {
          name = langData.name,
          intro = langData.intro,
        }
      end
    end

    -- Queue the intro to show after a delay (let player see the world first)
    state.pendingIntro = {
      data = {
        storyText = introText,
        signText = signText,
        signName = signName,
        postscript = postscript,
        chapter1Data = chapter1Data,  -- Include Chapter I data
        language = getCurrentLang(),  -- Pass language for Vue components
      },
      delayRemaining = 5.0,  -- Wait 5 seconds before showing the letter
    }
    log("I", logTag, "Queued grandfather's letter intro (showing in 5s)")
  end

  log("I", logTag, "MySummer Career initialized - Phase: " .. state.currentPhase .. ", Level: " .. state.reputation.level)
end

-- Called from Vue when intro is dismissed
local function markIntroSeen()
  state.hasSeenIntro = true
  saveState()
  log("I", logTag, "Intro marked as seen")
end

-- Debug function to reset intro (call from console: career_modules_mysummerCareer.resetIntro())
local function resetIntro()
  state.hasSeenIntro = false
  state.pendingIntro = nil
  saveState()
  log("I", logTag, "Intro reset - will show on next career load")
  print("MySummer: Intro reset. Reload career to see the grandfather's letter.")
end

-- ============================================================================
-- COMPUTER INTEGRATION
-- ============================================================================

local function onComputerAddFunctions(menuData, computerFunctions)
  if menuData and menuData.computerFacility and menuData.computerFacility.garageId then
    computerFunctions.general.mysummerCareer = {
      id = "mysummerCareer",
      label = "Career Progress",
      callback = function()
        log("I", logTag, "Career Progress callback triggered, navigating to mysummer-career")
        if guihooks then
          guihooks.trigger("ChangeState", { state = "mysummer-career" })
        end
      end,
      order = 14
    }
  end
end

-- ============================================================================
-- UPDATE LOOP
-- ============================================================================

local function onUpdate(dtReal, dtSim, dtRaw)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Process pending AI configurations
  if #state.pendingAIConfigs > 0 then
    local stillPending = {}
    for _, pending in ipairs(state.pendingAIConfigs) do
      pending.delay = pending.delay - dtReal
      if pending.delay <= 0 then
        -- Configure AI now
        local veh = be:getObjectByID(pending.vehId)
        if veh then
          veh:queueLuaCommand("ai.setMode('manual')")
          veh:queueLuaCommand("ai.setAvoidCars('on')")
          veh:queueLuaCommand("ai.setSpeedMode('off')")
          veh:queueLuaCommand("ai.setAggression(" .. pending.config.aggression .. ")")

          if pending.config.aiPath then
            local pathStr = serialize(pending.config.aiPath)
            veh:queueLuaCommand("ai.setPath(" .. pathStr .. ")")
          end

          log("I", logTag, "AI opponent configured: " .. pending.vehId)
        end
      else
        table.insert(stillPending, pending)
      end
    end
    state.pendingAIConfigs = stillPending
  end

  -- Process pending phase transition (show after native UI closes)
  if state.pendingPhaseTransition then
    state.pendingPhaseTransition.delayRemaining = state.pendingPhaseTransition.delayRemaining - dtReal
    if state.pendingPhaseTransition.delayRemaining <= 0 then
      log("I", logTag, "Showing delayed phase transition popup")
      guihooks.trigger("mysummerPhaseTransition", state.pendingPhaseTransition.data)
      state.pendingPhaseTransition = nil
    end
  end

  -- Process pending intro (grandfather's letter)
  if state.pendingIntro then
    state.pendingIntro.delayRemaining = state.pendingIntro.delayRemaining - dtReal
    if state.pendingIntro.delayRemaining <= 0 then
      log("I", logTag, "Showing grandfather's letter intro")
      guihooks.trigger("mysummerShowIntro", state.pendingIntro.data)
      state.pendingIntro = nil
    end
  end

  -- Process pending story scene sequences
  if state.pendingSceneSequences and #state.pendingSceneSequences > 0 then
    local current = state.pendingSceneSequences[1]
    current.delayRemaining = current.delayRemaining - dtReal
    if current.delayRemaining <= 0 then
      log("I", logTag, "Showing scene sequence: " .. tostring(current.id))
      showSceneSequence(current.id)
      table.remove(state.pendingSceneSequences, 1)
    end
  end
end

-- ============================================================================
-- RLS RACE COMPLETION DETECTION (via XP rewards)
-- ============================================================================

-- Race types that give XP when completing RLS races
local raceXPTypes = {
  rally = true,
  drift = true,
  motorsport = true,
  offroad = true,
  drag = true,
}

-- Track recently awarded reputation to avoid duplicates
local recentRaceRewards = {}

-- Listen for player attribute changes (XP from RLS races)
local function onPlayerAttributesChanged(change, reason)
  if not career_career or not career_career.isActive() then
    return
  end

  -- Check if this is a race reward (has gameplay/reward/mission tags or race type XP)
  local isRaceReward = false
  local raceType = nil
  local raceLabel = reason and reason.label or ""

  -- Check for race type XP in the change
  for attrType, _ in pairs(change) do
    if raceXPTypes[attrType] then
      isRaceReward = true
      raceType = attrType
      break
    end
  end

  if not isRaceReward then
    return
  end

  -- Avoid duplicate rewards (same label within 5 seconds)
  local now = os.time()
  if recentRaceRewards[raceLabel] and (now - recentRaceRewards[raceLabel]) < 5 then
    log("I", logTag, "Skipping duplicate race reward: " .. raceLabel)
    return
  end
  recentRaceRewards[raceLabel] = now

  -- Clean up old entries
  for label, time in pairs(recentRaceRewards) do
    if (now - time) > 60 then
      recentRaceRewards[label] = nil
    end
  end

  log("I", logTag, "Detected RLS race completion via XP: " .. raceLabel .. " (type: " .. tostring(raceType) .. ")")

  -- Extract race name from label (format: "Race Label - Time: XX:XX" or "Race Label - New Best Time!")
  local raceName = raceLabel:match("^([^%-]+)") or raceLabel
  raceName = raceName:gsub("%s+$", "")  -- Trim trailing spaces

  -- Find matching race in our mapping
  local matchedRace = nil
  local matchedReward = 0

  for rlsName, raceData in pairs(rlsRaceMapping) do
    if raceData.label == raceName then
      matchedRace = rlsName
      matchedReward = raceData.reputationReward
      break
    end
  end

  -- If not found by label, try to match by type
  if not matchedRace and raceType then
    -- Give a generic reward based on type
    local typeRewards = {
      rally = 200,
      drift = 200,
      motorsport = 250,
      offroad = 150,
      drag = 100,
    }
    matchedReward = typeRewards[raceType] or 150
    log("I", logTag, "Using generic reward for race type: " .. raceType)
  end

  if matchedReward > 0 then
    -- Check for new best time bonus
    local isNewBest = raceLabel:find("New Best") ~= nil
    if isNewBest then
      matchedReward = math.floor(matchedReward * 1.25)
    end

    addReputationPoints(matchedReward, "Carrera completada: " .. raceName)

    -- Show notification
    if ui_message then
      ui_message(string.format("+%d Reputación - %s", matchedReward, raceName), 4, "Career", "success")
    end

    -- Check if this race counts toward phase progress
    if matchedRace and state.currentPhase > 0 then
      local phaseRaceId, _ = findMappedPhaseRace(matchedRace)
      if phaseRaceId then
        log("I", logTag, "Race maps to phase race: " .. phaseRaceId .. " - counting as WIN")

        -- Treat completion as a win for phase progress
        local eventData = {
          eventType = "race",
          raceId = phaseRaceId,
          position = 1,  -- Completed = win (RLS races are time trials, completion = success)
          time = nil,
        }
        onFreeroamEventCompleted(eventData)
      end
    end
  end
end

-- ============================================================================
-- SKILL LEVEL UP HANDLER (Narrative Transitions)
-- ============================================================================

-- Called when player reaches a new tier/level in any branch/skill
local function onBranchTierReached(branchId, newTier)
  -- Only handle mysummer-streetracing skill
  if branchId ~= "mysummer-streetracing" then
    return
  end

  log("I", logTag, "Player reached tier " .. newTier .. " in mysummer-streetracing!")

  -- Get the skill data to access storyText
  local branch = career_branches.getBranchById(branchId)
  if not branch or not branch.levels then
    log("W", logTag, "Could not get branch data for " .. branchId)
    return
  end

  -- Tiers are 1-indexed, levels array is 1-indexed too
  local levelData = branch.levels[newTier]
  if not levelData then
    log("W", logTag, "No level data for tier " .. newTier)
    return
  end

  -- Check if this level has storyText (our custom narrative data)
  local storyText = levelData.storyText
  if not storyText then
    log("I", logTag, "No storyText for tier " .. newTier .. ", skipping transition")
    return
  end

  -- Get localized text
  local lang = getCurrentLang()
  local langData = storyText[lang] or storyText.en

  if not langData then
    log("W", logTag, "No language data for " .. lang)
    return
  end

  -- Get previous level data for completion text
  local prevLevelData = newTier > 1 and branch.levels[newTier - 1] or nil
  local completionText = nil
  if prevLevelData and prevLevelData.storyText then
    local prevLangData = prevLevelData.storyText[lang] or prevLevelData.storyText.en
    completionText = prevLangData and prevLangData.completion or nil
  end

  -- Check if this is the final tier (The Big One)
  local isFinalTier = newTier >= #branch.levels

  -- Build transition data
  local transitionData = {
    -- Completed level info
    completedLevel = newTier - 1,
    completionText = completionText,
    -- New level info
    newLevel = newTier,
    newLevelName = langData.name,
    newLevelIntro = langData.intro,
    -- Flags
    isFinalLevel = isFinalTier,
    -- Rewards were already given by the branch system
  }

  -- DISABLED: Phase transition popup (now using narrative system)
  -- state.pendingPhaseTransition = {
  --   data = transitionData,
  --   delayRemaining = 4.0,
  -- }

  log("I", logTag, "Tier reached: " .. newTier .. " (" .. (langData.name or "?") .. ") - Popup disabled, using narrative")
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

-- Lifecycle callbacks
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onSetupInventoryFinished = onSetupInventoryFinished
M.onFreeroamEventCompleted = onFreeroamEventCompleted
M.onComputerAddFunctions = onComputerAddFunctions
M.onBeamNGTrigger = onBeamNGTrigger  -- Listen for custom MySummer race triggers
M.onPlayerAttributesChanged = onPlayerAttributesChanged  -- Listen for RLS race XP rewards
M.onBranchTierReached = onBranchTierReached  -- Listen for skill level ups

-- Story/Narrative API
M.markIntroSeen = markIntroSeen
M.resetIntro = resetIntro  -- Debug: reset intro to show grandfather's letter again
M.onUpdate = onUpdate  -- Process pending AI configs and timers

-- Career data API
M.getCareerData = getCareerData
M.getReputation = getReputation
M.getProjectVehicleId = getProjectVehicleId
M.addReputationPoints = addReputationPoints
M.startPhase = startPhase
M.navigateToRace = navigateToRace
M.getAvailableRaces = getAvailableRaces

-- Custom race API
M.startCustomRace = startCustomRace
M.cancelCustomRace = cancelCustomRace
M.endCustomRace = endCustomRace

-- Chapter progression API (for parts unlock gating)
M.recordRaceWin = recordRaceWin
M.getCurrentChapter = getCurrentChapter
M.getCurrentPhase = function() return state.currentPhase or 0 end
M.getTotalRacesWon = getTotalRacesWon
M.getChapterProgress = getChapterProgress

-- Story scene API
M.handleSceneChoice = handleSceneChoice
M.showSceneSequence = showSceneSequence
M.queueSceneSequence = queueSceneSequence
M.debugShowSceneSequence = debugShowSceneSequence
M.debugQueueSceneSequence = debugQueueSceneSequence
M.debugResetSceneFlags = debugResetSceneFlags

return M
