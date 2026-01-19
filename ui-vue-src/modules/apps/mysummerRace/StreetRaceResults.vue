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
        <div class="player-result" :class="medalClass">
          <div class="position-badge" v-if="position > 0">
            <span class="position-number">{{ position }}</span>
            <span class="position-suffix">{{ positionSuffix }}</span>
          </div>
          <div class="position-badge unknown" v-else>
            <span class="position-text">FINISHED</span>
          </div>
          <div class="player-time">{{ formattedTime }}</div>
        </div>

        <!-- Medal Display -->
        <div class="medal-display" v-if="medal">
          <div class="medal-icon" :class="medal">
            <span v-if="medal === 'gold'">🥇</span>
            <span v-else-if="medal === 'silver'">🥈</span>
            <span v-else-if="medal === 'bronze'">🥉</span>
          </div>
          <div class="medal-text">{{ medal.toUpperCase() }}</div>
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

        <!-- No Rewards Message -->
        <div class="no-rewards" v-else>
          <p>Check your career progress for rewards!</p>
        </div>

        <!-- Actions -->
        <div class="actions">
          <button class="action-btn primary" @click="close">
            CONTINUE
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useEvents } from '@/services/events'

const events = useEvents()

// State
const showResults = ref(false)
const raceName = ref('')
const position = ref(0)
const formattedTime = ref('0:00.00')
const moneyEarned = ref(0)
const reputationEarned = ref(0)
const medal = ref(null)

// Computed
const positionSuffix = computed(() => {
  const pos = position.value
  if (pos === 1) return 'st'
  if (pos === 2) return 'nd'
  if (pos === 3) return 'rd'
  return 'th'
})

const medalClass = computed(() => {
  if (position.value === 1 || medal.value === 'gold') return 'position-1'
  if (position.value === 2 || medal.value === 'silver') return 'position-2'
  if (position.value === 3 || medal.value === 'bronze') return 'position-3'
  return ''
})

// Methods
function close() {
  showResults.value = false
}

// Event handlers
function onStreetRaceResults(data) {
  
  raceName.value = data.raceName || 'Street Race'
  position.value = data.position || 0
  formattedTime.value = data.formattedTime || '0:00.00'
  moneyEarned.value = data.moneyEarned || 0
  reputationEarned.value = data.reputationEarned || 0
  medal.value = data.medal || null
  showResults.value = true
}

// Lifecycle
onMounted(() => {
  events.on('mysummerStreetRaceResults', onStreetRaceResults)
})

onUnmounted(() => {
  events.off('mysummerStreetRaceResults', onStreetRaceResults)
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
  min-width: 400px;
  max-width: 500px;
  box-shadow: 0 20px 60px rgba(0, 0, 0, 0.5);
}

.results-header {
  text-align: center;
  margin-bottom: 20px;

  h1 {
    font-size: 2rem;
    font-weight: bold;
    color: #ff3333;
    margin: 0;
    text-transform: uppercase;
    letter-spacing: 4px;
  }

  h2 {
    font-size: 1.1rem;
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

    &.unknown .position-text {
      font-size: 1.5rem;
      color: #888;
    }
  }

  .player-time {
    font-size: 2rem;
    font-family: 'Roboto Mono', monospace;
    color: white;
  }
}

.medal-display {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 15px;
  margin-bottom: 20px;

  .medal-icon {
    font-size: 3rem;
  }

  .medal-text {
    font-size: 1.5rem;
    font-weight: bold;
    letter-spacing: 3px;

    &.gold { color: gold; }
    &.silver { color: silver; }
    &.bronze { color: #cd7f32; }
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
    text-align: center;
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

.no-rewards {
  text-align: center;
  padding: 15px;
  color: #666;
  margin-bottom: 20px;

  p {
    margin: 0;
  }
}

.actions {
  display: flex;
  justify-content: center;

  .action-btn {
    padding: 14px 50px;
    font-size: 1rem;
    font-weight: bold;
    border: none;
    border-radius: 8px;
    cursor: pointer;
    transition: all 0.2s ease;
    text-transform: uppercase;
    letter-spacing: 2px;

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
</style>
