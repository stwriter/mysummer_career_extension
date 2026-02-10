-- MySummer Calls System
-- Walkie-talkie voice calls during races
-- REBUILT FROM NARRATIVA_REEDIT.md (8-PHASE SYSTEM)

local M = {}
M.moduleName = "career_modules_mysummerCalls"

M.dependencies = {
  "career_career",
  "career_saveSystem",
}

local logTag = "mysummerCalls"
local saveFile = "mysummer_calls.json"

-- Forward declarations
local saveState
local loadState

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  -- Incoming call waiting to be answered
  incomingCall = nil,
  incomingTimer = 0,

  -- Active call in progress
  activeCall = nil,
  currentExchangeIndex = 0,
  waitingForChoice = false,

  -- Call history
  completedCalls = {},
  triggeredCalls = {},  -- Track which calls have been triggered (for narrative system)

  -- Settings
  enabled = true,
}

-- Timing
local RING_DURATION = 15        -- Seconds before missed call
local LINE_DISPLAY_TIME = 4.0   -- Seconds per dialogue line
local CALL_DELAY_MIN = 5        -- Min delay before call after trigger
local CALL_DELAY_MAX = 10       -- Max delay

-- ============================================================================
-- CALL DEFINITIONS (FROM NARRATIVA_REEDIT.md)
-- ============================================================================

-- Contact display info
local contactInfo = {
  ghost = { name = "Ghost", icon = "ghost" },
  rook = { name = "Rook", icon = "rook" },
  nova = { name = "Nova", icon = "nova" },
  muscle = { name = "Muscle", icon = "muscle" },
  techie = { name = "Techie", icon = "techie" },
  shadow = { name = "Shadow", icon = "shadow" },
  viper = { name = "Viper", icon = "viper" },
  unknown = { name = "???", icon = "unknown" },
}

-- Calls triggered by narrative events or race events
local eventCalls = {
  -- ========================================================================
  -- PHASE 0: EL PESO DEL SILENCIO
  -- ========================================================================

  -- phase0_race1_post - MOVED TO SMS (mysummerChat.lua) because it has choices

  phase0_race2_pre = {
    id = "call_phase0_race2",
    caller = "ghost",
    priority = "normal",
    dialogue = {
      { speaker = "ghost", text = {es = "Hoy corres contra Rook y Nova.", en = "Today you race against Rook and Nova."} },
      { speaker = "ghost", text = {es = "Él es constante, ella es peligrosa.", en = "He's steady, she's dangerous."} },
      { speaker = "ghost", text = {es = "No dejes que Nova te coma la moral, suele oler el miedo a un kilómetro.", en = "Don't let Nova eat your morale, she usually smells fear from a kilometer away."} },
    }
  },

  phase0_race3_intercept = {
    id = "call_phase0_race3_intercept",
    caller = "rook",
    priority = "urgent",
    isInterception = true,
    dialogue = {
      { speaker = "rook", text = {es = "¡Nova, el chico Miller me ha cerrado el paso!", en = "Nova, the Miller kid cut me off!"} },
      { speaker = "rook", text = {es = "Casi pierdo el control.", en = "I almost lost control."} },
      { speaker = "nova", text = {es = "¡Pues acelera, Rook!", en = "Then accelerate, Rook!"} },
      { speaker = "nova", text = {es = "No me llores por el walkie.", en = "Don't cry to me on the walkie."} },
      { speaker = "nova", text = {es = "Si te gana un novato, no esperes que te espere en la meta.", en = "If a rookie beats you, don't expect me to wait at the finish."} },
    }
  },

  -- ========================================================================
  -- PHASE 1: ORIGINS
  -- ========================================================================

  phase1_race1_during = {
    id = "call_phase1_race1",
    caller = "nova",
    priority = "normal",
    dialogue = {
      { speaker = "nova", text = {es = "¡Mirad ese horizonte!", en = "Look at that horizon!"} },
      { speaker = "nova", text = {es = "Miller, ¿no sientes que este sitio se nos queda pequeño?", en = "Miller, don't you feel like this place is getting small for us?"} },
      { speaker = "nova", text = {es = "Llevo meses diciéndole a Rook que tenemos que buscar retos de verdad en la capital...", en = "I've been telling Rook for months that we need to find real challenges in the capital..."} },
      { speaker = "nova", text = {es = "... pero él se empeña en pulir el mismo coche cada noche en este circuito de pueblo.", en = "... but he insists on polishing the same car every night on this town circuit."} },
      { speaker = "rook", text = {es = "No es 'pulir el coche', Nova. Se llama conocer tus límites.", en = "It's not 'polishing the car', Nova. It's called knowing your limits."} },
      { speaker = "rook", text = {es = "Miller sabe de lo que hablo.", en = "Miller knows what I'm talking about."} },
      { speaker = "rook", text = {es = "Si fuerzas el motor antes de que la temperatura sea la correcta...", en = "If you force the engine before the temperature is right..."} },
      { speaker = "rook", text = {es = "... solo estás comprando un billete para el desguace.", en = "... you're just buying a ticket to the scrapyard."} },
      { speaker = "rook", text = {es = "Ganar una carrera no sirve de nada si revientas la transmisión en la meta.", en = "Winning a race is useless if you blow the transmission at the finish."} },
      { speaker = "nova", text = {es = "Siempre con lo mismo... 'Límites, límites'.", en = "Always the same... 'Limits, limits'."} },
      { speaker = "nova", text = {es = "El abuelo de Miller no llegó a ser quien fue por ser prudente, Rook.", en = "Miller's grandfather didn't become who he was by being cautious, Rook."} },
      { speaker = "nova", text = {es = "El éxito está al otro lado del miedo.", en = "Success is on the other side of fear."} },
      { speaker = "nova", text = {es = "¿Tú qué dices, Miller? ¿Eres de los que cuidan el motor o de los que lo exprimen hasta que grita?", en = "What do you say, Miller? Are you one who takes care of the engine or one who squeezes it until it screams?"} },
    }
  },

  phase1_race2_during = {
    id = "call_phase1_race2",
    caller = "rook",
    priority = "normal",
    dialogue = {
      { speaker = "rook", text = {es = "Escuchad el motor, no solo el viento.", en = "Listen to the engine, not just the wind."} },
      { speaker = "rook", text = {es = "Miller, fíjate en cómo reacciona tu chasis en las transiciones de peso.", en = "Miller, notice how your chassis reacts in weight transitions."} },
      { speaker = "rook", text = {es = "Si aprendes a sentir el momento exacto en el que las gomas muerden el asfalto...", en = "If you learn to feel the exact moment when the tires bite the asphalt..."} },
      { speaker = "rook", text = {es = "... no necesitarás mil caballos para ser el más rápido.", en = "... you won't need a thousand horses to be the fastest."} },
      { speaker = "rook", text = {es = "Nova cree que la velocidad es un don, pero yo creo que es un lenguaje.", en = "Nova thinks speed is a gift, but I think it's a language."} },
      { speaker = "nova", text = {es = "¡Bla, bla, bla!", en = "Blah, blah, blah!"} },
      { speaker = "nova", text = {es = "Menos clases de yoga y más acción, Rook.", en = "Less yoga classes and more action, Rook."} },
      { speaker = "nova", text = {es = "Miller, no le hagas caso. Si ves un hueco, métete.", en = "Miller, don't listen to him. If you see a gap, take it."} },
      { speaker = "nova", text = {es = "El asfalto es de quien lo pisa primero.", en = "The asphalt belongs to who steps on it first."} },
      { speaker = "nova", text = {es = "Rook analiza tanto la pista que a veces se olvida de que esto es una competición...", en = "Rook analyzes the track so much that sometimes he forgets this is a competition..."} },
      { speaker = "nova", text = {es = "... no un examen de ingeniería.", en = "... not an engineering exam."} },
      { speaker = "rook", text = {es = "No me olvido de nada, Nova.", en = "I don't forget anything, Nova."} },
      { speaker = "rook", text = {es = "Solo intento que todos volvamos a casa en una pieza.", en = "I'm just trying to make sure we all get home in one piece."} },
      { speaker = "rook", text = {es = "Miller, ignora sus gritos y busca tu ritmo.", en = "Miller, ignore her screaming and find your rhythm."} },
      { speaker = "rook", text = {es = "El coche te dirá cuándo está listo para dar más.", en = "The car will tell you when it's ready to give more."} },
    }
  },

  phase1_race3_pre = {
    id = "call_phase1_race3",
    caller = "ghost",
    priority = "normal",
    dialogue = {
      { speaker = "ghost", text = {es = "Miller, abre bien los oídos.", en = "Miller, open your ears wide."} },
      { speaker = "ghost", text = {es = "Estoy viendo los tiempos de esa parejita y algo no cuadra.", en = "I'm watching that couple's times and something doesn't add up."} },
      { speaker = "ghost", text = {es = "Nova está arriesgando demasiado y Rook está empezando a cubrirle las espaldas de forma peligrosa.", en = "Nova is taking too much risk and Rook is starting to cover her back dangerously."} },
      { speaker = "ghost", text = {es = "Se están volviendo predecibles porque están más pendientes el uno del otro que de la carretera.", en = "They're becoming predictable because they're more aware of each other than the road."} },
      { speaker = "ghost", text = {es = "Es tu oportunidad de marcar distancia.", en = "It's your chance to mark distance."} },
      { speaker = "ghost", text = {es = "No te metas en su drama emocional, úsalo.", en = "Don't get into their emotional drama, use it."} },
      { speaker = "ghost", text = {es = "Si Nova se lanza, deja que se pase de frenada.", en = "If Nova lunges, let her overshoot the braking."} },
      { speaker = "ghost", text = {es = "Si Rook se cierra, busca el interior.", en = "If Rook closes, look for the inside."} },
      { speaker = "ghost", text = {es = "Tu abuelo siempre decía: 'En la pista, el único amigo que tienes es el volante'.", en = "Your grandfather always said: 'On the track, the only friend you have is the steering wheel'."} },
    }
  },

  -- ========================================================================
  -- PHASE 2: THE SPLIT
  -- ========================================================================

  phase2_race1_during = {
    id = "call_phase2_race1",
    caller = "nova",
    priority = "urgent",
    dialogue = {
      { speaker = "nova", text = {es = "¡Rook, deja de cerrar el paso!", en = "Rook, stop blocking!"} },
      { speaker = "nova", text = {es = "Miller tiene mejor línea que tú, déjale espacio si no puedes mantener el ritmo.", en = "Miller has a better line than you, give him space if you can't keep up."} },
      { speaker = "nova", text = {es = "Esto no es un paseo dominical, estamos aquí para ganar, no para hacernos compañía.", en = "This isn't a Sunday drive, we're here to win, not to keep each other company."} },
      { speaker = "rook", text = {es = "¡No estoy cerrando el paso, Nova, estoy protegiendo la trazada porque tus frenos están echando humo!", en = "I'm not blocking, Nova, I'm protecting the line because your brakes are smoking!"} },
      { speaker = "rook", text = {es = "Si sigues entrando así de pasado, te vas a quedar sin pastillas antes de la mitad del tramo.", en = "If you keep entering that late, you'll run out of pads before halfway."} },
      { speaker = "rook", text = {es = "¡Miller, no le sigas el juego, va a acabar mal!", en = "Miller, don't play her game, it's going to end badly!"} },
      { speaker = "nova", text = {es = "¡Mis frenos están bien!", en = "My brakes are fine!"} },
      { speaker = "nova", text = {es = "Lo que pasa es que tú tienes miedo de que Miller vea que te has quedado estancado.", en = "What's happening is you're afraid Miller will see you've stagnated."} },
      { speaker = "nova", text = {es = "Miller, si tienes lo que hay que tener, sígueme.", en = "Miller, if you have what it takes, follow me."} },
      { speaker = "nova", text = {es = "Vamos a enseñar de qué es capaz un motor de verdad cuando no lo castran con 'precaución'.", en = "Let's show what a real engine is capable of when it's not castrated with 'caution'."} },
    }
  },

  phase2_race2_during = {
    id = "call_phase2_race2",
    caller = "ghost",
    priority = "normal",
    dialogue = {
      { speaker = "ghost", text = {es = "Miller, ¿has visto el muscle car que se ha unido a esta carrera?", en = "Miller, did you see the muscle car that joined this race?"} },
      { speaker = "ghost", text = {es = "Es Muscle.", en = "It's Muscle."} },
      { speaker = "ghost", text = {es = "Ella no suele salir de su cueva a menos que vea algo que le interese...", en = "She doesn't usually leave her cave unless she sees something that interests her..."} },
      { speaker = "ghost", text = {es = "... y ha venido con su peor coche.", en = "... and she came with her worst car."} },
      { speaker = "ghost", text = {es = "Su padre murió en el accidente que hizo que tu abuelo dejara las llaves inglesas.", en = "Her father died in the accident that made your grandfather drop the wrenches."} },
      { speaker = "ghost", text = {es = "Ella no guarda rencor, pero tampoco regala respeto.", en = "She doesn't hold a grudge, but she doesn't give away respect either."} },
      { speaker = "ghost", text = {es = "Si quieres que te tome en serio, no hagas ninguna estupidez técnica.", en = "If you want her to take you seriously, don't make any technical mistakes."} },
      { speaker = "ghost", text = {es = "Conduce limpio, como lo haría Miller si no tuviera el alma rota.", en = "Drive clean, as Miller would if he didn't have a broken soul."} },
    }
  },

  phase2_race3_during = {
    id = "call_phase2_race3",
    caller = "rook",
    priority = "urgent",
    dialogue = {
      { speaker = "rook", text = {es = "Miller, escúchame bien.", en = "Miller, listen carefully."} },
      { speaker = "rook", text = {es = "He intentado hablar con Nova, pero ya no me escucha.", en = "I've tried to talk to Nova, but she doesn't listen to me anymore."} },
      { speaker = "rook", text = {es = "Cree que puede saltarse las fases de preparación y entrar directa en las grandes ligas de la capital.", en = "She thinks she can skip the preparation phases and go straight to the big leagues in the capital."} },
      { speaker = "rook", text = {es = "Tú tienes influencia sobre ella ahora... dile que es una locura.", en = "You have influence over her now... tell her it's crazy."} },
      { speaker = "rook", text = {es = "Los coches de allí no son como los nuestros, son máquinas de matar si no sabes lo que haces.", en = "The cars there aren't like ours, they're killing machines if you don't know what you're doing."} },
      { speaker = "nova", text = {es = "¡Deja de hablar por él, Rook!", en = "Stop speaking for him, Rook!"} },
      { speaker = "nova", text = {es = "Miller sabe que tengo razón.", en = "Miller knows I'm right."} },
      { speaker = "nova", text = {es = "Si nos quedamos aquí, acabaremos siendo como el abuelo de Miller...", en = "If we stay here, we'll end up like Miller's grandfather..."} },
      { speaker = "nova", text = {es = "... leyendas de un garaje que nadie visita.", en = "... legends of a garage no one visits."} },
      { speaker = "nova", text = {es = "Yo me voy, con o sin vosotros.", en = "I'm leaving, with or without you."} },
      { speaker = "nova", text = {es = "Miller, piénsalo. Hay un mundo ahí fuera esperándonos.", en = "Miller, think about it. There's a world out there waiting for us."} },
      { speaker = "rook", text = {es = "¡No se trata de irse, Nova, se trata de sobrevivir al viaje!", en = "It's not about leaving, Nova, it's about surviving the journey!"} },
      { speaker = "rook", text = {es = "Miller, por favor, razona con ella antes de que destroce todo lo que hemos construido.", en = "Miller, please, reason with her before she destroys everything we've built."} },
    }
  },

  -- ========================================================================
  -- PHASE 3: THE CRISIS
  -- ========================================================================

  phase3_race1_during = {
    id = "call_phase3_race1",
    caller = "nova",
    priority = "normal",
    dialogue = {
      { speaker = "nova", text = {es = "¡Miller, mira cómo entra Rook en la curva!", en = "Miller, look how Rook enters the corner!"} },
      { speaker = "nova", text = {es = "Está frenando demasiado pronto, tiene miedo de que las ruedas sufran.", en = "He's braking too early, he's afraid the wheels will suffer."} },
      { speaker = "nova", text = {es = "¡Así no se gana!", en = "That's not how you win!"} },
      { speaker = "nova", text = {es = "Si quieres llegar arriba, tienes que confiar en que todo aguantará.", en = "If you want to reach the top, you have to trust that everything will hold."} },
      { speaker = "nova", text = {es = "¡Sígueme a mí, olvida su manual de seguridad!", en = "Follow me, forget his safety manual!"} },
      { speaker = "rook", text = {es = "¡No es miedo, Nova, es gestión!", en = "It's not fear, Nova, it's management!"} },
      { speaker = "rook", text = {es = "Miller, si entras como ella, acabarás con los neumáticos achicharrados en una vuelta.", en = "Miller, if you enter like her, you'll end up with charred tires in one lap."} },
      { speaker = "rook", text = {es = "Nova cree que la suerte es un componente del coche, pero yo prefiero la mecánica.", en = "Nova thinks luck is a car component, but I prefer mechanics."} },
      { speaker = "rook", text = {es = "¡Mantén tu trazada y no dejes que su agresividad te desubique!", en = "Keep your line and don't let her aggression unsettle you!"} },
      { speaker = "nova", text = {es = "¡La suerte es para los que no tienen talento, Rook!", en = "Luck is for those without talent, Rook!"} },
      { speaker = "nova", text = {es = "Miller, si no arriesgas ahora que somos jóvenes, ¿cuándo lo vas a hacer?", en = "Miller, if you don't take risks now while we're young, when will you?"} },
      { speaker = "nova", text = {es = "¿Cuando seas un viejo encerrado en un garaje como Miller?", en = "When you're an old man locked in a garage like Miller?"} },
    }
  },

  phase3_race2_during = {
    id = "call_phase3_race2",
    caller = "ghost",
    priority = "normal",
    dialogue = {
      { speaker = "ghost", text = {es = "Miller, escucha el motor.", en = "Miller, listen to the engine."} },
      { speaker = "ghost", text = {es = "Tu abuelo y Viper eran el equipo perfecto porque él ponía la lógica y ella ponía la rabia.", en = "Your grandfather and Viper were the perfect team because he provided logic and she provided rage."} },
      { speaker = "ghost", text = {es = "Pero Rook y Nova... ellos no encajan.", en = "But Rook and Nova... they don't fit."} },
      { speaker = "ghost", text = {es = "Ella quiere ser Viper sin tener a un Miller detrás...", en = "She wants to be Viper without having a Miller behind her..."} },
      { speaker = "ghost", text = {es = "... y Rook quiere ser Miller sin tener a una Viper que sepa cuándo frenar.", en = "... and Rook wants to be Miller without having a Viper who knows when to brake."} },
      { speaker = "ghost", text = {es = "Estás viendo un desastre anunciado.", en = "You're watching a disaster waiting to happen."} },
      { speaker = "ghost", text = {es = "Asegúrate de no estar demasiado cerca cuando ocurra el impacto.", en = "Make sure you're not too close when the impact happens."} },
    }
  },

  phase3_race3_during = {
    id = "call_phase3_race3_nova",
    caller = "nova",
    priority = "normal",
    dialogue = {
      { speaker = "nova", text = {es = "Rook se ha quedado atrás gestionando neumáticos... siempre igual.", en = "Rook's fallen behind managing tires... always the same."} },
      { speaker = "nova", text = {es = "Ahora estamos fuera del alcance de su radio, escucha Miller...", en = "Now we're out of his radio range, listen Miller..."} },
      { speaker = "nova", text = {es = "He estado hablando con gente de la capital.", en = "I've been talking to people in the capital."} },
      { speaker = "nova", text = {es = "Dicen que allí buscan pilotos con tu perfil.", en = "They say they're looking for drivers with your profile there."} },
      { speaker = "nova", text = {es = "Rook no quiere ir, dice que no estamos listos.", en = "Rook doesn't want to go, he says we're not ready."} },
      { speaker = "nova", text = {es = "Pero yo sé que tú sí lo estás.", en = "But I know you are."} },
      { speaker = "nova", text = {es = "Piénsalo: tú, yo, y un circuito de verdad.", en = "Think about it: you, me, and a real circuit."} },
      { speaker = "nova", text = {es = "Sin sermones sobre la temperatura del aceite.", en = "Without sermons about oil temperature."} },
      { speaker = "rook", text = {es = "¿De qué estáis hablando?", en = "What are you talking about?"} },
      { speaker = "rook", text = {es = "Os habéis alejado mucho.", en = "You've gone too far."} },
      { speaker = "rook", text = {es = "Miller, ¿está todo bien con el coche?", en = "Miller, is everything okay with the car?"} },
      { speaker = "rook", text = {es = "He notado demasiado balanceo en tu culo al salir de la última curva.", en = "I noticed too much sway in your rear coming out of the last corner."} },
      { speaker = "nova", text = {es = "¡Todo está bien, Rook!", en = "Everything's fine, Rook!"} },
      { speaker = "nova", text = {es = "Deja de analizarlo todo y conduce.", en = "Stop analyzing everything and drive."} },
    }
  },

  -- ========================================================================
  -- PHASE 4: THE SPLIT (RUPTURA FINAL)
  -- ========================================================================

  phase4_race1_during = {
    id = "call_phase4_race1",
    caller = "nova",
    priority = "urgent",
    dialogue = {
      { speaker = "nova", text = {es = "¡Maldita sea!", en = "Damn it!"} },
      { speaker = "nova", text = {es = "Miller, algo le pasa al turbo.", en = "Miller, something's wrong with the turbo."} },
      { speaker = "nova", text = {es = "El coche empuja como un demonio pero suena como si fuera a desintegrarse.", en = "The car pushes like a demon but sounds like it's going to disintegrate."} },
      { speaker = "nova", text = {es = "¡Rook, no te acerques, voy a intentar una maniobra por el exterior!", en = "Rook, don't get close, I'm going to try a maneuver on the outside!"} },
      { speaker = "rook", text = {es = "¡Nova, frena!", en = "Nova, brake!"} },
      { speaker = "rook", text = {es = "Estás echando fuego por el escape.", en = "You're shooting fire from the exhaust."} },
      { speaker = "rook", text = {es = "Eso no es un ajuste estándar, ¿qué le has hecho al motor?", en = "That's not a standard adjustment, what did you do to the engine?"} },
      { speaker = "rook", text = {es = "Miller, ¿tú sabes algo de esto?", en = "Miller, do you know anything about this?"} },
      { speaker = "rook", text = {es = "Lleváis un par de noches actuando de forma rara los dos.", en = "You've both been acting strange for a couple nights."} },
      { speaker = "nova", text = {es = "¡No le he hecho nada que no fuera necesario, Rook!", en = "I didn't do anything that wasn't necessary, Rook!"} },
      { speaker = "nova", text = {es = "¡Cállate y conduce!", en = "Shut up and drive!"} },
      { speaker = "nova", text = {es = "Miller, si me ves perder tracción, no frenes, ¡pásame y gana tú!", en = "Miller, if you see me lose traction, don't brake, pass me and you win!"} },
      { speaker = "nova", text = {es = "No dejes que él tenga razón sobre 'sus límites'.", en = "Don't let him be right about 'his limits'."} },
      { speaker = "rook", text = {es = "¡No se trata de tener razón, se trata de que vas a gripar el motor!", en = "It's not about being right, it's about you're going to seize the engine!"} },
      { speaker = "rook", text = {es = "¡Miller, dile que pare antes de que vaya a peor!", en = "Miller, tell her to stop before it gets worse!"} },
    }
  },

  phase4_race2_during = {
    id = "call_phase4_race2",
    caller = "rook",
    priority = "normal",
    dialogue = {
      { speaker = "rook", text = {es = "Miller, escúchame bien.", en = "Miller, listen carefully."} },
      { speaker = "rook", text = {es = "He revisado el registro de telemetría de Nova.", en = "I've reviewed Nova's telemetry log."} },
      { speaker = "rook", text = {es = "Esos picos de potencia no son de Techie, ni de Muscle.", en = "Those power spikes aren't from Techie or Muscle."} },
      { speaker = "rook", text = {es = "Son de Shadow, ¿verdad?", en = "They're from Shadow, right?"} },
      { speaker = "rook", text = {es = "Dime la verdad.", en = "Tell me the truth."} },
      { speaker = "rook", text = {es = "Ella no me lo dirá, pero a ti te respeta.", en = "She won't tell me, but she respects you."} },
      { speaker = "rook", text = {es = "Si ella se mete en el mercado negro, no hay vuelta atrás.", en = "If she gets into the black market, there's no going back."} },
      { speaker = "rook", text = {es = "Ghost me ha dicho que Shadow no solo vende piezas, vende deudas.", en = "Ghost told me Shadow doesn't just sell parts, he sells debts."} },
      { speaker = "rook", text = {es = "No dejes que ella se hunda sola.", en = "Don't let her sink alone."} },
      { speaker = "ghost", text = {es = "Rook, deja de llorar.", en = "Rook, stop crying."} },
      { speaker = "ghost", text = {es = "Miller tiene que elegir su propio camino.", en = "Miller has to choose his own path."} },
      { speaker = "ghost", text = {es = "El abuelo Miller también tuvo que elegir entre la seguridad de su taller y la ambición de Viper.", en = "Grandfather Miller also had to choose between the safety of his workshop and Viper's ambition."} },
      { speaker = "ghost", text = {es = "Ya sabemos cómo acabó eso.", en = "We already know how that ended."} },
      { speaker = "ghost", text = {es = "Miller, el asfalto está frío hoy.", en = "Miller, the asphalt is cold today."} },
      { speaker = "ghost", text = {es = "Decide si vas a ser el que empuje a Nova al abismo o el que intente sujetarla.", en = "Decide if you're going to be the one who pushes Nova to the abyss or the one who tries to hold her."} },
    }
  },

  phase4_race3_explosion = {
    id = "call_phase4_race3_explosion",
    caller = "rook",
    priority = "urgent",
    dialogue = {
      { speaker = "rook", text = {es = "¡Lo he visto, Miller!", en = "I saw it, Miller!"} },
      { speaker = "rook", text = {es = "He visto el nombre de Shadow en el móvil de Nova.", en = "I saw Shadow's name on Nova's phone."} },
      { speaker = "rook", text = {es = "¡Nova, eres una idiota!", en = "Nova, you're an idiot!"} },
      { speaker = "rook", text = {es = "¿Sabes lo que le hacen a los que no pueden pagar esas piezas?", en = "Do you know what they do to those who can't pay for those parts?"} },
      { speaker = "rook", text = {es = "¿Qué estás haciendo?", en = "What are you doing?"} },
      { speaker = "nova", text = {es = "¡Lo que me da la gana, Rook!", en = "Whatever I want, Rook!"} },
      { speaker = "nova", text = {es = "¡Estoy harta de tu proteccionismo barato!", en = "I'm sick of your cheap protectionism!"} },
      { speaker = "nova", text = {es = "Miller y yo queremos salir de aquí, queremos ser algo más que leyendas de gasolinera.", en = "Miller and I want to get out of here, we want to be more than gas station legends."} },
      { speaker = "nova", text = {es = "¡Si no puedes seguirnos, apártate de nuestra puta trazada!", en = "If you can't follow us, get out of our fucking line!"} },
      { speaker = "rook", text = {es = "¡Bien!", en = "Fine!"} },
      { speaker = "rook", text = {es = "¡Haz lo que quieras!", en = "Do whatever you want!"} },
      { speaker = "rook", text = {es = "¡Miller, si te vas con ella, olvida que alguna vez te cubrí las espaldas!", en = "Miller, if you go with her, forget I ever had your back!"} },
      { speaker = "rook", text = {es = "¡A partir de ahora, solo sois dos coches más en mi retrovisor!", en = "From now on, you're just two more cars in my rearview!"} },
    }
  },

  -- ========================================================================
  -- PHASE 5: RALLY REGIONAL (POLVO Y TRAICIÓN)
  -- ========================================================================

  phase5_rally1_during = {
    id = "call_phase5_rally1",
    caller = "ghost",
    priority = "normal",
    dialogue = {
      { speaker = "ghost", text = {es = "Miller, el ETK-I suena exactamente como lo planeó tu abuelo hace treinta años.", en = "Miller, the ETK-I sounds exactly as your grandfather planned thirty years ago."} },
      { speaker = "ghost", text = {es = "Es estremecedor.", en = "It's thrilling."} },
      { speaker = "ghost", text = {es = "No dejes que el éxito se te suba a la cabeza...", en = "Don't let success go to your head..."} },
      { speaker = "ghost", text = {es = "... la tierra perdona menos que el asfalto.", en = "... dirt is less forgiving than asphalt."} },
      { speaker = "ghost", text = {es = "Rook y Nova están en la meta esperándote...", en = "Rook and Nova are at the finish waiting for you..."} },
      { speaker = "ghost", text = {es = "... aunque no se han mirado a la cara en todo el día.", en = "... though they haven't looked at each other all day."} },
    }
  },

  phase5_rally2_during = {
    id = "call_phase5_rally2",
    caller = "nova",
    priority = "normal",
    dialogue = {
      { speaker = "nova", text = {es = "¡Ese tiempo ha sido increíble, Miller!", en = "That time was incredible, Miller!"} },
      { speaker = "nova", text = {es = "Shadow dice que si ganas este rally, el ETK-I valdrá el triple en la capital.", en = "Shadow says if you win this rally, the ETK-I will be worth triple in the capital."} },
      { speaker = "nova", text = {es = "Podríamos largarnos de aquí mañana mismo.", en = "We could get out of here tomorrow."} },
      { speaker = "nova", text = {es = "Olvida los circuitos regionales, vamos a por el dinero de verdad.", en = "Forget regional circuits, let's go for the real money."} },
      { speaker = "rook", text = {es = "¡Para ya, Nova!", en = "Stop it, Nova!"} },
      { speaker = "rook", text = {es = "Miller no está corriendo por el dinero de Shadow.", en = "Miller isn't racing for Shadow's money."} },
      { speaker = "rook", text = {es = "Está corriendo por su abuelo.", en = "He's racing for his grandfather."} },
      { speaker = "rook", text = {es = "Ese coche es una pieza de historia, no una moneda de cambio.", en = "That car is a piece of history, not a bargaining chip."} },
      { speaker = "rook", text = {es = "Miller, no dejes que te convenza de vender tu alma antes de llegar a la Big One.", en = "Miller, don't let her convince you to sell your soul before reaching the Big One."} },
    }
  },

  -- ========================================================================
  -- PHASE 6: EL FONDO DEL POZO (COPA COVET)
  -- ========================================================================

  phase6_covet1_post = {
    id = "call_phase6_covet1",
    caller = "ghost",
    priority = "normal",
    dialogue = {
      { speaker = "ghost", text = {es = "Deja de mirar el retrovisor buscando culpables, Miller.", en = "Stop looking in the rearview for culprits, Miller."} },
      { speaker = "ghost", text = {es = "Ahora mismo eres un don nadie en un coche de 80 caballos.", en = "Right now you're a nobody in an 80-horsepower car."} },
      { speaker = "ghost", text = {es = "Si no ganas esta copa, no habrá Big One, ni ETK-I, ni respuestas.", en = "If you don't win this cup, there will be no Big One, no ETK-I, no answers."} },
      { speaker = "ghost", text = {es = "Concéntrate en el Covet.", en = "Focus on the Covet."} },
      { speaker = "ghost", text = {es = "Es un coche honesto, no como la gente con la que te juntas.", en = "It's an honest car, not like the people you hang out with."} },
    }
  },

  phase6_covet2_intercept = {
    id = "call_phase6_covet2_techie",
    caller = "techie",
    priority = "urgent",
    dialogue = {
      { speaker = "techie", text = {es = "Miller, he estado rastreando la señal del GPS que instalé en el ETK-I antes del rally.", en = "Miller, I've been tracking the GPS signal I installed in the ETK-I before the rally."} },
      { speaker = "techie", text = {es = "Se apagó justo después del golpe.", en = "It shut off right after the hit."} },
      { speaker = "techie", text = {es = "Pero he detectado actividad inusual en la cuenta de Shadow vinculada a (Rook/Nova).", en = "But I've detected unusual activity in Shadow's account linked to (Rook/Nova)."} },
      { speaker = "techie", text = {es = "Alguien ha recibido un pago grande en cripto.", en = "Someone received a large crypto payment."} },
      { speaker = "techie", text = {es = "No quiero sacar conclusiones, pero los datos son... feos.", en = "I don't want to jump to conclusions, but the data is... ugly."} },
    }
  },

  phase6_covet4_during = {
    id = "call_phase6_covet4_shadow",
    caller = "shadow",
    priority = "normal",
    dialogue = {
      { speaker = "shadow", text = {es = "Miller, felicidades por el progreso con esa cafetera japonesa.", en = "Miller, congratulations on the progress with that Japanese coffee maker."} },
      { speaker = "shadow", text = {es = "Me sorprende tu resiliencia.", en = "Your resilience surprises me."} },
      { speaker = "shadow", text = {es = "(Rook/Nova) me dio algo muy valioso a cambio de tu 'libertad' de deudas...", en = "(Rook/Nova) gave me something very valuable in exchange for your 'freedom' from debts..."} },
      { speaker = "shadow", text = {es = "... pero parece que no puedes estar lejos del asfalto.", en = "... but it seems you can't stay away from the asphalt."} },
      { speaker = "shadow", text = {es = "Si ganas esto, te veré en los circuitos oficiales.", en = "If you win this, I'll see you at the official circuits."} },
      { speaker = "shadow", text = {es = "Tengo un mensaje para ti de parte de tu 'amigo/a': 'No es personal, es supervivencia'.", en = "I have a message for you from your 'friend': 'It's not personal, it's survival'."} },
    }
  },

  -- ========================================================================
  -- PHASE 7: EL RASTRO DEL HIERRO (CLASIFICATORIAS)
  -- ========================================================================

  phase7_clasif1_post = {
    id = "call_phase7_clasif1_techie",
    caller = "techie",
    priority = "normal",
    dialogue = {
      { speaker = "techie", text = {es = "Miller, he analizado la transacción.", en = "Miller, I analyzed the transaction."} },
      { speaker = "techie", text = {es = "El dinero salió de una cuenta de Shadow y terminó en un fondo a nombre de tu pareja.", en = "The money came from a Shadow account and ended up in a fund under your partner's name."} },
      { speaker = "techie", text = {es = "No hay duda.", en = "No doubt."} },
      { speaker = "techie", text = {es = "Lo vendieron por piezas para que fuera imposible de rastrear.", en = "They sold it in parts to make it untraceable."} },
      { speaker = "techie", text = {es = "Lo siento, de verdad.", en = "I'm truly sorry."} },
    }
  },

  phase7_clasif3_intercept = {
    id = "call_phase7_clasif3_shadow",
    caller = "shadow",
    priority = "urgent",
    dialogue = {
      { speaker = "shadow", text = {es = "Miller, eres persistente.", en = "Miller, you're persistent."} },
      { speaker = "shadow", text = {es = "Te di una salida limpia y prefieres seguir rascando la herida.", en = "I gave you a clean exit and you prefer to keep scratching the wound."} },
      { speaker = "shadow", text = {es = "Tu pareja fue inteligente; aceptó el trato para que tú pudieras seguir respirando.", en = "Your partner was smart; they accepted the deal so you could keep breathing."} },
      { speaker = "shadow", text = {es = "Si sigues ganando estas clasificatorias, el precio por tu cabeza subirá...", en = "If you keep winning these qualifiers, the price on your head will go up..."} },
      { speaker = "shadow", text = {es = "... más de lo que ellos pueden pagar.", en = "... more than they can pay."} },
    }
  },

  -- ========================================================================
  -- PHASE 8: RECLAMACIÓN Y GLORIA (THE BIG ONE)
  -- ========================================================================

  phase8_duelo_during = {
    id = "call_phase8_duelo_shadow",
    caller = "shadow",
    priority = "urgent",
    dialogue = {
      { speaker = "shadow", text = {es = "¿Lo sientes, Miller?", en = "Do you feel it, Miller?"} },
      { speaker = "shadow", text = {es = "Este coche tiene el alma de un cobarde pero los pulmones de un monstruo.", en = "This car has the soul of a coward but the lungs of a monster."} },
      { speaker = "shadow", text = {es = "Tu abuelo lo construyó para ganar, pero no tenía el pulso para manejarlo.", en = "Your grandfather built it to win, but didn't have the pulse to handle it."} },
      { speaker = "shadow", text = {es = "Yo sí.", en = "I do."} },
      { speaker = "shadow", text = {es = "No es personal, es que este coche merece un piloto que no se detenga ante nada.", en = "It's not personal, it's that this car deserves a driver who won't stop at anything."} },
      { speaker = "shadow", text = {es = "¡Intenta seguirme si puedes!", en = "Try to follow me if you can!"} },
    }
  },

  phase8_bigone_during = {
    id = "call_phase8_bigone",
    caller = "viper",
    priority = "urgent",
    dialogue = {
      { speaker = "viper", text = {es = "¡Muéstrame esa rabia, Miller!", en = "Show me that rage, Miller!"} },
      { speaker = "viper", text = {es = "El ETK-I fue diseñado para este momento.", en = "The ETK-I was designed for this moment."} },
      { speaker = "viper", text = {es = "Tu abuelo nunca tuvo el valor de meter la quinta marcha en esta recta.", en = "Your grandfather never had the courage to shift into fifth on this straight."} },
      { speaker = "viper", text = {es = "¡No frenes ahora!", en = "Don't brake now!"} },
      { speaker = "viper", text = {es = "¡Si quieres respeto, tienes que quitármelo de las manos!", en = "If you want respect, you have to take it from my hands!"} },
      { speaker = "(chosen_partner)", text = {es = "¡Vamos, Miller!", en = "Come on, Miller!"} },
      { speaker = "(chosen_partner)", text = {es = "Todo este camino... el robo, la traición, el Covet... todo era para llegar aquí.", en = "All this way... the theft, the betrayal, the Covet... it was all to get here."} },
      { speaker = "(chosen_partner)", text = {es = "¡Demuéstrales a todos que tenías razón!", en = "Show them all you were right!"} },
    }
  },
}

-- ============================================================================
-- SYSTEM FUNCTIONS (KEEP EXISTING ARCHITECTURE)
-- ============================================================================

-- Helper to get chosen partner ID
local function getChosenPartner()
  local narrative = extensions.career_modules_mysummerNarrative
  if narrative and narrative.getNarrativeProgress then
    local progress = narrative.getNarrativeProgress()
    return progress.storyFlags.chosen_partner or "rook"
  end
  return "rook"
end

-- Replace dynamic placeholders in dialogue
local function replaceDialoguePlaceholders(dialogue)
  local chosenPartner = getChosenPartner()
  local result = {}

  for _, line in ipairs(dialogue) do
    local newLine = {}
    for k, v in pairs(line) do
      if k == "speaker" and v == "(chosen_partner)" then
        newLine[k] = chosenPartner
      elseif k == "text" and type(v) == "table" then
        newLine[k] = {}
        for lang, text in pairs(v) do
          -- Replace (Rook/Nova) with actual chosen partner
          local replaced = text:gsub("%(Rook/Nova%)", chosenPartner == "rook" and "Rook" or "Nova")
          newLine[k][lang] = replaced
        end
      else
        newLine[k] = v
      end
    end
    table.insert(result, newLine)
  end

  return result
end

-- Show incoming call
local function showIncomingCall(call)
  local contact = contactInfo[call.caller] or { name = "Unknown", icon = "unknown" }

  if guihooks and guihooks.trigger then
    guihooks.trigger("mysummerIncomingCall", {
      caller = call.caller,
      callerName = contact.name,
      icon = contact.icon,
      priority = call.priority or "normal",
    })
  end

  log("I", logTag, "Incoming call from: " .. call.caller)
end

-- Answer call
local function answerCall(call)
  -- Replace placeholders before showing
  local processedDialogue = replaceDialoguePlaceholders(call.dialogue)

  state.activeCall = {
    id = call.id,
    caller = call.caller,
    dialogue = processedDialogue,
    currentIndex = 1,
  }

  -- Detect language
  local lang = Steam and Steam.language or "en"

  -- Prepare messages for DialogueOverlay
  local messages = {}
  for i, line in ipairs(processedDialogue) do
    -- Skip choice lines - DialogueOverlay doesn't support decisions
    -- Calls with choices should use StoryScene instead (TODO: future improvement)
    if line.type ~= "choice" then
      local text = type(line.text) == "table" and (lang:find("es") and line.text.es or line.text.en) or line.text

      -- Get speaker info
      local speakerName = contactInfo[line.speaker] and contactInfo[line.speaker].name or "Unknown"

      table.insert(messages, {
        contactId = line.speaker,
        contactName = speakerName,
        content = text,
        emotion = "standard",
        isUnlocked = true
      })
    end
  end

  -- Send as dialogue sequence to DialogueOverlay
  if guihooks and guihooks.trigger and #messages > 0 then
    guihooks.trigger("mysummerDialogueShow", {
      messages = messages
    })
  end

  log("I", logTag, "Call answered: " .. call.id .. " (" .. #messages .. " lines sent to DialogueOverlay)")
end

-- Queue a call with delay
local function queueCall(call, delay)
  delay = delay or math.random(CALL_DELAY_MIN, CALL_DELAY_MAX)

  state.incomingCall = call
  state.incomingTimer = delay

  log("D", logTag, "Queued call: " .. tostring(call.id) .. " (delay: " .. delay .. "s)")
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Called by narrative system when events occur
function M.onNarrativeEvent(eventId)
  if not state.enabled then
    log("D", logTag, "Call system disabled, skipping: " .. tostring(eventId))
    return false
  end

  local call = eventCalls[eventId]
  if not call then
    log("D", logTag, "No call for event: " .. tostring(eventId))
    return false
  end

  -- Check if already triggered (unique calls only)
  if call.id and state.triggeredCalls[call.id] then
    log("D", logTag, "Call already triggered: " .. call.id)
    return false
  end

  -- Mark as triggered before queuing
  if call.id then
    state.triggeredCalls[call.id] = true
    saveState()
  end

  -- Queue with delay
  log("I", logTag, "Queuing call for event: " .. tostring(eventId))
  queueCall(call)
  return true
end

-- Force trigger call (for debugging)
function M.debugForceCall(eventId)
  local call = eventCalls[eventId]
  if not call then
    print("ERROR: Call not found: " .. tostring(eventId))
    return
  end

  showIncomingCall(call)
  answerCall(call)
end

-- Get list of all call IDs
function M.getAllCallIds()
  local ids = {}
  for eventId, call in pairs(eventCalls) do
    table.insert(ids, eventId)
  end
  return ids
end

-- Reset triggered state for a specific event (for race replay)
function M.resetTriggered(eventId)
  local call = eventCalls[eventId]
  if call and call.id then
    state.triggeredCalls[call.id] = nil
    log("D", logTag, "Reset triggered state for call: " .. call.id)
  end
end

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

loadState = function()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath)

  if data then
    state.completedCalls = data.completedCalls or {}
    state.triggeredCalls = data.triggeredCalls or {}
    log("I", logTag, "Loaded call state")
  else
    log("D", logTag, "No saved call state found")
  end
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
    completedCalls = state.completedCalls,
    triggeredCalls = state.triggeredCalls,
  }

  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("D", logTag, "Saved call state")
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onUpdate(dtReal, dtSim, dtRaw)
  -- Update incoming call timer
  if state.incomingCall then
    state.incomingTimer = state.incomingTimer - dtReal

    if state.incomingTimer <= 0 then
      showIncomingCall(state.incomingCall)
      state.incomingCall = nil
      state.incomingTimer = 0
    end
  end
end

local function onExtensionLoaded()
  log("I", logTag, "Call system loaded (8-phase narrative)")
end

local function onCareerActive()
  loadState()
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

-- ============================================================================
-- EXPORTS
-- ============================================================================

M.onUpdate = onUpdate
M.onExtensionLoaded = onExtensionLoaded
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
-- M.onNarrativeEvent is already defined above as function M.onNarrativeEvent()
-- M.debugForceCall is already defined above as function M.debugForceCall()
-- M.getAllCallIds is already defined above as function M.getAllCallIds()

return M
