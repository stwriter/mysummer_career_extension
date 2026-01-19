<template>
  <Teleport to="body">
    <div class="config-overlay" v-if="showConfig" @click.self="cancel">
      <div class="config-modal">
        <!-- Header -->
        <div class="config-header">
          <h1>CONFIGURE RACE</h1>
          <input
            type="text"
            v-model="raceData.name"
            class="race-name-input"
            placeholder="Enter race name..."
          />
        </div>

        <!-- Race Type -->
        <div class="config-section">
          <label class="section-label">RACE TYPE</label>
          <div class="button-group">
            <button
              v-for="type in raceTypes"
              :key="type.value"
              class="type-btn"
              :class="{ active: raceData.type === type.value }"
              @click="raceData.type = type.value"
            >
              {{ type.label }}
            </button>
          </div>
        </div>

        <!-- Laps (for circuit) -->
        <div class="config-section" v-if="raceData.closed">
          <label class="section-label">LAPS</label>
          <div class="button-group">
            <button
              v-for="lap in [1, 3, 5, 10]"
              :key="lap"
              class="lap-btn"
              :class="{ active: raceData.laps === lap }"
              @click="raceData.laps = lap"
            >
              {{ lap }}
            </button>
            <input
              type="number"
              v-model.number="customLaps"
              class="custom-input"
              min="1"
              max="99"
              placeholder="Custom"
              @input="raceData.laps = customLaps"
            />
          </div>
        </div>

        <!-- Traffic -->
        <div class="config-section">
          <label class="section-label">TRAFFIC</label>
          <div class="button-group">
            <button
              class="toggle-btn"
              :class="{ active: raceData.settings.traffic }"
              @click="raceData.settings.traffic = true"
            >
              ON
            </button>
            <button
              class="toggle-btn"
              :class="{ active: !raceData.settings.traffic }"
              @click="raceData.settings.traffic = false"
            >
              OFF
            </button>
          </div>
        </div>

        <!-- AI Racers -->
        <div class="config-section" v-if="raceData.type !== 'timeattack'">
          <label class="section-label">AI PILOTS</label>
          <div class="pilots-list">
            <div
              v-for="(pilot, index) in raceData.aiConfig.racers"
              :key="index"
              class="pilot-row"
            >
              <span class="pilot-position">{{ index + 1 }}.</span>
              <select v-model="pilot.name" class="pilot-select" @change="onPilotChange(index)">
                <option value="">[Random]</option>
                <option v-for="p in availablePilots" :key="p.name" :value="p.name">
                  {{ p.name }}
                </option>
              </select>
              <select v-model="pilot.vehicle" class="vehicle-select">
                <option v-for="v in availableVehicles" :key="v.value" :value="v.value">
                  {{ v.label }}
                </option>
              </select>
              <span class="pilot-aggr">Aggr: {{ pilot.aggression.toFixed(1) }}</span>
              <button class="remove-btn" @click="removePilot(index)">X</button>
            </div>
            <button class="add-pilot-btn" @click="addPilot" v-if="raceData.aiConfig.racers.length < 9">
              + Add Pilot
            </button>
          </div>
        </div>

        <!-- Grid Order -->
        <div class="config-section" v-if="raceData.type !== 'timeattack'">
          <label class="section-label">GRID ORDER</label>
          <div class="button-group">
            <button
              class="toggle-btn"
              :class="{ active: raceData.aiConfig.gridOrder === 'defined' }"
              @click="raceData.aiConfig.gridOrder = 'defined'"
            >
              DEFINED
            </button>
            <button
              class="toggle-btn"
              :class="{ active: raceData.aiConfig.gridOrder === 'random' }"
              @click="raceData.aiConfig.gridOrder = 'random'"
            >
              RANDOM
            </button>
          </div>
        </div>

        <!-- Time Attack Goals -->
        <div class="config-section" v-if="raceData.type === 'timeattack'">
          <label class="section-label">TIME GOALS (seconds)</label>
          <div class="time-goals">
            <div class="goal-input">
              <label>Gold</label>
              <input type="number" v-model.number="raceData.timeAttack.gold" min="0" />
            </div>
            <div class="goal-input">
              <label>Silver</label>
              <input type="number" v-model.number="raceData.timeAttack.silver" min="0" />
            </div>
            <div class="goal-input">
              <label>Bronze</label>
              <input type="number" v-model.number="raceData.timeAttack.bronze" min="0" />
            </div>
          </div>
        </div>

        <!-- Rewards -->
        <div class="config-section">
          <label class="section-label">REWARDS</label>
          <div class="rewards-config">
            <div class="reward-input">
              <label>Reputation</label>
              <input type="number" v-model.number="raceData.rewards.reputation" min="0" />
            </div>
            <div class="reward-input">
              <label>1st Place $</label>
              <input type="number" v-model.number="raceData.rewards.money.first" min="0" step="100" />
            </div>
          </div>
        </div>

        <!-- Info -->
        <div class="race-info">
          <span>{{ raceData.checkpoints.length }} checkpoints</span>
          <span>{{ raceData.closed ? 'Closed circuit' : 'Point to point' }}</span>
          <span>Level: {{ raceData.level }}</span>
        </div>

        <!-- Actions -->
        <div class="actions">
          <button class="action-btn secondary" @click="cancel">
            CANCEL
          </button>
          <button class="action-btn primary" @click="saveRace">
            SAVE RACE
          </button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup>
import { ref, reactive, onMounted, onUnmounted, watch } from 'vue'
import { useEvents } from '@/services/events'
import { useBridge } from '@/bridge'

const events = useEvents()
const { lua } = useBridge()

// State
const showConfig = ref(false)
const customLaps = ref(null)

const raceData = reactive({
  name: '',
  author: 'Player',
  level: '',
  type: 'sprint',
  checkpoints: [],
  closed: false,
  laps: 1,
  aiConfig: {
    count: 4,
    gridOrder: 'random',
    racers: []
  },
  settings: {
    traffic: false,
    countdown: true
  },
  timeAttack: {
    gold: 0,
    silver: 0,
    bronze: 0
  },
  rewards: {
    reputation: 50,
    money: {
      first: 5000,
      second: 2500,
      third: 1000
    }
  }
})

const raceTypes = [
  { value: 'sprint', label: 'Sprint' },
  { value: 'timeattack', label: 'Time Attack' },
  { value: 'rally', label: 'Rally' },
  { value: 'circuit', label: 'Circuit' }
]

const availablePilots = [
  { name: 'Ray Pacherson', vehicle: 'vivace', aggression: 0.9 },
  { name: 'Vax Merstapen', vehicle: 'etki', aggression: 0.85 },
  { name: 'Lewis Amilton', vehicle: 'covet', aggression: 0.8 },
  { name: 'Carlo Sunshine', vehicle: 'pessima', aggression: 0.7 },
  { name: 'Nando Alonslow', vehicle: 'moonhawk', aggression: 0.75 },
  { name: 'George Roussell', vehicle: 'fullsize', aggression: 0.65 },
  { name: 'Danny Ricardough', vehicle: 'legran', aggression: 0.7 },
  { name: 'Lando Norrington', vehicle: 'wendover', aggression: 0.8 },
  { name: 'Sharles Leclaire', vehicle: 'sunburst', aggression: 0.85 },
  { name: 'Sergio Perizo', vehicle: 'barstow', aggression: 0.6 }
]

const availableVehicles = [
  { value: 'vivace', label: 'Vivace' },
  { value: 'etki', label: 'ETK-I' },
  { value: 'covet', label: 'Covet' },
  { value: 'pessima', label: 'Pessima' },
  { value: 'moonhawk', label: 'Moonhawk' },
  { value: 'fullsize', label: 'Fullsize' },
  { value: 'legran', label: 'Legran' },
  { value: 'wendover', label: 'Wendover' },
  { value: 'sunburst', label: 'Sunburst' },
  { value: 'barstow', label: 'Barstow' },
  { value: 'bolide', label: 'Bolide' },
  { value: 'bx', label: 'BX' }
]

// Methods
function addPilot() {
  raceData.aiConfig.racers.push({
    name: '',
    vehicle: 'etki',
    config: 'base',
    aggression: 0.7
  })
}

function removePilot(index) {
  raceData.aiConfig.racers.splice(index, 1)
}

function onPilotChange(index) {
  const pilot = raceData.aiConfig.racers[index]
  const template = availablePilots.find(p => p.name === pilot.name)
  if (template) {
    pilot.vehicle = template.vehicle
    pilot.aggression = template.aggression
  }
}

function cancel() {
  showConfig.value = false
}

function saveRace() {
  // Update count based on racers array
  raceData.aiConfig.count = Math.max(raceData.aiConfig.racers.length, 4)

  lua.career_modules_mysummerRaceEditor.saveRaceFromConfig(JSON.parse(JSON.stringify(raceData)))
  showConfig.value = false
}

// Event handlers
function onRaceConfig(data) {
  // Copy data to reactive object
  Object.assign(raceData, data)

  // Set type based on closed
  if (data.closed && !data.type) {
    raceData.type = 'circuit'
  }

  // Initialize with some default pilots if empty
  if (raceData.aiConfig.racers.length === 0) {
    for (let i = 0; i < 4; i++) {
      raceData.aiConfig.racers.push({
        name: '',
        vehicle: 'etki',
        config: 'base',
        aggression: 0.7
      })
    }
  }

  showConfig.value = true
}

// Watch type changes
watch(() => raceData.type, (newType) => {
  if (newType === 'circuit' && raceData.closed) {
    if (raceData.laps < 2) raceData.laps = 3
  } else if (newType === 'sprint' || newType === 'rally') {
    raceData.laps = 1
  }
})

// Lifecycle
onMounted(() => {
  events.on('mysummerRaceConfig', onRaceConfig)
})

onUnmounted(() => {
  events.off('mysummerRaceConfig', onRaceConfig)
})
</script>

<style lang="scss" scoped>
.config-overlay {
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

.config-modal {
  background: linear-gradient(180deg, #1a1a2e 0%, #0f0f1a 100%);
  border: 2px solid #333;
  border-radius: 16px;
  padding: 25px 35px;
  min-width: 550px;
  max-width: 650px;
  max-height: 90vh;
  overflow-y: auto;
}

.config-header {
  text-align: center;
  margin-bottom: 20px;

  h1 {
    font-size: 1.8rem;
    color: #ff6b00;
    margin: 0 0 15px;
    letter-spacing: 3px;
  }

  .race-name-input {
    width: 100%;
    padding: 12px 16px;
    font-size: 1.2rem;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid #444;
    border-radius: 8px;
    color: white;
    text-align: center;

    &:focus {
      outline: none;
      border-color: #ff6b00;
    }
  }
}

.config-section {
  margin-bottom: 18px;

  .section-label {
    display: block;
    font-size: 0.75rem;
    color: #888;
    letter-spacing: 2px;
    margin-bottom: 8px;
  }
}

.button-group {
  display: flex;
  gap: 8px;
  flex-wrap: wrap;

  .type-btn,
  .lap-btn,
  .toggle-btn {
    padding: 10px 18px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid #444;
    border-radius: 6px;
    color: #888;
    cursor: pointer;
    transition: all 0.2s ease;
    font-size: 0.9rem;

    &:hover {
      background: rgba(255, 255, 255, 0.1);
    }

    &.active {
      background: rgba(255, 107, 0, 0.2);
      border-color: #ff6b00;
      color: #ff6b00;
    }
  }

  .custom-input {
    width: 80px;
    padding: 10px;
    background: rgba(255, 255, 255, 0.05);
    border: 1px solid #444;
    border-radius: 6px;
    color: white;
    text-align: center;

    &:focus {
      outline: none;
      border-color: #ff6b00;
    }
  }
}

.pilots-list {
  background: rgba(0, 0, 0, 0.3);
  border-radius: 8px;
  padding: 10px;

  .pilot-row {
    display: flex;
    align-items: center;
    gap: 8px;
    padding: 8px;
    background: rgba(255, 255, 255, 0.03);
    border-radius: 4px;
    margin-bottom: 6px;

    .pilot-position {
      width: 25px;
      color: #888;
      font-weight: bold;
    }

    .pilot-select,
    .vehicle-select {
      flex: 1;
      padding: 6px 10px;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid #444;
      border-radius: 4px;
      color: white;
      font-size: 0.85rem;
    }

    .pilot-aggr {
      font-size: 0.75rem;
      color: #666;
      width: 70px;
    }

    .remove-btn {
      width: 28px;
      height: 28px;
      background: rgba(255, 0, 0, 0.2);
      border: 1px solid rgba(255, 0, 0, 0.3);
      border-radius: 4px;
      color: #ff6b6b;
      cursor: pointer;
      font-weight: bold;

      &:hover {
        background: rgba(255, 0, 0, 0.3);
      }
    }
  }

  .add-pilot-btn {
    width: 100%;
    padding: 10px;
    background: rgba(76, 175, 80, 0.1);
    border: 1px dashed rgba(76, 175, 80, 0.3);
    border-radius: 6px;
    color: #4caf50;
    cursor: pointer;
    font-size: 0.9rem;

    &:hover {
      background: rgba(76, 175, 80, 0.2);
    }
  }
}

.time-goals,
.rewards-config {
  display: flex;
  gap: 15px;

  .goal-input,
  .reward-input {
    flex: 1;

    label {
      display: block;
      font-size: 0.75rem;
      color: #666;
      margin-bottom: 4px;
    }

    input {
      width: 100%;
      padding: 8px 12px;
      background: rgba(255, 255, 255, 0.05);
      border: 1px solid #444;
      border-radius: 6px;
      color: white;
      text-align: center;

      &:focus {
        outline: none;
        border-color: #ff6b00;
      }
    }
  }
}

.race-info {
  display: flex;
  justify-content: center;
  gap: 20px;
  padding: 12px;
  background: rgba(255, 255, 255, 0.03);
  border-radius: 6px;
  margin-bottom: 20px;
  font-size: 0.85rem;
  color: #666;
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
