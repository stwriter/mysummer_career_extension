<template>
  <PhoneWrapper app-name="Races" status-font-color="#FFFFFF" status-blend-mode="">
    <div class="races-screen">
      <div class="races-header">
        <h2>Available Races</h2>
        <p>Select a race to compete</p>
      </div>

      <div class="races-list" v-if="races.length > 0">
        <div
          v-for="race in races"
          :key="race.id || race.name"
          class="race-card"
          :class="{ selected: selectedRace === (race.id || race.name) }"
          @click="selectRace(race)"
        >
          <div class="race-info">
            <div class="race-name-row">
              <span class="race-name">{{ race.name }}</span>
              <span class="race-badge" v-if="race.isNative">STREET</span>
              <span class="race-badge custom" v-else-if="race.source === 'custom'">CUSTOM</span>
            </div>
            <div class="race-details">
              <span class="race-difficulty" :class="race.difficulty" v-if="race.difficulty">
                {{ race.difficulty }}
              </span>
            </div>
          </div>
        </div>
      </div>

      <div class="empty-state" v-else>
        <p>No races available.</p>
      </div>

      <div class="actions" v-if="selectedRaceData">
        <button class="action-btn primary" @click="startRace">
          START RACE
        </button>
      </div>
    </div>
  </PhoneWrapper>
</template>

<script setup>
import PhoneWrapper from "./PhoneWrapper.vue"
import { ref, onMounted } from 'vue'
import { lua } from "@/bridge"

const races = ref([])
const selectedRace = ref(null)
const selectedRaceData = ref(null)

function selectRace(race) {
  selectedRace.value = race.id || race.name
  selectedRaceData.value = race
}

async function startRace() {
  if (selectedRaceData.value) {
    const race = selectedRaceData.value

    if (race.isNative && race.id) {
      bngApi.engineLua(`career_modules_mysummerRaceManager.startNativeMission("${race.id}")`)
    } else if (race.source === 'custom') {
      bngApi.engineLua(`career_modules_mysummerRaceManager.startRace("${race.name}")`)
    }

    bngApi.engineLua('career_modules_phone.closePhone()')
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

onMounted(() => {
  loadRaces()
})
</script>

<style scoped lang="scss">
.races-screen {
  padding: 16px;
  padding-top: 72px;
  height: 100%;
  display: flex;
  flex-direction: column;
  box-sizing: border-box;
  overflow-y: auto;
}

.races-header {
  text-align: center;
  margin-bottom: 16px;

  h2 {
    font-size: 1.2rem;
    color: white;
    margin: 0;
  }

  p {
    color: #888;
    margin: 4px 0 0;
    font-size: 0.8rem;
  }
}

.races-list {
  flex: 1;
  overflow-y: auto;

  .race-card {
    display: flex;
    justify-content: space-between;
    align-items: center;
    padding: 12px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid #333;
    border-radius: 8px;
    margin-bottom: 8px;
    cursor: pointer;
    transition: all 0.2s ease;

    &:hover {
      background: rgba(255, 255, 255, 0.1);
      border-color: #444;
    }

    &.selected {
      background: rgba(255, 51, 51, 0.2);
      border-color: #ff3333;
    }

    .race-info {
      .race-name-row {
        display: flex;
        align-items: center;
        gap: 8px;
        margin-bottom: 4px;
      }

      .race-name {
        font-size: 0.9rem;
        font-weight: bold;
        color: white;
      }

      .race-badge {
        font-size: 0.6rem;
        font-weight: bold;
        padding: 2px 6px;
        border-radius: 3px;
        background: #ff3333;
        color: white;

        &.custom {
          background: #2196f3;
        }
      }

      .race-details {
        .race-difficulty {
          font-size: 0.7rem;
          padding: 2px 6px;
          border-radius: 3px;
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
  }
}

.empty-state {
  text-align: center;
  padding: 40px 20px;
  color: #666;
}

.actions {
  padding-top: 16px;

  .action-btn {
    width: 100%;
    padding: 14px;
    font-size: 1rem;
    font-weight: bold;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    text-transform: uppercase;
    letter-spacing: 1px;

    &.primary {
      background: linear-gradient(135deg, #ff3333 0%, #ff6666 100%);
      color: white;

      &:hover {
        transform: translateY(-2px);
        box-shadow: 0 5px 20px rgba(255, 51, 51, 0.4);
      }
    }
  }
}

:deep(.phone-content) {
  background: linear-gradient(to bottom, #1a0a0a, #2a0a0a);
}
</style>
