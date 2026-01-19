<template>
  <Teleport to="body">
    <div class="results-overlay" v-if="showResults" @click.self="close">
      <div class="results-modal">
        <!-- Header -->
        <div class="results-header">
          <h1>RACE COMPLETE</h1>
          <h2>{{ raceName }}</h2>
        </div>

        <!-- Player Result -->
        <div class="player-result" :class="'position-' + playerPosition">
          <div class="position-badge">
            <span class="position-number">{{ playerPosition }}</span>
            <span class="position-suffix">{{ positionSuffix }}</span>
          </div>
          <div class="player-time">{{ playerTime }}</div>
        </div>

        <!-- Full Standings -->
        <div class="standings">
          <div
            v-for="result in results"
            :key="result.name"
            class="standing-row"
            :class="{ 'is-player': result.isPlayer, 'is-dnf': result.time < 0 }"
          >
            <div class="standing-position">{{ result.position }}</div>
            <div class="standing-name">{{ result.name }}</div>
            <div class="standing-time">{{ result.formattedTime }}</div>
            <div class="standing-gap" v-if="result.position > 1 && result.time > 0">
              +{{ formatGap(result.time - results[0].time) }}
            </div>
          </div>
        </div>

        <!-- Rewards -->
        <div class="rewards" v-if="moneyEarned > 0 || reputationEarned > 0">
          <div class="rewards-title">REWARDS</div>
          <div class="rewards-list">
            <div class="reward-item" v-if="moneyEarned > 0">
              <span class="reward-icon">$</span>
              <span class="reward-value">{{ moneyEarned.toLocaleString() }}</span>
            </div>
            <div class="reward-item" v-if="reputationEarned > 0">
              <span class="reward-icon">REP</span>
              <span class="reward-value">+{{ reputationEarned }}</span>
            </div>
          </div>
        </div>

        <!-- Actions -->
        <div class="actions">
          <button class="action-btn secondary" @click="close">
            EXIT
          </button>
          <button class="action-btn primary" @click="raceAgain">
            RACE AGAIN
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
const showResults = ref(false)
const raceName = ref('')
const results = ref([])
const playerPosition = ref(1)
const playerTime = ref('0:00.00')
const moneyEarned = ref(0)
const reputationEarned = ref(0)
const lastRaceName = ref('')

// Computed
const positionSuffix = computed(() => {
  const pos = playerPosition.value
  if (pos === 1) return 'st'
  if (pos === 2) return 'nd'
  if (pos === 3) return 'rd'
  return 'th'
})

// Methods
function formatGap(seconds) {
  if (seconds < 60) {
    return seconds.toFixed(2) + 's'
  }
  const mins = Math.floor(seconds / 60)
  const secs = (seconds % 60).toFixed(2)
  return `${mins}:${secs.padStart(5, '0')}`
}

function close() {
  showResults.value = false
  lua.career_modules_mysummerRaceManager.cleanupRace()
}

function raceAgain() {
  showResults.value = false
  if (lastRaceName.value) {
    lua.career_modules_mysummerRaceManager.startRace(lastRaceName.value)
  }
}

// Event handlers
function onRaceResults(data) {
  raceName.value = data.raceName || 'Race'
  results.value = data.results || []
  playerPosition.value = data.playerPosition || 1
  playerTime.value = data.playerTime || '0:00.00'
  moneyEarned.value = data.moneyEarned || 0
  reputationEarned.value = data.reputationEarned || 0
  lastRaceName.value = data.raceName
  showResults.value = true
}

// Lifecycle
onMounted(() => {
  events.on('mysummerRaceResults', onRaceResults)
})

onUnmounted(() => {
  events.off('mysummerRaceResults', onRaceResults)
})
</script>

<style lang="scss" scoped>
.results-overlay {
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
  animation: fadeIn 0.3s ease;
}

@keyframes fadeIn {
  from { opacity: 0; }
  to { opacity: 1; }
}

.results-modal {
  background: linear-gradient(180deg, #1a1a2e 0%, #0f0f1a 100%);
  border: 2px solid #333;
  border-radius: 16px;
  padding: 30px 40px;
  min-width: 500px;
  max-width: 600px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
}

.results-header {
  text-align: center;
  margin-bottom: 20px;

  h1 {
    font-size: 2.5rem;
    font-weight: bold;
    color: #ff6b00;
    margin: 0;
    text-transform: uppercase;
    letter-spacing: 4px;
  }

  h2 {
    font-size: 1.2rem;
    color: #888;
    margin: 8px 0 0;
    font-weight: normal;
  }
}

.player-result {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 30px;
  padding: 20px;
  margin-bottom: 20px;
  border-radius: 12px;
  background: rgba(255, 255, 255, 0.05);

  &.position-1 {
    background: linear-gradient(135deg, rgba(255, 215, 0, 0.2) 0%, rgba(255, 215, 0, 0.05) 100%);
    border: 1px solid rgba(255, 215, 0, 0.5);

    .position-badge {
      color: gold;
    }
  }

  &.position-2 {
    background: linear-gradient(135deg, rgba(192, 192, 192, 0.2) 0%, rgba(192, 192, 192, 0.05) 100%);
    border: 1px solid rgba(192, 192, 192, 0.5);

    .position-badge {
      color: silver;
    }
  }

  &.position-3 {
    background: linear-gradient(135deg, rgba(205, 127, 50, 0.2) 0%, rgba(205, 127, 50, 0.05) 100%);
    border: 1px solid rgba(205, 127, 50, 0.5);

    .position-badge {
      color: #cd7f32;
    }
  }

  .position-badge {
    display: flex;
    align-items: baseline;

    .position-number {
      font-size: 4rem;
      font-weight: bold;
    }

    .position-suffix {
      font-size: 1.5rem;
    }
  }

  .player-time {
    font-size: 2rem;
    font-family: 'Roboto Mono', monospace;
    color: white;
  }
}

.standings {
  margin-bottom: 20px;
  max-height: 250px;
  overflow-y: auto;

  .standing-row {
    display: grid;
    grid-template-columns: 40px 1fr 100px 80px;
    gap: 10px;
    padding: 10px 15px;
    border-radius: 6px;
    margin-bottom: 4px;
    background: rgba(255, 255, 255, 0.03);
    color: #ccc;
    font-size: 0.95rem;

    &.is-player {
      background: rgba(255, 107, 0, 0.2);
      color: white;
      font-weight: bold;
    }

    &.is-dnf {
      opacity: 0.5;
    }

    .standing-position {
      font-weight: bold;
      text-align: center;
    }

    .standing-name {
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }

    .standing-time {
      font-family: 'Roboto Mono', monospace;
      text-align: right;
    }

    .standing-gap {
      font-family: 'Roboto Mono', monospace;
      text-align: right;
      color: #ff6b6b;
      font-size: 0.85rem;
    }
  }
}

.rewards {
  background: rgba(76, 175, 80, 0.1);
  border: 1px solid rgba(76, 175, 80, 0.3);
  border-radius: 10px;
  padding: 15px 20px;
  margin-bottom: 20px;

  .rewards-title {
    font-size: 0.8rem;
    color: #4caf50;
    letter-spacing: 2px;
    margin-bottom: 10px;
  }

  .rewards-list {
    display: flex;
    gap: 30px;
    justify-content: center;

    .reward-item {
      display: flex;
      align-items: center;
      gap: 8px;

      .reward-icon {
        font-size: 1.2rem;
        color: #4caf50;
        font-weight: bold;
      }

      .reward-value {
        font-size: 1.5rem;
        font-weight: bold;
        color: white;
      }
    }
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

      &:hover {
        transform: translateY(-2px);
        box-shadow: 0 5px 20px rgba(255, 107, 0, 0.4);
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
