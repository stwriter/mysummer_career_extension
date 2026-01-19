<template>
  <div class="race-hud" v-if="raceActive">
    <!-- Position Display -->
    <div class="position-display">
      <div class="position-number">{{ playerPosition }}</div>
      <div class="position-suffix">{{ positionSuffix }}</div>
      <div class="total-racers">/ {{ totalRacers }}</div>
    </div>

    <!-- Lap Counter (for circuits) -->
    <div class="lap-display" v-if="totalLaps > 1">
      <span class="lap-label">LAP</span>
      <span class="lap-current">{{ currentLap }}</span>
      <span class="lap-separator">/</span>
      <span class="lap-total">{{ totalLaps }}</span>
    </div>

    <!-- Time Display -->
    <div class="time-display">
      <div class="time-value">{{ formattedTime }}</div>
    </div>

    <!-- Checkpoint Progress -->
    <div class="checkpoint-display">
      <div class="checkpoint-bar">
        <div class="checkpoint-fill" :style="{ width: checkpointProgress + '%' }"></div>
      </div>
      <div class="checkpoint-text">{{ currentCheckpoint }} / {{ totalCheckpoints }}</div>
    </div>

    <!-- Mini Leaderboard -->
    <div class="mini-leaderboard">
      <div
        v-for="(racer, index) in topRacers"
        :key="racer.name"
        class="leaderboard-entry"
        :class="{ 'is-player': racer.isPlayer }"
      >
        <span class="lb-position">{{ racer.position }}</span>
        <span class="lb-name">{{ racer.name }}</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useEvents } from '@/services/events'

const events = useEvents()

// State
const raceActive = ref(false)
const raceName = ref('')
const playerPosition = ref(1)
const totalRacers = ref(1)
const currentLap = ref(1)
const totalLaps = ref(1)
const elapsedTime = ref(0)
const currentCheckpoint = ref(0)
const totalCheckpoints = ref(1)
const positions = ref([])

// Computed
const positionSuffix = computed(() => {
  const pos = playerPosition.value
  if (pos === 1) return 'st'
  if (pos === 2) return 'nd'
  if (pos === 3) return 'rd'
  return 'th'
})

const formattedTime = computed(() => {
  const secs = elapsedTime.value
  const mins = Math.floor(secs / 60)
  const remainingSecs = (secs % 60).toFixed(2)
  return `${mins}:${remainingSecs.padStart(5, '0')}`
})

const checkpointProgress = computed(() => {
  if (totalCheckpoints.value === 0) return 0
  return (currentCheckpoint.value / totalCheckpoints.value) * 100
})

const topRacers = computed(() => {
  return positions.value.slice(0, 5)
})

// Event handlers
function onRaceStarted(data) {
  raceActive.value = true
  raceName.value = data.raceName || ''
  totalLaps.value = data.totalLaps || 1
  totalRacers.value = data.racerCount || 1
  currentLap.value = 1
  currentCheckpoint.value = 0
}

function onRaceTime(data) {
  elapsedTime.value = data.elapsed || 0
}

function onRacePositions(data) {
  positions.value = data || []

  // Find player position
  for (const racer of positions.value) {
    if (racer.isPlayer) {
      playerPosition.value = racer.position
      currentLap.value = racer.lap || 1
      currentCheckpoint.value = racer.checkpoint || 0
      break
    }
  }
}

function onRaceCheckpoint(data) {
  currentCheckpoint.value = data.checkpoint || 0
  totalCheckpoints.value = data.total || 1
}

function onRaceLapComplete(data) {
  currentLap.value = data.lap + 1
}

function onRaceResults() {
  raceActive.value = false
}

function onRaceCancelled() {
  raceActive.value = false
}

// Lifecycle
onMounted(() => {
  events.on('mysummerRaceStarted', onRaceStarted)
  events.on('mysummerRaceTime', onRaceTime)
  events.on('mysummerRacePositions', onRacePositions)
  events.on('mysummerRaceCheckpoint', onRaceCheckpoint)
  events.on('mysummerRaceLapComplete', onRaceLapComplete)
  events.on('mysummerRaceResults', onRaceResults)
  events.on('mysummerRaceCancelled', onRaceCancelled)
})

onUnmounted(() => {
  events.off('mysummerRaceStarted', onRaceStarted)
  events.off('mysummerRaceTime', onRaceTime)
  events.off('mysummerRacePositions', onRacePositions)
  events.off('mysummerRaceCheckpoint', onRaceCheckpoint)
  events.off('mysummerRaceLapComplete', onRaceLapComplete)
  events.off('mysummerRaceResults', onRaceResults)
  events.off('mysummerRaceCancelled', onRaceCancelled)
})
</script>

<style lang="scss" scoped>
.race-hud {
  position: fixed;
  top: 20px;
  right: 20px;
  display: flex;
  flex-direction: column;
  gap: 10px;
  font-family: 'Roboto Mono', monospace;
  color: white;
  text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.8);
}

.position-display {
  display: flex;
  align-items: baseline;
  background: rgba(0, 0, 0, 0.7);
  padding: 10px 20px;
  border-radius: 8px;
  border-left: 4px solid #ff6b00;

  .position-number {
    font-size: 4rem;
    font-weight: bold;
    color: #ff6b00;
  }

  .position-suffix {
    font-size: 1.5rem;
    color: #ff6b00;
    margin-right: 8px;
  }

  .total-racers {
    font-size: 1.5rem;
    opacity: 0.7;
  }
}

.lap-display {
  background: rgba(0, 0, 0, 0.7);
  padding: 8px 16px;
  border-radius: 8px;
  font-size: 1.2rem;
  display: flex;
  align-items: center;
  gap: 8px;

  .lap-label {
    color: #888;
    font-size: 0.9rem;
  }

  .lap-current {
    font-size: 1.5rem;
    font-weight: bold;
    color: #4caf50;
  }

  .lap-separator {
    opacity: 0.5;
  }

  .lap-total {
    opacity: 0.7;
  }
}

.time-display {
  background: rgba(0, 0, 0, 0.7);
  padding: 8px 16px;
  border-radius: 8px;

  .time-value {
    font-size: 1.8rem;
    font-weight: bold;
    letter-spacing: 2px;
  }
}

.checkpoint-display {
  background: rgba(0, 0, 0, 0.7);
  padding: 8px 16px;
  border-radius: 8px;

  .checkpoint-bar {
    height: 6px;
    background: rgba(255, 255, 255, 0.2);
    border-radius: 3px;
    overflow: hidden;
    margin-bottom: 4px;

    .checkpoint-fill {
      height: 100%;
      background: linear-gradient(90deg, #4caf50, #8bc34a);
      transition: width 0.3s ease;
    }
  }

  .checkpoint-text {
    font-size: 0.9rem;
    text-align: center;
    opacity: 0.8;
  }
}

.mini-leaderboard {
  background: rgba(0, 0, 0, 0.7);
  padding: 10px;
  border-radius: 8px;
  min-width: 200px;

  .leaderboard-entry {
    display: flex;
    gap: 10px;
    padding: 4px 8px;
    font-size: 0.9rem;

    &.is-player {
      background: rgba(255, 107, 0, 0.3);
      border-radius: 4px;
      font-weight: bold;
    }

    .lb-position {
      width: 20px;
      text-align: right;
      font-weight: bold;
    }

    .lb-name {
      flex: 1;
      overflow: hidden;
      text-overflow: ellipsis;
      white-space: nowrap;
    }
  }
}
</style>
