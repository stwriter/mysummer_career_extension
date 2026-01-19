<template>
  <div class="online-shop">
    <!-- Shop Header with back button -->
    <div class="shop-header">
      <button class="back-btn" @click="goBack">[BACK]</button>
      <div class="shop-title">
        <h2>ETK_PARTS_DIRECT.net</h2>
        <p class="tagline">// Official distributor - Pickup at Port</p>
      </div>
      <div class="header-right">
        <div class="player-funds">
          <span class="label">BALANCE:</span>
          <span class="amount">${{ formatNumber(playerFunds) }}</span>
        </div>
      </div>
    </div>

    <div class="shop-body">
      <!-- Left: Parts Catalog -->
      <div class="catalog-panel">
        <div class="filter-bar">
          <input
            v-model="searchQuery"
            type="text"
            placeholder="Search parts..."
            class="search-input"
          />
        </div>

        <div class="categories-list">
          <!-- Category sections -->
          <div
            v-for="category in filteredCategories"
            :key="category.name"
            class="category-section"
          >
            <div
              class="category-header"
              :class="{ expanded: expandedCategories[category.name] }"
              @click="toggleCategory(category.name)"
            >
              <span class="expand-icon">
                {{ expandedCategories[category.name] ? '[-]' : '[+]' }}
              </span>
              <span class="category-name">{{ category.displayName.toUpperCase() }}</span>
              <span class="category-count">({{ category.totalParts }})</span>
            </div>

            <!-- Subcategories -->
            <div v-if="expandedCategories[category.name]" class="subcategories-container">
              <div
                v-for="subcategory in category.subcategories"
                :key="subcategory.name"
                class="subcategory-section"
              >
                <div
                  class="subcategory-header"
                  :class="{ expanded: isSubcategoryExpanded(category.name, subcategory.name) }"
                  @click="toggleSubcategory(category.name, subcategory.name)"
                >
                  <span class="expand-icon">
                    {{ isSubcategoryExpanded(category.name, subcategory.name) ? '[-]' : '[+]' }}
                  </span>
                  <span class="subcategory-name">{{ subcategory.displayName }}</span>
                  <span class="subcategory-count">({{ subcategory.parts.length }})</span>
                </div>

                <!-- Parts in subcategory -->
                <div v-if="isSubcategoryExpanded(category.name, subcategory.name)" class="subcategory-parts">
                  <div
                    v-for="part in subcategory.parts"
                    :key="part.name"
                    class="part-item"
                    :class="{ 'in-cart': isInCart(part.name) }"
                    @click="addToCart(part)"
                  >
                    <div class="part-info">
                      <span class="part-name">{{ part.niceName }}</span>
                      <span class="part-slot">{{ formatSlotType(part.slotType) }}</span>
                    </div>
                    <div class="part-price">${{ formatNumber(part.shopPrice) }}</div>
                    <div class="add-icon">{{ isInCart(part.name) ? '[OK]' : '[ADD]' }}</div>
                  </div>
                </div>
              </div>
            </div>
          </div>

          <div v-if="filteredCategories.length === 0" class="no-parts">
            -- NO_RESULTS_FOUND --
          </div>
        </div>
      </div>

      <!-- Right: Shopping Cart -->
      <div class="cart-panel">
        <div class="cart-header">
          <h3>// CART</h3>
          <span class="cart-count">[{{ cartItemCount }}]</span>
        </div>

        <div class="cart-items">
          <div v-if="cart.length === 0" class="empty-cart">
            -- CART_EMPTY --
          </div>

          <div
            v-for="item in cart"
            :key="item.name"
            class="cart-item"
          >
            <div class="item-info">
              <span class="item-name">{{ item.niceName }}</span>
              <span class="item-qty">x{{ item.quantity }}</span>
            </div>
            <div class="item-price">${{ formatNumber(item.shopPrice * item.quantity) }}</div>
            <button class="remove-btn" @click.stop="removeFromCart(item.name)">[X]</button>
          </div>
        </div>

        <div class="cart-footer">
          <div class="cart-total">
            <span class="total-label">TOTAL:</span>
            <span class="total-amount">${{ formatNumber(cartTotal) }}</span>
          </div>

          <div class="delivery-info">
            <span>&gt; Pickup location: PORT</span>
          </div>

          <button
            class="checkout-btn"
            :disabled="cart.length === 0 || cartTotal > playerFunds || purchasing"
            @click="checkout"
          >
            <span v-if="purchasing">[PROCESSING...]</span>
            <span v-else-if="cartTotal > playerFunds">[INSUFFICIENT_FUNDS]</span>
            <span v-else>[PLACE_ORDER]</span>
          </button>

          <button
            v-if="cart.length > 0"
            class="clear-btn"
            @click="clearCart"
          >
            [CLEAR]
          </button>
        </div>
      </div>
    </div>

    <!-- Order Success Modal -->
    <div v-if="orderSuccess" class="order-modal">
      <div class="modal-content">
        <div class="success-icon">[OK]</div>
        <h2>ORDER_CONFIRMED</h2>
        <p>&gt; Parts ready for pickup at: PORT</p>
        <p class="order-details">{{ cartItemCount }} items - ${{ formatNumber(cartTotal) }}</p>
        <button class="modal-btn" @click="orderSuccess = false; clearCart()">
          [CONTINUE]
        </button>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, reactive } from 'vue'
import { useBridge } from '@/bridge'

const { lua, events } = useBridge()

const parts = ref([])
const playerFunds = ref(0)
const searchQuery = ref('')
const cart = ref([])
const purchasing = ref(false)
const orderSuccess = ref(false)
const expandedCategories = reactive({})
const expandedSubcategories = reactive({})

// Category and subcategory definitions - based on real ETK-I slotTypes
const categoryDefinitions = {
  engine: {
    displayName: 'Engine',
    icon: 'local_fire_department',
    order: 1,
    subcategories: {
      engine: { displayName: 'Engine', order: 1 },
      internals: { displayName: 'Internals', order: 2 },
      intake: { displayName: 'Intake', order: 3 },
      ecu: { displayName: 'ECU', order: 4 },
      mounts: { displayName: 'Engine Mounts', order: 5 },
      oilpan: { displayName: 'Oil Pan', order: 6 },
      cooling: { displayName: 'Oil Cooler', order: 7 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  drivetrain: {
    displayName: 'Drivetrain',
    icon: 'settings',
    order: 2,
    subcategories: {
      transmission: { displayName: 'Transmission', order: 1 },
      transfer_case: { displayName: 'Transfer Case', order: 2 },
      flywheel: { displayName: 'Flywheel', order: 3 },
      differential: { displayName: 'Differential', order: 4 },
      finaldrive: { displayName: 'Final Drive', order: 5 },
      driveshafts: { displayName: 'Driveshafts', order: 6 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  exhaust: {
    displayName: 'Exhaust',
    icon: 'air',
    order: 3,
    subcategories: {
      exhaust: { displayName: 'Exhaust System', order: 1 },
      converter: { displayName: 'Catalytic Converter', order: 2 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  suspension: {
    displayName: 'Suspension',
    icon: 'height',
    order: 4,
    subcategories: {
      front: { displayName: 'Front', order: 1 },
      rear: { displayName: 'Rear', order: 2 },
      struts: { displayName: 'Struts', order: 3 },
      coilovers: { displayName: 'Coilovers', order: 4 },
      swaybars: { displayName: 'Sway Bars', order: 5 },
      strut_bar: { displayName: 'Strut Bar', order: 6 },
      suspension: { displayName: 'General', order: 7 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  brakes: {
    displayName: 'Brakes',
    icon: 'do_not_disturb_on',
    order: 5,
    subcategories: {
      front: { displayName: 'Front Brakes', order: 1 },
      rear: { displayName: 'Rear Brakes', order: 2 },
      pads_front: { displayName: 'Front Pads', order: 3 },
      pads_rear: { displayName: 'Rear Pads', order: 4 },
      pads: { displayName: 'Brake Pads', order: 5 },
      abs: { displayName: 'ABS', order: 6 },
      brakes: { displayName: 'General', order: 7 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  steering: {
    displayName: 'Steering',
    icon: 'swap_horiz',
    order: 6,
    subcategories: {
      wheel: { displayName: 'Steering Wheel', order: 1 },
      steering: { displayName: 'Steering System', order: 2 },
      steeringbox: { displayName: 'Steering Box', order: 3 },
      power_steering: { displayName: 'Power Steering', order: 4 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  wheels: {
    displayName: 'Wheels & Tires',
    icon: 'trip_origin',
    order: 7,
    subcategories: {
      rims_front: { displayName: 'Front Rims', order: 1 },
      rims_rear: { displayName: 'Rear Rims', order: 2 },
      tires_front: { displayName: 'Front Tires', order: 3 },
      tires_rear: { displayName: 'Rear Tires', order: 4 },
      tires: { displayName: 'Tires', order: 5 },
      wheeldata_front: { displayName: 'Front Wheel Data', order: 6 },
      wheeldata_rear: { displayName: 'Rear Wheel Data', order: 7 },
      wheeldata: { displayName: 'Wheel Data', order: 8 },
      hubcaps: { displayName: 'Hubcaps', order: 9 },
      wheels: { displayName: 'General', order: 10 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  body: {
    displayName: 'Body',
    icon: 'directions_car',
    order: 8,
    subcategories: {
      body: { displayName: 'Body Shell', order: 1 },
      hood: { displayName: 'Hood', order: 2 },
      trunk: { displayName: 'Trunk', order: 3 },
      doors: { displayName: 'Doors', order: 4 },
      door_panels: { displayName: 'Door Panels', order: 5 },
      door_glass: { displayName: 'Door Glass', order: 6 },
      fenders: { displayName: 'Fenders', order: 7 },
      bumpers: { displayName: 'Bumpers', order: 8 },
      bumper_bars: { displayName: 'Bumper Bars', order: 9 },
      grille: { displayName: 'Grille', order: 10 },
      glass: { displayName: 'Glass', order: 11 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  exterior: {
    displayName: 'Exterior',
    icon: 'auto_awesome',
    order: 9,
    subcategories: {
      mirrors: { displayName: 'Mirrors', order: 1 },
      spoilers: { displayName: 'Spoilers', order: 2 },
      window_spoiler: { displayName: 'Window Spoiler', order: 3 },
      sideskirts: { displayName: 'Side Skirts', order: 4 },
      lips: { displayName: 'Lips', order: 5 },
      fenderflares: { displayName: 'Fender Flares', order: 6 },
      mudflaps: { displayName: 'Mudflaps', order: 7 },
      skidplates: { displayName: 'Skid Plates', order: 8 },
      towhitch: { displayName: 'Tow Hitch', order: 9 },
      licenseplate: { displayName: 'License Plate', order: 10 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  lights: {
    displayName: 'Lights',
    icon: 'lightbulb',
    order: 10,
    subcategories: {
      headlights: { displayName: 'Headlights', order: 1 },
      taillights: { displayName: 'Taillights', order: 2 },
      backlights: { displayName: 'Back Lights', order: 3 },
      fog_lights: { displayName: 'Fog Lights', order: 4 },
      rally_lights: { displayName: 'Rally Lights', order: 5 },
      bumper_lights: { displayName: 'Bumper Lights', order: 6 },
      flashers: { displayName: 'Flashers', order: 7 },
      signals: { displayName: 'Signals', order: 8 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  interior: {
    displayName: 'Interior',
    icon: 'event_seat',
    order: 11,
    subcategories: {
      interior: { displayName: 'Interior', order: 1 },
      seats: { displayName: 'Seats', order: 2 },
      trim: { displayName: 'Trim', order: 3 },
      switches: { displayName: 'Switches', order: 4 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  rollcage: {
    displayName: 'Roll Cage',
    icon: 'grid_on',
    order: 12,
    subcategories: {
      cage: { displayName: 'Cage', order: 1 },
      lightbar: { displayName: 'Light Bar', order: 2 },
      accessories: { displayName: 'Accessories', order: 3 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  roof: {
    displayName: 'Roof',
    icon: 'roofing',
    order: 13,
    subcategories: {
      accessories: { displayName: 'Accessories', order: 1 },
      antenna: { displayName: 'Antenna', order: 2 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  cooling: {
    displayName: 'Cooling',
    icon: 'ac_unit',
    order: 14,
    subcategories: {
      radiator: { displayName: 'Radiator', order: 1 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  fuel: {
    displayName: 'Fuel',
    icon: 'local_gas_station',
    order: 15,
    subcategories: {
      fueltank: { displayName: 'Fuel Tank', order: 1 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  cosmetic: {
    displayName: 'Cosmetic',
    icon: 'palette',
    order: 16,
    subcategories: {
      lettering: { displayName: 'Lettering', order: 1 },
      logos: { displayName: 'Logos', order: 2 },
      paint: { displayName: 'Paint', order: 3 },
      light_skins: { displayName: 'Light Skins', order: 4 },
      interior_skins: { displayName: 'Interior Skins', order: 5 },
      gauge_skins: { displayName: 'Gauge Skins', order: 6 },
      sunstrip: { displayName: 'Sunstrip', order: 7 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  electronics: {
    displayName: 'Electronics',
    icon: 'memory',
    order: 17,
    subcategories: {
      gps: { displayName: 'GPS', order: 1 },
      gauges: { displayName: 'Gauges', order: 2 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  misc: {
    displayName: 'Miscellaneous',
    icon: 'more_horiz',
    order: 18,
    subcategories: {
      wipers: { displayName: 'Wipers', order: 1 },
      spare: { displayName: 'Spare Parts', order: 2 },
      cargo: { displayName: 'Cargo', order: 3 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  other: {
    displayName: 'Other',
    icon: 'help_outline',
    order: 99,
    subcategories: {
      other: { displayName: 'Uncategorized', order: 99 },
    }
  },
}

// Categorize a part based on its slotType - using real BeamNG ETK-I slots from config
const categorizePart = (part) => {
  const slot = (typeof part.slotType === 'string' ? part.slotType : '').toLowerCase()

  // ENGINE - etki_engine, etki_engine_internals, etki_engine_ecu, etki_enginemounts, etki_intake, etki_oilpan, etki_oilcooler
  if (slot.includes('engine') || slot.includes('intake') || slot.includes('oilpan') || slot.includes('oilcooler')) {
    if (slot.includes('internals')) return { category: 'engine', subcategory: 'internals' }
    if (slot.includes('ecu')) return { category: 'engine', subcategory: 'ecu' }
    if (slot.includes('mounts')) return { category: 'engine', subcategory: 'mounts' }
    if (slot.includes('intake')) return { category: 'engine', subcategory: 'intake' }
    if (slot.includes('oilpan')) return { category: 'engine', subcategory: 'oilpan' }
    if (slot.includes('oilcooler')) return { category: 'engine', subcategory: 'oilcooler' }
    return { category: 'engine', subcategory: 'engine' }
  }

  // DRIVETRAIN - etki_transmission, etki_transfer_case, etki_flywheel, etki_differential_F/R, etki_finaldrive_F/R, etki_driveshaft_F/R, etki_halfshafts_F/R
  if (slot.includes('transmission') || slot.includes('transfer_case') || slot.includes('flywheel') ||
      slot.includes('differential') || slot.includes('finaldrive') || slot.includes('driveshaft') || slot.includes('halfshaft')) {
    if (slot.includes('transmission')) return { category: 'drivetrain', subcategory: 'transmission' }
    if (slot.includes('transfer_case')) return { category: 'drivetrain', subcategory: 'transfer_case' }
    if (slot.includes('flywheel')) return { category: 'drivetrain', subcategory: 'flywheel' }
    if (slot.includes('differential')) return { category: 'drivetrain', subcategory: 'differential' }
    if (slot.includes('finaldrive')) return { category: 'drivetrain', subcategory: 'finaldrive' }
    if (slot.includes('driveshaft') || slot.includes('halfshaft')) return { category: 'drivetrain', subcategory: 'driveshafts' }
    return { category: 'drivetrain', subcategory: 'other' }
  }

  // EXHAUST - etki_exhaust, etki_exhaust_offroad, etki_converter
  if (slot.includes('exhaust') || slot.includes('converter')) {
    if (slot.includes('converter')) return { category: 'exhaust', subcategory: 'converter' }
    return { category: 'exhaust', subcategory: 'exhaust' }
  }

  // SUSPENSION - etki_suspension_F/R, etki_strut_F, etki_coilover_R, etki_swaybar_F/R, etki_strut_bar
  if (slot.includes('suspension') || slot.includes('strut') || slot.includes('coilover') || slot.includes('swaybar')) {
    if (slot.includes('strut_bar')) return { category: 'suspension', subcategory: 'strut_bar' }
    if (slot.includes('strut')) return { category: 'suspension', subcategory: 'struts' }
    if (slot.includes('coilover')) return { category: 'suspension', subcategory: 'coilovers' }
    if (slot.includes('swaybar')) return { category: 'suspension', subcategory: 'swaybars' }
    if (slot.includes('_f')) return { category: 'suspension', subcategory: 'front' }
    if (slot.includes('_r')) return { category: 'suspension', subcategory: 'rear' }
    return { category: 'suspension', subcategory: 'suspension' }
  }

  // BRAKES - etki_brake_F/R, brakepad_F/R, etki_ABS
  if (slot.includes('brake') || slot.includes('brakepad') || slot.includes('abs')) {
    if (slot.includes('abs')) return { category: 'brakes', subcategory: 'abs' }
    if (slot.includes('brakepad')) {
      if (slot.includes('_f')) return { category: 'brakes', subcategory: 'pads_front' }
      if (slot.includes('_r')) return { category: 'brakes', subcategory: 'pads_rear' }
      return { category: 'brakes', subcategory: 'pads' }
    }
    if (slot.includes('_f')) return { category: 'brakes', subcategory: 'front' }
    if (slot.includes('_r')) return { category: 'brakes', subcategory: 'rear' }
    return { category: 'brakes', subcategory: 'brakes' }
  }

  // WHEELS & TIRES - wheel_F/R, tire_F/R, etki_wheeldata_F/R, hubcap
  if (slot.includes('wheel') || slot.includes('tire') || slot.includes('hubcap')) {
    if (slot.includes('tire')) {
      if (slot.includes('_f')) return { category: 'wheels', subcategory: 'tires_front' }
      if (slot.includes('_r')) return { category: 'wheels', subcategory: 'tires_rear' }
      return { category: 'wheels', subcategory: 'tires' }
    }
    if (slot.includes('hubcap')) return { category: 'wheels', subcategory: 'hubcaps' }
    if (slot.includes('wheeldata')) {
      if (slot.includes('_f')) return { category: 'wheels', subcategory: 'wheeldata_front' }
      if (slot.includes('_r')) return { category: 'wheels', subcategory: 'wheeldata_rear' }
      return { category: 'wheels', subcategory: 'wheeldata' }
    }
    // wheel_F_5, wheel_R_5 - actual wheel rims
    if (slot.includes('_f')) return { category: 'wheels', subcategory: 'rims_front' }
    if (slot.includes('_r')) return { category: 'wheels', subcategory: 'rims_rear' }
    return { category: 'wheels', subcategory: 'wheels' }
  }

  // STEERING - etki_steering, etki_steeringbox, etki_steer, etki_power_steering
  if (slot.includes('steer')) {
    if (slot.includes('steeringbox')) return { category: 'steering', subcategory: 'steeringbox' }
    if (slot.includes('power_steering')) return { category: 'steering', subcategory: 'power_steering' }
    if (slot === 'etki_steer') return { category: 'steering', subcategory: 'wheel' }
    return { category: 'steering', subcategory: 'steering' }
  }

  // COOLING - etki_radiator
  if (slot.includes('radiator')) {
    return { category: 'cooling', subcategory: 'radiator' }
  }

  // FUEL - etki_fueltank
  if (slot.includes('fuel')) {
    return { category: 'fuel', subcategory: 'fueltank' }
  }

  // BODY PANELS - etki_body, etki_hood, etki_trunk, etki_door_*, etki_fender_*, etki_glass, etki_windshield, etki_doorglass_*, etki_bumper_*, etki_grille
  if (slot.includes('body') || slot.includes('hood') || slot.includes('trunk') || slot.includes('door') ||
      slot.includes('fender') || slot.includes('windshield') || slot.includes('bumper') || slot.includes('grille') ||
      slot === 'etki_glass') {
    if (slot.includes('body')) return { category: 'body', subcategory: 'body' }
    if (slot.includes('hood')) return { category: 'body', subcategory: 'hood' }
    if (slot.includes('trunk')) return { category: 'body', subcategory: 'trunk' }
    if (slot.includes('doorglass')) return { category: 'body', subcategory: 'door_glass' }
    if (slot.includes('doorpanel')) return { category: 'body', subcategory: 'door_panels' }
    if (slot.includes('door')) return { category: 'body', subcategory: 'doors' }
    if (slot.includes('fender') && !slot.includes('fenderflare')) return { category: 'body', subcategory: 'fenders' }
    if (slot.includes('windshield') || slot === 'etki_glass') return { category: 'body', subcategory: 'glass' }
    if (slot.includes('bumper') && !slot.includes('bumperlight') && !slot.includes('bumperbar')) return { category: 'body', subcategory: 'bumpers' }
    if (slot.includes('bumperbar')) return { category: 'body', subcategory: 'bumper_bars' }
    if (slot.includes('grille')) return { category: 'body', subcategory: 'grille' }
    return { category: 'body', subcategory: 'other' }
  }

  // EXTERIOR - etki_mirror_*, etki_spoiler, etki_window_spoiler, etki_sideskirt, etki_lip_F, etki_fenderflare_*, etki_mudflap_*, etki_skidplate*, etki_towhitch, licenseplate
  if (slot.includes('mirror') || slot.includes('spoiler') || slot.includes('sideskirt') || slot.includes('lip_') ||
      slot.includes('fenderflare') || slot.includes('mudflap') || slot.includes('skidplate') || slot.includes('towhitch') ||
      slot.includes('licenseplate')) {
    if (slot.includes('mirror')) return { category: 'exterior', subcategory: 'mirrors' }
    if (slot.includes('window_spoiler')) return { category: 'exterior', subcategory: 'window_spoiler' }
    if (slot.includes('spoiler')) return { category: 'exterior', subcategory: 'spoilers' }
    if (slot.includes('sideskirt')) return { category: 'exterior', subcategory: 'sideskirts' }
    if (slot.includes('lip_')) return { category: 'exterior', subcategory: 'lips' }
    if (slot.includes('fenderflare')) return { category: 'exterior', subcategory: 'fenderflares' }
    if (slot.includes('mudflap')) return { category: 'exterior', subcategory: 'mudflaps' }
    if (slot.includes('skidplate')) return { category: 'exterior', subcategory: 'skidplates' }
    if (slot.includes('towhitch')) return { category: 'exterior', subcategory: 'towhitch' }
    if (slot.includes('licenseplate')) return { category: 'exterior', subcategory: 'licenseplate' }
    return { category: 'exterior', subcategory: 'other' }
  }

  // LIGHTS - etki_headlight_*, etki_taillight, etki_backlight*, etki_rallylights*, etki_foglight*, etki_bumperlight_*, etki_flashers_*, etki_lipsignal*
  if (slot.includes('light') || slot.includes('flasher') || slot.includes('signal')) {
    if (slot.includes('headlight') && !slot.includes('wiper')) return { category: 'lights', subcategory: 'headlights' }
    if (slot.includes('taillight')) return { category: 'lights', subcategory: 'taillights' }
    if (slot.includes('backlight')) return { category: 'lights', subcategory: 'backlights' }
    if (slot.includes('rally')) return { category: 'lights', subcategory: 'rally_lights' }
    if (slot.includes('fog')) return { category: 'lights', subcategory: 'fog_lights' }
    if (slot.includes('bumperlight')) return { category: 'lights', subcategory: 'bumper_lights' }
    if (slot.includes('flasher')) return { category: 'lights', subcategory: 'flashers' }
    if (slot.includes('signal')) return { category: 'lights', subcategory: 'signals' }
    return { category: 'lights', subcategory: 'other' }
  }

  // INTERIOR - etki_interior, etki_seat_*, etki_seats_R, etki_trim, etki_rally_switches
  if (slot.includes('interior') || slot.includes('seat') || slot.includes('trim') || slot.includes('switches')) {
    if (slot.includes('seat')) return { category: 'interior', subcategory: 'seats' }
    if (slot.includes('trim')) return { category: 'interior', subcategory: 'trim' }
    if (slot.includes('switches')) return { category: 'interior', subcategory: 'switches' }
    return { category: 'interior', subcategory: 'interior' }
  }

  // ROLLCAGE - etki_rollcage, etki_rollcage_lightbar, etki_rollcage_jerrycan, etki_rollcage_load
  if (slot.includes('rollcage')) {
    if (slot.includes('lightbar')) return { category: 'rollcage', subcategory: 'lightbar' }
    if (slot.includes('jerrycan')) return { category: 'rollcage', subcategory: 'accessories' }
    if (slot.includes('load')) return { category: 'rollcage', subcategory: 'accessories' }
    return { category: 'rollcage', subcategory: 'cage' }
  }

  // ROOF - etki_roof_accessory, etki_roof_antenna
  if (slot.includes('roof')) {
    if (slot.includes('antenna')) return { category: 'roof', subcategory: 'antenna' }
    return { category: 'roof', subcategory: 'accessories' }
  }

  // COSMETIC - etki_lettering_*, etki_logo_*, paint_design, skin_*, etki_sunstrip
  if (slot.includes('lettering') || slot.includes('logo') || slot.includes('paint') ||
      slot.includes('skin_') || slot.includes('sunstrip')) {
    if (slot.includes('lettering')) return { category: 'cosmetic', subcategory: 'lettering' }
    if (slot.includes('logo')) return { category: 'cosmetic', subcategory: 'logos' }
    if (slot.includes('paint')) return { category: 'cosmetic', subcategory: 'paint' }
    if (slot.includes('skin_lights')) return { category: 'cosmetic', subcategory: 'light_skins' }
    if (slot.includes('skin_interior')) return { category: 'cosmetic', subcategory: 'interior_skins' }
    if (slot.includes('skin_gauges')) return { category: 'cosmetic', subcategory: 'gauge_skins' }
    if (slot.includes('sunstrip')) return { category: 'cosmetic', subcategory: 'sunstrip' }
    return { category: 'cosmetic', subcategory: 'other' }
  }

  // ELECTRONICS - gps
  if (slot.includes('gps')) {
    return { category: 'electronics', subcategory: 'gps' }
  }

  // MISC - etki_headlightwiper, etki_cut_spare, etki_trunk_load
  if (slot.includes('headlightwiper')) return { category: 'misc', subcategory: 'wipers' }
  if (slot.includes('cut_spare')) return { category: 'misc', subcategory: 'spare' }
  if (slot.includes('trunk_load')) return { category: 'misc', subcategory: 'cargo' }

  return { category: 'other', subcategory: 'other' }
}

// Group parts by category and subcategory
const categorizedParts = computed(() => {
  const categories = {}

  for (const part of parts.value) {
    const { category: categoryKey, subcategory: subcategoryKey } = categorizePart(part)
    const catDef = categoryDefinitions[categoryKey] || categoryDefinitions.other
    const subDef = catDef.subcategories?.[subcategoryKey] || catDef.subcategories?.other || { displayName: 'Other', order: 99 }

    // Initialize category if needed
    if (!categories[categoryKey]) {
      categories[categoryKey] = {
        name: categoryKey,
        displayName: catDef.displayName,
        icon: catDef.icon,
        order: catDef.order,
        subcategories: {},
        totalParts: 0
      }
    }

    // Initialize subcategory if needed
    if (!categories[categoryKey].subcategories[subcategoryKey]) {
      categories[categoryKey].subcategories[subcategoryKey] = {
        name: subcategoryKey,
        displayName: subDef.displayName,
        order: subDef.order,
        parts: []
      }
    }

    categories[categoryKey].subcategories[subcategoryKey].parts.push(part)
    categories[categoryKey].totalParts++
  }

  // Sort parts within each subcategory and convert subcategories to sorted array
  for (const cat of Object.values(categories)) {
    const subcatArray = Object.values(cat.subcategories)
    for (const subcat of subcatArray) {
      subcat.parts.sort((a, b) => a.niceName.localeCompare(b.niceName))
    }
    cat.subcategories = subcatArray.sort((a, b) => a.order - b.order)
  }

  // Convert to array and sort by order
  return Object.values(categories).sort((a, b) => a.order - b.order)
})

// Filter categories based on search
const filteredCategories = computed(() => {
  if (!searchQuery.value) {
    return categorizedParts.value
  }

  const query = searchQuery.value.toLowerCase()
  const filtered = []

  for (const category of categorizedParts.value) {
    const filteredSubcategories = []
    let categoryTotalParts = 0

    for (const subcategory of category.subcategories) {
      const matchingParts = subcategory.parts.filter(p => {
        const niceName = (typeof p.niceName === 'string' ? p.niceName : '').toLowerCase()
        const name = (typeof p.name === 'string' ? p.name : '').toLowerCase()
        const slotType = (typeof p.slotType === 'string' ? p.slotType : '').toLowerCase()
        return niceName.includes(query) || name.includes(query) || slotType.includes(query)
      })
      if (matchingParts.length > 0) {
        filteredSubcategories.push({
          ...subcategory,
          parts: matchingParts
        })
        categoryTotalParts += matchingParts.length
      }
    }

    if (filteredSubcategories.length > 0) {
      filtered.push({
        ...category,
        subcategories: filteredSubcategories,
        totalParts: categoryTotalParts
      })
    }
  }

  return filtered
})

// Cart total
const cartTotal = computed(() => {
  return cart.value.reduce((sum, item) => sum + (item.shopPrice * item.quantity), 0)
})

// Cart item count (with quantities)
const cartItemCount = computed(() => {
  return cart.value.reduce((sum, item) => sum + item.quantity, 0)
})

// Format number with commas
const formatNumber = (num) => {
  return Math.round(num).toLocaleString()
}

// Format slot type for display
const formatSlotType = (slot) => {
  if (!slot || typeof slot !== 'string') return ''
  return slot
    .replace(/^etki_/, '')
    .replace(/_/g, ' ')
    .replace(/\b\w/g, l => l.toUpperCase())
}

// Toggle category expansion
const toggleCategory = (categoryName) => {
  expandedCategories[categoryName] = !expandedCategories[categoryName]
}

// Toggle subcategory expansion
const toggleSubcategory = (categoryName, subcategoryName) => {
  const key = `${categoryName}_${subcategoryName}`
  expandedSubcategories[key] = !expandedSubcategories[key]
}

// Check if subcategory is expanded
const isSubcategoryExpanded = (categoryName, subcategoryName) => {
  const key = `${categoryName}_${subcategoryName}`
  return expandedSubcategories[key]
}

// Check if part is in cart
const isInCart = (partName) => {
  return cart.value.some(item => item.name === partName)
}

// Add part to cart
const addToCart = (part) => {
  const existing = cart.value.find(item => item.name === part.name)
  if (existing) {
    existing.quantity++
  } else {
    cart.value.push({ ...part, quantity: 1 })
  }
}

// Remove part from cart
const removeFromCart = (partName) => {
  const index = cart.value.findIndex(item => item.name === partName)
  if (index !== -1) {
    if (cart.value[index].quantity > 1) {
      cart.value[index].quantity--
    } else {
      cart.value.splice(index, 1)
    }
  }
}

// Clear cart
const clearCart = () => {
  cart.value = []
}

// Go back to internet browser
const goBack = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('guihooks.trigger("ChangeState", { state = "mysummer-internet" })')
  }
}

// Checkout - place order
const checkout = async () => {
  if (cart.value.length === 0 || purchasing.value) return

  purchasing.value = true

  try {
    // Send order to Lua
    const orderItems = cart.value.map(item => ({
      name: item.name,
      niceName: item.niceName,
      slotType: item.slotType,
      quantity: item.quantity,
      price: item.shopPrice
    }))

    const orderData = JSON.stringify(orderItems).replace(/"/g, '\\"')

    if (window.bngApi) {
      window.bngApi.engineLua(`career_modules_mysummerPartShops.placeOnlineOrder("${orderData}")`, (result) => {
        if (result && result.success) {
          orderSuccess.value = true
          updatePlayerFunds()
        } else {
          console.error('Order failed:', result)
        }
        purchasing.value = false
      })
    }
  } catch (err) {
    console.error('Checkout error:', err)
    purchasing.value = false
  }
}

// Update player funds
const updatePlayerFunds = async () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_playerAttributes.getAttributeValue("money")', (result) => {
      playerFunds.value = result || 0
    })
  }
}

// Load parts catalog
const loadParts = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.getOnlineShopParts()', (result) => {
      if (result && Array.isArray(result)) {
        parts.value = result
        // Expand first category by default
        if (categorizedParts.value.length > 0) {
          expandedCategories[categorizedParts.value[0].name] = true
        }
      }
    })
  }
}

onMounted(() => {
  loadParts()
  updatePlayerFunds()
})
</script>

<style scoped lang="scss">
// ============================================
// RETRO INTERNET BROWSER STYLE
// Official parts store - cleaner but still retro
// ============================================

$terminal-green: #00ff41;
$terminal-amber: #ffb000;
$terminal-cyan: #00ffff;
$terminal-red: #ff3333;
$bg-dark: #0a0a0a;
$bg-panel: #111111;
$border-color: #333333;

.online-shop {
  display: flex;
  flex-direction: column;
  height: 100%;
  background: $bg-dark;
  color: $terminal-green;
  font-family: "Courier New", Courier, monospace;
  font-size: 13px;
}

.shop-header {
  display: flex;
  align-items: center;
  gap: 1rem;
  padding: 0.5rem 0.75rem;
  background: linear-gradient(180deg, #1a1a1a 0%, #0d0d0d 100%);
  border: 1px solid $border-color;
  border-bottom: 2px solid #444;

  .back-btn {
    padding: 0.3rem 0.6rem;
    background: $bg-panel;
    border: 1px solid $border-color;
    color: $terminal-amber;
    font-family: inherit;
    font-size: 11px;
    cursor: pointer;

    &:hover {
      background: #222;
      border-color: $terminal-amber;
    }
  }

  .shop-title {
    flex: 1;

    h2 {
      margin: 0;
      font-size: 14px;
      font-weight: normal;
      color: $terminal-cyan;
      text-shadow: 0 0 10px rgba(0, 255, 255, 0.4);

      &::before {
        content: ">> ";
        color: $terminal-green;
      }
    }

    .tagline {
      margin: 0;
      font-size: 10px;
      color: #555;
    }
  }

  .header-right {
    .player-funds {
      display: flex;
      gap: 0.5rem;
      font-size: 12px;

      .label {
        color: #666;
      }

      .amount {
        color: $terminal-green;
        font-weight: bold;
        text-shadow: 0 0 8px rgba(0, 255, 65, 0.4);
      }
    }
  }
}

.shop-body {
  display: flex;
  flex: 1;
  overflow: hidden;
}

.catalog-panel {
  flex: 2;
  display: flex;
  flex-direction: column;
  border-right: 1px solid $border-color;
}

.filter-bar {
  padding: 0.5rem;
  background: $bg-panel;
  border-bottom: 1px solid $border-color;

  .search-input {
    width: 100%;
    padding: 0.4rem 0.6rem;
    background: #000;
    border: 1px inset #333;
    color: $terminal-green;
    font-family: inherit;
    font-size: 12px;

    &::placeholder {
      color: #444;
    }

    &:focus {
      outline: none;
      border-color: $terminal-cyan;
      box-shadow: 0 0 5px rgba(0, 255, 255, 0.3);
    }
  }
}

.categories-list {
  flex: 1;
  overflow-y: auto;
  padding: 0.3rem;
  background: #000;
}

.categories-list::-webkit-scrollbar {
  width: 12px;
  background: #111;
}

.categories-list::-webkit-scrollbar-thumb {
  background: linear-gradient(180deg, #444 0%, #222 100%);
  border: 1px solid #555;
}

.category-section {
  margin-bottom: 2px;
  background: rgba(0, 255, 255, 0.02);
  border: 1px solid $border-color;
}

.category-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0.6rem;
  cursor: pointer;
  border-bottom: 1px solid transparent;

  &:hover {
    background: rgba(0, 255, 255, 0.05);
  }

  &.expanded {
    background: rgba(0, 255, 255, 0.08);
    border-bottom-color: #333;
  }

  .expand-icon {
    color: $terminal-cyan;
    font-size: 11px;
    min-width: 24px;
  }

  .category-name {
    flex: 1;
    font-weight: bold;
    color: $terminal-cyan;
    letter-spacing: 1px;
  }

  .category-count {
    color: #555;
    font-size: 10px;
  }
}

.subcategories-container {
  padding-left: 1rem;
  border-left: 1px dashed #333;
  margin-left: 0.5rem;
}

.subcategory-section {
  margin-bottom: 1px;
}

.subcategory-header {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.35rem 0.5rem;
  cursor: pointer;
  background: rgba(0, 255, 65, 0.02);

  &:hover {
    background: rgba(0, 255, 65, 0.08);
  }

  &.expanded {
    background: rgba(0, 255, 65, 0.1);
  }

  .expand-icon {
    color: $terminal-green;
    font-size: 10px;
    min-width: 20px;
  }

  .subcategory-name {
    flex: 1;
    font-size: 11px;
    color: #aaa;
  }

  .subcategory-count {
    color: #555;
    font-size: 10px;
  }
}

.subcategory-parts {
  padding: 0.2rem 0 0.2rem 0.5rem;
  border-left: 1px dotted #333;
  margin-left: 0.5rem;
}

.part-item {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.35rem 0.5rem;
  margin-bottom: 1px;
  background: rgba(0, 255, 65, 0.02);
  cursor: pointer;

  &:nth-child(odd) {
    background: rgba(0, 255, 65, 0.04);
  }

  &:hover {
    background: rgba(0, 255, 65, 0.1);
  }

  &.in-cart {
    background: rgba(255, 176, 0, 0.1);
    border-left: 2px solid $terminal-amber;

    .add-icon {
      color: $terminal-amber;
    }
  }

  .part-info {
    flex: 1;
    min-width: 0;

    .part-name {
      display: block;
      font-size: 11px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      color: #ccc;
    }

    .part-slot {
      font-size: 9px;
      color: #555;
    }
  }

  .part-price {
    color: $terminal-cyan;
    font-weight: bold;
    font-size: 11px;
  }

  .add-icon {
    color: $terminal-green;
    font-size: 10px;
    min-width: 35px;
    text-align: right;
  }
}

.no-parts {
  padding: 2rem;
  text-align: center;
  color: #555;
}

.cart-panel {
  flex: 1;
  display: flex;
  flex-direction: column;
  min-width: 250px;
  max-width: 280px;
  background: $bg-panel;
  border-left: 1px solid $border-color;
}

.cart-header {
  display: flex;
  align-items: center;
  gap: 0.5rem;
  padding: 0.5rem 0.75rem;
  background: linear-gradient(180deg, #1a1a1a 0%, #111 100%);
  border-bottom: 1px solid $border-color;

  h3 {
    margin: 0;
    flex: 1;
    font-size: 12px;
    font-weight: normal;
    color: $terminal-amber;
  }

  .cart-count {
    color: $terminal-amber;
    font-size: 11px;
  }
}

.cart-items {
  flex: 1;
  overflow-y: auto;
  padding: 0.3rem;
  background: #000;
}

.cart-items::-webkit-scrollbar {
  width: 10px;
  background: #111;
}

.cart-items::-webkit-scrollbar-thumb {
  background: #333;
  border: 1px solid #444;
}

.empty-cart {
  padding: 2rem;
  text-align: center;
  color: #444;
  font-size: 11px;
}

.cart-item {
  display: flex;
  align-items: center;
  gap: 0.4rem;
  padding: 0.35rem 0.5rem;
  margin-bottom: 1px;
  background: rgba(255, 176, 0, 0.05);

  .item-info {
    flex: 1;
    min-width: 0;

    .item-name {
      display: block;
      font-size: 10px;
      white-space: nowrap;
      overflow: hidden;
      text-overflow: ellipsis;
      color: #aaa;
    }

    .item-qty {
      font-size: 9px;
      color: $terminal-amber;
    }
  }

  .item-price {
    color: $terminal-cyan;
    font-size: 10px;
  }

  .remove-btn {
    padding: 0.1rem 0.3rem;
    background: transparent;
    border: 1px solid #333;
    color: #666;
    font-family: inherit;
    font-size: 9px;
    cursor: pointer;

    &:hover {
      border-color: $terminal-red;
      color: $terminal-red;
    }
  }
}

.cart-footer {
  padding: 0.5rem;
  border-top: 1px solid $border-color;
  background: $bg-panel;

  .cart-total {
    display: flex;
    justify-content: space-between;
    margin-bottom: 0.5rem;
    font-size: 12px;
    padding: 0.3rem;
    background: #000;
    border: 1px solid $border-color;

    .total-label {
      color: #888;
    }

    .total-amount {
      color: $terminal-green;
      font-weight: bold;
      text-shadow: 0 0 8px rgba(0, 255, 65, 0.4);
    }
  }

  .delivery-info {
    margin-bottom: 0.5rem;
    padding: 0.3rem 0.5rem;
    background: rgba(0, 255, 255, 0.05);
    border: 1px dashed #333;
    font-size: 10px;
    color: #888;
  }

  .checkout-btn {
    width: 100%;
    padding: 0.5rem;
    background: #002200;
    border: 1px solid $terminal-green;
    color: $terminal-green;
    font-family: inherit;
    font-size: 11px;
    cursor: pointer;
    text-transform: uppercase;

    &:hover:not(:disabled) {
      background: $terminal-green;
      color: #000;
    }

    &:disabled {
      background: #111;
      border-color: #333;
      color: #444;
      cursor: not-allowed;
    }
  }

  .clear-btn {
    width: 100%;
    margin-top: 0.3rem;
    padding: 0.3rem;
    background: transparent;
    border: 1px solid #333;
    color: #666;
    font-family: inherit;
    font-size: 10px;
    cursor: pointer;

    &:hover {
      border-color: $terminal-red;
      color: $terminal-red;
    }
  }
}

.order-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.9);
  z-index: 1000;

  .modal-content {
    padding: 1.5rem 2rem;
    background: $bg-panel;
    border: 2px solid $terminal-green;
    text-align: center;
    max-width: 350px;

    .success-icon {
      font-size: 32px;
      color: $terminal-green;
      text-shadow: 0 0 20px rgba(0, 255, 65, 0.6);
      margin-bottom: 0.5rem;
    }

    h2 {
      margin: 0.5rem 0;
      font-size: 16px;
      font-weight: normal;
      color: $terminal-green;
      letter-spacing: 2px;
    }

    p {
      color: #888;
      margin: 0.3rem 0;
      font-size: 11px;
    }

    .order-details {
      color: $terminal-cyan;
      font-weight: bold;
      margin-top: 0.5rem;
    }

    .modal-btn {
      margin-top: 1rem;
      padding: 0.5rem 1.5rem;
      background: #002200;
      border: 1px solid $terminal-green;
      color: $terminal-green;
      font-family: inherit;
      font-size: 11px;
      cursor: pointer;

      &:hover {
        background: $terminal-green;
        color: #000;
      }
    }
  }
}
</style>
