-- MySummer Messages System
-- Handles narrative documents: letters, newspapers, digital evidence
-- Provides story content through document system

local M = {}
M.moduleName = "career_modules_mysummerMessages"

M.dependencies = {
  "career_career",
  "career_saveSystem",
  "career_modules_mysummerChat",
}

local logTag = "mysummerMessages"
local saveFile = "mysummer_messages.json"

-- ============================================================================
-- LOCALIZATION
-- ============================================================================

local function tr(key, default)
  return translateLanguage(key, default or key)
end

-- Resolve bilingual text to current language
local function resolveBilingualText(text)
  if type(text) ~= "table" then
    return tostring(text)
  end

  if text.es or text.en then
    local lang = Steam and Steam.language or "en_US"
    local langCode = string.sub(lang, 1, 2)

    if langCode == "es" and text.es then
      return text.es
    elseif langCode == "en" and text.en then
      return text.en
    elseif text.es then
      return text.es
    elseif text.en then
      return text.en
    else
      return tostring(text)
    end
  end

  return tostring(text)
end

-- ============================================================================
-- STATE
-- ============================================================================

local state = {
  documents = {},  -- Array of document objects
  nextDocumentId = 1,
  unreadCount = 0,
  triggeredDocuments = {},  -- Track which documents have been triggered
}

-- Forward declarations
local saveState
local loadState

-- ============================================================================
-- DOCUMENT DEFINITIONS (NARRATIVE CONTENT)
-- ============================================================================

-- Document templates triggered by narrative events
-- Extracted from NARRATIVA_REEDIT.md
local documentTemplates = {
  -- FASE 0: Grandfather's Letter (Prologue)
  grandfather_letter = {
    id = "grandfather_letter",
    type = "letter",
    from = "Miller Senior",
    title = {
      es = "Carta del Abuelo Miller",
      en = "Grandfather Miller's Letter",
    },
    date = "15 años atrás / 15 years ago",
    icon = "✉️",
    priority = "critical",
    content = {
      es = [[Querido nieto,

Si estás leyendo esto, significa que me he ido, y que finalmente has decidido abrir el garaje. No te culpo por haber tardado tanto. Yo tampoco sabría qué hacer con este lugar si estuviera en tu posición.

El ETK-I que encontrarás ahí dentro no es solo un coche. Es una promesa que nunca cumplí. Lo construí para Viper, la mejor piloto que he conocido jamás. Ella confiaba en mí para preparar las máquinas que la llevarían a la gloria... pero fallé.

Su marido murió en una carrera. No era mi coche el que conducía esa noche, pero me sentí responsable igual. Dejé de trabajar con ella. Dejé de trabajar, punto. Y ese ETK-I se quedó ahí, en el garaje, cubierto de polvo y de arrepentimiento.

Ahora es tuyo. Quizá puedas hacer lo que yo no pude: terminarlo. Correrlo. Demostrar que los Miller no solo construimos fantasmas.

El manual de taller está en el banco de trabajo. Las llaves, en el cajón de arriba. Y mi teléfono viejo... tiene algunos contactos que quizá te sean útiles. Ghost sabrá quién eres. Dile que vienes de mi parte.

No cometas mis errores. No dejes que el miedo te detenga antes de cruzar la línea de meta.

Con todo mi cariño y todos mis remordimientos,
Tu abuelo, Miller Senior

P.D.: Si Ghost te ofrece piezas del mercado negro, piénsatelo dos veces. Ese hombre vive en las sombras por una razón.]],
      en = [[Dear Grandson,

If you're reading this, it means I'm gone, and you've finally decided to open the garage. I don't blame you for taking so long. I wouldn't know what to do with this place either if I were in your shoes.

The ETK-I you'll find inside isn't just a car. It's a promise I never kept. I built it for Viper, the best driver I've ever known. She trusted me to prepare the machines that would take her to glory... but I failed.

Her husband died in a race. It wasn't my car he was driving that night, but I felt responsible anyway. I stopped working with her. I stopped working, period. And that ETK-I stayed there, in the garage, covered in dust and regret.

Now it's yours. Maybe you can do what I couldn't: finish it. Race it. Prove that the Millers don't just build ghosts.

The workshop manual is on the workbench. The keys are in the top drawer. And my old phone... it has some contacts that might be useful to you. Ghost will know who you are. Tell him you come from me.

Don't make my mistakes. Don't let fear stop you before crossing the finish line.

With all my love and all my regrets,
Your grandfather, Miller Senior

P.S.: If Ghost offers you black market parts, think twice. That man lives in the shadows for a reason.]],
    },
  },

  -- FASE 2: Newspaper Clipping (The Accident)
  newspaper_accident = {
    id = "newspaper_accident",
    type = "newspaper",
    from = "West Coast Chronicle",
    title = {
      es = "Recorte de Periódico: Tragedia en el Circuito",
      en = "Newspaper Clipping: Circuit Tragedy",
    },
    date = "15 años atrás / 15 years ago",
    icon = "📰",
    priority = "high",
    content = {
      -- NOTE: This message contains a trailing ']' (archive note), which would
      -- collide with Lua's long-string terminator ']]'. Use [=[ ... ]=] to
      -- avoid syntax errors.
      es = [=[WEST COAST CHRONICLE
Sección: Deportes de Motor
Fecha: 15 años atrás

TRAGEDIA EN EL CIRCUITO: MUERE PILOTO EN CARRERA NOCTURNA

Un accidente fatal durante una carrera clandestina en las afueras de la ciudad ha cobrado la vida del piloto Marcus "Muscle" Vega, de 32 años, conocido en el circuito underground por su dominio de los muscle cars americanos.

El accidente ocurrió en la recta principal del antiguo circuito industrial, cuando el vehículo de Vega, un Dodge Challenger preparado, perdió el control a alta velocidad y se estrelló contra el muro de contención. Los testigos afirman que el coche mostraba signos de fallo mecánico momentos antes del impacto.

La investigación policial determinó que las condiciones del circuito no eran aptas para competición y que no se contaba con medidas de seguridad adecuadas. No se presentaron cargos criminales, pero la comunidad de carreras underground quedó profundamente marcada por el suceso.

Vega deja atrás a su esposa, Victoria "Viper" Vega, también piloto profesional, y a su hija de 8 años. Viper Vega, quien competía en la misma serie, anunció su retiro temporal de las carreras tras el accidente.

Miller Senior, reconocido mecánico y preparador de vehículos que trabajaba regularmente con el equipo de los Vega, también anunció su retiro indefinido del mundo de las carreras, citando "responsabilidad moral" en declaraciones a la prensa.

"No puedo seguir construyendo máquinas que ponen vidas en riesgo", declaró Miller. "Marcus era un amigo. Su muerte no debería haber ocurrido."

Las autoridades han intensificado las redadas contra las carreras ilegales en la zona desde el incidente.

[Nota del archivo: Este recorte fue encontrado en el banco de trabajo del garaje de Miller Senior, junto a herramientas sin usar y un proyecto ETK-I sin terminar.]]=],
      en = [=[WEST COAST CHRONICLE
Section: Motorsports
Date: 15 years ago

CIRCUIT TRAGEDY: DRIVER DIES IN NIGHT RACE

A fatal accident during a clandestine race on the outskirts of the city has claimed the life of 32-year-old driver Marcus "Muscle" Vega, known in the underground circuit for his mastery of American muscle cars.

The accident occurred on the main straight of the old industrial circuit, when Vega's vehicle, a prepared Dodge Challenger, lost control at high speed and crashed into the retaining wall. Witnesses claim the car showed signs of mechanical failure moments before impact.

Police investigation determined that circuit conditions were not suitable for competition and that adequate safety measures were not in place. No criminal charges were filed, but the underground racing community was deeply marked by the incident.

Vega is survived by his wife, Victoria "Viper" Vega, also a professional driver, and their 8-year-old daughter. Viper Vega, who competed in the same series, announced her temporary retirement from racing after the accident.

Miller Senior, renowned mechanic and vehicle preparer who regularly worked with the Vega team, also announced his indefinite retirement from the racing world, citing "moral responsibility" in statements to the press.

"I can't keep building machines that put lives at risk," Miller declared. "Marcus was a friend. His death shouldn't have happened."

Authorities have intensified raids against illegal racing in the area since the incident.

[Archive note: This clipping was found on Miller Senior's garage workbench, alongside unused tools and an unfinished ETK-I project.]]=],
    },
  },

  -- FASE 6: False Evidence (Techie's Blockchain Analysis)
  false_evidence_blockchain = {
    id = "false_evidence_blockchain",
    type = "digital_evidence",
    from = "Techie",
    title = {
      es = "Análisis Blockchain: Transacción Sospechosa",
      en = "Blockchain Analysis: Suspicious Transaction",
    },
    date = "Hoy / Today",
    icon = "💻",
    priority = "urgent",
    content = {
      es = [[TECHIE - ANÁLISIS FORENSE DIGITAL
Timestamp: [TIMESTAMP_ACTUAL]
Clasificación: CONFIDENCIAL

RESUMEN EJECUTIVO:
He completado el análisis de la blockchain que me pediste. Los resultados son... preocupantes.

DETALLES DE LA TRANSACCIÓN:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Wallet Origen:    0x7a4B...9c2D (Shadow - Conocido)
Wallet Destino:   0x3f1A...8e7B (IDENTIFICADO)
Monto:            $45,000 USD (en cripto)
Fecha:            2 días después del Rally Regional
Concepto:         "Pago por servicios - ETK-I"
Estado:           CONFIRMADO (128 bloques)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

IDENTIFICACIÓN DEL DESTINATARIO:
La wallet destino está vinculada a: [ROOK / NOVA - según elección]

Cross-referencia con otros movimientos:
- Misma wallet recibió $3,200 de fuente desconocida 3 semanas antes
- Patrón de gastos compatible con necesidades financieras recientes
- Sin actividad previa de este tipo en el historial

CONCLUSIÓN:
Los datos sugieren que [ROOK/NOVA] recibió un pago significativo de Shadow justo después del robo del ETK-I. La correlación temporal y el monto son demasiado específicos para ser coincidencia.

No quiero creer esto, Miller. Pero los números no mienten. La blockchain es inmutable.

Lo siento.

- Techie

[Adjunto: blockchain_evidence_45k.json - 2.4 MB]
[Firma Digital: VERIFICADA]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
ADVERTENCIA: Este análisis se basa en datos de blockchain públicos.
La interpretación de transacciones cripto puede estar sujeta a errores
si las wallets están mal etiquetadas o han sido comprometidas.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━]],
      en = [[TECHIE - DIGITAL FORENSIC ANALYSIS
Timestamp: [CURRENT_TIMESTAMP]
Classification: CONFIDENTIAL

EXECUTIVE SUMMARY:
I've completed the blockchain analysis you requested. The results are... concerning.

TRANSACTION DETAILS:
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Source Wallet:      0x7a4B...9c2D (Shadow - Known)
Destination Wallet: 0x3f1A...8e7B (IDENTIFIED)
Amount:             $45,000 USD (in crypto)
Date:               2 days after Regional Rally
Memo:               "Payment for services - ETK-I"
Status:             CONFIRMED (128 blocks)
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

RECIPIENT IDENTIFICATION:
The destination wallet is linked to: [ROOK / NOVA - based on choice]

Cross-reference with other movements:
- Same wallet received $3,200 from unknown source 3 weeks prior
- Spending pattern compatible with recent financial needs
- No prior activity of this type in history

CONCLUSION:
Data suggests that [ROOK/NOVA] received a significant payment from Shadow right after the ETK-I theft. The temporal correlation and amount are too specific to be coincidence.

I don't want to believe this, Miller. But the numbers don't lie. The blockchain is immutable.

I'm sorry.

- Techie

[Attachment: blockchain_evidence_45k.json - 2.4 MB]
[Digital Signature: VERIFIED]

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
WARNING: This analysis is based on public blockchain data.
Interpretation of crypto transactions may be subject to errors
if wallets are mislabeled or have been compromised.
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━]],
    },
  },

  -- FASE 7: Anonymous Hint (Truth About Shadow)
  anonymous_truth_shadow = {
    id = "anonymous_truth_shadow",
    type = "anonymous_message",
    from = "Unknown",
    title = {
      es = "Mensaje Anónimo: La Verdad sobre Shadow",
      en = "Anonymous Message: The Truth About Shadow",
    },
    date = "Hoy / Today",
    icon = "❓",
    priority = "urgent",
    content = {
      es = [=[▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
MENSAJE ENCRIPTADO - ORIGEN DESCONOCIDO
Protocolo: TOR / IP Enmascarado
▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂

Miller,

No todo lo que brilla es oro.
No todo lo que Techie ve en su pantalla es verdad.

Shadow es un maestro de los espejismos digitales.
Las wallets pueden ser falsificadas.
Las transacciones pueden ser fabricadas.
Los registros pueden ser manipulados.

Tu pareja no te traicionó.
Shadow lo hizo parecer así.

Busca en el contenedor 402 del puerto.
Encontrarás piezas del ETK-I.
Encontrarás la verdad.

No confíes en las pantallas.
Confía en el hierro.

Las máquinas no mienten.
Las personas que las controlan, sí.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Shadow te quitó el coche.
Shadow te quitó la confianza.
Shadow quiere que corras solo.

Porque los pilotos solos son fáciles de destruir.

No caigas en su trampa.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Este mensaje se autodestruirá.
No intentes rastrearlo.

Un amigo en las sombras.

▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
[CONEXIÓN TERMINADA]]=],
      en = [=[▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
ENCRYPTED MESSAGE - UNKNOWN ORIGIN
Protocol: TOR / Masked IP
▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂

Miller,

Not everything that glitters is gold.
Not everything Techie sees on his screen is true.

Shadow is a master of digital mirages.
Wallets can be forged.
Transactions can be fabricated.
Records can be manipulated.

Your partner didn't betray you.
Shadow made it look that way.

Look in container 402 at the port.
You'll find ETK-I parts.
You'll find the truth.

Don't trust the screens.
Trust the iron.

Machines don't lie.
The people who control them do.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

Shadow took your car.
Shadow took your trust.
Shadow wants you to race alone.

Because lone drivers are easy to destroy.

Don't fall for his trap.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

This message will self-destruct.
Don't try to trace it.

A friend in the shadows.

▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂▂
[CONNECTION TERMINATED]]=],
    },
  },

  -- FASE 8: Viper's Recognition (After Big One)
  viper_recognition = {
    id = "viper_recognition",
    type = "letter",
    from = "Viper",
    title = {
      es = "Carta de Viper: Reconocimiento",
      en = "Letter from Viper: Recognition",
    },
    date = "Hoy / Today",
    icon = "🏁",
    priority = "high",
    content = {
      es = [[Miller,

No suelo escribir cartas. Prefiero dejar que los neumáticos hablen por mí. Pero después de verte cruzar esa línea de meta con el ETK-I... necesito decir esto.

Tu abuelo fue el mejor mecánico con el que trabajé. También fue un cobarde.

Cuando Marcus murió, él se hundió. Dejó de construir. Dejó de creer. Ese ETK-I que acabas de pilotar estaba destinado a ser mi coche para la temporada siguiente. Él lo abandonó a mitad de construcción porque no pudo soportar el peso de la pérdida.

Yo lo entendí. Pero nunca lo perdoné.

Hoy, al verte correr, vi algo que pensé que nunca vería: un Miller que no frena antes de la meta. Un Miller que termina lo que empieza. Un Miller que no deja que el miedo dicte su trazada.

El coche suena exactamente como él lo habría querido. Ruge con la voz de alguien que no tiene miedo de morir intentándolo.

Mi hija, la que conoces como Muscle, me dijo que eres diferente. Tenía razón. Tienes su técnica, pero no su cobardía. Tienes su corazón, pero no su culpa.

Ese ETK-I ahora es tuyo de verdad. No porque lo heredaste, sino porque lo ganaste. Lo terminaste. Lo corriste. Lo hiciste rugir.

Miller Senior habría estado orgulloso.
O aterrorizado.
Probablemente ambas cosas.

Nos vemos en la pista. Y esta vez, no voy a frenar.

- Viper

P.D.: El garaje de mi padre tiene algunas piezas que podrían interesarte. Muscle sabe dónde están. Dile que yo te envié. Considera que hemos saldado las cuentas del pasado.]],
      en = [[Miller,

I don't usually write letters. I prefer to let the tires speak for me. But after seeing you cross that finish line with the ETK-I... I need to say this.

Your grandfather was the best mechanic I ever worked with. He was also a coward.

When Marcus died, he sank. He stopped building. He stopped believing. That ETK-I you just piloted was meant to be my car for the next season. He abandoned it mid-construction because he couldn't bear the weight of loss.

I understood it. But I never forgave it.

Today, watching you race, I saw something I thought I'd never see: a Miller who doesn't brake before the finish line. A Miller who finishes what he starts. A Miller who doesn't let fear dictate his racing line.

The car sounds exactly as he would have wanted it. It roars with the voice of someone who's not afraid to die trying.

My daughter, the one you know as Muscle, told me you're different. She was right. You have his technique, but not his cowardice. You have his heart, but not his guilt.

That ETK-I is now truly yours. Not because you inherited it, but because you earned it. You finished it. You raced it. You made it roar.

Miller Senior would have been proud.
Or terrified.
Probably both.

See you on the track. And this time, I'm not braking.

- Viper

P.S.: My father's garage has some parts that might interest you. Muscle knows where they are. Tell her I sent you. Consider the past debts settled.]],
    },
  },
}

-- ============================================================================
-- SAVE/LOAD
-- ============================================================================

loadState = function()
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  if not savePath then return end

  local filePath = savePath .. "/career/mysummer/" .. saveFile
  local data = jsonReadFile(filePath) or {}

  state.documents = data.documents or {}
  state.nextDocumentId = data.nextDocumentId or 1
  state.unreadCount = data.unreadCount or 0
  state.triggeredDocuments = data.triggeredDocuments or {}

  -- Recalculate unread count
  state.unreadCount = 0
  for _, doc in ipairs(state.documents) do
    if not doc.read then
      state.unreadCount = state.unreadCount + 1
    end
  end

  log("I", logTag, "Loaded " .. #state.documents .. " documents (" .. state.unreadCount .. " unread)")
end

saveState = function(currentSavePath)
  local _, savePath = career_saveSystem.getCurrentSaveSlot()
  savePath = currentSavePath or savePath
  if not savePath then return end

  -- Ensure directory exists
  local dirPath = savePath .. "/career/mysummer"
  if not FS:directoryExists(dirPath) then
    FS:directoryCreate(dirPath, true)
  end

  local filePath = dirPath .. "/" .. saveFile
  local data = {
    documents = state.documents,
    nextDocumentId = state.nextDocumentId,
    unreadCount = state.unreadCount,
    triggeredDocuments = state.triggeredDocuments,
  }
  career_saveSystem.jsonWriteFileSafe(filePath, data, true)
  log("I", logTag, "Saved " .. #state.documents .. " documents")
end

-- ============================================================================
-- DOCUMENT FUNCTIONS
-- ============================================================================

-- Send a document from a template
local function sendDocument(templateId, customData)
  local template = documentTemplates[templateId]
  if not template then
    log("W", logTag, "Unknown document template: " .. tostring(templateId))
    return nil
  end

  -- Check if already triggered
  if state.triggeredDocuments[templateId] then
    log("I", logTag, "Document " .. templateId .. " already triggered, skipping")
    return nil
  end

  -- Mark as triggered
  state.triggeredDocuments[templateId] = true

  -- Resolve bilingual content
  local resolvedTitle = resolveBilingualText(template.title)
  local resolvedContent = resolveBilingualText(template.content)

  -- Apply custom data placeholders
  if customData then
    -- Replace (Rook/Nova) placeholder with actual chosen partner
    if customData.chosen_partner then
      local partnerName = customData.chosen_partner == "rook" and "Rook" or "Nova"
      resolvedContent = string.gsub(resolvedContent, "%[ROOK / NOVA %- según elección%]", partnerName)
      resolvedContent = string.gsub(resolvedContent, "%[ROOK / NOVA %- based on choice%]", partnerName)
      resolvedContent = string.gsub(resolvedContent, "%[ROOK/NOVA%]", partnerName)
    end
  end

  local document = {
    id = state.nextDocumentId,
    templateId = templateId,
    type = template.type or "document",
    from = template.from,
    title = resolvedTitle,
    date = template.date,
    icon = template.icon or "📄",
    priority = template.priority or "normal",
    content = resolvedContent,
    timestamp = os.time(),
    read = false,
  }

  state.nextDocumentId = state.nextDocumentId + 1
  state.unreadCount = state.unreadCount + 1

  -- Insert at beginning (newest first)
  table.insert(state.documents, 1, document)

  log("I", logTag, "Sent document: " .. document.title .. " from " .. document.from)

  -- Notify UI
  if guihooks then
    guihooks.trigger("mysummerNewDocument", {
      id = document.id,
      from = document.from,
      title = document.title,
      type = document.type,
      icon = document.icon,
      priority = document.priority,
    })

    -- Show toast notification
    guihooks.trigger("toastrMsg", {
      type = document.priority == "critical" and "warning" or "info",
      title = tr("mysummer.notifications.newDocument", "New Document"),
      msg = document.icon .. " " .. document.title,
    })
  end

  saveState()
  return document.id
end

-- Mark a document as read
local function markAsRead(documentId)
  for _, doc in ipairs(state.documents) do
    if doc.id == documentId and not doc.read then
      doc.read = true
      state.unreadCount = math.max(0, state.unreadCount - 1)
      saveState()

      -- Notify UI
      if guihooks then
        guihooks.trigger("mysummerDocumentRead", {
          id = documentId,
          unreadCount = state.unreadCount,
        })
      end
      return true
    end
  end
  return false
end

-- Mark all documents as read
local function markAllAsRead()
  for _, doc in ipairs(state.documents) do
    doc.read = true
  end
  state.unreadCount = 0
  saveState()

  if guihooks then
    guihooks.trigger("mysummerDocumentsAllRead", {
      unreadCount = 0,
    })
  end
  return true
end

-- Delete a document
local function deleteDocument(documentId)
  for i, doc in ipairs(state.documents) do
    if doc.id == documentId then
      if not doc.read then
        state.unreadCount = math.max(0, state.unreadCount - 1)
      end
      table.remove(state.documents, i)
      saveState()

      if guihooks then
        guihooks.trigger("mysummerDocumentDeleted", {
          id = documentId,
          unreadCount = state.unreadCount,
        })
      end
      return true
    end
  end
  return false
end

-- Get all documents for UI
local function getDocuments()
  local copy = {}
  for _, doc in ipairs(state.documents) do
    table.insert(copy, {
      id = doc.id,
      templateId = doc.templateId,
      type = doc.type,
      from = doc.from,
      title = doc.title,
      date = doc.date,
      icon = doc.icon,
      priority = doc.priority,
      content = doc.content,
      timestamp = doc.timestamp,
      read = doc.read,
    })
  end
  return copy
end

-- Get unread count
local function getUnreadCount()
  return state.unreadCount
end

-- Get a specific document by ID
local function getDocument(documentId)
  for _, doc in ipairs(state.documents) do
    if doc.id == documentId then
      return {
        id = doc.id,
        templateId = doc.templateId,
        type = doc.type,
        from = doc.from,
        title = doc.title,
        date = doc.date,
        icon = doc.icon,
        priority = doc.priority,
        content = doc.content,
        timestamp = doc.timestamp,
        read = doc.read,
      }
    end
  end
  return nil
end

-- ============================================================================
-- NARRATIVE EVENT INTEGRATION
-- ============================================================================

-- Trigger document based on narrative event
local function onNarrativeEvent(eventId, eventData)
  eventData = eventData or {}

  -- Map narrative events to document templates
  local eventToDocumentMap = {
    -- Grandfather's letter triggers at game start (handled in onCareerActive)
    phase2_newspaper = "newspaper_accident",
    phase6_false_evidence = "false_evidence_blockchain",
    phase7_anonymous_hint = "anonymous_truth_shadow",
    phase8_viper_letter = "viper_recognition",
  }

  local templateId = eventToDocumentMap[eventId]
  if templateId then
    -- Get chosen partner for placeholder replacement
    local customData = {}
    if extensions.career_modules_mysummerNarrative then
      local narrative = extensions.career_modules_mysummerNarrative
      if narrative.getStoryFlags then
        local flags = narrative.getStoryFlags()
        if flags.chosen_partner then
          customData.chosen_partner = flags.chosen_partner
        end
      end
    end

    sendDocument(templateId, customData)
    log("I", logTag, "Narrative event " .. eventId .. " triggered document: " .. templateId)
  end
end

-- ============================================================================
-- LEGACY MESSAGE SYSTEM (For backwards compatibility)
-- ============================================================================

-- Send a custom message (routes to chat system if available)
local function sendCustomMessage(messageData)
  if not messageData then
    log("W", logTag, "sendCustomMessage called with nil data")
    return nil
  end

  -- Route to chat system if available
  if career_modules_mysummerChat then
    local contactId = messageData.from or "system"
    local content = messageData.body or ""

    -- For mission offers, format the message nicely
    if messageData.actionType == "mission_offer" then
      content = messageData.subject .. "\n\n" .. content
    end

    -- Determine if this is from a contact or system
    local isContact = contactId ~= "system" and contactId ~= "unknown"

    if isContact then
      -- Unlock contact if needed
      career_modules_mysummerChat.unlockContact(contactId)

      -- Send as contact message with mission data
      career_modules_mysummerChat.sendContactMessage(contactId, content, {
        contentType = "text",
        actionType = messageData.actionType,
        actionData = {
          missionId = messageData.missionId,
          isStoryMission = messageData.isStoryMission or false,
          templateId = messageData.templateId,
          contactId = contactId,
          quizOptions = messageData.quizOptions,
          quizCallback = messageData.quizCallback,
        },
      })
    else
      -- Send as system message
      career_modules_mysummerChat.sendSystemMessage(content, {
        actionType = messageData.actionType,
        actionData = {
          missionId = messageData.missionId,
          isStoryMission = messageData.isStoryMission or false,
          templateId = messageData.templateId,
        },
      })
    end

    log("I", logTag, "Custom message routed to chat: " .. (messageData.subject or "no subject"))
    return 1 -- Return dummy ID
  end

  log("W", logTag, "Chat system not available for custom message routing")
  return nil
end

-- Send welcome message (legacy template)
local function sendMessage(templateId, customData)
  log("W", logTag, "Legacy sendMessage called with template: " .. tostring(templateId))
  -- Legacy templates are no longer used, route to document system
  return sendDocument(templateId, customData)
end

-- ============================================================================
-- LIFECYCLE
-- ============================================================================

local function onCareerActive(active)
  if active then
    loadState()

    -- Send grandfather's letter if this is a new game (no documents yet)
    if #state.documents == 0 then
      -- Send the grandfather's letter as the first document
      sendDocument("grandfather_letter")
      log("I", logTag, "New game detected, sent grandfather's letter")
    end
  else
    -- Reset state on career deactivate
    state.documents = {}
    state.nextDocumentId = 1
    state.unreadCount = 0
    state.triggeredDocuments = {}
  end
end

local function onSaveCurrentSaveSlot(currentSavePath)
  saveState(currentSavePath)
end

local function onExtensionLoaded()
  log("I", logTag, "MySummer Messages system loaded (Document System)")
end

-- ============================================================================
-- MODULE INTERFACE
-- ============================================================================

-- Document API
M.sendDocument = sendDocument
M.markAsRead = markAsRead
M.markAllAsRead = markAllAsRead
M.deleteDocument = deleteDocument
M.getDocuments = getDocuments
M.getDocument = getDocument
M.getUnreadCount = getUnreadCount

-- Narrative integration
M.onNarrativeEvent = onNarrativeEvent

-- Legacy compatibility
M.sendMessage = sendMessage
M.sendCustomMessage = sendCustomMessage

-- Lifecycle
M.onCareerActive = onCareerActive
M.onSaveCurrentSaveSlot = onSaveCurrentSaveSlot
M.onExtensionLoaded = onExtensionLoaded

return M
