# DialogueOverlay - Guía de Uso con Avatares e Emociones

## Descripción
Sistema de diálogos en pantalla (overlay inferior) que ahora soporta imágenes de contactos con estados emocionales.

## Formato de Mensajes desde Lua

### Estructura Básica

```lua
-- Desde mysummerChat.lua
career_modules_mysummerChat.showDialogue(contactId, messages)
```

### Mensaje Simple (String)

```lua
career_modules_mysummerChat.showDialogue("ghost", {
  "Tengo un trabajo para ti..."
})
```

### Mensaje con Emoción (Tabla)

```lua
career_modules_mysummerChat.showDialogue("ghost", {
  {
    content = "¡Me has decepcionado!",
    emotion = "angry"
  }
})
```

### Múltiples Mensajes con Diferentes Emociones

```lua
career_modules_mysummerChat.showDialogue("nova", {
  { content = "Hola, necesito un favor...", emotion = "standard" },
  { content = "Es algo... especial.", emotion = "seductive" },
  { content = "¿Me ayudarás?", emotion = "happy" }
})
```

## Estados Emocionales Disponibles

### Para Todos los Contactos
- `standard` - Neutral/estándar (por defecto si no se especifica)
- `happy` - Feliz
- `content` - Satisfecho
- `sad` - Triste
- `angry` - Enojado

### Solo para Nova y Rook
- `seductive` - Seductor

## Contactos con Imágenes

Los siguientes contactos tienen imágenes de avatar:
- `grandfather` - El abuelo
- `ghost` - Contacto misterioso
- `import` - Especialista en imports
- `muscle` - Fanático de muscle cars
- `nova` - Contacto femenino (tiene seductive)
- `rook` - Contacto femenino (tiene seductive)
- `shadow` - Contacto sombrío
- `techie` - Mecánico/técnico
- `viper` - Street racer agresivo

### Contactos sin Imagen
Si usas un contactId que no tiene imágenes (ej: "player", "system"), el sistema mostrará la inicial del nombre como antes.

## Ejemplos de Uso

### 1. Monólogo del Jugador (Sin Imagen)

```lua
-- En mysummerMonologues.lua
career_modules_mysummerChat.showDialogue("player", {
  "\"Necesito conseguir más dinero...\"",
  "\"Quizás debería revisar el mercado de piezas.\""
})
```

### 2. Contacto Feliz por Misión Completada

```lua
local function onMissionComplete()
  career_modules_mysummerChat.showDialogue("techie", {
    {
      content = "¡Excelente trabajo! Sabía que podía contar contigo.",
      emotion = "happy"
    }
  })
end
```

### 3. Contacto Enojado por Misión Fallida

```lua
local function onMissionFailed()
  career_modules_mysummerChat.showDialogue("viper", {
    {
      content = "¡Incompetente! No vuelvas a perder mi tiempo.",
      emotion = "angry"
    }
  })
end
```

### 4. Conversación Cambiando Emociones

```lua
local function showNegotiation()
  career_modules_mysummerChat.showDialogue("muscle", {
    {
      content = "Tengo un trabajo, pero es peligroso.",
      emotion = "standard"
    },
    {
      content = "No sé si estás listo para esto...",
      emotion = "sad"
    },
    {
      content = "¡Pero si lo logras, te pagaré el doble!",
      emotion = "happy"
    }
  })
end
```

### 5. Nova/Rook con Emoción Seductiva

```lua
local function showNovaOffer()
  career_modules_mysummerChat.showDialogue("nova", {
    {
      content = "Necesito que me consigas unas piezas especiales.",
      emotion = "standard"
    },
    {
      content = "Podría hacerte un descuento... especial.",
      emotion = "seductive"
    }
  })
end
```

### 6. Diálogo con Contacto No Desbloqueado

```lua
-- Si el contacto no está desbloqueado (isUnlocked = false)
-- Se mostrará "?" en lugar de la imagen y "???" en el nombre
career_modules_mysummerChat.showDialogue("shadow", {
  "Un trabajo te espera en el warehouse..."
})
-- Nota: Primero desbloquea el contacto con unlockContact()
```

## Integración con Sistema de Historia

### En mysummerStoryRaces.lua

```lua
-- Añadir emoción a los diálogos de historia
local CHAPTER_1_INTRO = {
  en = {
    {
      content = "Welcome to West Coast, kid.",
      emotion = "content"
    },
    {
      content = "Your grandfather left you quite the challenge.",
      emotion = "standard"
    },
    {
      content = "Let's see what you're made of!",
      emotion = "happy"
    }
  },
  es = {
    {
      content = "Bienvenido a West Coast, chico.",
      emotion = "content"
    },
    {
      content = "Tu abuelo te dejó un buen desafío.",
      emotion = "standard"
    },
    {
      content = "¡Veamos de qué estás hecho!",
      emotion = "happy"
    }
  }
}

local function showChapterIntro(chapterId)
  local lang = getCurrentLang()
  local intro = CHAPTER_1_INTRO[lang] or CHAPTER_1_INTRO.en

  career_modules_mysummerChat.showDialogue("grandfather", intro)
end
```

## Integración con Deep Web

### En mysummerDeepWeb.lua

```lua
-- Ejemplo: Reacción del contacto al aceptar/rechazar misión

local function onContactMissionAccepted(contactId)
  local reactions = {
    ghost = {
      content = "Sabía que no me fallarías. Te contacto pronto.",
      emotion = "content"
    },
    viper = {
      content = "¡Así se habla! Vamos a hacer algo de dinero.",
      emotion = "happy"
    },
    shadow = {
      content = "Interesante. Prepárate para lo que viene.",
      emotion = "standard"
    }
  }

  local reaction = reactions[contactId]
  if reaction then
    career_modules_mysummerChat.showDialogue(contactId, { reaction })
  end
end

local function onContactMissionRejected(contactId)
  local reactions = {
    ghost = {
      content = "Decepcionante. Esperaba más de ti.",
      emotion = "sad"
    },
    viper = {
      content = "¡Cobarde! No vuelvas a molestarme.",
      emotion = "angry"
    }
  }

  local reaction = reactions[contactId]
  if reaction then
    career_modules_mysummerChat.showDialogue(contactId, { reaction })
  end
end
```

## Comportamiento del Sistema

### Auto-Advance
- Cada mensaje se escribe con efecto de tipeo (25ms por carácter)
- Después de terminar el tipeo, espera 3 segundos y avanza automáticamente
- Los puntos en la parte inferior indican cuántos mensajes quedan

### Skip Typing
- Actualmente no hay tecla para saltar, pero se puede implementar

### Escape Key
- Presionar `Esc` cierra el diálogo inmediatamente

## Notas de Implementación

- Las imágenes se cargan desde `/ui/images/contacts/{contactId}_{emotion}.png`
- Si no existe imagen para un contacto, se muestra la inicial del nombre
- El sistema es retrocompatible: mensajes string simples funcionan sin cambios
- Emoción por defecto es `standard` si no se especifica
- Las emociones inválidas fallback a `standard` automáticamente

## TODO Futuro

- [ ] Añadir tecla para saltar tipeo (Espacio/Enter)
- [ ] Precarga de imágenes de contactos al inicio
- [ ] Soporte para imágenes del jugador en monólogos
- [ ] Efectos de sonido por emoción
- [ ] Animaciones de transición entre emociones
