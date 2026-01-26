<template>
  <div v-if="visible" class="surveillance-hud" :class="{ 'searching-mode': isSearching }">
    <!-- Searching Mode - Simplified UI -->
    <template v-if="isSearching">
      <div class="searching-header">LOCATING TARGET</div>
      <div class="searching-distance">
        <span class="distance-value">{{ distance }}m</span>
        <span class="distance-label">to target</span>
      </div>
      <div class="searching-hint">Follow the GPS marker</div>
    </template>

    <!-- Active Surveillance Mode - Full UI -->
    <template v-else>
      <!-- Detection Meter -->
      <div class="detection-section">
        <div class="section-label">DETECTION</div>
        <div class="detection-bar-container">
          <div
            class="detection-bar"
            :class="detectionClass"
            :style="{ width: detectionMeter + '%' }"
          ></div>
          <div class="detection-value">{{ detectionMeter }}%</div>
        </div>
        <!-- Detection Trend Indicator -->
        <div class="detection-trend" :class="detectionTrendClass">
          {{ detectionTrendText }}
        </div>
      </div>

      <!-- Distance to Target -->
      <div class="distance-section">
        <div class="section-label">TARGET DISTANCE</div>
        <div class="distance-display" :class="distanceStatusClass">
          <span class="distance-value">{{ distance }}m</span>
          <span class="distance-status">{{ distanceStatusText }}</span>
        </div>
      </div>

      <!-- Target Info -->
      <div class="target-info">
        <span class="target-speed">Target: {{ targetSpeed }} km/h</span>
        <span v-if="isFollowingBehind" class="following-icon">[BEHIND]</span>
        <span v-else-if="isOncoming" class="safe-icon">[SAFE]</span>
      </div>
    </template>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from 'vue'
import { useEvents } from '@/services/events'

const events = useEvents()

// State
const visible = ref(false)
const mode = ref('searching')
const detectionMeter = ref(0)
const detectionRate = ref(0)
const distance = ref(0)
const distanceStatus = ref('optimal')
const targetSpeed = ref(0)
const isFollowingBehind = ref(false)
const isOncoming = ref(false)

// Computed
const isSearching = computed(() => mode.value === 'searching')

const detectionClass = computed(() => {
  if (detectionMeter.value < 30) return 'safe'
  if (detectionMeter.value < 60) return 'warning'
  if (detectionMeter.value < 85) return 'danger'
  return 'critical'
})

const detectionTrendClass = computed(() => {
  if (detectionRate.value > 5) return 'rising-fast'
  if (detectionRate.value > 0) return 'rising'
  if (detectionRate.value < -3) return 'falling'
  return 'stable'
})

const detectionTrendText = computed(() => {
  if (detectionRate.value > 10) return '>>> ALERT!'
  if (detectionRate.value > 5) return '>> Rising fast'
  if (detectionRate.value > 0) return '> Rising'
  if (detectionRate.value < -3) return 'Falling'
  return 'Stable'
})

const distanceStatusClass = computed(() => {
  return distanceStatus.value.replace('_', '-')
})

const distanceStatusText = computed(() => {
  switch (distanceStatus.value) {
    case 'too_close': return 'TOO CLOSE!'
    case 'close': return 'Getting close'
    case 'optimal': return 'Good distance'
    case 'safe_oncoming': return 'Safe (oncoming)'
    case 'far': return 'Getting far'
    case 'too_far': return 'TOO FAR!'
    case 'lost': return 'TARGET LOST'
    default: return ''
  }
})

// Event handlers
function onSurveillanceUpdate(data) {
  if (!data) {
    visible.value = false
    return
  }

  visible.value = true
  mode.value = data.mode || 'active'
  detectionMeter.value = data.detectionMeter || 0
  detectionRate.value = data.detectionRate || 0
  distance.value = data.distance || 0
  distanceStatus.value = data.distanceStatus || 'optimal'
  targetSpeed.value = data.targetSpeed || 0
  isFollowingBehind.value = data.isFollowingBehind || false
  isOncoming.value = data.isOncoming || false
}

// Lifecycle
onMounted(() => {
  events.on('mysummerSurveillanceUpdate', onSurveillanceUpdate)
})

onUnmounted(() => {
  events.off('mysummerSurveillanceUpdate', onSurveillanceUpdate)
})
</script>

<style scoped lang="scss">
.surveillance-hud {
  position: fixed;
  top: 120px;
  right: 20px;
  width: 220px;
  background: rgba(0, 0, 0, 0.85);
  border: 2px solid rgba(255, 255, 255, 0.3);
  border-radius: 8px;
  padding: 12px;
  font-family: 'Consolas', 'Monaco', monospace;
  color: #fff;
  z-index: 9999;
  pointer-events: none;

  &.searching-mode {
    border-color: rgba(59, 130, 246, 0.6);
    background: rgba(0, 0, 30, 0.85);
  }
}

// Searching Mode Styles
.searching-header {
  font-size: 12px;
  font-weight: bold;
  text-align: center;
  color: #3b82f6;
  margin-bottom: 10px;
  letter-spacing: 2px;
  animation: pulse-search 1.5s ease-in-out infinite;
}

.searching-distance {
  display: flex;
  align-items: baseline;
  justify-content: center;
  gap: 6px;
  margin-bottom: 8px;

  .distance-value {
    font-size: 24px;
    font-weight: bold;
    color: #fff;
  }

  .distance-label {
    font-size: 11px;
    color: rgba(255, 255, 255, 0.6);
  }
}

.searching-hint {
  font-size: 10px;
  text-align: center;
  color: rgba(255, 255, 255, 0.5);
}

@keyframes pulse-search {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.5; }
}

.section-label {
  font-size: 10px;
  color: rgba(255, 255, 255, 0.6);
  margin-bottom: 4px;
  letter-spacing: 1px;
}

// Detection Section
.detection-section {
  margin-bottom: 12px;
}

.detection-bar-container {
  position: relative;
  height: 20px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 4px;
  overflow: hidden;
}

.detection-bar {
  height: 100%;
  transition: width 0.2s ease-out;

  &.safe {
    background: linear-gradient(90deg, #22c55e, #16a34a);
  }
  &.warning {
    background: linear-gradient(90deg, #eab308, #ca8a04);
  }
  &.danger {
    background: linear-gradient(90deg, #f97316, #ea580c);
  }
  &.critical {
    background: linear-gradient(90deg, #ef4444, #dc2626);
    animation: pulse-critical 0.5s ease-in-out infinite;
  }
}

.detection-value {
  position: absolute;
  right: 8px;
  top: 50%;
  transform: translateY(-50%);
  font-size: 12px;
  font-weight: bold;
  text-shadow: 0 0 4px rgba(0, 0, 0, 0.8);
}

.detection-trend {
  margin-top: 4px;
  font-size: 10px;
  text-align: center;
  padding: 2px 6px;
  border-radius: 3px;

  &.stable {
    color: rgba(255, 255, 255, 0.6);
  }
  &.falling {
    color: #22c55e;
  }
  &.rising {
    color: #eab308;
  }
  &.rising-fast {
    color: #ef4444;
    font-weight: bold;
    animation: pulse-critical 0.5s ease-in-out infinite;
  }
}

// Distance Section
.distance-section {
  margin-bottom: 12px;
}

.distance-display {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 6px 10px;
  border-radius: 4px;
  background: rgba(255, 255, 255, 0.1);

  &.too-close, &.close {
    background: rgba(239, 68, 68, 0.3);
    border-left: 3px solid #ef4444;
  }
  &.optimal, &.safe-oncoming {
    background: rgba(34, 197, 94, 0.3);
    border-left: 3px solid #22c55e;
  }
  &.far {
    background: rgba(234, 179, 8, 0.3);
    border-left: 3px solid #eab308;
  }
  &.too-far, &.lost {
    background: rgba(239, 68, 68, 0.3);
    border-left: 3px solid #ef4444;
    animation: blink 0.5s ease-in-out infinite;
  }
}

.distance-value {
  font-size: 18px;
  font-weight: bold;
}

.distance-status {
  font-size: 10px;
  opacity: 0.8;
}

// Target Info
.target-info {
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-size: 10px;
  color: rgba(255, 255, 255, 0.7);
  margin-top: 8px;
  padding-top: 8px;
  border-top: 1px solid rgba(255, 255, 255, 0.2);
}

.following-icon {
  color: #eab308;
  font-weight: bold;
}

.safe-icon {
  color: #22c55e;
  font-weight: bold;
}

@keyframes pulse-critical {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.7; }
}

@keyframes blink {
  0%, 100% { opacity: 1; }
  50% { opacity: 0.3; }
}
</style>
