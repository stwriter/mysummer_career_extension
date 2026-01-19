<template>
  <Teleport to="body">
    <div class="select-overlay" v-if="showSelect" @click.self="close">
      <div class="select-modal">
        <!-- Header -->
        <div class="select-header">
          <h1>SELECT RACE</h1>
          <p>Choose a race to compete in</p>
        </div>
        <!-- Race List -->
        <div class="race-list" v-if="races.length > 0">
          <div
            v-for="race in races"
            :key="race.name"
            class="race-card"
            :class="{ selected: selectedRace === race.name }"
            @click="selectRace(race)"
          >
            <div class="race-info">
              <div class="race-name-row">
                <span class="race-name">{{ race.name }}</span>
                <span class="race-source" v-if="race.source === 'bundled'">STREET</span>
                <span class="race-source custom" v-else-if="race.source === 'custom'">CUSTOM</span>
              </div>
              <div class="race-details">
                <span class="race-type">{{ formatType(race.type) }}</span>
                <span class="race-laps" v-if="race.laps > 1">{{ race.laps }} laps</span>
                <span class="race-difficulty" :class="race.difficulty" v-if="race.difficulty">
                  {{ race.difficulty }}
                </span>
              </div>
            </div>
            <div class="race-meta">
              <div class="race-ai" v-if="race.type !== 'timeattack'">
                {{ race.aiConfig?.count || 4 }} AI
              </div>
              <div class="race-reward">
                ${{ (race.rewards?.money?.first || 5000).toLocaleString() }}
              </div>
            </div>
          </div>
        </div>
        <!-- Empty State -->
        <div class="empty-state" v-else>
          <p>No races available for this level.</p>
          <p class="hint">Create races using the Race Editor (console command + Shift+B)</p>
        </div>
        <!-- Selected Race Info -->
        <div class="selected-info" v-if="selectedRaceData">
          <div class="info-description" v-if="selectedRaceData.description">
            {{ selectedRaceData.description }}
          </div>
        </div>
        <!-- Actions -->
        <div class="actions">
          <button class="action-btn secondary" @click="close">
            CANCEL
          </button>
          <button
            class="action-btn primary"
            :disabled="!selectedRace"
            @click="startRace"
          >
            START RACE
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>
<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useEvents } from '@/services/events'
import { useBridge } from '@/bridge'
const events = useEvents()
const { lua } = useBridge()
// State
const showSelect = ref(false)
const races = ref([])
const selectedRace = ref(null)
const selectedRaceData = ref(null)
// Methods
function formatType(type) {
  const types = {
    sprint: 'Sprint',
    timeattack: 'Time Attack',
    rally: 'Rally Stage',
    circuit: 'Circuit'
  }
  return types[type] || type
}
function close() {
  showSelect.value = false
  selectedRace.value = null
  selectedRaceData.value = null
}
function selectRace(race) {
  selectedRace.value = race.name
  selectedRaceData.value = race
}
async function startRace() {
  if (selectedRaceData.value) {
    const race = selectedRaceData.value
    if (race.isNative && race.id) {
      // Native BeamNG mission - use the mission system
      bngApi.engineLua(`career_modules_mysummerRaceManager.startNativeMission("${race.id}")`)
    } else if (race.source === 'custom') {
      // Custom race - start by name
      bngApi.engineLua(`career_modules_mysummerRaceManager.startRace("${race.name}")`)
    }
    close()
  }
}
async function loadRaces() {
  try {
    const result = await lua.career_modules_mysummerRaceManager.getAvailableRaces()
    if (result) {
      races.value = Object.values(result)
    }
  } catch (e) {
    races.value = []
  }
}
// Event handlers
function onShowRaceSelect(data) {
  loadRaces()
  showSelect.value = true
}
// Lifecycle
onMounted(() => {
  events.on('mysummerShowRaceSelect', onShowRaceSelect)
})
onUnmounted(() => {
  events.off('mysummerShowRaceSelect', onShowRaceSelect)
})
</script>
<style lang="scss" scoped>
.select-overlay {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  background: rgba(0, 0, 0, 0.85);
  display: flex;
  align-items: center;
  justify-content: center;
  z-index: 9999;
}
.select-modal {
  background: linear-gradient(180deg, #1a1a2e 0%, #0f0f1a 100%);
  border: 2px solid #333;
  border-radius: 16px;
  padding: 25px 35px;
  min-width: 550px;
  max-width: 650px;
  max-height: 80vh;
}
.select-header {
  text-align: center;
  margin-bottom: 20px;
  h1 {
    font-size: 1.8rem;
    color: #ff6b00;
    margin: 0;
    letter-spacing: 3px;
  }
  p {
    color: #666;
    margin: 8px 0 0;
  }
}
.race-list {
  max-height: 350px;
  overflow-y: auto;
  margin-bottom: 15px;
  .race-card {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px 16px;
    background: rgba(255, 255, 255, 0.03);
    border: 1px solid #333;
    border-radius: 8px;
    margin-bottom: 6px;
    cursor: pointer;
    transition: all 0.2s ease;
    &:hover {
      background: rgba(255, 255, 255, 0.06);
      border-color: #444;
    }
    &.selected {
      background: rgba(255, 107, 0, 0.15);
      border-color: #ff6b00;
    }
    .race-info {
      .race-name-row {
        display: flex;
        align-items: center;
        gap: 10px;
        margin-bottom: 4px;
      }
      .race-name {
        font-size: 1rem;
        font-weight: bold;
        color: white;
      }
      .race-source {
        font-size: 0.65rem;
        font-weight: bold;
        padding: 2px 6px;
        border-radius: 3px;
        background: #ff6b00;
        color: white;
        letter-spacing: 0.5px;
        &.custom {
          background: #2196f3;
        }
      }
      .race-details {
        display: flex;
        gap: 10px;
        font-size: 0.75rem;
        color: #666;
        .race-type {
          color: #4caf50;
          font-weight: 500;
        }
        .race-laps {
          color: #888;
        }
        .race-difficulty {
          padding: 1px 5px;
          border-radius: 3px;
          font-size: 0.7rem;
          text-transform: uppercase;
          &.high {
            background: rgba(244, 67, 54, 0.2);
            color: #f44336;
          }
          &.medium {
            background: rgba(255, 152, 0, 0.2);
            color: #ff9800;
          }
          &.low {
            background: rgba(76, 175, 80, 0.2);
            color: #4caf50;
          }
        }
      }
    }
    .race-meta {
      text-align: right;
      .race-ai {
        font-size: 0.8rem;
        color: #888;
      }
      .race-reward {
        font-size: 0.95rem;
        font-weight: bold;
        color: #4caf50;
      }
    }
  }
}
.selected-info {
  background: rgba(255, 255, 255, 0.03);
  border-radius: 8px;
  padding: 12px 15px;
  margin-bottom: 15px;
  .info-description {
    font-size: 0.8rem;
    color: #999;
    line-height: 1.4;
    max-height: 60px;
    overflow-y: auto;
  }
}
.empty-state {
  text-align: center;
  padding: 40px 20px;
  color: #666;
  p {
    margin: 8px 0;
  }
  .hint {
    font-size: 0.85rem;
    color: #555;
  }
}
.actions {
  display: flex;
  gap: 15px;
  justify-content: center;
  .action-btn {
    padding: 12px 30px;
    font-size: 1rem;
    font-weight: bold;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.2s ease;
    text-transform: uppercase;
    letter-spacing: 1px;
    &.primary {
      background: linear-gradient(135deg, #ff6b00 0%, #ff8c00 100%);
      color: white;
      &:hover:not(:disabled) {
        transform: translateY(-2px);
        box-shadow: 0 5px 20px rgba(255, 107, 0, 0.4);
      }
      &:disabled {
        opacity: 0.5;
        cursor: not-allowed;
      }
    }
    &.secondary {
      background: rgba(255, 255, 255, 0.1);
      color: #888;
      border: 1px solid #444;
      &:hover {
        background: rgba(255, 255, 255, 0.15);
        color: white;
      }
    }
  }
}
</style>
