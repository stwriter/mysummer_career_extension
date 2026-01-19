<template>
  <div class="internet-browser">
    <!-- Browser Header -->
    <div class="browser-header">
      <div class="address-bar">
        <span class="protocol">mysummer://</span>
        <span class="address">home</span>
      </div>
      <button class="close-btn" @click="closeBrowser">✕</button>
    </div>

    <!-- Browser Content -->
    <div class="browser-content">
      <div class="home-page">
        <h1 class="welcome-title">MySummer Internet</h1>
        <p class="welcome-subtitle">Select a destination</p>

        <!-- Website Cards -->
        <div class="websites-grid">
          <div
            v-for="site in websites"
            :key="site.id"
            class="website-card"
            :style="{ '--accent-color': site.color }"
            @click="navigateTo(site.id)"
          >
            <div class="site-icon">
              <span class="material-icons">{{ site.icon }}</span>
            </div>
            <div class="site-info">
              <h3>{{ site.name }}</h3>
              <p>{{ site.description }}</p>
            </div>
            <div class="site-arrow">
              <span class="material-icons">arrow_forward</span>
            </div>
          </div>
        </div>

        <!-- Future: Custom URLs section -->
        <div class="bookmarks-section">
          <h2>Bookmarks</h2>
          <p class="coming-soon">More sites coming soon...</p>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, onMounted, onUnmounted } from 'vue'
import { useBridge } from '@/bridge'

const { lua, events } = useBridge()

const websites = ref([])

const closeBrowser = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerInternet.closeBrowser()')
  }
}

const navigateTo = (siteId) => {
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerInternet.navigateTo("${siteId}")`)
  }
}

const handleBrowserOpened = (data) => {
  console.log('[MySummerInternet] Browser opened:', data)
  if (data && data.websites) {
    websites.value = data.websites
  }
}

onMounted(() => {
  events.on('mysummerInternetOpened', handleBrowserOpened)

  // Request initial data
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerInternet.getWebsites()', (result) => {
      if (result) {
        websites.value = result
      }
    })
  }
})

onUnmounted(() => {
  events.off('mysummerInternetOpened', handleBrowserOpened)
})
</script>

<style scoped lang="scss">
.internet-browser {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: #1a1a2e;
  color: #e0e0e0;
}

.browser-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.75rem 1rem;
  background: #16213e;
  border-bottom: 1px solid #0f3460;

  .address-bar {
    flex: 1;
    display: flex;
    align-items: center;
    padding: 0.5rem 1rem;
    background: #0f3460;
    border-radius: 20px;
    font-family: monospace;

    .protocol {
      color: #4caf50;
    }

    .address {
      color: #fff;
    }
  }

  .close-btn {
    padding: 0.5rem 1rem;
    background: #c62828;
    border: none;
    border-radius: 4px;
    color: #fff;
    cursor: pointer;
    font-weight: bold;

    &:hover {
      background: #e53935;
    }
  }
}

.browser-content {
  flex: 1;
  overflow-y: auto;
  padding: 2rem;
}

.home-page {
  max-width: 800px;
  margin: 0 auto;
}

.welcome-title {
  text-align: center;
  font-size: 2.5rem;
  margin: 0 0 0.5rem 0;
  background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
  -webkit-background-clip: text;
  -webkit-text-fill-color: transparent;
  background-clip: text;
}

.welcome-subtitle {
  text-align: center;
  color: #888;
  margin: 0 0 2rem 0;
}

.websites-grid {
  display: flex;
  flex-direction: column;
  gap: 1rem;
  margin-bottom: 2rem;
}

.website-card {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 1.25rem;
  background: #16213e;
  border-radius: 12px;
  border-left: 4px solid var(--accent-color, #667eea);
  cursor: pointer;
  transition: all 0.2s ease;

  &:hover {
    background: #1a2744;
    transform: translateX(8px);

    .site-arrow {
      opacity: 1;
      transform: translateX(0);
    }
  }

  .site-icon {
    width: 50px;
    height: 50px;
    display: flex;
    align-items: center;
    justify-content: center;
    background: var(--accent-color, #667eea);
    border-radius: 12px;

    .material-icons {
      font-size: 28px;
      color: #fff;
    }
  }

  .site-info {
    flex: 1;

    h3 {
      margin: 0 0 0.25rem 0;
      font-size: 1.2rem;
      color: #fff;
    }

    p {
      margin: 0;
      font-size: 0.9rem;
      color: #888;
    }
  }

  .site-arrow {
    opacity: 0;
    transform: translateX(-10px);
    transition: all 0.2s ease;

    .material-icons {
      font-size: 24px;
      color: var(--accent-color, #667eea);
    }
  }
}

.bookmarks-section {
  padding-top: 1rem;
  border-top: 1px solid #333;

  h2 {
    font-size: 1rem;
    color: #666;
    margin: 0 0 0.5rem 0;
    text-transform: uppercase;
    letter-spacing: 1px;
  }

  .coming-soon {
    color: #555;
    font-style: italic;
  }
}
</style>
