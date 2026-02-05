<template>
  <div class="tutorial-overlay" @click.self="closeTutorial">
    <div class="tutorial-panel">
      <!-- Header -->
      <div class="tutorial-header">
        <div class="header-icon">
          <span class="icon-car"></span>
        </div>
        <h1 class="header-title">MySummer Street Racing</h1>
        <p class="header-subtitle">{{ t.subtitle }}</p>
      </div>

      <!-- Content -->
      <div class="tutorial-content">
        <!-- Features Section -->
        <div class="section">
          <h2 class="section-title">{{ t.featuresTitle }}</h2>
          <ul class="feature-list">
            <li v-for="(feature, index) in t.features" :key="index">
              <span class="feature-icon">{{ feature.icon }}</span>
              <span>{{ feature.text }}</span>
            </li>
          </ul>
        </div>

        <!-- Getting Started Section -->
        <div class="section highlight">
          <h2 class="section-title">{{ t.stepsTitle }}</h2>
          <ol class="steps-list">
            <li v-for="(step, index) in t.steps" :key="index">
              <strong>{{ step.title }}</strong>
              <span>{{ step.description }}</span>
            </li>
          </ol>
        </div>

        <!-- Project Car Section -->
        <div class="section warning">
          <h2 class="section-title">{{ t.projectTitle.replace('{car}', projectCarName) }}</h2>
          <div class="project-info">
            <p>{{ t.projectIntro }}</p>
            <ul class="source-list">
              <li>
                <span class="source-badge speed">Speed Parts</span>
                {{ t.sourceSpeed }}
              </li>
              <li>
                <span class="source-badge used">{{ t.sourceUsedLabel }}</span>
                {{ t.sourceUsed }}
              </li>
            </ul>
            <p class="important-note">
              <strong>{{ t.importantLabel }}</strong> {{ t.importantNote }}
            </p>
          </div>
        </div>
      </div>

      <!-- Footer -->
      <div class="tutorial-footer">
        <button class="start-btn" @click="closeTutorial">
          {{ t.buttonText }}
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  projectCarName: {
    type: String,
    default: 'ETK-I'
  },
  projectCarFullName: {
    type: String,
    default: 'ETK I-Series'
  },
  language: {
    type: String,
    default: 'en'
  }
})

const emit = defineEmits(['return'])

// Language detection from prop (passed from Lua)
const isSpanish = computed(() => props.language === 'es')

// Translations
const translations = {
  en: {
    subtitle: 'Thanks for playing this mod',
    featuresTitle: 'What this mod includes',
    features: [
      { icon: '🏎️', text: 'Narrative story with street racing' },
      { icon: '📱', text: 'Chat system with characters' },
      { icon: '🔧', text: 'Project car to restore' },
      { icon: '📦', text: 'Delivery jobs to earn money' },
      { icon: '🛒', text: 'Used parts marketplace' }
    ],
    stepsTitle: 'Recommended first steps',
    steps: [
      {
        title: 'Upgrade your Miramar:',
        description: 'Buy better tires and suspension at the parts shop. Your starter car needs upgrades to compete.'
      },
      {
        title: 'Install cargo boxes:',
        description: 'Add cargo boxes to the Miramar to be able to do delivery jobs.'
      },
      {
        title: 'Work as a courier:',
        description: 'Earn money making deliveries. Plus, you can pick up parts you buy online for your project car.'
      },
      {
        title: 'Participate in races:',
        description: 'Find street races to earn XP and unlock the story.'
      }
    ],
    projectTitle: 'About the project car ({car})',
    projectIntro: 'Your grandfather\'s car needs to be restored. The parts to complete it can only be obtained in two ways:',
    sourceSpeed: 'The official performance parts store',
    sourceUsedLabel: 'Used parts',
    sourceUsed: 'The used parts market (cheaper but variable quality)',
    importantLabel: 'Important:',
    importantNote: 'Some parts of the story can only be completed with this car. Restoring it is part of the journey.',
    buttonText: 'Start playing'
  },
  es: {
    subtitle: 'Gracias por jugar este mod',
    featuresTitle: 'Que incluye este mod',
    features: [
      { icon: '🏎️', text: 'Historia narrativa con carreras callejeras' },
      { icon: '📱', text: 'Sistema de chat con personajes' },
      { icon: '🔧', text: 'Coche proyecto para restaurar' },
      { icon: '📦', text: 'Trabajos de reparto para ganar dinero' },
      { icon: '🛒', text: 'Mercado de piezas de segunda mano' }
    ],
    stepsTitle: 'Primeros pasos recomendados',
    steps: [
      {
        title: 'Mejora tu Miramar:',
        description: 'Compra mejores neumaticos y suspensiones en la tienda de piezas. Tu coche inicial necesita mejoras para competir.'
      },
      {
        title: 'Instala cajas de carga:',
        description: 'Añade cajas de carga al Miramar para poder hacer trabajos de reparto.'
      },
      {
        title: 'Trabaja como repartidor:',
        description: 'Gana dinero haciendo entregas. Ademas, podras ir a recoger las piezas que compres online para tu coche proyecto.'
      },
      {
        title: 'Participa en carreras:',
        description: 'Busca carreras callejeras para ganar XP y desbloquear la historia.'
      }
    ],
    projectTitle: 'Sobre el coche proyecto ({car})',
    projectIntro: 'El coche de tu abuelo necesita ser restaurado. Las piezas para completarlo solo se pueden conseguir de dos formas:',
    sourceSpeed: 'La tienda oficial de piezas de rendimiento',
    sourceUsedLabel: 'Segunda mano',
    sourceUsed: 'El mercado de piezas usadas (mas barato pero variable calidad)',
    importantLabel: 'Importante:',
    importantNote: 'Algunas partes de la historia solo se podran completar con este coche. Restaurarlo es parte del viaje.',
    buttonText: 'Empezar a jugar'
  }
}

const t = computed(() => isSpanish.value ? translations.es : translations.en)

function closeTutorial() {
  emit('return', true)
}
</script>

<style scoped lang="scss">
// Colors
$bg-dark: #0a0a0a;
$panel-bg: linear-gradient(180deg, #1a1a1a 0%, #0d0d0d 100%);
$accent-orange: #ff6b35;
$accent-blue: #3498db;
$accent-green: #2ecc71;
$accent-yellow: #f1c40f;
$text-primary: #ffffff;
$text-secondary: rgba(255, 255, 255, 0.7);
$text-muted: rgba(255, 255, 255, 0.5);
$border-subtle: rgba(255, 255, 255, 0.1);

.tutorial-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.95);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 99999;
  padding: 20px;
  pointer-events: all;
}

.tutorial-panel {
  background: $panel-bg;
  border: 1px solid $border-subtle;
  border-radius: 12px;
  max-width: 700px;
  max-height: 85vh;
  overflow-y: auto;
  box-shadow: 0 25px 80px rgba(0, 0, 0, 0.8);
  animation: panelSlideIn 0.5s ease-out;
}

@keyframes panelSlideIn {
  from {
    opacity: 0;
    transform: translateY(30px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

// Header
.tutorial-header {
  text-align: center;
  padding: 35px 40px 25px;
  border-bottom: 1px solid $border-subtle;
  background: linear-gradient(180deg, rgba($accent-orange, 0.1) 0%, transparent 100%);
}

.header-icon {
  width: 60px;
  height: 60px;
  margin: 0 auto 15px;
  background: linear-gradient(135deg, $accent-orange 0%, darken($accent-orange, 15%) 100%);
  border-radius: 50%;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 28px;

  .icon-car::before {
    content: '🏁';
  }
}

.header-title {
  font-size: 1.8rem;
  font-weight: 700;
  color: $text-primary;
  margin: 0 0 8px 0;
  letter-spacing: -0.5px;
}

.header-subtitle {
  font-size: 1rem;
  color: $text-secondary;
  margin: 0;
}

// Content
.tutorial-content {
  padding: 25px 35px;
}

.section {
  margin-bottom: 28px;

  &:last-child {
    margin-bottom: 0;
  }

  &.highlight {
    background: rgba($accent-blue, 0.08);
    border: 1px solid rgba($accent-blue, 0.2);
    border-radius: 8px;
    padding: 20px;
    margin-left: -15px;
    margin-right: -15px;
  }

  &.warning {
    background: rgba($accent-orange, 0.08);
    border: 1px solid rgba($accent-orange, 0.2);
    border-radius: 8px;
    padding: 20px;
    margin-left: -15px;
    margin-right: -15px;
  }
}

.section-title {
  font-size: 1.1rem;
  font-weight: 600;
  color: $text-primary;
  margin: 0 0 15px 0;
  display: flex;
  align-items: center;
  gap: 8px;

  &::before {
    content: '';
    width: 3px;
    height: 18px;
    background: $accent-orange;
    border-radius: 2px;
  }
}

// Feature list
.feature-list {
  list-style: none;
  padding: 0;
  margin: 0;
  display: grid;
  gap: 12px;

  li {
    display: flex;
    align-items: center;
    gap: 12px;
    color: $text-secondary;
    font-size: 0.95rem;
  }

  .feature-icon {
    font-size: 1.2rem;
    width: 28px;
    text-align: center;
  }
}

// Steps list
.steps-list {
  list-style: none;
  padding: 0;
  margin: 0;
  counter-reset: step;

  li {
    display: flex;
    flex-direction: column;
    gap: 4px;
    margin-bottom: 16px;
    padding-left: 40px;
    position: relative;

    &:last-child {
      margin-bottom: 0;
    }

    &::before {
      counter-increment: step;
      content: counter(step);
      position: absolute;
      left: 0;
      top: 0;
      width: 26px;
      height: 26px;
      background: $accent-blue;
      color: white;
      border-radius: 50%;
      display: flex;
      align-items: center;
      justify-content: center;
      font-size: 0.85rem;
      font-weight: 600;
    }

    strong {
      color: $text-primary;
      font-size: 0.95rem;
    }

    span {
      color: $text-secondary;
      font-size: 0.9rem;
      line-height: 1.5;
    }
  }
}

// Project info
.project-info {
  p {
    color: $text-secondary;
    font-size: 0.95rem;
    line-height: 1.6;
    margin: 0 0 15px 0;
  }
}

.source-list {
  list-style: none;
  padding: 0;
  margin: 0 0 15px 0;
  display: flex;
  flex-direction: column;
  gap: 10px;

  li {
    display: flex;
    align-items: center;
    gap: 12px;
    color: $text-secondary;
    font-size: 0.9rem;
  }
}

.source-badge {
  padding: 4px 10px;
  border-radius: 4px;
  font-size: 0.8rem;
  font-weight: 600;
  text-transform: uppercase;

  &.speed {
    background: rgba($accent-green, 0.2);
    color: $accent-green;
    border: 1px solid rgba($accent-green, 0.3);
  }

  &.used {
    background: rgba($accent-yellow, 0.2);
    color: $accent-yellow;
    border: 1px solid rgba($accent-yellow, 0.3);
  }
}

.important-note {
  background: rgba(255, 255, 255, 0.05);
  border-left: 3px solid $accent-orange;
  padding: 12px 15px;
  border-radius: 0 6px 6px 0;
  margin: 0;

  strong {
    color: $accent-orange;
  }
}

// Footer
.tutorial-footer {
  padding: 25px 35px;
  border-top: 1px solid $border-subtle;
  text-align: center;
}

.start-btn {
  padding: 14px 50px;
  font-size: 1rem;
  font-weight: 600;
  text-transform: uppercase;
  letter-spacing: 1px;
  background: linear-gradient(180deg, $accent-orange 0%, darken($accent-orange, 10%) 100%);
  color: white;
  border: none;
  border-radius: 6px;
  cursor: pointer;
  transition: all 0.3s ease;
  box-shadow: 0 4px 15px rgba($accent-orange, 0.3);

  &:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba($accent-orange, 0.4);
    background: linear-gradient(180deg, lighten($accent-orange, 5%) 0%, $accent-orange 100%);
  }

  &:active {
    transform: translateY(0);
  }
}

// Scrollbar styling
.tutorial-panel {
  &::-webkit-scrollbar {
    width: 8px;
  }

  &::-webkit-scrollbar-track {
    background: rgba(255, 255, 255, 0.05);
  }

  &::-webkit-scrollbar-thumb {
    background: rgba(255, 255, 255, 0.2);
    border-radius: 4px;

    &:hover {
      background: rgba(255, 255, 255, 0.3);
    }
  }
}
</style>
