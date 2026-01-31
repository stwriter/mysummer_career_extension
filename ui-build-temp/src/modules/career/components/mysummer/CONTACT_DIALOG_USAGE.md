# ContactDialog - Guía de Uso

## Descripción
Componente para mostrar diálogos con avatares de contactos que cambian según el estado emocional.

## Personajes Disponibles
- `grandfather` - El abuelo
- `ghost` - Contacto Ghost
- `import` - Especialista en imports
- `muscle` - Fanático de muscle cars
- `nova` - Contacto femenino Nova (tiene seductive)
- `rook` - Contacto femenino Rook (tiene seductive)
- `shadow` - Contacto Shadow
- `techie` - Mecánico/técnico
- `viper` - Street racer agresivo

## Estados Emocionales
- `standard` - Neutral
- `happy` - Feliz
- `content` - Satisfecho
- `sad` - Triste
- `angry` - Enojado
- `seductive` - Seductor (solo nova y rook)

## Uso desde Vue Store (Pinia)

```javascript
import { addPopup } from "@/services/popup"
import { markRaw } from "vue"
import ContactDialog from "../components/mysummer/ContactDialog.vue"
import { CONTACTS, EMOTIONS } from "../utils/contactImages"

// Ejemplo 1: Diálogo simple con botón continuar
const showSimpleDialog = async () => {
  const popup = addPopup(markRaw(ContactDialog), {
    contactId: CONTACTS.GRANDFATHER,
    contactName: "Abuelo",
    emotion: EMOTIONS.HAPPY,
    dialogText: "¡Bienvenido a West Coast! He preparado algo especial para ti...",
    continueLabel: "Continuar"
  })

  await popup.promise
  console.log("Dialog closed")
}

// Ejemplo 2: Diálogo con opciones
const showChoiceDialog = async () => {
  const popup = addPopup(markRaw(ContactDialog), {
    contactId: CONTACTS.GHOST,
    contactName: "Ghost",
    emotion: EMOTIONS.STANDARD,
    dialogText: "Tengo un trabajo para ti. ¿Estás interesado?",
    choices: [
      { label: "Acepto el trabajo", value: "accept" },
      { label: "No me interesa", value: "decline" },
      { label: "Dime más detalles", value: "info" }
    ]
  })

  popup.promise.then((result) => {
    if (result && result.value) {
      console.log("User chose:", result.value)
      // Manejar la elección del usuario
      if (result.value === 'accept') {
        // Iniciar misión
      }
    }
  })
}

// Ejemplo 3: Diálogo con emoción cambiante
const showDynamicDialog = async () => {
  const emotion = ref(EMOTIONS.STANDARD)

  const popup = addPopup(markRaw(ContactDialog), {
    contactId: CONTACTS.VIPER,
    contactName: "Viper",
    emotion: emotion.value,
    dialogText: "¿Crees que puedes ganarme? ¡Ja!",
  })

  // Cambiar emoción después de 2 segundos
  setTimeout(() => {
    emotion.value = EMOTIONS.ANGRY
  }, 2000)

  await popup.promise
}
```

## Uso desde Lua

### 1. Trigger evento desde Lua

```lua
-- En mysummerDeepWeb.lua o cualquier módulo
local function showContactDialog(contactId, contactName, emotion, text, choices)
  local data = {
    contactId = contactId,
    contactName = contactName,
    emotion = emotion or "standard",
    dialogText = text,
    choices = choices,  -- nil para diálogo simple
  }

  guihooks.trigger("mysummerShowContactDialog", data)
end

-- Ejemplo de uso:
showContactDialog(
  "ghost",
  "Ghost",
  "angry",
  "¡Me has decepcionado! Este no era el trato.",
  nil  -- Sin opciones, solo continuar
)

-- Con opciones:
showContactDialog(
  "nova",
  "Nova",
  "seductive",
  "Podríamos hacer un trato... especial.",
  {
    { label = "Acepto", value = "accept" },
    { label = "No gracias", value = "decline" }
  }
)
```

### 2. Crear handler en Vue Store

```javascript
// En un store (ej: mysummerDialogStore.js)
import { defineStore } from "pinia"
import { useBridge } from "@/bridge"
import { addPopup } from "@/services/popup"
import { markRaw } from "vue"
import ContactDialog from "../components/mysummer/ContactDialog.vue"

export const useMySummerDialogStore = defineStore("mysummerDialog", () => {
  const { events } = useBridge()

  const handleShowContactDialog = async (data) => {
    console.log("[DialogStore] Showing contact dialog:", data)

    const popup = addPopup(markRaw(ContactDialog), {
      contactId: data.contactId,
      contactName: data.contactName,
      emotion: data.emotion || "standard",
      dialogText: data.dialogText,
      choices: data.choices || null,
      continueLabel: data.continueLabel || "Continuar"
    })

    const result = await popup.promise

    // Enviar resultado de vuelta a Lua si hubo una elección
    if (result && result.value && window.bngApi) {
      window.bngApi.engineLua(
        `career_modules_mysummerDeepWeb.handleDialogChoice("${data.contactId}", "${result.value}")`
      )
    }
  }

  // Registrar evento
  events.on("mysummerShowContactDialog", handleShowContactDialog)

  return {
    handleShowContactDialog
  }
})
```

### 3. Handler en Lua para recibir respuesta

```lua
-- En mysummerDeepWeb.lua
local function handleDialogChoice(contactId, choiceValue)
  log("I", logTag, "User chose: " .. choiceValue .. " for contact: " .. contactId)

  if contactId == "ghost" and choiceValue == "accept" then
    -- Iniciar misión de Ghost
    startGhostMission()
  elseif choiceValue == "decline" then
    -- Rechazar oferta
    log("I", logTag, "User declined offer from " .. contactId)
  end
end

M.handleDialogChoice = handleDialogChoice
```

## Integración con Sistema de Historia

Puedes integrar esto con el sistema de story races:

```lua
-- En mysummerStoryRaces.lua
local function showStoryDialog(chapterId, sceneId)
  local scene = STORY_SCENES[chapterId][sceneId]
  if not scene then return end

  guihooks.trigger("mysummerShowContactDialog", {
    contactId = scene.contactId,
    contactName = scene.contactName,
    emotion = scene.emotion,
    dialogText = getCurrentLang() == "es" and scene.textEs or scene.textEn,
    choices = scene.choices,
  })
end
```

## Precargar Imágenes

Para mejor rendimiento, puedes precargar las imágenes de un contacto:

```javascript
import { preloadContactImages, CONTACTS } from "../utils/contactImages"

// Precargar todas las emociones de Ghost
const loadGhostImages = async () => {
  try {
    await Promise.all(preloadContactImages(CONTACTS.GHOST))
    console.log("Ghost images preloaded")
  } catch (err) {
    console.error("Failed to preload Ghost images:", err)
  }
}
```

## Ejemplos de Diálogos por Contexto

### Misión Aceptada
```javascript
{
  contactId: CONTACTS.TECHIE,
  contactName: "Techie",
  emotion: EMOTIONS.HAPPY,
  dialogText: "¡Excelente! Sabía que podía contar contigo. Te envío los detalles por mensaje.",
  continueLabel: "Entendido"
}
```

### Misión Fallida
```javascript
{
  contactId: CONTACTS.VIPER,
  contactName: "Viper",
  emotion: EMOTIONS.ANGRY,
  dialogText: "¡Incompetente! No vuelvas a perder mi tiempo.",
  continueLabel: "Lo siento"
}
```

### Misión Completada
```javascript
{
  contactId: CONTACTS.MUSCLE,
  contactName: "Muscle",
  emotion: EMOTIONS.CONTENT,
  dialogText: "Buen trabajo, amigo. Tu pago está en camino. Volveremos a trabajar juntos.",
  continueLabel: "Gracias"
}
```

### Negociación
```javascript
{
  contactId: CONTACTS.NOVA,
  contactName: "Nova",
  emotion: EMOTIONS.SEDUCTIVE,
  dialogText: "Podría darte un descuento especial... si me ayudas con algo primero.",
  choices: [
    { label: "¿Qué necesitas?", value: "help" },
    { label: "Prefiero pagar el precio completo", value: "pay_full" },
    { label: "No me interesa", value: "decline" }
  ]
}
```
