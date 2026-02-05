<template>
  <div class="story-races-page">
    <!-- Header -->
    <div class="page-header">
      <h1 class="page-title">{{ $t('mysummer.storyRaces.title') }}</h1>
      <div class="player-info">
        <span class="level-badge">{{ $t('mysummer.storyRaces.level') }}: {{ currentLevel }}</span>
        <span class="car-badge" :class="{ warning: !isInProjectCar }">
          {{ isInProjectCar ? $t('mysummer.storyRaces.projectCar') : $t('mysummer.storyRaces.normalCar') }}
        </span>
      </div>
    </div>

    <!-- Loading -->
    <div v-if="loading" class="loading-state">
      {{ $t('mysummer.storyRaces.loading') }}
    </div>

    <!-- Chapters -->
    <div v-else class="chapters-container">
      <div
        v-for="chapter in chapters"
        :key="chapter.chapter"
        class="chapter-section"
        :class="{ locked: !chapter.isAccessible }"
      >
        <!-- Chapter Header -->
        <div class="chapter-header" @click="toggleChapter(chapter.chapter)">
          <div class="chapter-title">
            <span class="chapter-number">{{ $t('mysummer.storyRaces.chapter') }} {{ chapter.chapter }}</span>
            <span class="chapter-name">{{ getChapterName(chapter.chapter) }}</span>
          </div>
          <div class="chapter-badges">
            <span v-if="chapter.requiresProjectCar" class="badge project-required">
              {{ $t('mysummer.storyRaces.projectRequired') }}
            </span>
            <span v-if="!chapter.isAccessible" class="badge locked">
              {{ $t('mysummer.storyRaces.level') }} {{ chapter.requiredLevel + 1 }}
            </span>
            <span class="progress-badge">
              {{ getChapterProgress(chapter) }}
            </span>
            <span class="expand-icon">{{ expandedChapters[chapter.chapter] ? '[-]' : '[+]' }}</span>
          </div>
        </div>

        <!-- Chapter Content (Collapsible) -->
        <div v-if="expandedChapters[chapter.chapter]" class="chapter-content">
          <!-- Story Mission (1 per chapter, mandatory) -->
          <div v-if="chapter.mission" class="mission-section">
            <div class="section-label">{{ $t('mysummer.storyRaces.contactMission') }}</div>
            <div
              class="mission-card"
              :class="{
                completed: chapter.mission.completed,
                locked: !chapter.mission.isAccessible,
                active: activeMission?.missionId === chapter.mission.id
              }"
            >
              <div class="mission-icon">
                <span v-if="chapter.mission.type === 'meet'">[M]</span>
                <span v-else-if="chapter.mission.type === 'delivery'">[D]</span>
                <span v-else-if="chapter.mission.type === 'chase'">[C]</span>
                <span v-else>[?]</span>
              </div>
              <div class="mission-info">
                <div class="mission-header">
                  <span class="mission-name">{{ chapter.mission.name }}</span>
                  <span v-if="chapter.mission.completed" class="completed-icon">[OK]</span>
                  <span v-else-if="!chapter.mission.isAccessible" class="locked-icon">[X]</span>
                  <span v-else class="required-badge">{{ $t('mysummer.storyRaces.required') }}</span>
                </div>
                <div class="mission-description">{{ chapter.mission.description }}</div>
                <div class="mission-details">
                  <span class="mission-contact">{{ chapter.mission.contact }}</span>
                  <span class="mission-rewards">{{ chapter.mission.xpReward }} XP</span>
                </div>
              </div>
              <div class="mission-actions">
                <button
                  v-if="chapter.mission.isAccessible && !chapter.mission.completed && !activeMission"
                  class="mission-btn start"
                  @click="startMission(chapter.mission.id)"
                  :disabled="startingMission"
                >
                  {{ startingMission ? $t('mysummer.storyRaces.starting') : $t('mysummer.storyRaces.startMission') }}
                </button>
                <button
                  v-else-if="activeMission?.missionId === chapter.mission.id"
                  class="mission-btn cancel"
                  @click="cancelMission"
                >
                  {{ $t('mysummer.storyRaces.cancel') }}
                </button>
                <div v-else-if="!chapter.mission.isAccessible" class="locked-reason">
                  <span v-if="chapter.mission.lockedReason === 'level'">{{ $t('mysummer.storyRaces.needLevel') }}</span>
                  <span v-else-if="chapter.mission.lockedReason === 'projectcar'">{{ $t('mysummer.storyRaces.needProjectCar') }}</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Races List -->
          <div class="races-section">
            <div class="section-label">{{ $t('mysummer.storyRaces.races') }}</div>
            <div class="races-list">
              <div
                v-for="race in (chapter.races || [])"
                :key="race.id"
                class="race-card"
                :class="{
                  completed: race.completed,
                  locked: !race.isAccessible,
                  active: activeRace?.raceId === race.id
                }"
              >
                <div class="race-info">
                  <div class="race-header">
                    <span class="race-name">{{ race.name }}</span>
                    <span v-if="race.completed" class="completed-icon">[OK]</span>
                    <span v-else-if="!race.isAccessible" class="locked-icon">[X]</span>
                  </div>
                  <div class="race-description">{{ race.description }}</div>
                  <div class="race-details">
                    <span class="race-contact">{{ $t('mysummer.storyRaces.contact') }}: {{ race.contact }}</span>
                    <span class="race-rewards">
                      {{ race.xpReward }} XP | {{ formatMoney(race.moneyReward) }}
                    </span>
                  </div>
                  <div v-if="race.completed && race.wins > 0" class="race-stats">
                    {{ $t('mysummer.storyRaces.wins') }}: {{ race.wins }}
                    <span v-if="race.bestTime"> | {{ $t('mysummer.storyRaces.bestTime') }}: {{ formatTime(race.bestTime) }}</span>
                  </div>
                </div>
                <div class="race-actions">
                  <button
                    v-if="race.isAccessible && !activeRace"
                    class="race-btn start"
                    @click="startRace(race.id)"
                    :disabled="startingRace"
                  >
                    {{ startingRace ? $t('mysummer.storyRaces.starting') : $t('mysummer.storyRaces.start') }}
                  </button>
                  <button
                    v-else-if="activeRace?.raceId === race.id"
                    class="race-btn cancel"
                    @click="cancelRace"
                  >
                    {{ $t('mysummer.storyRaces.cancel') }}
                  </button>
                  <div v-else-if="!race.isAccessible" class="locked-reason">
                    <span v-if="race.lockedReason === 'level'">{{ $t('mysummer.storyRaces.needLevel') }}</span>
                    <span v-else-if="race.lockedReason === 'projectcar'">{{ $t('mysummer.storyRaces.needProjectCar') }}</span>
                  </div>
                </div>
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useI18n } from 'petite-vue-i18n'

const { t } = useI18n()
const emit = defineEmits(['navigate'])

const loading = ref(true)
const chapters = ref([])
const currentLevel = ref(0)
const isInProjectCar = ref(false)
const activeRace = ref(null)
const activeMission = ref(null)
const startingRace = ref(false)
const startingMission = ref(false)
const expandedChapters = ref({})

const chapterNames = {
  1: { en: 'Racing Among Friends', es: 'Carreras entre Conocidos' },
  2: { en: 'Low Underground', es: 'Underground Bajo' },
  3: { en: 'Regional Rallies', es: 'Rallys Regionales' },
  4: { en: 'High Underground', es: 'Underground Alto' },
  5: { en: 'Official Rallies', es: 'Rallys Oficiales' },
  6: { en: 'The Big One', es: 'The Big One' },
}

const getChapterName = (chapterNum) => {
  const names = chapterNames[chapterNum]
  if (!names) return `Chapter ${chapterNum}`
  const lang = navigator.language || 'en'
  return lang.includes('es') ? names.es : names.en
}

const getChapterProgress = (chapter) => {
  const races = chapter.races || []
  const racesCompleted = races.filter(r => r.completed).length
  const missionCompleted = chapter.mission?.completed ? 1 : 0
  const total = races.length + (chapter.mission ? 1 : 0)
  return `${racesCompleted + missionCompleted}/${total}`
}

const formatMoney = (amount) => {
  return `$${amount.toLocaleString()}`
}

const formatTime = (seconds) => {
  if (!seconds) return '--:--'
  const mins = Math.floor(seconds / 60)
  const secs = (seconds % 60).toFixed(2)
  return `${mins}:${secs.padStart(5, '0')}`
}

const toggleChapter = (chapterNum) => {
  expandedChapters.value[chapterNum] = !expandedChapters.value[chapterNum]
}

const loadRaces = () => {
  loading.value = true
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerStoryRaces.getStoryRacesForUI()', (result) => {
      if (result) {
        chapters.value = result.chapters || []
        currentLevel.value = result.currentLevel || 0
        isInProjectCar.value = result.isInProjectCar || false
        activeRace.value = result.activeRace || null
        activeMission.value = result.activeMission || null

        // Expand current chapter by default
        const currentChapter = currentLevel.value + 1
        if (currentChapter <= 6) {
          expandedChapters.value[currentChapter] = true
        }
      }
      loading.value = false
    })
  } else {
    // Mock data for development
    chapters.value = []
    loading.value = false
  }
}

// Mission functions
const startMission = (missionId) => {
  if (!window.bngApi || startingMission.value) return

  startingMission.value = true
  window.bngApi.engineLua(`career_modules_mysummerStoryRaces.selectMission("${missionId}")`, (result) => {
    startingMission.value = false
    if (result && result.success) {
      activeMission.value = { missionId }
      // Close menu after starting mission
      window.bngApi.engineLua("guihooks.trigger('MenuHide')")
    } else if (result) {
      console.error('Failed to start mission:', result.reason)
    }
  })
}

const cancelMission = () => {
  if (!window.bngApi) return

  window.bngApi.engineLua('career_modules_mysummerStoryRaces.cancelMission()', () => {
    activeMission.value = null
    loadRaces()
  })
}

const startRace = (raceId) => {
  if (!window.bngApi || startingRace.value) return

  startingRace.value = true
  window.bngApi.engineLua(`career_modules_mysummerStoryRaces.selectRace("${raceId}")`, (result) => {
    startingRace.value = false
    if (result && result.success) {
      activeRace.value = { raceId }
      // Close menu after starting race
      window.bngApi.engineLua("guihooks.trigger('MenuHide')")
    } else if (result) {
      console.error('Failed to start race:', result.reason)
    }
  })
}

const cancelRace = () => {
  if (!window.bngApi) return

  window.bngApi.engineLua('career_modules_mysummerStoryRaces.cancelRace()', () => {
    activeRace.value = null
    loadRaces()
  })
}

// Event handlers
const handleRaceCompleted = (data) => {
  loadRaces()
}

const handleRaceSelected = (data) => {
  activeRace.value = data
}

const handleMissionCompleted = (data) => {
  loadRaces()
}

const handleMissionSelected = (data) => {
  activeMission.value = data
}

onMounted(() => {
  loadRaces()

  // Register event listeners (only if bngApi.on exists)
  if (window.bngApi && typeof window.bngApi.on === 'function') {
    window.bngApi.on('mysummerStoryRaceCompleted', handleRaceCompleted)
    window.bngApi.on('mysummerStoryRaceSelected', handleRaceSelected)
    window.bngApi.on('mysummerStoryMissionCompleted', handleMissionCompleted)
    window.bngApi.on('mysummerStoryMissionSelected', handleMissionSelected)
  }
})

onUnmounted(() => {
  if (window.bngApi && typeof window.bngApi.off === 'function') {
    window.bngApi.off('mysummerStoryRaceCompleted', handleRaceCompleted)
    window.bngApi.off('mysummerStoryRaceSelected', handleRaceSelected)
    window.bngApi.off('mysummerStoryMissionCompleted', handleMissionCompleted)
    window.bngApi.off('mysummerStoryMissionSelected', handleMissionSelected)
  }
})
</script>

<style scoped lang="scss">
$win-gray: #c0c0c0;
$win-dark: #808080;
$win-blue: #000080;
$win-white: #ffffff;
$win-black: #000000;
$accent-green: #25D366;
$accent-gold: #ffd700;

.story-races-page {
  padding: 16px;
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  background: $win-gray;
  min-height: 100%;
  color: $win-black;
}

.page-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 16px;
  padding-bottom: 8px;
  border-bottom: 2px solid $win-dark;
}

.page-title {
  font-size: 1.4rem;
  font-weight: bold;
  margin: 0;
}

.player-info {
  display: flex;
  gap: 8px;
}

.level-badge, .car-badge {
  padding: 4px 8px;
  background: $win-blue;
  color: $win-white;
  font-size: 0.75rem;
  border: 2px solid;
  border-color: $win-white $win-dark $win-dark $win-white;
}

.car-badge.warning {
  background: #aa5500;
}

.loading-state {
  text-align: center;
  padding: 40px;
  color: $win-dark;
}

.chapters-container {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.chapter-section {
  background: $win-white;
  border: 2px solid;
  border-color: $win-white $win-dark $win-dark $win-white;

  &.locked {
    opacity: 0.7;
  }
}

.chapter-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 12px;
  background: linear-gradient(180deg, $win-blue 0%, #000050 100%);
  color: $win-white;
  cursor: pointer;

  &:hover {
    background: linear-gradient(180deg, #0000a0 0%, $win-blue 100%);
  }
}

.chapter-title {
  display: flex;
  gap: 12px;
  align-items: baseline;
}

.chapter-number {
  font-weight: bold;
  font-size: 0.9rem;
}

.chapter-name {
  font-size: 0.85rem;
  opacity: 0.9;
}

.chapter-badges {
  display: flex;
  gap: 8px;
  align-items: center;
}

.badge {
  padding: 2px 6px;
  font-size: 0.7rem;
  background: $win-dark;
  border-radius: 2px;

  &.project-required {
    background: #aa5500;
  }

  &.locked {
    background: #aa0000;
  }
}

.progress-badge {
  font-size: 0.75rem;
  padding: 2px 6px;
  background: rgba(255,255,255,0.2);
  border-radius: 2px;
}

.expand-icon {
  font-family: monospace;
  font-size: 0.8rem;
}

.races-list {
  padding: 8px;
  display: flex;
  flex-direction: column;
  gap: 8px;
}

.race-card {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px 12px;
  background: $win-gray;
  border: 2px solid;
  border-color: $win-white $win-dark $win-dark $win-white;

  &.completed {
    background: #d0ffd0;
  }

  &.locked {
    background: #e0e0e0;
    opacity: 0.6;
  }

  &.active {
    background: #ffffd0;
    border-color: $accent-gold;
  }
}

.race-info {
  flex: 1;
}

.race-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}

.race-name {
  font-weight: bold;
  font-size: 0.9rem;
}

.completed-icon {
  color: green;
  font-family: monospace;
}

.locked-icon {
  color: #aa0000;
  font-family: monospace;
}

.race-description {
  font-size: 0.75rem;
  color: $win-dark;
  margin-bottom: 4px;
}

.race-details {
  display: flex;
  gap: 16px;
  font-size: 0.7rem;
  color: $win-black;
}

.race-stats {
  font-size: 0.7rem;
  color: $win-blue;
  margin-top: 4px;
}

.race-actions {
  display: flex;
  flex-direction: column;
  gap: 4px;
  min-width: 100px;
}

.race-btn {
  padding: 6px 12px;
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 0.8rem;
  cursor: pointer;
  border: 2px solid;
  border-color: $win-white $win-dark $win-dark $win-white;

  &:active {
    border-color: $win-dark $win-white $win-white $win-dark;
  }

  &.start {
    background: $accent-green;
    color: white;
  }

  &.cancel {
    background: #cc0000;
    color: white;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}

.locked-reason {
  font-size: 0.7rem;
  color: #aa0000;
  text-align: right;
}

// Chapter content sections
.chapter-content {
  padding: 8px;
}

.section-label {
  font-size: 0.7rem;
  font-weight: bold;
  color: $win-dark;
  text-transform: uppercase;
  margin-bottom: 6px;
  padding-left: 2px;
}

.mission-section {
  margin-bottom: 12px;
}

.races-section {
  .races-list {
    padding: 0;
  }
}

// Mission card styles
.mission-card {
  display: flex;
  align-items: center;
  padding: 12px;
  background: linear-gradient(180deg, #ffe4b5 0%, #ffd090 100%);
  border: 2px solid;
  border-color: $win-white $win-dark $win-dark $win-white;
  gap: 12px;

  &.completed {
    background: linear-gradient(180deg, #d0ffd0 0%, #a0e0a0 100%);
  }

  &.locked {
    background: linear-gradient(180deg, #e0e0e0 0%, #c0c0c0 100%);
    opacity: 0.6;
  }

  &.active {
    background: linear-gradient(180deg, #ffffd0 0%, #fff0a0 100%);
    border-color: $accent-gold;
  }
}

.mission-icon {
  width: 40px;
  height: 40px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: $win-blue;
  color: $win-white;
  font-family: monospace;
  font-size: 1.2rem;
  font-weight: bold;
  border: 2px solid;
  border-color: $win-white $win-dark $win-dark $win-white;
}

.mission-info {
  flex: 1;
}

.mission-header {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
}

.mission-name {
  font-weight: bold;
  font-size: 0.95rem;
}

.required-badge {
  background: #cc6600;
  color: white;
  padding: 1px 6px;
  font-size: 0.65rem;
  border-radius: 2px;
}

.mission-description {
  font-size: 0.75rem;
  color: $win-dark;
  margin-bottom: 4px;
}

.mission-details {
  display: flex;
  gap: 16px;
  font-size: 0.7rem;
  color: $win-black;
}

.mission-contact {
  text-transform: capitalize;
}

.mission-actions {
  min-width: 100px;
}

.mission-btn {
  padding: 8px 14px;
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 0.8rem;
  cursor: pointer;
  border: 2px solid;
  border-color: $win-white $win-dark $win-dark $win-white;
  width: 100%;

  &:active {
    border-color: $win-dark $win-white $win-white $win-dark;
  }

  &.start {
    background: #cc6600;
    color: white;
  }

  &.cancel {
    background: #cc0000;
    color: white;
  }

  &:disabled {
    opacity: 0.5;
    cursor: not-allowed;
  }
}
</style>
