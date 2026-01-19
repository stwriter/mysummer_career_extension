<template>
  <div class="retro-browser">
    <!-- Window Title Bar (Windows 95 style) -->
    <div class="title-bar">
      <div class="title-bar-text">
        <span class="title-icon">[]</span>
        Internet Explorer 4.0
      </div>
      <div class="title-bar-controls">
        <button class="title-btn minimize">_</button>
        <button class="title-btn maximize">[]</button>
        <button class="title-btn close" @click="closeMenu">X</button>
      </div>
    </div>

    <!-- Menu Bar -->
    <div class="menu-bar">
      <span class="menu-item">File</span>
      <span class="menu-item">Edit</span>
      <span class="menu-item">View</span>
      <span class="menu-item">Favorites</span>
      <span class="menu-item">Help</span>
    </div>

    <!-- Navigation Bar -->
    <div class="nav-bar">
      <div class="nav-buttons">
        <button class="nav-btn" :disabled="!canGoBack" @click="goBack" title="Back">
          <span class="btn-icon">&lt;</span>
          <span class="btn-label">Back</span>
        </button>
        <button class="nav-btn" :disabled="!canGoForward" @click="goForward" title="Forward">
          <span class="btn-icon">&gt;</span>
          <span class="btn-label">Forward</span>
        </button>
        <button class="nav-btn" @click="refreshPage" title="Refresh">
          <span class="btn-icon">@</span>
          <span class="btn-label">Refresh</span>
        </button>
        <button class="nav-btn" @click="goHome" title="Home">
          <span class="btn-icon">H</span>
          <span class="btn-label">Home</span>
        </button>
      </div>
    </div>

    <!-- Address Bar -->
    <div class="address-bar">
      <span class="address-label">Address</span>
      <div class="address-input-wrapper">
        <span class="address-icon">@</span>
        <input
          type="text"
          class="address-input"
          v-model="addressBarValue"
          @keyup.enter="navigateToUrl"
          @focus="selectAddressBar"
        />
      </div>
      <button class="go-btn" @click="navigateToUrl">Go</button>
    </div>

    <!-- Bookmarks / Favorites Bar -->
    <div class="bookmarks-bar">
      <span class="bookmarks-label">Links</span>
      <div class="bookmarks-list">
        <button
          v-for="bookmark in bookmarks"
          :key="bookmark.id"
          class="bookmark"
          :class="{ active: currentPage === bookmark.id }"
          @click="navigateTo(bookmark.id)"
        >
          <span class="bookmark-icon">{{ bookmark.icon }}</span>
          <span class="bookmark-text">{{ bookmark.name }}</span>
        </button>
      </div>
    </div>

    <!-- Browser Content Area -->
    <div class="browser-content">
      <!-- Home Page - Desktop style with icons grid -->
      <div v-if="currentPage === 'home'" class="page home-page desktop">
        <div class="desktop-icons">
          <button
            v-for="bookmark in bookmarks"
            :key="bookmark.id"
            class="desktop-icon"
            @click="navigateTo(bookmark.id)"
            @dblclick="navigateTo(bookmark.id)"
          >
            <div class="icon-image" :class="bookmark.id">
              <span class="icon-glyph">{{ bookmark.icon }}</span>
            </div>
            <span class="icon-label">{{ bookmark.name }}</span>
          </button>
        </div>
      </div>

      <!-- Deep Web - Leads/Soplos -->
      <DeepWebPage
        v-else-if="currentPage === 'deepweb'"
        @navigate="navigateTo"
      />

      <!-- PartsBay - Second Hand Parts -->
      <PartsBayPage
        v-else-if="currentPage === 'partsbay'"
        @navigate="navigateTo"
      />

      <!-- Official Store -->
      <OfficialStorePage
        v-else-if="currentPage === 'official'"
        @navigate="navigateTo"
      />

      <!-- Project Checklist -->
      <ProjectChecklistPage
        v-else-if="currentPage === 'checklist'"
        @navigate="navigateTo"
      />
    </div>

    <!-- Status Bar -->
    <div class="status-bar">
      <div class="status-left">
        <span class="status-icon" :class="statusClass">{{ statusIcon }}</span>
        <span class="status-text">{{ statusText }}</span>
      </div>
      <div class="status-right">
        <span class="status-zone">Internet Zone</span>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, onUnmounted } from "vue"
import { useMySummerPartsStore } from "../../stores/mysummerPartsStore"
import DeepWebPage from "./browser/DeepWebPage.vue"
import PartsBayPage from "./browser/PartsBayPage.vue"
import OfficialStorePage from "./browser/OfficialStorePage.vue"
import ProjectChecklistPage from "./browser/ProjectChecklistPage.vue"

const store = useMySummerPartsStore()

const currentPage = ref("home")
const history = ref(["home"])
const historyIndex = ref(0)
const addressBarValue = ref("about:home")

const bookmarks = [
  {
    id: "deepweb",
    name: "SilkRoad Parts",
    icon: "[!]",
    url: "s1lkr04d.onion",
    description: "Anonymous leads... shh!"
  },
  {
    id: "partsbay",
    name: "PartsBay",
    icon: "[$]",
    url: "partsbay.com",
    description: "Used parts from local sellers"
  },
  {
    id: "official",
    name: "SpeedParts",
    icon: "[S]",
    url: "speedparts.com",
    description: "OEM & Performance parts"
  },
  {
    id: "checklist",
    name: "Project",
    icon: "[P]",
    url: "localhost/project",
    description: "Your ETK-I build checklist"
  }
]

const urls = {
  home: "about:home",
  deepweb: "http://s1lkr04d.onion/",
  partsbay: "http://www.partsbay.com/",
  official: "https://www.speedparts.com/",
  checklist: "file:///C:/Project/checklist.txt"
}

// Reverse lookup: URL pattern to page ID
const urlToPage = {
  "about:home": "home",
  "s1lkr04d.onion": "deepweb",
  "partsbay.com": "partsbay",
  "speedparts.com": "official",
  "file:///c:/project": "checklist",
  "localhost/project": "checklist",
}

const currentUrl = computed(() => urls[currentPage.value] || "about:blank")

const canGoBack = computed(() => historyIndex.value > 0)
const canGoForward = computed(() => historyIndex.value < history.value.length - 1)

const statusText = computed(() => {
  if (store.loading) return "Loading..."
  return "Done"
})

const statusIcon = computed(() => {
  if (store.loading) return "@"
  return "v"
})

const statusClass = computed(() => {
  if (store.loading) return "loading"
  return "done"
})

// Parse URL and find matching page ID
const parseUrlToPageId = (url) => {
  const normalizedUrl = url.toLowerCase().trim()

  // Direct match first
  for (const [pattern, pageId] of Object.entries(urlToPage)) {
    if (normalizedUrl === pattern || normalizedUrl.includes(pattern)) {
      return pageId
    }
  }

  // Check bookmarks by URL
  for (const bookmark of bookmarks) {
    if (normalizedUrl.includes(bookmark.url.toLowerCase())) {
      return bookmark.id
    }
  }

  return null
}

const navigateTo = (pageId) => {
  if (pageId === currentPage.value) return

  // Truncate forward history if navigating from middle
  if (historyIndex.value < history.value.length - 1) {
    history.value = history.value.slice(0, historyIndex.value + 1)
  }

  history.value.push(pageId)
  historyIndex.value = history.value.length - 1
  currentPage.value = pageId

  // Update address bar
  addressBarValue.value = urls[pageId] || "about:blank"
}

const navigateToUrl = () => {
  const url = addressBarValue.value.trim()
  if (!url) return

  const pageId = parseUrlToPageId(url)
  if (pageId) {
    navigateTo(pageId)
  } else {
    // Unknown URL - show 404 or stay on current page
    // For now, just update the address bar to show invalid
    console.log("[MySummerBrowser] Unknown URL:", url)
  }
}

const selectAddressBar = (event) => {
  event.target.select()
}

const goBack = () => {
  if (canGoBack.value) {
    historyIndex.value--
    currentPage.value = history.value[historyIndex.value]
    addressBarValue.value = urls[currentPage.value] || "about:blank"
  }
}

const goForward = () => {
  if (canGoForward.value) {
    historyIndex.value++
    currentPage.value = history.value[historyIndex.value]
    addressBarValue.value = urls[currentPage.value] || "about:blank"
  }
}

const goHome = () => {
  navigateTo("home")
}

const refreshPage = () => {
  store.requestData()
}

const closeMenu = () => {
  store.closeMenu()
}

onMounted(() => {
  store.requestData()
})

onUnmounted(() => {
  store.dispose()
})
</script>

<style scoped lang="scss">
// ============================================
// RETRO BROWSER - Windows 95/IE4 Style
// ============================================

$win-gray: #c0c0c0;
$win-dark: #808080;
$win-light: #ffffff;
$win-shadow: #404040;
$win-blue: #000080;
$win-cyan: #008080;

$border-raised: inset -1px -1px $win-shadow, inset 1px 1px $win-light, inset -2px -2px $win-dark, inset 2px 2px $win-gray;
$border-sunken: inset 1px 1px $win-shadow, inset -1px -1px $win-light, inset 2px 2px $win-dark, inset -2px -2px $win-gray;

.retro-browser {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: $win-gray;
  font-family: "MS Sans Serif", "Segoe UI", Tahoma, sans-serif;
  font-size: 11px;
  color: #000;
  box-shadow: $border-raised;
}

// Title Bar
.title-bar {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 2px 3px;
  background: linear-gradient(90deg, $win-blue, $win-cyan);
  color: white;
  font-weight: bold;
}

.title-bar-text {
  display: flex;
  align-items: center;
  gap: 4px;
}

.title-icon {
  font-family: monospace;
  font-size: 10px;
}

.title-bar-controls {
  display: flex;
  gap: 2px;
}

.title-btn {
  width: 16px;
  height: 14px;
  background: $win-gray;
  border: none;
  box-shadow: $border-raised;
  font-size: 9px;
  font-weight: bold;
  cursor: pointer;
  display: flex;
  align-items: center;
  justify-content: center;

  &:active {
    box-shadow: $border-sunken;
  }

  &.close:hover {
    background: #ff6666;
  }
}

// Menu Bar
.menu-bar {
  display: flex;
  gap: 0;
  padding: 1px 2px;
  background: $win-gray;
  border-bottom: 1px solid $win-dark;
}

.menu-item {
  padding: 2px 8px;
  cursor: pointer;

  &:hover {
    background: $win-blue;
    color: white;
  }
}

// Navigation Bar
.nav-bar {
  display: flex;
  padding: 2px 4px;
  background: $win-gray;
  border-bottom: 1px solid $win-dark;
}

.nav-buttons {
  display: flex;
  gap: 2px;
}

.nav-btn {
  display: flex;
  flex-direction: column;
  align-items: center;
  padding: 2px 8px;
  background: $win-gray;
  border: none;
  box-shadow: $border-raised;
  cursor: pointer;
  min-width: 50px;

  &:active:not(:disabled) {
    box-shadow: $border-sunken;
  }

  &:disabled {
    color: $win-dark;
    cursor: default;
  }

  .btn-icon {
    font-family: monospace;
    font-size: 14px;
    font-weight: bold;
  }

  .btn-label {
    font-size: 9px;
  }
}

// Address Bar
.address-bar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 4px;
  background: $win-gray;
  border-bottom: 1px solid $win-dark;
}

.address-label {
  font-size: 10px;
  color: #000;
  min-width: 42px;
}

.address-input-wrapper {
  flex: 1;
  display: flex;
  align-items: center;
  background: white;
  box-shadow: $border-sunken;
  padding: 1px 2px;
}

.address-icon {
  padding: 0 4px;
  font-family: monospace;
  color: $win-blue;
}

.address-input {
  flex: 1;
  border: none;
  background: transparent;
  font-family: monospace;
  font-size: 11px;
  outline: none;
}

.go-btn {
  padding: 2px 12px;
  background: $win-gray;
  border: none;
  box-shadow: $border-raised;
  cursor: pointer;

  &:active {
    box-shadow: $border-sunken;
  }
}

// Bookmarks Bar
.bookmarks-bar {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 4px;
  background: $win-gray;
  border-bottom: 2px solid $win-dark;
}

.bookmarks-label {
  font-size: 10px;
  min-width: 30px;
}

.bookmarks-list {
  display: flex;
  gap: 2px;
  flex: 1;
}

.bookmark {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 2px 8px;
  background: $win-gray;
  border: none;
  box-shadow: $border-raised;
  cursor: pointer;
  font-size: 10px;

  &:active, &.active {
    box-shadow: $border-sunken;
    background: #d4d0c8;
  }

  &:hover:not(.active) {
    background: #d8d8d8;
  }

  .bookmark-icon {
    font-family: monospace;
    font-size: 9px;
    color: $win-blue;
  }
}

// Browser Content
.browser-content {
  flex: 1;
  background: white;
  box-shadow: $border-sunken;
  margin: 2px;
  overflow: auto;
}

// Home Page - Desktop with icons grid
.home-page.desktop {
  padding: 20px;
  background: linear-gradient(180deg, #008080 0%, #004040 100%); // Teal desktop
  min-height: 100%;
}

.desktop-icons {
  display: grid;
  grid-template-columns: repeat(auto-fill, 90px);
  gap: 16px;
  padding: 16px;
  justify-content: start;
  align-content: start;
}

.desktop-icon {
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 4px;
  padding: 8px;
  background: transparent;
  border: 1px solid transparent;
  cursor: pointer;
  width: 80px;

  &:hover {
    background: rgba(255, 255, 255, 0.1);
    border: 1px dotted white;
  }

  &:focus {
    background: $win-blue;
    border: 1px dotted yellow;
    outline: none;

    .icon-label {
      background: $win-blue;
      color: white;
    }
  }

  &:active {
    .icon-image {
      transform: translate(1px, 1px);
    }
  }
}

.icon-image {
  width: 48px;
  height: 48px;
  display: flex;
  align-items: center;
  justify-content: center;
  background: $win-gray;
  border: 2px outset $win-light;
  box-shadow: 2px 2px 0 rgba(0, 0, 0, 0.3);

  // Different colors per site
  &.deepweb {
    background: linear-gradient(135deg, #1a1a2e 0%, #16213e 100%);
    border-color: #0f3460;
    .icon-glyph { color: #00ff00; }
  }

  &.partsbay {
    background: linear-gradient(135deg, #ffff00 0%, #e6c200 100%);
    border-color: #cc9900;
    .icon-glyph { color: #0000cc; }
  }

  &.official {
    background: linear-gradient(135deg, #0066cc 0%, #004499 100%);
    border-color: #003366;
    .icon-glyph { color: #ff6600; }
  }

  &.checklist {
    background: linear-gradient(135deg, #ffffff 0%, #e0e0e0 100%);
    border-color: #808080;
    .icon-glyph { color: #000080; }
  }
}

.icon-glyph {
  font-family: monospace;
  font-size: 20px;
  font-weight: bold;
}

.icon-label {
  font-family: "MS Sans Serif", Tahoma, sans-serif;
  font-size: 10px;
  color: white;
  text-shadow: 1px 1px 0 black, -1px -1px 0 black, 1px -1px 0 black, -1px 1px 0 black;
  text-align: center;
  word-wrap: break-word;
  max-width: 75px;
  padding: 1px 3px;
}

// Status Bar
.status-bar {
  display: flex;
  justify-content: space-between;
  padding: 2px 4px;
  background: $win-gray;
  border-top: 1px solid $win-light;
  font-size: 10px;
}

.status-left {
  display: flex;
  align-items: center;
  gap: 4px;
  flex: 1;
  box-shadow: $border-sunken;
  padding: 1px 4px;
  background: $win-gray;
}

.status-icon {
  font-family: monospace;
  font-weight: bold;

  &.loading {
    color: $win-blue;
    animation: spin 1s linear infinite;
  }

  &.done {
    color: green;
  }
}

@keyframes spin {
  from { transform: rotate(0deg); }
  to { transform: rotate(360deg); }
}

.status-right {
  box-shadow: $border-sunken;
  padding: 1px 8px;
  background: $win-gray;
  min-width: 100px;
  text-align: center;
}

// Scrollbar styling
.browser-content::-webkit-scrollbar {
  width: 16px;
  background: $win-gray;
}

.browser-content::-webkit-scrollbar-thumb {
  background: $win-gray;
  box-shadow: $border-raised;
}

.browser-content::-webkit-scrollbar-button {
  height: 16px;
  background: $win-gray;
  box-shadow: $border-raised;
}
</style>
