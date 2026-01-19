<template>
  <div class="checklist-root" :class="{ compact }">
    <!-- Notepad Header -->
    <div class="notepad-header">
      <div class="notepad-title">
        <span class="notepad-icon">[ ]</span>
        <span>build_checklist.txt - Notepad</span>
      </div>
      <div class="notepad-controls">
        <span>_</span>
        <span>[]</span>
        <span>X</span>
      </div>
    </div>
    <div class="notepad-menu">
      <span>File</span>
      <span>Edit</span>
      <span>Format</span>
      <span>View</span>
      <span>Help</span>
    </div>

    <!-- Content Area -->
    <div class="notepad-content">
      <div class="notepad-text">
        <!-- Title -->
        <div class="text-line title">========================================</div>
        <div class="text-line title">      ETK-I PROJECT BUILD CHECKLIST</div>
        <div class="text-line title">========================================</div>
        <div class="text-line empty">&nbsp;</div>

        <!-- Progress Bar -->
        <div class="text-line">Progress: {{ generateAsciiProgress() }}</div>
        <div class="text-line">Parts Installed: {{ stats.perfectMatches + stats.compatibleParts }}/{{ stats.totalSlots }}</div>
        <div class="text-line empty">&nbsp;</div>

        <!-- Stats Summary -->
        <div class="text-line">--- SUMMARY ---</div>
        <div class="text-line">[OK] Perfect Matches: {{ stats.perfectMatches }}</div>
        <div class="text-line">[~~] Compatible Parts: {{ stats.compatibleParts }}</div>
        <div class="text-line">[  ] Missing Parts: {{ stats.missingParts }}</div>
        <div class="text-line" v-if="stats.mandatoryMissing > 0">[!!] CRITICAL Missing: {{ stats.mandatoryMissing }}</div>
        <div class="text-line empty">&nbsp;</div>

        <!-- Warnings -->
        <template v-if="missingReasons.length > 0">
          <div class="text-line">--- WARNINGS ---</div>
          <div class="text-line warning" v-for="reason in missingReasons" :key="reason">
            ! {{ reason }}
          </div>
          <div class="text-line empty">&nbsp;</div>
        </template>

        <!-- Filter Options -->
        <div class="text-line">--- FILTER ---</div>
        <div class="filter-options">
          <span class="filter-option" :class="{ active: filter === 'all' }" @click="filter = 'all'">
            [{{ filter === 'all' ? 'X' : ' ' }}] All ({{ totalParts }})
          </span>
          <span class="filter-option" :class="{ active: filter === 'missing' }" @click="filter = 'missing'">
            [{{ filter === 'missing' ? 'X' : ' ' }}] Missing ({{ stats.missingParts }})
          </span>
          <span class="filter-option" :class="{ active: filter === 'installed' }" @click="filter = 'installed'">
            [{{ filter === 'installed' ? 'X' : ' ' }}] Installed ({{ stats.perfectMatches + stats.compatibleParts }})
          </span>
        </div>
        <div class="text-line empty">&nbsp;</div>

        <!-- Parts List -->
        <div class="text-line">--- PARTS LIST ---</div>
        <div class="text-line separator">----------------------------------------</div>

        <div v-if="filteredParts.length === 0" class="text-line empty-state">
          > No parts to display.
        </div>

        <div
          v-for="part in filteredParts"
          :key="part.slotType"
          class="part-line"
          :class="part.status"
        >
          <span class="part-status">{{ getStatusSymbol(part.status) }}</span>
          <span class="part-name">{{ part.niceName || part.slotType }}</span>
          <span v-if="part.mandatory" class="mandatory-mark">[!]</span>
          <template v-if="part.installedPart">
            <span class="part-arrow"> -> </span>
            <span class="part-installed">{{ part.installedPart }}</span>
          </template>
        </div>

        <div class="text-line separator">----------------------------------------</div>
        <div class="text-line empty">&nbsp;</div>

        <!-- Refresh Button -->
        <div class="action-line">
          <button class="notepad-btn" @click="refresh" :disabled="store.loading">
            [ Refresh List ]
          </button>
        </div>

        <!-- Cursor -->
        <div class="text-line cursor">_</div>
      </div>
    </div>

    <!-- Status Bar -->
    <div class="notepad-statusbar">
      <span>Ln 1, Col 1</span>
      <span>{{ store.loading ? 'Loading...' : 'Ready' }}</span>
    </div>
  </div>
</template>

<script setup>
import { computed, onMounted, ref, onUnmounted } from "vue"
import { useMySummerChecklistStore } from "../../stores/mysummerChecklistStore"

const props = defineProps({
  compact: {
    type: Boolean,
    default: false,
  },
})

const store = useMySummerChecklistStore()
const filter = ref("all")

const stats = computed(() => store.checklistData.stats || {
  totalSlots: 0,
  perfectMatches: 0,
  compatibleParts: 0,
  missingParts: 0,
  mandatoryMissing: 0,
  completionPercent: 0,
})

const completionPercent = computed(() => stats.value.completionPercent || 0)
const missingReasons = computed(() => store.checklistData.missingReasons || [])

const allParts = computed(() => {
  const checklist = store.checklistData.checklist || {}
  return Object.values(checklist).sort((a, b) => {
    if (a.status !== b.status) {
      if (a.status === "missing") return -1
      if (b.status === "missing") return 1
    }
    if (a.mandatory !== b.mandatory) {
      return a.mandatory ? -1 : 1
    }
    return (a.niceName || a.slotType).localeCompare(b.niceName || b.slotType)
  })
})

const totalParts = computed(() => allParts.value.length)

const filteredParts = computed(() => {
  if (filter.value === "all") return allParts.value
  if (filter.value === "missing") return allParts.value.filter(p => p.status === "missing")
  if (filter.value === "installed") return allParts.value.filter(p => p.status === "perfect" || p.status === "compatible")
  return allParts.value
})

// Generate ASCII progress bar
const generateAsciiProgress = () => {
  const percent = Math.floor(completionPercent.value)
  const filled = Math.floor(percent / 5)  // 20 chars total
  const empty = 20 - filled
  const bar = '█'.repeat(filled) + '░'.repeat(empty)
  return `[${bar}] ${percent}%`
}

// Get status symbol for each part
const getStatusSymbol = (status) => {
  if (status === "perfect") return "[OK]"
  if (status === "compatible") return "[~~]"
  if (status === "missing") return "[  ]"
  return "[??]"
}

const refresh = async () => {
  await store.refresh()
}

onMounted(() => {
  store.requestData()
})

onUnmounted(() => {
  store.dispose()
})
</script>

<style scoped lang="scss">
// Notepad colors
$notepad-bg: #ffffff;
$notepad-text: #000000;
$notepad-gray: #808080;
$notepad-blue: #000080;
$notepad-selection: #0000ff;

.checklist-root {
  display: flex;
  flex-direction: column;
  height: 100%;
  overflow: hidden;
  background: #c0c0c0;
  font-family: 'Courier New', 'Lucida Console', monospace;
  font-size: 12px;
  color: $notepad-text;
  border: 2px solid;
  border-color: #ffffff #808080 #808080 #ffffff;
}

.checklist-root.compact {
  padding-top: 3rem;
}

// Notepad Header
.notepad-header {
  background: linear-gradient(to right, $notepad-blue, #1084d0);
  color: #ffffff;
  padding: 2px 4px;
  display: flex;
  justify-content: space-between;
  align-items: center;
  font-weight: bold;
}

.notepad-title {
  display: flex;
  align-items: center;
  gap: 4px;
}

.notepad-icon {
  font-size: 10px;
}

.notepad-controls {
  display: flex;
  gap: 2px;

  span {
    background: #c0c0c0;
    color: $notepad-text;
    width: 16px;
    height: 14px;
    display: flex;
    align-items: center;
    justify-content: center;
    font-size: 10px;
    border: 2px solid;
    border-color: #ffffff #808080 #808080 #ffffff;
    cursor: pointer;

    &:active {
      border-color: #808080 #ffffff #ffffff #808080;
    }
  }
}

// Menu Bar
.notepad-menu {
  background: #c0c0c0;
  padding: 2px 4px;
  border-bottom: 1px solid $notepad-gray;

  span {
    padding: 2px 8px;
    cursor: pointer;

    &:hover {
      background: $notepad-blue;
      color: #ffffff;
    }
  }
}

// Content Area
.notepad-content {
  flex: 1;
  background: $notepad-bg;
  overflow: auto;
  border: 2px solid;
  border-color: #808080 #ffffff #ffffff #808080;
  margin: 2px;
}

.notepad-text {
  padding: 4px 8px;
  white-space: pre-wrap;
  line-height: 1.5;
}

.text-line {
  min-height: 1.5em;

  &.title {
    font-weight: bold;
  }

  &.empty {
    color: transparent;
  }

  &.separator {
    color: $notepad-gray;
  }

  &.warning {
    color: #800000;
  }
}

// Filter Options
.filter-options {
  display: flex;
  gap: 16px;
  padding: 4px 0;
}

.filter-option {
  cursor: pointer;
  color: $notepad-text;

  &:hover {
    background: $notepad-selection;
    color: #ffffff;
  }

  &.active {
    font-weight: bold;
  }
}

// Part Lines
.part-line {
  display: flex;
  align-items: baseline;
  gap: 8px;
  padding: 2px 0;
  border-bottom: 1px dotted #e0e0e0;

  &.missing {
    .part-status {
      color: #800000;
    }
  }

  &.perfect {
    .part-status {
      color: #008000;
    }
  }

  &.compatible {
    .part-status {
      color: $notepad-blue;
    }
  }
}

.part-status {
  font-weight: bold;
  min-width: 40px;
}

.part-name {
  flex: 1;
}

.mandatory-mark {
  color: #800000;
  font-weight: bold;
}

.part-arrow {
  color: $notepad-gray;
}

.part-installed {
  color: $notepad-gray;
  font-style: italic;
}

.empty-state {
  color: $notepad-gray;
  font-style: italic;
  padding: 8px 0;
}

// Action Line
.action-line {
  padding: 8px 0;
}

.notepad-btn {
  background: #c0c0c0;
  border: 2px solid;
  border-color: #ffffff #808080 #808080 #ffffff;
  color: $notepad-text;
  padding: 4px 16px;
  font-family: 'Courier New', monospace;
  font-size: 12px;
  cursor: pointer;

  &:hover {
    background: #d0d0d0;
  }

  &:active {
    border-color: #808080 #ffffff #ffffff #808080;
  }

  &:disabled {
    color: $notepad-gray;
    cursor: not-allowed;
  }
}

// Cursor blink
.cursor {
  animation: cursor-blink 1s infinite;
  color: $notepad-text;
}

@keyframes cursor-blink {
  0%, 49% { opacity: 1; }
  50%, 100% { opacity: 0; }
}

// Status Bar
.notepad-statusbar {
  background: #c0c0c0;
  padding: 2px 8px;
  display: flex;
  justify-content: space-between;
  font-size: 11px;
  border-top: 2px solid;
  border-color: #808080 #ffffff #ffffff #808080;
}

// Scrollbar styling
.notepad-content::-webkit-scrollbar {
  width: 16px;
}

.notepad-content::-webkit-scrollbar-track {
  background: #c0c0c0;
  border: 1px solid $notepad-gray;
}

.notepad-content::-webkit-scrollbar-thumb {
  background: #c0c0c0;
  border: 2px solid;
  border-color: #ffffff #808080 #808080 #ffffff;
}
</style>
