<template>
  <div class="career-root" :class="{ compact }">
    <div class="career-header">
      <div>
        <h2>Street Racing</h2>
        <p>Build your reputation in the underground racing scene.</p>
      </div>
    </div>

    <!-- Native Progression Section -->
    <div class="progression-section">
      <div class="progression-header">
        <span class="level-label">{{ nativeProgress.levelName }}</span>
        <span class="level-badge">Level {{ nativeProgress.level }}</span>
      </div>
      <div class="xp-bar-container">
        <div class="xp-bar" :style="{ width: xpPercentage + '%' }"></div>
      </div>
      <div class="xp-text">
        <span v-if="nativeProgress.isMaxLevel">MAX LEVEL</span>
        <span v-else>{{ nativeProgress.currentXP }} / {{ xpNeeded }} XP</span>
      </div>
    </div>

    <!-- Level Tiers Preview -->
    <div class="tiers-section">
      <h3>Progression Tiers</h3>
      <div class="tiers-list">
        <div
          v-for="tier in tiers"
          :key="tier.level"
          class="tier-item"
          :class="{ current: tier.level === nativeProgress.level, unlocked: tier.level <= nativeProgress.level }"
        >
          <span class="tier-level">{{ tier.level }}</span>
          <span class="tier-name">{{ tier.name }}</span>
          <span class="tier-xp">{{ tier.xpRequired }} XP</span>
        </div>
      </div>
    </div>

    <!-- Available Races -->
    <div class="races-section" v-if="availableRaces.length > 0">
      <h3>Available Races</h3>
      <div class="races-list">
        <div
          v-for="race in availableRaces"
          :key="race.id"
          class="race-card"
          :class="{ completed: race.completed }"
        >
          <div class="race-info">
            <div class="race-name">{{ race.name }}</div>
            <div class="race-description">{{ race.description }}</div>
          </div>
          <div class="race-status-badge" v-if="race.completed">Completed</div>
          <button
            v-else
            class="navigate-btn"
            @click="navigateToRace(race.id)"
            :disabled="store.loading"
          >
            Navigate
          </button>
        </div>
      </div>
    </div>

    <!-- Current Phase -->
    <div class="phase-section" v-if="currentPhase">
      <h3>Current Objective</h3>
      <div class="phase-card current">
        <div class="phase-header">
          <span class="phase-number">Act {{ currentPhase.id }}</span>
          <span class="phase-status">In Progress</span>
        </div>
        <div class="phase-name">{{ currentPhase.name }}</div>
        <div class="phase-description">{{ currentPhase.description }}</div>
        <div class="phase-objectives" v-if="currentPhase.objectives">
          <div
            v-for="(obj, idx) in currentPhase.objectives"
            :key="idx"
            class="objective-item"
            :class="{ completed: obj.completed }"
          >
            <span class="objective-check">{{ obj.completed ? '✓' : '○' }}</span>
            <span class="objective-text">{{ obj.text }}</span>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, onUnmounted } from "vue"
import { useMySummerCareerStore } from "../../stores/mysummerCareerStore"

const props = defineProps({
  compact: {
    type: Boolean,
    default: false,
  },
})

const store = useMySummerCareerStore()

// Native progression data from BeamNG's career_branches system
const nativeProgress = computed(() => store.careerData.nativeProgress || {
  level: 1,
  levelName: "Rookie Racer",
  currentXP: 0,
  minXP: 0,
  maxXP: 250,
  totalXP: 0,
  isMaxLevel: false,
})

const xpNeeded = computed(() => {
  const prog = nativeProgress.value
  return prog.maxXP - prog.minXP
})

const xpPercentage = computed(() => {
  const prog = nativeProgress.value
  if (prog.isMaxLevel) return 100
  const needed = prog.maxXP - prog.minXP
  if (needed <= 0) return 0
  return Math.min(100, Math.max(0, (prog.currentXP / needed) * 100))
})

// Tier definitions (matching the info.json)
const tiers = [
  { level: 1, name: "Rookie Racer", xpRequired: 0 },
  { level: 2, name: "Known Driver", xpRequired: 250 },
  { level: 3, name: "Street Regular", xpRequired: 750 },
  { level: 4, name: "Underground Star", xpRequired: 1500 },
  { level: 5, name: "Street Legend", xpRequired: 3000 },
]

const currentPhase = computed(() => store.careerData.currentPhase)
const availableRaces = computed(() => store.careerData.availableRaces || [])

const navigateToRace = async (raceId) => {
  await store.navigateToRace(raceId)
}

onMounted(() => {
  store.requestData()
})

onUnmounted(() => {
  store.dispose()
})
</script>

<style scoped lang="scss">
.career-root {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  color: #f5f5f5;
  background: rgba(16, 16, 16, 0.9);
  border-radius: 16px;
  padding: 1.2rem;
  height: 100%;
  overflow: auto;
}

.career-root.compact {
  border-radius: 0;
  padding-top: 3.5rem;
  background: #1b1b1b;
}

.career-header {
  h2 {
    margin: 0;
    font-size: 1.4rem;
    color: #fbbf24;
  }

  p {
    margin: 0.3rem 0 0;
    color: rgba(255, 255, 255, 0.6);
    font-size: 0.85rem;
  }
}

// Native Progression Section
.progression-section {
  background: rgba(24, 24, 24, 0.9);
  border: 1px solid rgba(251, 191, 36, 0.3);
  border-radius: 14px;
  padding: 1rem;
}

.progression-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.75rem;
}

.level-label {
  font-size: 1.2rem;
  font-weight: 700;
  color: #fbbf24;
}

.level-badge {
  padding: 0.2rem 0.6rem;
  border-radius: 6px;
  font-size: 0.75rem;
  font-weight: 700;
  text-transform: uppercase;
  background: rgba(251, 191, 36, 0.2);
  color: #fbbf24;
}

.xp-bar-container {
  height: 8px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 4px;
  overflow: hidden;
}

.xp-bar {
  height: 100%;
  background: linear-gradient(90deg, #f59e0b, #fbbf24);
  border-radius: 4px;
  transition: width 0.3s ease;
}

.xp-text {
  margin-top: 0.5rem;
  font-size: 0.85rem;
  color: rgba(255, 255, 255, 0.6);
  text-align: right;
}

// Tiers Section
.tiers-section {
  h3 {
    margin: 0 0 0.75rem;
    font-size: 1rem;
    color: rgba(255, 255, 255, 0.8);
  }
}

.tiers-list {
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

.tier-item {
  display: flex;
  align-items: center;
  gap: 0.75rem;
  padding: 0.5rem 0.75rem;
  background: rgba(24, 24, 24, 0.6);
  border-radius: 8px;
  border: 1px solid rgba(255, 255, 255, 0.05);
  opacity: 0.5;
}

.tier-item.unlocked {
  opacity: 0.8;
  border-color: rgba(34, 197, 94, 0.3);
}

.tier-item.current {
  opacity: 1;
  border-color: rgba(251, 191, 36, 0.5);
  background: rgba(251, 191, 36, 0.1);
}

.tier-level {
  width: 24px;
  height: 24px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 50%;
  font-size: 0.75rem;
  font-weight: 700;
}

.tier-item.current .tier-level {
  background: #fbbf24;
  color: #000;
}

.tier-item.unlocked .tier-level {
  background: rgba(34, 197, 94, 0.3);
  color: #22c55e;
}

.tier-name {
  flex: 1;
  font-size: 0.9rem;
}

.tier-xp {
  font-size: 0.75rem;
  color: rgba(255, 255, 255, 0.4);
}

// Phase Section
.phase-section {
  h3 {
    margin: 0 0 0.75rem;
    font-size: 1rem;
    color: rgba(255, 255, 255, 0.8);
  }
}

.phase-card {
  background: rgba(24, 24, 24, 0.9);
  border: 1px solid rgba(255, 255, 255, 0.08);
  border-radius: 12px;
  padding: 0.9rem;
}

.phase-card.current {
  border-color: rgba(251, 191, 36, 0.5);
  background: rgba(251, 191, 36, 0.05);
}

.phase-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 0.4rem;
}

.phase-number {
  font-size: 0.8rem;
  color: rgba(255, 255, 255, 0.5);
}

.phase-status {
  font-size: 0.7rem;
  padding: 0.15rem 0.4rem;
  border-radius: 4px;
  background: rgba(251, 191, 36, 0.2);
  color: #fbbf24;
}

.phase-name {
  font-size: 1.1rem;
  font-weight: 600;
  margin-bottom: 0.3rem;
}

.phase-description {
  font-size: 0.85rem;
  color: rgba(255, 255, 255, 0.6);
}

.phase-objectives {
  margin-top: 0.75rem;
  display: flex;
  flex-direction: column;
  gap: 0.4rem;
}

.objective-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  font-size: 0.85rem;
}

.objective-item.completed {
  color: #22c55e;
}

.objective-check {
  width: 1.2rem;
  text-align: center;
}

// Races Section
.races-section {
  h3 {
    margin: 0 0 0.75rem;
    font-size: 1rem;
    color: rgba(255, 255, 255, 0.8);
  }
}

.races-list {
  display: flex;
  flex-direction: column;
  gap: 0.5rem;
}

.race-card {
  background: rgba(24, 24, 24, 0.9);
  border: 1px solid rgba(59, 130, 246, 0.3);
  border-radius: 10px;
  padding: 0.75rem;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 0.75rem;

  &.completed {
    border-color: rgba(34, 197, 94, 0.4);
    opacity: 0.7;
  }
}

.race-info {
  flex: 1;
}

.race-name {
  font-weight: 600;
  font-size: 0.95rem;
}

.race-description {
  font-size: 0.8rem;
  color: rgba(255, 255, 255, 0.5);
  margin-top: 0.2rem;
}

.race-status-badge {
  font-size: 0.75rem;
  padding: 0.25rem 0.6rem;
  border-radius: 6px;
  background: rgba(34, 197, 94, 0.2);
  color: #22c55e;
}

.navigate-btn {
  background: #3b82f6;
  border: none;
  color: #fff;
  padding: 0.4rem 0.8rem;
  border-radius: 6px;
  cursor: pointer;
  font-weight: 600;
  font-size: 0.85rem;

  &:hover:not(:disabled) {
    background: #2563eb;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.career-root::-webkit-scrollbar {
  width: 6px;
}

.career-root::-webkit-scrollbar-thumb {
  background: rgba(255, 255, 255, 0.1);
  border-radius: 999px;
}
</style>
