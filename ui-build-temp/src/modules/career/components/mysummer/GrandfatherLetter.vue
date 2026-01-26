<template>
  <div class="scrapbook-overlay" @click.self="closeLetter">
    <div class="desk-surface">
      <!-- Items on desk - aligned -->
      <div class="scrapbook-layout">

        <!-- Left column: photo + clipping -->
        <div class="left-column">
          <!-- Polaroid photo with tape -->
          <div class="polaroid-wrapper">
            <div class="tape tape-top"></div>
            <div class="polaroid">
              <img
                :src="photoSrc"
                alt="Grandfather with the Miramar"
                class="polaroid-image"
              />
              <span class="polaroid-caption">{{ photoCaption }}</span>
            </div>
          </div>

          <!-- Newspaper clipping -->
          <div class="clipping-wrapper">
            <div class="tape tape-clipping"></div>
            <div class="newspaper-clipping">
              <div class="clipping-masthead">WEST COAST GAZETTE</div>
              <div class="clipping-headline">THE BIG ONE</div>
              <div class="clipping-subhead">{{ clippingSubtext }}</div>
              <div class="clipping-handwritten">"{{ clippingNote }}"</div>
            </div>
          </div>
        </div>

        <!-- Right column: letter -->
        <div class="letter-wrapper">
          <div class="paper-clip"></div>
          <div class="letter-paper">
            <div class="letter-content">
              <p class="letter-greeting">{{ headerText }}</p>

              <div class="letter-body">
                <p v-for="(paragraph, index) in paragraphs" :key="index">
                  {{ paragraph }}
                </p>
              </div>

              <div class="letter-closing">
                <p class="closing-text">{{ signText }}</p>
                <p class="signature">{{ signName }}</p>
              </div>

              <p v-if="postscript" class="postscript">P.D. {{ postscript }}</p>
            </div>
          </div>
        </div>

      </div>

      <!-- Continue button -->
      <button class="continue-btn" @click="closeLetter">
        {{ buttonText }}
      </button>
    </div>
  </div>
</template>

<script setup>
import { computed } from 'vue'

const props = defineProps({
  storyText: {
    type: String,
    default: ''
  },
  signText: {
    type: String,
    default: 'Te quiere,'
  },
  signName: {
    type: String,
    default: 'El abuelo'
  },
  postscript: {
    type: String,
    default: ''
  }
})

const emit = defineEmits(['return'])

const isSpanish = computed(() => {
  return props.signName === 'El abuelo' || props.signText === 'Te quiere,'
})

// Photo source - computed to prevent Vite from treating it as an import
const photoSrc = computed(() => '/ui/images/grandad_and_miramar.png')

// Localized UI strings
const headerText = computed(() => isSpanish.value ? 'Querido nieto,' : 'Dear grandson,')
const photoCaption = computed(() => isSpanish.value ? 'Verano del 87' : 'Summer of 87')
const clippingSubtext = computed(() => isSpanish.value ? 'La carrera que lo cambio todo' : 'The race that changed everything')
const clippingNote = computed(() => isSpanish.value ? 'Hazlo por los dos.' : 'Do it for both of us.')
const buttonText = computed(() => isSpanish.value ? 'Empezar el viaje' : 'Begin the journey')

const paragraphs = computed(() => {
  if (!props.storyText) return []
  return props.storyText.split('\n\n').filter(p => p.trim())
})

function closeLetter() {
  emit('return', true)
}
</script>

<style scoped lang="scss">
// Fonts
$typewriter: 'Courier New', 'Courier', monospace;
$newspaper: 'Georgia', 'Times New Roman', serif;

// Colors
$paper-cream: #f4edd8;
$paper-aged: #e8dcc4;
$ink-dark: #222;
$ink-faded: #444;

.scrapbook-overlay {
  position: fixed;
  inset: 0;
  background: rgba(0, 0, 0, 0.92);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 99999;
  padding: 20px;
  pointer-events: all;
}

// Wooden desk surface
.desk-surface {
  background:
    // Wood grain pattern
    repeating-linear-gradient(
      90deg,
      transparent 0px,
      rgba(0,0,0,0.03) 1px,
      transparent 2px,
      transparent 20px
    ),
    repeating-linear-gradient(
      90deg,
      transparent 0px,
      rgba(255,255,255,0.02) 1px,
      transparent 3px,
      transparent 40px
    ),
    linear-gradient(
      180deg,
      #3d2e1f 0%,
      #2a1f14 30%,
      #1f170e 70%,
      #2a1f14 100%
    );
  padding: 50px 60px;
  border-radius: 8px;
  box-shadow:
    0 25px 80px rgba(0, 0, 0, 0.8),
    inset 0 1px 0 rgba(255, 255, 255, 0.05),
    inset 0 -1px 0 rgba(0, 0, 0, 0.3);
  max-width: 950px;
  max-height: 85vh;
  overflow-y: auto;
  animation: deskFadeIn 0.8s ease-out;
}

@keyframes deskFadeIn {
  from {
    opacity: 0;
    transform: scale(0.95) translateY(20px);
  }
  to {
    opacity: 1;
    transform: scale(1) translateY(0);
  }
}

.scrapbook-layout {
  display: flex;
  gap: 40px;
  align-items: flex-start;
}

.left-column {
  display: flex;
  flex-direction: column;
  gap: 25px;
  flex-shrink: 0;
}

// === POLAROID PHOTO ===
.polaroid-wrapper {
  position: relative;
  animation: itemFade 0.6s ease-out 0.2s both;
}

@keyframes itemFade {
  from {
    opacity: 0;
    transform: translateY(-15px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

.polaroid {
  background: linear-gradient(
    180deg,
    #fefefa 0%,
    #f5f0e6 50%,
    #ebe4d4 100%
  );
  padding: 12px 12px 50px 12px;
  box-shadow:
    0 8px 25px rgba(0, 0, 0, 0.5),
    0 2px 5px rgba(0, 0, 0, 0.3),
    inset 0 0 0 1px rgba(0, 0, 0, 0.05);
}

.polaroid-image {
  width: 240px;
  height: 180px;
  object-fit: cover;
  display: block;
  filter: sepia(20%) contrast(1.05) brightness(0.95) saturate(0.9);
}

.polaroid-caption {
  position: absolute;
  bottom: 15px;
  left: 0;
  right: 0;
  text-align: center;
  font-family: $typewriter;
  font-size: 13px;
  color: $ink-faded;
}

// === TAPE STRIPS ===
.tape {
  position: absolute;
  background: linear-gradient(
    180deg,
    rgba(255, 248, 220, 0.8) 0%,
    rgba(245, 235, 200, 0.75) 50%,
    rgba(255, 248, 220, 0.8) 100%
  );
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.2),
    inset 0 0 0 1px rgba(255, 255, 255, 0.3);
  z-index: 10;

  &::before {
    content: '';
    position: absolute;
    inset: 0;
    background: repeating-linear-gradient(
      90deg,
      transparent 0px,
      rgba(0, 0, 0, 0.02) 1px,
      transparent 2px,
      transparent 4px
    );
  }
}

.tape-top {
  width: 70px;
  height: 22px;
  top: -8px;
  left: 50%;
  transform: translateX(-50%);
}

.tape-clipping {
  width: 55px;
  height: 18px;
  top: -6px;
  left: 50%;
  transform: translateX(-50%);
}

// === LETTER ===
.letter-wrapper {
  position: relative;
  flex: 1;
  animation: itemFade 0.6s ease-out 0.3s both;
}

.paper-clip {
  position: absolute;
  top: 15px;
  left: -12px;
  width: 26px;
  height: 70px;
  z-index: 10;

  &::before {
    content: '';
    position: absolute;
    top: 0;
    left: 6px;
    width: 18px;
    height: 60px;
    border: 3px solid #888;
    border-radius: 9px 9px 0 0;
    border-bottom: none;
    background: transparent;
    box-shadow:
      1px 1px 2px rgba(0,0,0,0.3),
      inset 0 0 0 1px rgba(255,255,255,0.15);
  }

  &::after {
    content: '';
    position: absolute;
    top: 12px;
    left: 10px;
    width: 10px;
    height: 38px;
    border: 2px solid #999;
    border-radius: 5px 5px 0 0;
    border-bottom: none;
    background: transparent;
  }
}

.letter-paper {
  background:
    radial-gradient(ellipse at 15% 85%, rgba(180, 150, 100, 0.06) 0%, transparent 50%),
    radial-gradient(ellipse at 85% 15%, rgba(180, 150, 100, 0.04) 0%, transparent 50%),
    linear-gradient(
      180deg,
      $paper-cream 0%,
      $paper-aged 100%
    );
  padding: 40px 45px;
  min-height: 480px;
  box-shadow:
    0 10px 40px rgba(0, 0, 0, 0.4),
    0 2px 8px rgba(0, 0, 0, 0.2),
    inset 0 0 50px rgba(139, 115, 85, 0.08);
}

.letter-content {
  font-family: $typewriter;
  color: $ink-dark;
}

.letter-greeting {
  font-size: 18px;
  margin-bottom: 30px;
  color: $ink-dark;
}

.letter-body {
  font-size: 15px;
  line-height: 1.9;

  p {
    margin-bottom: 20px;
    text-indent: 40px;

    &:last-child {
      margin-bottom: 0;
    }
  }
}

.letter-closing {
  margin-top: 40px;
  text-align: right;

  .closing-text {
    font-size: 15px;
    color: $ink-faded;
    margin-bottom: 8px;
  }

  .signature {
    font-size: 18px;
    color: $ink-dark;
  }
}

.postscript {
  margin-top: 35px;
  font-size: 14px;
  color: $ink-faded;
  padding-left: 20px;
  border-left: 2px solid rgba(100, 80, 60, 0.25);
}

// === NEWSPAPER CLIPPING ===
.clipping-wrapper {
  position: relative;
  animation: itemFade 0.6s ease-out 0.4s both;
}

.newspaper-clipping {
  background:
    repeating-linear-gradient(
      0deg,
      transparent 0px,
      rgba(0, 0, 0, 0.015) 1px,
      transparent 2px,
      transparent 3px
    ),
    linear-gradient(
      180deg,
      #f5ecd0 0%,
      #ebe0c0 50%,
      #e0d4b0 100%
    );
  padding: 15px 20px;
  box-shadow:
    0 5px 15px rgba(0, 0, 0, 0.35),
    inset 0 0 20px rgba(100, 80, 50, 0.08);
  width: 264px;
}

.clipping-masthead {
  font-family: $newspaper;
  font-size: 9px;
  text-transform: uppercase;
  letter-spacing: 3px;
  color: #666;
  border-bottom: 1px solid #aaa;
  padding-bottom: 6px;
  margin-bottom: 12px;
}

.clipping-headline {
  font-family: $newspaper;
  font-size: 24px;
  font-weight: bold;
  color: #1a1a1a;
  text-transform: uppercase;
  letter-spacing: 1px;
  line-height: 1.1;
}

.clipping-subhead {
  font-family: $newspaper;
  font-size: 12px;
  color: #555;
  font-style: italic;
  margin-top: 6px;
}

.clipping-handwritten {
  font-family: $typewriter;
  font-size: 14px;
  color: #333;
  margin-top: 15px;
  font-weight: bold;
}

// === CONTINUE BUTTON ===
.continue-btn {
  display: block;
  margin: 45px auto 0;
  padding: 14px 45px;
  font-family: $typewriter;
  font-size: 16px;
  text-transform: uppercase;
  letter-spacing: 2px;
  background: linear-gradient(180deg, #4a4a4a 0%, #2a2a2a 100%);
  color: #e8e8e8;
  border: none;
  border-radius: 3px;
  cursor: pointer;
  transition: all 0.3s ease;
  box-shadow:
    0 4px 15px rgba(0, 0, 0, 0.4),
    inset 0 1px 0 rgba(255, 255, 255, 0.1);

  &:hover {
    transform: translateY(-2px);
    box-shadow: 0 6px 20px rgba(0, 0, 0, 0.5);
    background: linear-gradient(180deg, #5a5a5a 0%, #3a3a3a 100%);
  }

  &:active {
    transform: translateY(0);
  }
}
</style>
