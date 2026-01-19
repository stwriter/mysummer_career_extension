<template>
  <div class="checklist-page">
    <!-- Notepad header (Windows 98 style) -->
    <div class="notepad-header">
      <div class="notepad-title">
        <span class="notepad-icon">[#]</span>
        <span>etki_project_build.txt - Notepad</span>
      </div>
      <div class="notepad-menu">
        <span class="menu-item">File</span>
        <span class="menu-item">Edit</span>
        <span class="menu-item">Format</span>
        <span class="menu-item">View</span>
        <span class="menu-item">Help</span>
      </div>
    </div>

    <!-- Notepad content -->
    <div class="notepad-content">
      <pre class="notepad-text">
============================================================
    ____  ____   ___      _ _____ ____ _____
   |  _ \|  _ \ / _ \    | | ____/ ___|_   _|
   | |_) | |_) | | | |_  | |  _|| |     | |
   |  __/|  _ &lt;| |_| | |_| | |__| |___  | |
   |_|   |_| \_\\___/ \___/|_____\____| |_|

             ETK I-Series 2400Ti TT Sport
                  BUILD CHECKLIST
============================================================

Last updated: {{ currentDate }}
Project status: {{ projectStatus }}
Builder: Anonymous Mechanic

------------------------------------------------------------
   ENGINE & DRIVETRAIN                           STATUS
------------------------------------------------------------
{{ getPartStatus('engine') }} 2.4L Turbocharged Engine Block
{{ getPartStatus('turbo') }} Turbocharger Assembly
{{ getPartStatus('intercooler') }} Front-Mount Intercooler
{{ getPartStatus('intake') }} Cold Air Intake System
{{ getPartStatus('exhaust') }} Sport Exhaust System
{{ getPartStatus('radiator') }} Performance Radiator
{{ getPartStatus('ecu') }} ECU / Engine Management
{{ getPartStatus('transmission') }} 6-Speed Manual Gearbox
{{ getPartStatus('clutch') }} Stage 2 Clutch Kit
{{ getPartStatus('flywheel') }} Lightweight Flywheel
{{ getPartStatus('differential') }} Limited Slip Differential

------------------------------------------------------------
   SUSPENSION & BRAKES                           STATUS
------------------------------------------------------------
{{ getPartStatus('suspension_f') }} Front Coilover Kit
{{ getPartStatus('suspension_r') }} Rear Coilover Kit
{{ getPartStatus('brakes_f') }} Front Big Brake Kit
{{ getPartStatus('brakes_r') }} Rear Brake Upgrade
{{ getPartStatus('wheels') }} Lightweight Alloy Wheels
{{ getPartStatus('tires') }} Performance Tires

------------------------------------------------------------
   BODY & EXTERIOR                               STATUS
------------------------------------------------------------
{{ getPartStatus('hood') }} Carbon Fiber Hood
{{ getPartStatus('fenders') }} Widebody Fender Kit
{{ getPartStatus('bumper_f') }} Front Bumper / Splitter
{{ getPartStatus('bumper_r') }} Rear Bumper / Diffuser
{{ getPartStatus('spoiler') }} Rear Wing / Spoiler
{{ getPartStatus('lights_f') }} Headlight Assembly
{{ getPartStatus('lights_r') }} Tail Light Assembly
{{ getPartStatus('mirrors') }} Aero Side Mirrors

------------------------------------------------------------
   INTERIOR                                      STATUS
------------------------------------------------------------
{{ getPartStatus('seats') }} Racing Bucket Seats
{{ getPartStatus('steering') }} Sport Steering Wheel
{{ getPartStatus('rollcage') }} Roll Cage
{{ getPartStatus('harness') }} Racing Harness
{{ getPartStatus('gauges') }} Additional Gauges

------------------------------------------------------------
   ELECTRICAL                                    STATUS
------------------------------------------------------------
{{ getPartStatus('battery') }} Lightweight Battery
{{ getPartStatus('alternator') }} High Output Alternator
{{ getPartStatus('wiring') }} Engine Wiring Harness

============================================================
   BUILD PROGRESS: {{ completedCount }}/{{ totalParts }} parts ({{ progressPercent }}%)
============================================================

   [X] = Installed on vehicle
   [~] = In your parts inventory
   [ ] = Not yet acquired

------------------------------------------------------------
                    SHOPPING TIPS
------------------------------------------------------------

   * PartsBay - Great for used parts, cheap prices
              but condition varies. Meet sellers
              in person to inspect parts!

   * SpeedParts - Brand new OEM & aftermarket parts.
                More expensive but guaranteed quality.
                Free shipping over $500!

   * SilkRoad - "Free" parts if you know what I mean...
              But watch out for the heat!
              (Not responsible for police encounters)

------------------------------------------------------------
                  BUILD NOTES
------------------------------------------------------------
{{ buildNotes }}

============================================================
        "Slow car fast > fast car slow"
                            - Some guy on the internet
============================================================
      </pre>
    </div>

    <!-- Progress Section -->
    <div class="progress-section">
      <div class="progress-header">
        <span>BUILD PROGRESS</span>
        <span class="progress-pct">{{ progressPercent }}%</span>
      </div>
      <div class="progress-bar">
        <div class="progress-fill" :style="{ width: progressPercent + '%' }">
          <span class="progress-text" v-if="progressPercent > 15">{{ progressPercent }}%</span>
        </div>
      </div>
      <div class="progress-stats">
        <div class="stat-item installed">
          <span class="stat-icon">[X]</span>
          <span class="stat-value">{{ installedParts.length }}</span>
          <span class="stat-label">Installed</span>
        </div>
        <div class="stat-item inventory">
          <span class="stat-icon">[~]</span>
          <span class="stat-value">{{ inventoryParts.length }}</span>
          <span class="stat-label">In Storage</span>
        </div>
        <div class="stat-item missing">
          <span class="stat-icon">[ ]</span>
          <span class="stat-value">{{ missingParts.length }}</span>
          <span class="stat-label">Needed</span>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed } from "vue"
import { useMySummerPartsStore } from "../../../stores/mysummerPartsStore"

const emit = defineEmits(["navigate"])
const store = useMySummerPartsStore()

// Mock project parts - in real implementation comes from backend
const projectParts = ref({
  engine: { status: "missing", name: "Engine Block" },
  turbo: { status: "missing", name: "Turbocharger" },
  intercooler: { status: "missing", name: "Intercooler" },
  intake: { status: "missing", name: "Intake" },
  exhaust: { status: "missing", name: "Exhaust" },
  radiator: { status: "missing", name: "Radiator" },
  ecu: { status: "missing", name: "ECU" },
  transmission: { status: "missing", name: "Gearbox" },
  clutch: { status: "missing", name: "Clutch" },
  flywheel: { status: "missing", name: "Flywheel" },
  differential: { status: "missing", name: "Diff" },
  suspension_f: { status: "inventory", name: "Front Suspension" },
  suspension_r: { status: "missing", name: "Rear Suspension" },
  brakes_f: { status: "installed", name: "Front Brakes" },
  brakes_r: { status: "installed", name: "Rear Brakes" },
  wheels: { status: "missing", name: "Wheels" },
  tires: { status: "missing", name: "Tires" },
  hood: { status: "installed", name: "Hood" },
  fenders: { status: "installed", name: "Fenders" },
  bumper_f: { status: "missing", name: "Front Bumper" },
  bumper_r: { status: "missing", name: "Rear Bumper" },
  spoiler: { status: "missing", name: "Spoiler" },
  lights_f: { status: "inventory", name: "Headlights" },
  lights_r: { status: "missing", name: "Tail Lights" },
  mirrors: { status: "installed", name: "Mirrors" },
  seats: { status: "missing", name: "Seats" },
  steering: { status: "missing", name: "Steering" },
  rollcage: { status: "missing", name: "Roll Cage" },
  harness: { status: "missing", name: "Harness" },
  gauges: { status: "missing", name: "Gauges" },
  battery: { status: "installed", name: "Battery" },
  alternator: { status: "missing", name: "Alternator" },
  wiring: { status: "missing", name: "Wiring" }
})

const buildNotes = ref(`
   - Need to source turbo ASAP, engine is ready
   - Check PartsBay for used coilovers
   - SilkRoad had a lead on cheap ECUs last week
   - Remember: measure twice, bolt once!
`)

const currentDate = computed(() => {
  return new Date().toLocaleDateString("en-US", {
    year: "numeric",
    month: "short",
    day: "numeric"
  })
})

const totalParts = computed(() => Object.keys(projectParts.value).length)

const installedParts = computed(() =>
  Object.entries(projectParts.value).filter(([_, p]) => p.status === "installed")
)

const inventoryParts = computed(() =>
  Object.entries(projectParts.value).filter(([_, p]) => p.status === "inventory")
)

const missingParts = computed(() =>
  Object.entries(projectParts.value).filter(([_, p]) => p.status === "missing")
)

const completedCount = computed(() => installedParts.value.length)

const progressPercent = computed(() =>
  Math.round((completedCount.value / totalParts.value) * 100)
)

const projectStatus = computed(() => {
  const pct = progressPercent.value
  if (pct === 100) return "COMPLETE! Time to rip!"
  if (pct >= 75) return "Almost there..."
  if (pct >= 50) return "Halfway done"
  if (pct >= 25) return "Making progress"
  return "Just getting started"
})

const getPartStatus = (partId) => {
  const part = projectParts.value[partId]
  if (!part) return "[ ]"

  switch (part.status) {
    case "installed":
      return "[X]"
    case "inventory":
      return "[~]"
    default:
      return "[ ]"
  }
}
</script>

<style scoped lang="scss">
// Windows 98 colors
$win-gray: #c0c0c0;
$win-white: #ffffff;
$win-dark: #808080;
$win-shadow: #404040;
$win-blue: #000080;
$text-black: #000000;

.checklist-page {
  min-height: 100%;
  background: $win-gray;
  font-family: "Courier New", Courier, monospace;
  font-size: 11px;
  display: flex;
  flex-direction: column;
}

// Notepad header
.notepad-header {
  background: linear-gradient(90deg, $win-blue 0%, #1084d0 100%);
  color: white;
}

.notepad-title {
  display: flex;
  align-items: center;
  gap: 6px;
  padding: 3px 6px;
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 11px;
}

.notepad-icon {
  font-weight: bold;
}

.notepad-menu {
  display: flex;
  padding: 1px 3px;
  background: $win-gray;
  color: $text-black;
  font-family: "MS Sans Serif", Tahoma, sans-serif;
}

.menu-item {
  padding: 2px 8px;
  cursor: pointer;

  &:hover {
    background: $win-blue;
    color: white;
  }
}

// Notepad content
.notepad-content {
  flex: 1;
  background: $win-white;
  border: 2px inset $win-gray;
  margin: 2px;
  overflow: auto;
}

.notepad-text {
  margin: 0;
  padding: 8px;
  font-family: "Courier New", Courier, monospace;
  font-size: 11px;
  line-height: 1.4;
  white-space: pre;
  color: $text-black;
}

// Progress Section
.progress-section {
  background: $win-gray;
  border-top: 2px groove $win-white;
  padding: 8px;
}

.progress-header {
  display: flex;
  justify-content: space-between;
  margin-bottom: 4px;
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 11px;
  font-weight: bold;
}

.progress-pct {
  color: $win-blue;
}

.progress-bar {
  height: 20px;
  background: $win-white;
  border: 2px inset $win-gray;
  margin-bottom: 8px;
  overflow: hidden;
}

.progress-fill {
  height: 100%;
  background: repeating-linear-gradient(
    90deg,
    $win-blue 0px,
    $win-blue 10px,
    lighten($win-blue, 20%) 10px,
    lighten($win-blue, 20%) 20px
  );
  display: flex;
  align-items: center;
  justify-content: center;
  transition: width 0.3s ease;
}

.progress-text {
  color: white;
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 10px;
  font-weight: bold;
  text-shadow: 1px 1px 0 rgba(0, 0, 0, 0.5);
}

.progress-stats {
  display: flex;
  justify-content: space-around;
}

.stat-item {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 6px 12px;
  background: $win-white;
  border: 2px inset $win-gray;
  min-width: 70px;
}

.stat-icon {
  font-family: "Courier New", monospace;
  font-size: 12px;
  font-weight: bold;
  margin-bottom: 2px;

  .installed & { color: #008000; }
  .inventory & { color: #808000; }
  .missing & { color: #800000; }
}

.stat-value {
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 16px;
  font-weight: bold;
  color: $win-blue;
}

.stat-label {
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 9px;
  color: $win-dark;
}

// Scrollbar (Windows 98 style)
.notepad-content::-webkit-scrollbar {
  width: 16px;
  height: 16px;
}

.notepad-content::-webkit-scrollbar-track {
  background: $win-gray;
}

.notepad-content::-webkit-scrollbar-thumb {
  background: $win-gray;
  border: 2px outset $win-white;
}

.notepad-content::-webkit-scrollbar-thumb:hover {
  background: darken($win-gray, 5%);
}

.notepad-content::-webkit-scrollbar-button {
  width: 16px;
  height: 16px;
  background: $win-gray;
  border: 2px outset $win-white;
}

.notepad-content::-webkit-scrollbar-button:hover {
  background: darken($win-gray, 5%);
}

.notepad-content::-webkit-scrollbar-corner {
  background: $win-gray;
}
</style>
