<template>
  <div class="speedparts-page">
    <!-- Header -->
    <div class="site-header">
      <div class="header-main">
        <div class="logo">
          <span class="logo-speed">SPEED</span>
          <span class="logo-parts">PARTS</span>
          <span class="logo-dot">.com</span>
        </div>
        <div class="header-search">
          <input
            type="text"
            v-model="searchQuery"
            placeholder="Search 500,000+ parts..."
            class="search-input"
          />
          <button class="search-btn">SEARCH</button>
        </div>
        <div class="header-cart" @click="showCart = !showCart">
          <span class="cart-icon">[CART]</span>
          <span class="cart-count" v-if="cart.length > 0">{{ cartItemCount }}</span>
        </div>
      </div>
      <div class="header-nav">
        <span class="nav-item">HOME</span>
        <span class="nav-item active">CAR PARTS</span>
        <span class="nav-item">PERFORMANCE</span>
        <span class="nav-item">TOOLS</span>
        <span class="nav-item">DEALS</span>
        <span class="nav-item" @click="showOrders = !showOrders" :class="{ highlight: hasOrders }">
          MY ORDERS
          <span v-if="hasOrders" class="orders-badge">{{ totalOrderCount }}</span>
        </span>
        <span class="nav-item">HELP</span>
      </div>
      <div class="promo-bar">
        *** FREE SHIPPING on orders over $500! *** Use code SPEED10 for 10% off! ***
      </div>
    </div>

    <!-- Main Content -->
    <div class="main-content">
      <!-- Sidebar with categories -->
      <div class="sidebar">
        <div class="vehicle-selector">
          <h4>Your Vehicle</h4>
          <div class="vehicle-display">
            <span class="vehicle-icon">[CAR]</span>
            <div class="vehicle-info">
              <span class="vehicle-name">ETK I-Series</span>
              <span class="vehicle-year">2400Ti TT Sport</span>
            </div>
          </div>
        </div>

        <div class="categories-box">
          <h4>Categories</h4>
          <div class="categories-tree">
            <div
              v-for="category in filteredCategories"
              :key="category.name"
              class="category-section"
            >
              <!-- Category Header -->
              <div
                class="category-header"
                :class="{ expanded: expandedCategories[category.name] }"
                @click="toggleCategory(category.name)"
              >
                <span class="expand-icon">{{ expandedCategories[category.name] ? '[-]' : '[+]' }}</span>
                <span class="category-name">{{ category.displayName }}</span>
                <span class="category-count">({{ countNodeParts(category) }})</span>
              </div>

              <!-- Level 1: Direct children of category -->
              <div v-if="expandedCategories[category.name]" class="subcategories-container">
                <template v-for="child1 in category.children" :key="child1.name">
                  <!-- Node with children (expandable) -->
                  <template v-if="child1.children && child1.children.length > 0">
                    <div
                      class="subcategory-item expandable"
                      :class="{
                        expanded: isNodeExpanded(`${category.name}:::${child1.name}`),
                        active: selectedSubcategory === `${category.name}:::${child1.name}`
                      }"
                    >
                      <span
                        class="subcat-expand"
                        @click.stop="toggleNode(`${category.name}:::${child1.name}`)"
                      >{{ isNodeExpanded(`${category.name}:::${child1.name}`) ? '[-]' : '[+]' }}</span>
                      <span
                        class="subcat-name clickable"
                        @click="selectNode(`${category.name}:::${child1.name}`)"
                      >{{ child1.displayName }}</span>
                      <span class="subcat-count">({{ countNodeParts(child1) }})</span>
                    </div>

                    <!-- Level 2: Children of child1 -->
                    <div v-if="isNodeExpanded(`${category.name}:::${child1.name}`)" class="nested-container level-2">
                      <template v-for="child2 in child1.children" :key="child2.name">
                        <!-- Node with children (expandable) -->
                        <template v-if="child2.children && child2.children.length > 0">
                          <div
                            class="subcategory-item expandable"
                            :class="{
                              expanded: isNodeExpanded(`${category.name}:::${child1.name}:::${child2.name}`),
                              active: selectedSubcategory === `${category.name}:::${child1.name}:::${child2.name}`
                            }"
                          >
                            <span
                              class="subcat-expand"
                              @click.stop="toggleNode(`${category.name}:::${child1.name}:::${child2.name}`)"
                            >{{ isNodeExpanded(`${category.name}:::${child1.name}:::${child2.name}`) ? '[-]' : '[+]' }}</span>
                            <span
                              class="subcat-name clickable"
                              @click="selectNode(`${category.name}:::${child1.name}:::${child2.name}`)"
                            >{{ child2.displayName }}</span>
                            <span class="subcat-count">({{ countNodeParts(child2) }})</span>
                          </div>

                          <!-- Level 3: Children of child2 (leaf nodes - sizes) -->
                          <div v-if="isNodeExpanded(`${category.name}:::${child1.name}:::${child2.name}`)" class="nested-container level-3">
                            <div
                              v-for="child3 in child2.children"
                              :key="child3.name"
                              class="subcategory-item leaf"
                              :class="{ active: selectedSubcategory === `${category.name}:::${child1.name}:::${child2.name}:::${child3.name}` }"
                              @click="selectNode(`${category.name}:::${child1.name}:::${child2.name}:::${child3.name}`)"
                            >
                              <span class="subcat-bullet">•</span>
                              <span class="subcat-name">{{ child3.displayName }}</span>
                              <span class="subcat-count">({{ countNodeParts(child3) }})</span>
                            </div>
                          </div>
                        </template>

                        <!-- Leaf node at level 2 -->
                        <template v-else>
                          <div
                            class="subcategory-item leaf"
                            :class="{ active: selectedSubcategory === `${category.name}:::${child1.name}:::${child2.name}` }"
                            @click="selectNode(`${category.name}:::${child1.name}:::${child2.name}`)"
                          >
                            <span class="subcat-bullet">•</span>
                            <span class="subcat-name">{{ child2.displayName }}</span>
                            <span class="subcat-count">({{ countNodeParts(child2) }})</span>
                          </div>
                        </template>
                      </template>
                    </div>
                  </template>

                  <!-- Leaf node at level 1 -->
                  <template v-else>
                    <div
                      class="subcategory-item leaf"
                      :class="{ active: selectedSubcategory === `${category.name}:::${child1.name}` }"
                      @click="selectNode(`${category.name}:::${child1.name}`)"
                    >
                      <span class="subcat-bullet">></span>
                      <span class="subcat-name">{{ child1.displayName }}</span>
                      <span class="subcat-count">({{ countNodeParts(child1) }})</span>
                    </div>
                  </template>
                </template>
              </div>
            </div>
          </div>
        </div>

        <div class="info-box">
          <h4>Why SpeedParts?</h4>
          <ul class="benefits-list">
            <li>OEM Quality Parts</li>
            <li>24hr Express Delivery</li>
            <li>30-Day Returns</li>
            <li>Expert Support</li>
          </ul>
        </div>
      </div>

      <!-- Products -->
      <div class="products-area">
        <div class="products-header">
          <h2>{{ currentCategoryName }}</h2>
          <span class="products-count">{{ displayedParts.length }} products</span>
          <div class="sort-options">
            <label>Sort:</label>
            <select v-model="sortBy">
              <option value="name">Name A-Z</option>
              <option value="price-asc">Price: Low to High</option>
              <option value="price-desc">Price: High to Low</option>
            </select>
          </div>
        </div>

        <div v-if="loading" class="loading-indicator">
          Loading parts catalog...
        </div>

        <div v-else-if="displayedParts.length === 0" class="no-products">
          <p>No parts found. Try a different search or category.</p>
        </div>

        <div v-else class="products-grid">
          <div
            v-for="part in displayedParts"
            :key="part.name"
            class="product-card"
            :class="{ 'out-of-stock': !part.inStock && !part.locked, 'part-locked': part.locked }"
          >
            <div class="product-image">
              <div class="no-image">
                <span>[PART]</span>
              </div>
              <div class="product-badge new" v-if="part.inStock && !part.locked && part.shopPrice > 2000">PRO</div>
              <div class="product-badge sold" v-if="!part.inStock && !part.locked">SOLD</div>
              <div class="product-badge locked" v-if="part.locked">CH.{{ part.requiredChapter }}</div>
            </div>

            <div class="product-info">
              <h3 class="product-name">{{ part.niceName }}</h3>
              <div class="product-sku">{{ formatSlotType(part.slotType) }}</div>
              <div v-if="part.locked" class="product-stock locked-label">
                <span class="stock-dot locked"></span>
                Requires Chapter {{ part.requiredChapter }}
              </div>
              <div v-else-if="part.inStock" class="product-stock in-stock">
                <span class="stock-dot"></span>
                In Stock - Ships Today!
              </div>
              <div v-else class="product-stock out-of-stock-label">
                <span class="stock-dot out"></span>
                {{ part.owned ? 'You own this' : (part.pending ? 'On order' : 'Out of Stock') }}
              </div>
            </div>

            <div class="product-pricing">
              <div class="price-row">
                <span class="price-label">List Price:</span>
                <span class="price-msrp">${{ formatPrice(part.shopPrice * 1.25) }}</span>
              </div>
              <div class="price-row our-price">
                <span class="price-label">Our Price:</span>
                <span class="price-value">${{ formatPrice(part.shopPrice) }}</span>
              </div>
              <div class="savings">You Save: ${{ formatPrice(part.shopPrice * 0.25) }} (20%)</div>
            </div>

            <div class="product-actions">
              <template v-if="part.locked">
                <button class="add-to-cart-btn locked-btn" disabled>
                  LOCKED - CH.{{ part.requiredChapter }}
                </button>
              </template>
              <template v-else-if="part.inStock">
                <div class="qty-selector">
                  <label>Qty:</label>
                  <select class="qty-select" v-model="partQuantities[part.name]" disabled>
                    <option :value="1">1</option>
                  </select>
                </div>
                <button
                  class="add-to-cart-btn"
                  :class="{ 'in-cart': isInCart(part.name) }"
                  @click="addToCart(part)"
                  :disabled="isInCart(part.name)"
                >
                  {{ isInCart(part.name) ? 'IN CART' : 'ADD TO CART' }}
                </button>
              </template>
              <template v-else>
                <button class="add-to-cart-btn sold-out" disabled>
                  NOT AVAILABLE
                </button>
              </template>
            </div>
          </div>
        </div>
      </div>

      <!-- Cart Panel -->
      <div class="cart-panel" :class="{ open: showCart }">
        <div class="cart-header">
          <h3>Shopping Cart</h3>
          <button class="close-cart" @click="showCart = false">X</button>
        </div>

        <div v-if="cart.length === 0" class="cart-empty">
          <span class="empty-icon">[CART]</span>
          <p>Your cart is empty</p>
          <p class="empty-sub">Add some parts to get started!</p>
        </div>

        <div v-else class="cart-content">
          <div class="cart-items">
            <div v-for="(item, idx) in cart" :key="idx" class="cart-item" :class="{ 'child-part': item.isChildPart }">
              <div class="item-image">{{ item.isChildPart ? '[+]' : '[P]' }}</div>
              <div class="item-details">
                <span class="item-name">{{ item.niceName }}</span>
                <span class="item-qty">Qty: {{ item.quantity }}</span>
                <span v-if="item.isChildPart" class="item-required">(Required)</span>
              </div>
              <div class="item-price">${{ formatPrice(item.shopPrice * item.quantity) }}</div>
              <button v-if="!item.isChildPart" class="item-remove" @click="removeFromCart(item.name)">X</button>
            </div>
          </div>

          <div class="cart-summary">
            <div class="summary-row">
              <span>Subtotal:</span>
              <span>${{ formatPrice(cartTotal) }}</span>
            </div>
            <div class="summary-row">
              <span>Shipping:</span>
              <span class="free-ship">{{ cartTotal >= 500 ? 'FREE' : '$25.00' }}</span>
            </div>
            <div class="summary-row total">
              <span>Total:</span>
              <span>${{ formatPrice(cartTotal + (cartTotal >= 500 ? 0 : 25)) }}</span>
            </div>
          </div>

          <button class="checkout-btn" @click="checkout" :disabled="checkingOut">
            {{ checkingOut ? 'Processing...' : 'PROCEED TO CHECKOUT' }}
          </button>

          <div v-if="orderError" class="order-error">
            <span class="error-icon">[!]</span>
            {{ orderError }}
          </div>

          <button class="clear-cart-btn" @click="clearCart">CLEAR CART</button>

          <div class="secure-badge">
            <span>[LOCK]</span> Secure Checkout - 256-bit SSL
          </div>
        </div>
      </div>

      <!-- Orders Panel -->
      <div class="orders-panel" :class="{ open: showOrders }">
        <div class="orders-header">
          <h3>My Orders</h3>
          <button class="close-orders" @click="showOrders = false">X</button>
        </div>

        <div v-if="!hasOrders" class="orders-empty">
          <span class="empty-icon">[BOX]</span>
          <p>No pending orders</p>
          <p class="empty-sub">Your orders will appear here</p>
        </div>

        <div v-else class="orders-content">
          <!-- Parts waiting at port -->
          <div v-if="pendingOrders.totalPendingCount > 0" class="order-section">
            <div class="section-header pickup">
              <span class="section-icon">[PORT]</span>
              <div class="section-info">
                <span class="section-title">Waiting at Port</span>
                <span class="section-subtitle">{{ pendingOrders.totalPendingCount }} parts ready for pickup</span>
              </div>
            </div>
            <div class="order-items">
              <div v-for="(part, idx) in pendingOrders.pendingPickup" :key="'pending-' + idx" class="order-item">
                <span class="order-item-name">{{ part.niceName || part.name }}</span>
                <span class="order-item-price">${{ formatPrice(part.price) }}</span>
                <button class="order-item-cancel" @click="cancelOrder(idx + 1)" title="Cancel & Refund">X</button>
              </div>
            </div>
            <div class="order-buttons">
              <button class="waypoint-btn" @click="setWaypointToPickup">
                [GPS] SET WAYPOINT TO PORT
              </button>
              <button class="cancel-all-btn" @click="cancelAllOrders">
                CANCEL ALL (REFUND)
              </button>
            </div>
          </div>

          <!-- Parts in cargo (being transported) -->
          <div v-if="pendingOrders.totalCarryingCount > 0" class="order-section">
            <div class="section-header carrying">
              <span class="section-icon">[TRUCK]</span>
              <div class="section-info">
                <span class="section-title">In Your Cargo</span>
                <span class="section-subtitle">{{ pendingOrders.totalCarryingCount }} parts - deliver to garage</span>
              </div>
            </div>
            <div class="order-items">
              <div v-for="(part, idx) in pendingOrders.carrying" :key="'carrying-' + idx" class="order-item">
                <span class="order-item-name">{{ part.niceName || part.name }}</span>
                <span class="order-item-price">${{ formatPrice(part.price) }}</span>
              </div>
            </div>
            <button class="waypoint-btn delivery" @click="setWaypointToDelivery">
              [GPS] SET WAYPOINT TO GARAGE
            </button>
          </div>
        </div>
      </div>
    </div>

    <!-- Order Success Modal -->
    <div v-if="orderSuccess" class="order-modal" @click="orderSuccess = false">
      <div class="modal-content" @click.stop>
        <div class="success-icon">[OK]</div>
        <h2>Order Confirmed!</h2>
        <p>Your parts will be available for pickup at the PORT.</p>
        <button class="modal-btn" @click="orderSuccess = false; clearCart()">
          CONTINUE SHOPPING
        </button>
      </div>
    </div>

    <!-- Footer -->
    <div class="site-footer">
      <div class="footer-bottom">
        <p>2005 SpeedParts.com - Your #1 Source for Auto Parts</p>
      </div>
    </div>
  </div>
</template>

<script setup>
import { ref, computed, onMounted, reactive } from "vue"

const emit = defineEmits(["navigate"])

const parts = ref([])
const loading = ref(true)
const searchQuery = ref("")
const sortBy = ref("name")
const showCart = ref(false)
const showOrders = ref(false)
const cart = ref([])
const checkingOut = ref(false)
const orderSuccess = ref(false)
const orderError = ref("")
const expandedCategories = reactive({})
const expandedNodes = reactive({}) // Track expanded state for hierarchical nodes: "wheels:::rims" -> true
const selectedSubcategory = ref(null)
const partQuantities = reactive({})
const pendingOrders = ref({
  pendingPickup: [],
  carrying: [],
  totalPendingCount: 0,
  totalCarryingCount: 0,
})

const hasOrders = computed(() => pendingOrders.value.totalPendingCount > 0 || pendingOrders.value.totalCarryingCount > 0)
const totalOrderCount = computed(() => pendingOrders.value.totalPendingCount + pendingOrders.value.totalCarryingCount)

// Category and subcategory definitions - based on real ETK-I slotTypes
const categoryDefinitions = {
  engine: {
    displayName: 'Engine',
    order: 1,
    subcategories: {
      engine: { displayName: 'Engine', order: 1 },
      internals: { displayName: 'Internals', order: 2 },
      intake: { displayName: 'Intake', order: 3 },
      ecu: { displayName: 'ECU', order: 4 },
      mounts: { displayName: 'Engine Mounts', order: 5 },
      oilpan: { displayName: 'Oil Pan', order: 6 },
      oilcooler: { displayName: 'Oil Cooler', order: 7 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  drivetrain: {
    displayName: 'Drivetrain',
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
    order: 3,
    subcategories: {
      exhaust: { displayName: 'Exhaust System', order: 1 },
      converter: { displayName: 'Catalytic Converter', order: 2 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  suspension: {
    displayName: 'Suspension',
    order: 4,
    subcategories: {
      front: { displayName: 'Front', order: 1 },
      rear: { displayName: 'Rear', order: 2 },
      struts: { displayName: 'Struts', order: 3 },
      coilovers: { displayName: 'Coilovers', order: 4 },
      swaybars: { displayName: 'Sway Bars', order: 5 },
      strut_bar: { displayName: 'Strut Bar', order: 6 },
      spindles_front: { displayName: 'Front Spindles', order: 7 },
      spindles_rear: { displayName: 'Rear Spindles', order: 8 },
      spindles: { displayName: 'Spindles', order: 9 },
      suspension: { displayName: 'General', order: 10 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  brakes: {
    displayName: 'Brakes',
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
    order: 7,
    subcategories: {
      rims_front: { displayName: 'Front Rims', order: 1 },
      rims_rear: { displayName: 'Rear Rims', order: 2 },
      // Tires are dynamically generated: tires_front_15, tires_front_16, tires_rear_15, etc.
      tires_front: { displayName: 'Front Tires', order: 100 },
      tires_rear: { displayName: 'Rear Tires', order: 200 },
      tires: { displayName: 'Tires', order: 300 },
      hubcaps_front: { displayName: 'Front Hubcaps', order: 400 },
      hubcaps_rear: { displayName: 'Rear Hubcaps', order: 401 },
      hubcaps: { displayName: 'Hubcaps', order: 402 },
      wheels: { displayName: 'General', order: 500 },
      other: { displayName: 'Other', order: 999 },
    }
  },
  body: {
    displayName: 'Body',
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
    order: 13,
    subcategories: {
      accessories: { displayName: 'Accessories', order: 1 },
      antenna: { displayName: 'Antenna', order: 2 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  cooling: {
    displayName: 'Cooling',
    order: 14,
    subcategories: {
      radiator: { displayName: 'Radiator', order: 1 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  fuel: {
    displayName: 'Fuel',
    order: 15,
    subcategories: {
      fueltank: { displayName: 'Fuel Tank', order: 1 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  cosmetic: {
    displayName: 'Cosmetic',
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
    order: 17,
    subcategories: {
      gps: { displayName: 'GPS', order: 1 },
      gauges: { displayName: 'Gauges', order: 2 },
      other: { displayName: 'Other', order: 99 },
    }
  },
  misc: {
    displayName: 'Miscellaneous',
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
    order: 99,
    subcategories: {
      other: { displayName: 'Uncategorized', order: 99 },
    }
  },
}

// Helper to check front/rear patterns
// Matches: _F_ or _F at end (case insensitive)
// Examples: tire_F_15x7, wheel_F_5, etki_wheeldata_F, brakepad_F
const isFrontPart = (slot) => /_f_/i.test(slot) || /_f$/i.test(slot)
const isRearPart = (slot) => /_r_/i.test(slot) || /_r$/i.test(slot)

// Categorize a part based on its slotType
const categorizePart = (part) => {
  const slot = typeof part.slotType === 'string' ? part.slotType : ''
  const slotLower = slot.toLowerCase()

  // WHEELDATA/SPINDLES → go to SUSPENSION
  if (slotLower.includes('wheeldata')) {
    if (isFrontPart(slot)) return { category: 'suspension', subcategory: 'spindles_front' }
    if (isRearPart(slot)) return { category: 'suspension', subcategory: 'spindles_rear' }
    return { category: 'suspension', subcategory: 'spindles' }
  }

  // TIRES - 4-level hierarchy: wheels > tires > front/rear > size
  // SlotTypes: tire_F_15x7, tire_R_17x8
  if (/^tire_[fr]_/i.test(slot)) {
    const sizeMatch = slot.match(/(\d+)x\d+/)
    const rimSize = sizeMatch ? sizeMatch[1] : null
    const position = isFrontPart(slot) ? 'front' : (isRearPart(slot) ? 'rear' : '')

    if (rimSize && position) {
      // Format: tires::front::15 or tires::rear::17
      return { category: 'wheels', subcategory: `tires::${position}::${rimSize}` }
    }
    if (position) return { category: 'wheels', subcategory: `tires::${position}` }
    return { category: 'wheels', subcategory: 'tires' }
  }

  // WHEELS/RIMS - 4-level hierarchy: wheels > rims > front/rear > size
  // SlotTypes: wheel_F_5, wheel_R_5
  // Part names like: wheel_19a_15x7_F, etk_wheel_07a_16x7_R
  if (/^wheel_[fr]_/i.test(slot)) {
    const position = isFrontPart(slot) ? 'front' : (isRearPart(slot) ? 'rear' : '')
    // Try to extract rim size from part name
    const partName = (part.name || '').toLowerCase()
    const sizeMatch = partName.match(/(\d+)x\d+/)
    const rimSize = sizeMatch ? sizeMatch[1] : null

    if (rimSize && position) {
      return { category: 'wheels', subcategory: `rims::${position}::${rimSize}` }
    }
    if (position) return { category: 'wheels', subcategory: `rims::${position}` }
    return { category: 'wheels', subcategory: 'rims' }
  }

  // HUBCAPS: hubcap_F_xxx, hubcap_R_xxx
  if (/^hubcap_/i.test(slot)) {
    const position = isFrontPart(slot) ? 'front' : (isRearPart(slot) ? 'rear' : '')
    if (position) return { category: 'wheels', subcategory: `hubcaps::${position}` }
    return { category: 'wheels', subcategory: 'hubcaps' }
  }

  // ENGINE
  if (slotLower.includes('engine') || slotLower.includes('intake') || slotLower.includes('oilpan') || slotLower.includes('oilcooler')) {
    if (slotLower.includes('internals')) return { category: 'engine', subcategory: 'internals' }
    if (slotLower.includes('ecu')) return { category: 'engine', subcategory: 'ecu' }
    if (slotLower.includes('mounts')) return { category: 'engine', subcategory: 'mounts' }
    if (slotLower.includes('intake')) return { category: 'engine', subcategory: 'intake' }
    if (slotLower.includes('oilpan')) return { category: 'engine', subcategory: 'oilpan' }
    if (slotLower.includes('oilcooler')) return { category: 'engine', subcategory: 'oilcooler' }
    return { category: 'engine', subcategory: 'engine' }
  }

  // DRIVETRAIN
  if (slotLower.includes('transmission') || slotLower.includes('transfer_case') || slotLower.includes('flywheel') ||
      slotLower.includes('differential') || slotLower.includes('finaldrive') || slotLower.includes('driveshaft') || slotLower.includes('halfshaft')) {
    if (slotLower.includes('transmission')) return { category: 'drivetrain', subcategory: 'transmission' }
    if (slotLower.includes('transfer_case')) return { category: 'drivetrain', subcategory: 'transfer_case' }
    if (slotLower.includes('flywheel')) return { category: 'drivetrain', subcategory: 'flywheel' }
    if (slotLower.includes('differential')) return { category: 'drivetrain', subcategory: 'differential' }
    if (slotLower.includes('finaldrive')) return { category: 'drivetrain', subcategory: 'finaldrive' }
    if (slotLower.includes('driveshaft') || slotLower.includes('halfshaft')) return { category: 'drivetrain', subcategory: 'driveshafts' }
    return { category: 'drivetrain', subcategory: 'other' }
  }

  // EXHAUST
  if (slotLower.includes('exhaust') || slotLower.includes('converter')) {
    if (slotLower.includes('converter')) return { category: 'exhaust', subcategory: 'converter' }
    return { category: 'exhaust', subcategory: 'exhaust' }
  }

  // SUSPENSION
  if (slotLower.includes('suspension') || slotLower.includes('strut') || slotLower.includes('coilover') || slotLower.includes('swaybar')) {
    if (slotLower.includes('strut_bar')) return { category: 'suspension', subcategory: 'strut_bar' }
    if (slotLower.includes('strut')) return { category: 'suspension', subcategory: 'struts' }
    if (slotLower.includes('coilover')) return { category: 'suspension', subcategory: 'coilovers' }
    if (slotLower.includes('swaybar')) return { category: 'suspension', subcategory: 'swaybars' }
    if (isFrontPart(slot)) return { category: 'suspension', subcategory: 'front' }
    if (isRearPart(slot)) return { category: 'suspension', subcategory: 'rear' }
    return { category: 'suspension', subcategory: 'suspension' }
  }

  // BRAKES
  if (slotLower.includes('brake') || slotLower.includes('brakepad') || slotLower.includes('abs')) {
    if (slotLower.includes('abs')) return { category: 'brakes', subcategory: 'abs' }
    if (slotLower.includes('brakepad')) {
      if (isFrontPart(slot)) return { category: 'brakes', subcategory: 'pads_front' }
      if (isRearPart(slot)) return { category: 'brakes', subcategory: 'pads_rear' }
      return { category: 'brakes', subcategory: 'pads' }
    }
    if (isFrontPart(slot)) return { category: 'brakes', subcategory: 'front' }
    if (isRearPart(slot)) return { category: 'brakes', subcategory: 'rear' }
    return { category: 'brakes', subcategory: 'brakes' }
  }

  // STEERING
  if (slotLower.includes('steer')) {
    if (slotLower.includes('steeringbox')) return { category: 'steering', subcategory: 'steeringbox' }
    if (slotLower.includes('power_steering')) return { category: 'steering', subcategory: 'power_steering' }
    if (slotLower === 'etki_steer') return { category: 'steering', subcategory: 'wheel' }
    return { category: 'steering', subcategory: 'steering' }
  }

  // COOLING
  if (slotLower.includes('radiator')) {
    return { category: 'cooling', subcategory: 'radiator' }
  }

  // FUEL
  if (slotLower.includes('fuel')) {
    return { category: 'fuel', subcategory: 'fueltank' }
  }

  // BODY PANELS
  if (slotLower.includes('body') || slotLower.includes('hood') || slotLower.includes('trunk') || slotLower.includes('door') ||
      slotLower.includes('fender') || slotLower.includes('windshield') || slotLower.includes('bumper') || slotLower.includes('grille') ||
      slotLower === 'etki_glass') {
    if (slotLower.includes('body')) return { category: 'body', subcategory: 'body' }
    if (slotLower.includes('hood')) return { category: 'body', subcategory: 'hood' }
    if (slotLower.includes('trunk')) return { category: 'body', subcategory: 'trunk' }
    if (slotLower.includes('doorglass')) return { category: 'body', subcategory: 'door_glass' }
    if (slotLower.includes('doorpanel')) return { category: 'body', subcategory: 'door_panels' }
    if (slotLower.includes('door')) return { category: 'body', subcategory: 'doors' }
    if (slotLower.includes('fender') && !slotLower.includes('fenderflare')) return { category: 'body', subcategory: 'fenders' }
    if (slotLower.includes('windshield') || slotLower === 'etki_glass') return { category: 'body', subcategory: 'glass' }
    if (slotLower.includes('bumper') && !slotLower.includes('bumperlight') && !slotLower.includes('bumperbar')) return { category: 'body', subcategory: 'bumpers' }
    if (slotLower.includes('bumperbar')) return { category: 'body', subcategory: 'bumper_bars' }
    if (slotLower.includes('grille')) return { category: 'body', subcategory: 'grille' }
    return { category: 'body', subcategory: 'other' }
  }

  // EXTERIOR
  if (slotLower.includes('mirror') || slotLower.includes('spoiler') || slotLower.includes('sideskirt') || slotLower.includes('lip_') ||
      slotLower.includes('fenderflare') || slotLower.includes('mudflap') || slotLower.includes('skidplate') || slotLower.includes('towhitch') ||
      slotLower.includes('licenseplate')) {
    if (slotLower.includes('mirror')) return { category: 'exterior', subcategory: 'mirrors' }
    if (slotLower.includes('window_spoiler')) return { category: 'exterior', subcategory: 'window_spoiler' }
    if (slotLower.includes('spoiler')) return { category: 'exterior', subcategory: 'spoilers' }
    if (slotLower.includes('sideskirt')) return { category: 'exterior', subcategory: 'sideskirts' }
    if (slotLower.includes('lip_')) return { category: 'exterior', subcategory: 'lips' }
    if (slotLower.includes('fenderflare')) return { category: 'exterior', subcategory: 'fenderflares' }
    if (slotLower.includes('mudflap')) return { category: 'exterior', subcategory: 'mudflaps' }
    if (slotLower.includes('skidplate')) return { category: 'exterior', subcategory: 'skidplates' }
    if (slotLower.includes('towhitch')) return { category: 'exterior', subcategory: 'towhitch' }
    if (slotLower.includes('licenseplate')) return { category: 'exterior', subcategory: 'licenseplate' }
    return { category: 'exterior', subcategory: 'other' }
  }

  // LIGHTS
  if (slotLower.includes('light') || slotLower.includes('flasher') || slotLower.includes('signal')) {
    if (slotLower.includes('headlight') && !slotLower.includes('wiper')) return { category: 'lights', subcategory: 'headlights' }
    if (slotLower.includes('taillight')) return { category: 'lights', subcategory: 'taillights' }
    if (slotLower.includes('backlight')) return { category: 'lights', subcategory: 'backlights' }
    if (slotLower.includes('rally')) return { category: 'lights', subcategory: 'rally_lights' }
    if (slotLower.includes('fog')) return { category: 'lights', subcategory: 'fog_lights' }
    if (slotLower.includes('bumperlight')) return { category: 'lights', subcategory: 'bumper_lights' }
    if (slotLower.includes('flasher')) return { category: 'lights', subcategory: 'flashers' }
    if (slotLower.includes('signal')) return { category: 'lights', subcategory: 'signals' }
    return { category: 'lights', subcategory: 'other' }
  }

  // INTERIOR
  if (slotLower.includes('interior') || slotLower.includes('seat') || slotLower.includes('trim') || slotLower.includes('switches')) {
    if (slotLower.includes('seat')) return { category: 'interior', subcategory: 'seats' }
    if (slotLower.includes('trim')) return { category: 'interior', subcategory: 'trim' }
    if (slotLower.includes('switches')) return { category: 'interior', subcategory: 'switches' }
    return { category: 'interior', subcategory: 'interior' }
  }

  // ROLLCAGE
  if (slotLower.includes('rollcage')) {
    if (slotLower.includes('lightbar')) return { category: 'rollcage', subcategory: 'lightbar' }
    if (slotLower.includes('jerrycan')) return { category: 'rollcage', subcategory: 'accessories' }
    if (slotLower.includes('load')) return { category: 'rollcage', subcategory: 'accessories' }
    return { category: 'rollcage', subcategory: 'cage' }
  }

  // ROOF
  if (slotLower.includes('roof')) {
    if (slotLower.includes('antenna')) return { category: 'roof', subcategory: 'antenna' }
    return { category: 'roof', subcategory: 'accessories' }
  }

  // COSMETIC
  if (slotLower.includes('lettering') || slotLower.includes('logo') || slotLower.includes('paint') ||
      slotLower.includes('skin_') || slotLower.includes('sunstrip')) {
    if (slotLower.includes('lettering')) return { category: 'cosmetic', subcategory: 'lettering' }
    if (slotLower.includes('logo')) return { category: 'cosmetic', subcategory: 'logos' }
    if (slotLower.includes('paint')) return { category: 'cosmetic', subcategory: 'paint' }
    if (slotLower.includes('skin_lights')) return { category: 'cosmetic', subcategory: 'light_skins' }
    if (slotLower.includes('skin_interior')) return { category: 'cosmetic', subcategory: 'interior_skins' }
    if (slotLower.includes('skin_gauges')) return { category: 'cosmetic', subcategory: 'gauge_skins' }
    if (slotLower.includes('sunstrip')) return { category: 'cosmetic', subcategory: 'sunstrip' }
    return { category: 'cosmetic', subcategory: 'other' }
  }

  // ELECTRONICS
  if (slotLower.includes('gps')) {
    return { category: 'electronics', subcategory: 'gps' }
  }

  // MISC
  if (slotLower.includes('headlightwiper')) return { category: 'misc', subcategory: 'wipers' }
  if (slotLower.includes('cut_spare')) return { category: 'misc', subcategory: 'spare' }
  if (slotLower.includes('trunk_load')) return { category: 'misc', subcategory: 'cargo' }

  return { category: 'other', subcategory: 'other' }
}

// Build hierarchical tree from subcategory key like "tires::front::15"
const buildHierarchicalCategories = (parts) => {
  const categories = {}

  for (const part of parts) {
    const { category: categoryKey, subcategory: subcategoryKey } = categorizePart(part)
    const catDef = categoryDefinitions[categoryKey] || categoryDefinitions.other

    if (!categories[categoryKey]) {
      categories[categoryKey] = {
        name: categoryKey,
        displayName: catDef.displayName,
        order: catDef.order,
        children: {},
        parts: [],
        totalParts: 0
      }
    }

    // Parse hierarchical subcategory (e.g., "tires::front::15")
    const subParts = subcategoryKey.split('::')

    if (subParts.length === 1) {
      // Simple subcategory (not hierarchical)
      const subKey = subParts[0]
      const subDef = catDef.subcategories?.[subKey] || { displayName: subKey, order: 99 }

      if (!categories[categoryKey].children[subKey]) {
        categories[categoryKey].children[subKey] = {
          name: subKey,
          displayName: subDef.displayName,
          order: subDef.order,
          children: {},
          parts: []
        }
      }
      categories[categoryKey].children[subKey].parts.push(part)
    } else {
      // Hierarchical: tires::front::15
      let current = categories[categoryKey].children
      for (let i = 0; i < subParts.length; i++) {
        const key = subParts[i]
        const isLast = i === subParts.length - 1

        // Generate display name and order
        let displayName = key
        let order = 99

        if (key === 'tires') { displayName = 'Tires'; order = 10 }
        else if (key === 'rims') { displayName = 'Rims'; order = 5 }
        else if (key === 'hubcaps') { displayName = 'Hubcaps'; order = 20 }
        else if (key === 'front') { displayName = 'Front'; order = 1 }
        else if (key === 'rear') { displayName = 'Rear'; order = 2 }
        else if (/^\d+$/.test(key)) { displayName = `${key}"`; order = parseInt(key) }

        if (!current[key]) {
          current[key] = {
            name: key,
            displayName: displayName,
            order: order,
            children: {},
            parts: []
          }
        }

        if (isLast) {
          current[key].parts.push(part)
        } else {
          current = current[key].children
        }
      }
    }

    categories[categoryKey].totalParts++
  }

  // Convert children objects to sorted arrays recursively
  const sortChildren = (node) => {
    if (node.children && Object.keys(node.children).length > 0) {
      node.children = Object.values(node.children)
        .map(child => sortChildren(child))
        .sort((a, b) => a.order - b.order)
    } else {
      node.children = []
    }
    if (node.parts) {
      node.parts.sort((a, b) => (a.niceName || '').localeCompare(b.niceName || ''))
    }
    return node
  }

  return Object.values(categories)
    .filter(cat => cat.totalParts > 0)
    .map(cat => sortChildren(cat))
    .sort((a, b) => a.order - b.order)
}

// Group parts by category with hierarchical subcategories
const categorizedParts = computed(() => {
  return buildHierarchicalCategories(parts.value)
})

// Count total parts in a node recursively
const countNodeParts = (node) => {
  let count = node.parts?.length || 0
  if (node.children) {
    for (const child of node.children) {
      count += countNodeParts(child)
    }
  }
  return count
}

// Get all parts from a node recursively
const getNodeParts = (node) => {
  let allParts = [...(node.parts || [])]
  if (node.children) {
    for (const child of node.children) {
      allParts = allParts.concat(getNodeParts(child))
    }
  }
  return allParts
}

// Filter categories based on search (recursive for hierarchical structure)
const filteredCategories = computed(() => {
  if (!searchQuery.value) {
    return categorizedParts.value
  }

  const query = searchQuery.value.toLowerCase()

  const filterNode = (node) => {
    // Filter direct parts
    const matchingParts = (node.parts || []).filter(p => {
      const niceName = (typeof p.niceName === 'string' ? p.niceName : '').toLowerCase()
      const name = (typeof p.name === 'string' ? p.name : '').toLowerCase()
      const slotType = (typeof p.slotType === 'string' ? p.slotType : '').toLowerCase()
      return niceName.includes(query) || name.includes(query) || slotType.includes(query)
    })

    // Filter children recursively
    const filteredChildren = (node.children || [])
      .map(child => filterNode(child))
      .filter(child => child !== null)

    // Return null if no matches
    if (matchingParts.length === 0 && filteredChildren.length === 0) {
      return null
    }

    return {
      ...node,
      parts: matchingParts,
      children: filteredChildren,
      totalParts: matchingParts.length + filteredChildren.reduce((sum, c) => sum + (c.totalParts || countNodeParts(c)), 0)
    }
  }

  return categorizedParts.value
    .map(cat => filterNode(cat))
    .filter(cat => cat !== null)
})

// Find a node by path (e.g., "wheels::rims::front")
const findNodeByPath = (categories, path) => {
  const parts = path.split(':::')
  let current = categories.find(c => c.name === parts[0])
  if (!current) return null

  for (let i = 1; i < parts.length; i++) {
    if (!current.children) return null
    current = current.children.find(c => c.name === parts[i])
    if (!current) return null
  }
  return current
}

// Get currently displayed parts
const displayedParts = computed(() => {
  let result = []

  if (selectedSubcategory.value) {
    // Path format: "category:::child1:::child2:::..."
    const node = findNodeByPath(filteredCategories.value, selectedSubcategory.value)
    if (node) {
      result = getNodeParts(node)
    }
  } else {
    // Show all parts from filtered categories
    for (const cat of filteredCategories.value) {
      result = result.concat(getNodeParts(cat))
    }
  }

  // Sort
  switch (sortBy.value) {
    case 'name':
      result.sort((a, b) => (a.niceName || '').localeCompare(b.niceName || ''))
      break
    case 'price-asc':
      result.sort((a, b) => (a.shopPrice || 0) - (b.shopPrice || 0))
      break
    case 'price-desc':
      result.sort((a, b) => (b.shopPrice || 0) - (a.shopPrice || 0))
      break
  }

  return result
})

const currentCategoryName = computed(() => {
  if (selectedSubcategory.value) {
    // Use ':::' as separator for hierarchical paths
    const pathParts = selectedSubcategory.value.split(':::')
    const node = findNodeByPath(categorizedParts.value, selectedSubcategory.value)
    if (node) {
      // Build breadcrumb from path
      const breadcrumb = []
      let currentPath = ''
      for (const part of pathParts) {
        currentPath = currentPath ? `${currentPath}:::${part}` : part
        const pathNode = findNodeByPath(categorizedParts.value, currentPath)
        if (pathNode) {
          breadcrumb.push(pathNode.displayName)
        }
      }
      return breadcrumb.join(' > ')
    }
  }
  return 'All ETK I-Series Parts'
})

const cartTotal = computed(() => cart.value.reduce((sum, item) => sum + (item.shopPrice * item.quantity), 0))
const cartItemCount = computed(() => cart.value.reduce((sum, item) => sum + item.quantity, 0))

const toggleCategory = (categoryName) => {
  expandedCategories[categoryName] = !expandedCategories[categoryName]
}

// Toggle expansion of a hierarchical node
const toggleNode = (path) => {
  expandedNodes[path] = !expandedNodes[path]
}

// Check if a node is expanded
const isNodeExpanded = (path) => {
  return !!expandedNodes[path]
}

// Select a node (shows all parts under that node)
const selectNode = (path) => {
  selectedSubcategory.value = selectedSubcategory.value === path ? null : path
}

const selectSubcategory = (categoryName, subcategoryName) => {
  // Use ':::' as separator for hierarchical paths
  const key = `${categoryName}:::${subcategoryName}`
  selectedSubcategory.value = selectedSubcategory.value === key ? null : key
}

const isInCart = (partName) => cart.value.some(item => item.name === partName)

const addToCart = (part) => {
  // Don't add if out of stock, locked, or already in cart
  if (!part.inStock || part.locked || isInCart(part.name)) return
  
  // Stock is 1, so quantity is always 1
  cart.value.push({ ...part, quantity: 1 })

  // Check for required child parts and add them to cart
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerPartShops.getRequiredChildParts("${part.name}", 2.0)`, (childParts) => {
      if (childParts && Array.isArray(childParts) && childParts.length > 0) {
        for (const childPart of childParts) {
          // Check if child part is already in cart
          const childExists = cart.value.find(item => item.name === childPart.name)
          if (!childExists) {
            cart.value.push({
              name: childPart.name,
              niceName: childPart.niceName,
              slotType: childPart.slotType,
              shopPrice: childPart.price,
              quantity: 1,
              isChildPart: true,
              parentPart: part.name
            })
          }
        }
      }
    })
  }

  showCart.value = true
}

const removeFromCart = (partName) => {
  const index = cart.value.findIndex(item => item.name === partName)
  if (index !== -1) {
    if (cart.value[index].quantity > 1) {
      cart.value[index].quantity--
    } else {
      // Remove the item
      cart.value.splice(index, 1)
      // Also remove any child parts that depend on this item
      cart.value = cart.value.filter(item => item.parentPart !== partName)
    }
  }
}

const clearCart = () => {
  cart.value = []
}

const checkout = () => {
  if (cart.value.length === 0 || checkingOut.value) return

  checkingOut.value = true
  orderError.value = ""

  try {
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
          orderError.value = ""
        } else {
          console.error('Order failed:', result)
          orderError.value = (result && result.message) ? result.message : "Order failed. Please try again."
        }
        checkingOut.value = false
      })
    } else {
      orderError.value = "System error: API not available"
      checkingOut.value = false
    }
  } catch (err) {
    console.error('Checkout error:', err)
    orderError.value = "Checkout error: " + (err.message || "Unknown error")
    checkingOut.value = false
  }
}

const formatPrice = (value) => {
  return Number(value || 0).toLocaleString("en-US", { minimumFractionDigits: 2 })
}

const formatSlotType = (slot) => {
  if (!slot || typeof slot !== 'string') return ''
  return slot.replace(/^etki_/, '').replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())
}

const loadParts = () => {
  loading.value = true
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.getOnlineShopParts()', (result) => {
      if (result && Array.isArray(result)) {
        parts.value = result
        // Initialize quantities
        result.forEach(p => {
          partQuantities[p.name] = 1
        })
        // Expand first category
        if (categorizedParts.value.length > 0) {
          expandedCategories[categorizedParts.value[0].name] = true
        }
      }
      loading.value = false
    })
  } else {
    console.error('bngApi not available')
    loading.value = false
  }
}

const loadPendingOrders = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.getPendingOrders()', (result) => {
      if (result) {
        pendingOrders.value = result
      }
    })
  }
}

const setWaypointToPickup = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.setWaypointToPickup()')
  }
}

const setWaypointToDelivery = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.setWaypointToDelivery()')
  }
}

const cancelOrder = (index) => {
  if (window.bngApi) {
    window.bngApi.engineLua(`career_modules_mysummerPartShops.cancelPendingOrder(${index})`, (result) => {
      if (result && result.success) {
        loadPendingOrders()
      }
    })
  }
}

const cancelAllOrders = () => {
  if (window.bngApi) {
    window.bngApi.engineLua('career_modules_mysummerPartShops.cancelAllPendingOrders()', (result) => {
      if (result && result.success) {
        loadPendingOrders()
      }
    })
  }
}

onMounted(() => {
  loadParts()
  loadPendingOrders()
})
</script>

<style scoped lang="scss">
// SpeedParts colors - modern 2000s e-commerce
$brand-orange: #ff6600;
$brand-blue: #003366;
$brand-green: #339933;
$bg-white: #ffffff;
$bg-gray: #f0f0f0;
$text-dark: #333333;
$text-light: #666666;
$border-color: #dddddd;

.speedparts-page {
  min-height: 100%;
  background: $bg-white;
  font-family: Verdana, Arial, sans-serif;
  font-size: 11px;
  color: $text-dark;
}

// Header
.site-header {
  background: $brand-blue;
  color: white;
}

.header-main {
  display: flex;
  align-items: center;
  gap: 20px;
  padding: 10px 15px;
}

.logo {
  display: flex;
  align-items: baseline;
}

.logo-speed {
  font-size: 22px;
  font-weight: bold;
  color: $brand-orange;
  font-style: italic;
}

.logo-parts {
  font-size: 22px;
  font-weight: bold;
  color: white;
  font-style: italic;
}

.logo-dot {
  font-size: 12px;
  color: #aaa;
}

.header-search {
  flex: 1;
  display: flex;
  max-width: 400px;
}

.search-input {
  flex: 1;
  padding: 8px 10px;
  border: 2px solid $brand-orange;
  font-size: 12px;
}

.search-btn {
  padding: 8px 16px;
  background: $brand-orange;
  border: none;
  color: white;
  font-weight: bold;
  font-size: 11px;
  cursor: pointer;

  &:hover {
    background: #e55a00;
  }
}

.header-cart {
  display: flex;
  align-items: center;
  gap: 4px;
  cursor: pointer;
  padding: 6px 12px;
  background: rgba(255, 255, 255, 0.1);
  border-radius: 4px;

  &:hover {
    background: rgba(255, 255, 255, 0.2);
  }
}

.cart-count {
  background: $brand-orange;
  color: white;
  font-size: 10px;
  font-weight: bold;
  padding: 2px 6px;
  border-radius: 10px;
}

.header-nav {
  display: flex;
  background: #002244;
  padding: 0 15px;
}

.nav-item {
  padding: 8px 14px;
  font-size: 11px;
  font-weight: bold;
  cursor: pointer;

  &:hover {
    background: rgba(255, 255, 255, 0.1);
  }

  &.active {
    background: $brand-orange;
  }
}

.promo-bar {
  padding: 6px 15px;
  background: $brand-green;
  color: white;
  font-size: 11px;
  font-weight: bold;
  text-align: center;
}

// Main Content
.main-content {
  display: flex;
  min-height: 500px;
  position: relative;
}

// Sidebar
.sidebar {
  width: 220px;
  background: $bg-gray;
  border-right: 1px solid $border-color;
  padding: 12px;
  flex-shrink: 0;
  overflow-y: auto;
  max-height: calc(100vh - 200px);
}

.vehicle-selector {
  background: $bg-white;
  border: 1px solid $border-color;
  padding: 10px;
  margin-bottom: 12px;

  h4 {
    margin: 0 0 8px;
    font-size: 11px;
    color: $brand-blue;
    text-transform: uppercase;
  }
}

.vehicle-display {
  display: flex;
  align-items: center;
  gap: 8px;
}

.vehicle-icon {
  font-size: 20px;
  color: $brand-blue;
}

.vehicle-info {
  display: flex;
  flex-direction: column;
}

.vehicle-name {
  font-weight: bold;
  font-size: 12px;
}

.vehicle-year {
  font-size: 10px;
  color: $text-light;
}

.categories-box {
  background: $bg-white;
  border: 1px solid $border-color;
  padding: 10px;
  margin-bottom: 12px;

  h4 {
    margin: 0 0 8px;
    font-size: 11px;
    color: $brand-blue;
    text-transform: uppercase;
    border-bottom: 1px solid $border-color;
    padding-bottom: 6px;
  }
}

.categories-tree {
  max-height: 400px;
  overflow-y: auto;
}

.category-section {
  margin-bottom: 2px;
}

.category-header {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 5px 6px;
  cursor: pointer;
  font-size: 11px;
  background: #f8f8f8;
  border: 1px solid transparent;

  &:hover {
    background: #eee;
  }

  &.expanded {
    background: #e8f4ff;
    border-color: #cce0ff;
  }
}

.expand-icon {
  color: $brand-orange;
  font-size: 10px;
  min-width: 16px;
  font-family: monospace;
}

.category-name {
  flex: 1;
  font-weight: bold;
  color: $brand-blue;
}

.category-count {
  font-size: 9px;
  color: $text-light;
}

.subcategories-container {
  padding-left: 12px;
  border-left: 1px dashed #ccc;
  margin-left: 8px;
}

.nested-container {
  padding-left: 12px;
  border-left: 1px dashed #ddd;
  margin-left: 8px;

  &.level-2 {
    border-color: #e0e0e0;
  }

  &.level-3 {
    border-color: #eee;
  }
}

.subcategory-item {
  display: flex;
  align-items: center;
  gap: 4px;
  padding: 3px 6px;
  cursor: pointer;
  font-size: 10px;

  &:hover {
    background: #f0f0f0;
  }

  &.active {
    background: $brand-orange;
    color: white;

    .subcat-bullet, .subcat-count, .subcat-expand {
      color: white;
    }
  }

  &.expandable {
    font-weight: bold;

    &.expanded {
      background: #f5f5f5;
    }
  }

  &.leaf {
    font-weight: normal;
  }
}

.subcat-expand {
  color: $brand-orange;
  font-size: 9px;
  min-width: 16px;
  font-family: monospace;
  cursor: pointer;

  &:hover {
    color: darken($brand-orange, 10%);
  }
}

.subcat-bullet {
  color: $brand-orange;
  font-size: 9px;
  min-width: 10px;
}

.subcat-name {
  flex: 1;

  &.clickable {
    cursor: pointer;

    &:hover {
      text-decoration: underline;
    }
  }
}

.subcat-count {
  font-size: 9px;
  color: $text-light;
}

.info-box {
  background: #fffff0;
  border: 1px solid #e0e0a0;
  padding: 10px;

  h4 {
    margin: 0 0 6px;
    font-size: 11px;
    color: $brand-green;
  }
}

.benefits-list {
  margin: 0;
  padding-left: 16px;
  font-size: 10px;

  li {
    margin-bottom: 2px;
  }
}

// Products Area
.products-area {
  flex: 1;
  padding: 12px;
  overflow-y: auto;
}

.products-header {
  display: flex;
  align-items: center;
  gap: 12px;
  margin-bottom: 12px;
  padding-bottom: 8px;
  border-bottom: 2px solid $brand-orange;

  h2 {
    margin: 0;
    font-size: 14px;
    color: $brand-blue;
  }
}

.products-count {
  color: $text-light;
  font-size: 11px;
}

.sort-options {
  margin-left: auto;
  display: flex;
  align-items: center;
  gap: 6px;
  font-size: 11px;

  select {
    padding: 3px 6px;
    border: 1px solid $border-color;
    font-size: 11px;
  }
}

.loading-indicator, .no-products {
  text-align: center;
  padding: 40px;
  color: $text-light;
}

.products-grid {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(180px, 1fr));
  gap: 12px;
}

.product-card {
  background: $bg-white;
  border: 1px solid $border-color;
  padding: 10px;
  display: flex;
  flex-direction: column;

  &:hover {
    border-color: $brand-orange;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.1);
  }
  
  &.out-of-stock {
    opacity: 0.6;
    background: #f5f5f5;

    &:hover {
      border-color: #999;
      box-shadow: none;
    }

    .product-name {
      color: #888;
    }

    .price-value {
      color: #999 !important;
    }

    .savings {
      color: #999;
    }
  }

  &.part-locked {
    opacity: 0.7;
    background: linear-gradient(135deg, #2a2a2a 0%, #1a1a1a 100%);
    border-color: #444;

    &:hover {
      border-color: #666;
      box-shadow: 0 0 10px rgba(255, 100, 0, 0.2);
    }

    .product-name {
      color: #ff9900;
    }

    .product-sku {
      color: #888;
    }

    .price-value {
      color: #666 !important;
    }

    .price-msrp {
      color: #555 !important;
    }

    .savings {
      color: #555;
    }

    .no-image {
      color: #555;
    }
  }
}

.product-image {
  height: 80px;
  background: $bg-gray;
  border: 1px solid $border-color;
  display: flex;
  align-items: center;
  justify-content: center;
  margin-bottom: 8px;
  position: relative;
}

.no-image {
  color: #ccc;
  font-size: 14px;
}

.product-badge {
  position: absolute;
  top: 4px;
  right: 4px;
  padding: 2px 6px;
  font-size: 9px;
  font-weight: bold;
  background: $brand-green;
  color: white;

  &.sold {
    background: #999;
  }

  &.locked {
    background: linear-gradient(135deg, #ff6600 0%, #cc3300 100%);
    color: white;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
  }
}

.product-info {
  flex: 1;
  margin-bottom: 8px;
}

.product-name {
  margin: 0 0 4px;
  font-size: 11px;
  font-weight: bold;
  color: $brand-blue;
  line-height: 1.2;
}

.product-sku {
  font-size: 9px;
  color: $text-light;
  margin-bottom: 4px;
}

.product-stock {
  font-size: 10px;
  display: flex;
  align-items: center;
  gap: 4px;
  color: $brand-green;

  &.out-of-stock-label {
    color: #999;
  }

  &.locked-label {
    color: #ff6600;
  }
}

.stock-dot {
  width: 6px;
  height: 6px;
  background: $brand-green;
  border-radius: 50%;

  &.out {
    background: #999;
  }

  &.locked {
    background: #ff6600;
  }
}

.product-pricing {
  margin-bottom: 8px;
  padding: 6px;
  background: $bg-gray;
}

.price-row {
  display: flex;
  justify-content: space-between;
  font-size: 10px;
  margin-bottom: 2px;

  &.our-price {
    font-weight: bold;

    .price-value {
      font-size: 14px;
      color: $brand-orange;
    }
  }
}

.price-msrp {
  text-decoration: line-through;
  color: $text-light;
}

.savings {
  font-size: 10px;
  color: $brand-green;
  font-weight: bold;
}

.product-actions {
  display: flex;
  gap: 6px;
  align-items: center;
}

.qty-selector {
  display: flex;
  align-items: center;
  gap: 4px;
  font-size: 10px;
}

.qty-select {
  width: 40px;
  padding: 2px;
  border: 1px solid $border-color;
  font-size: 10px;
}

.add-to-cart-btn {
  flex: 1;
  padding: 6px 10px;
  background: $brand-orange;
  border: none;
  color: white;
  font-weight: bold;
  font-size: 10px;
  cursor: pointer;

  &:hover:not(:disabled) {
    background: #e55a00;
  }

  &.in-cart {
    background: $brand-green;
    cursor: default;
  }
  
  &.sold-out {
    background: #ccc;
    color: #666;
    cursor: not-allowed;
  }

  &.locked-btn {
    background: linear-gradient(135deg, #333 0%, #222 100%);
    color: #ff6600;
    border: 1px solid #444;
    cursor: not-allowed;
    text-shadow: 0 1px 2px rgba(0, 0, 0, 0.5);
  }

  &:disabled {
    cursor: not-allowed;
  }
}

// Cart Panel
.cart-panel {
  position: absolute;
  top: 0;
  right: -280px;
  width: 280px;
  height: 100%;
  background: $bg-white;
  border-left: 2px solid $brand-blue;
  box-shadow: -4px 0 12px rgba(0, 0, 0, 0.15);
  display: flex;
  flex-direction: column;
  transition: right 0.3s ease;
  z-index: 10;

  &.open {
    right: 0;
  }
}

.cart-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px;
  background: $brand-blue;
  color: white;

  h3 {
    margin: 0;
    font-size: 12px;
  }
}

.close-cart {
  background: none;
  border: none;
  color: white;
  font-size: 14px;
  cursor: pointer;
  font-weight: bold;

  &:hover {
    color: $brand-orange;
  }
}

.cart-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 20px;
  text-align: center;
  color: $text-light;
}

.empty-icon {
  font-size: 24px;
  margin-bottom: 8px;
}

.cart-content {
  flex: 1;
  display: flex;
  flex-direction: column;
}

.cart-items {
  flex: 1;
  overflow: auto;
  padding: 10px;
}

.cart-item {
  display: flex;
  align-items: center;
  gap: 8px;
  padding: 8px;
  border-bottom: 1px solid $border-color;
}

.item-image {
  width: 30px;
  height: 30px;
  background: $bg-gray;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 10px;
  color: #aaa;
}

.item-details {
  flex: 1;
  min-width: 0;
}

.item-name {
  display: block;
  font-size: 10px;
  font-weight: bold;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}

.item-qty {
  font-size: 9px;
  color: $text-light;
}

.item-price {
  font-weight: bold;
  font-size: 11px;
}

.item-remove {
  background: none;
  border: none;
  color: #cc0000;
  cursor: pointer;
  font-weight: bold;

  &:hover {
    color: #ff0000;
  }
}

.cart-item.child-part {
  background: #fff8e1;
  border-left: 3px solid #ff9800;
  padding-left: 5px;
  
  .item-image {
    color: #ff9800;
    font-weight: bold;
  }
  
  .item-name {
    font-size: 9px;
  }
}

.item-required {
  display: block;
  font-size: 8px;
  color: #ff9800;
  font-style: italic;
}

.cart-summary {
  padding: 10px;
  background: $bg-gray;
  border-top: 1px solid $border-color;
}

.summary-row {
  display: flex;
  justify-content: space-between;
  margin-bottom: 4px;
  font-size: 11px;

  &.total {
    font-weight: bold;
    font-size: 13px;
    color: $brand-blue;
    padding-top: 6px;
    border-top: 1px solid $border-color;
    margin-top: 6px;
  }
}

.free-ship {
  color: $brand-green;
  font-weight: bold;
}

.checkout-btn {
  margin: 10px;
  padding: 10px;
  background: $brand-green;
  border: none;
  color: white;
  font-weight: bold;
  font-size: 11px;
  cursor: pointer;

  &:hover:not(:disabled) {
    background: #2d8a2d;
  }

  &:disabled {
    background: #999;
    cursor: default;
  }
}

.order-error {
  margin: 5px 10px;
  padding: 8px;
  background: #ff4444;
  color: white;
  font-size: 11px;
  border-radius: 3px;
  display: flex;
  align-items: center;
  gap: 5px;

  .error-icon {
    font-weight: bold;
  }
}

.clear-cart-btn {
  margin: 0 10px 10px;
  padding: 6px;
  background: $bg-gray;
  border: 1px solid $border-color;
  font-size: 10px;
  cursor: pointer;

  &:hover {
    background: #ddd;
  }
}

.secure-badge {
  text-align: center;
  padding: 6px;
  font-size: 9px;
  color: $text-light;
  background: #f8f8f8;
}

// Order Modal
.order-modal {
  position: fixed;
  top: 0;
  left: 0;
  right: 0;
  bottom: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  background: rgba(0, 0, 0, 0.7);
  z-index: 1000;

  .modal-content {
    padding: 30px;
    background: white;
    border: 2px solid $brand-green;
    text-align: center;
    max-width: 350px;
  }

  .success-icon {
    font-size: 40px;
    color: $brand-green;
    margin-bottom: 10px;
  }

  h2 {
    margin: 0 0 10px;
    color: $brand-green;
  }

  p {
    color: $text-light;
    margin: 0 0 15px;
  }

  .modal-btn {
    padding: 10px 20px;
    background: $brand-green;
    border: none;
    color: white;
    font-weight: bold;
    cursor: pointer;

    &:hover {
      background: #2d8a2d;
    }
  }
}

// Footer
.site-footer {
  background: $brand-blue;
  color: white;
}

.footer-bottom {
  text-align: center;
  padding: 10px;
  font-size: 10px;

  p {
    margin: 0;
  }
}

// My Orders nav highlight
.nav-item.highlight {
  background: $brand-orange;
  position: relative;
}

.orders-badge {
  background: white;
  color: $brand-orange;
  font-size: 9px;
  font-weight: bold;
  padding: 1px 5px;
  border-radius: 8px;
  margin-left: 4px;
}

// Orders Panel
.orders-panel {
  position: absolute;
  top: 0;
  right: -320px;
  width: 320px;
  height: 100%;
  background: $bg-white;
  border-left: 2px solid $brand-blue;
  box-shadow: -4px 0 12px rgba(0, 0, 0, 0.15);
  display: flex;
  flex-direction: column;
  transition: right 0.3s ease;
  z-index: 11;

  &.open {
    right: 0;
  }
}

.orders-header {
  display: flex;
  justify-content: space-between;
  align-items: center;
  padding: 10px;
  background: $brand-blue;
  color: white;

  h3 {
    margin: 0;
    font-size: 12px;
  }
}

.close-orders {
  background: none;
  border: none;
  color: white;
  font-size: 14px;
  cursor: pointer;
  font-weight: bold;

  &:hover {
    color: $brand-orange;
  }
}

.orders-empty {
  flex: 1;
  display: flex;
  flex-direction: column;
  align-items: center;
  justify-content: center;
  padding: 20px;
  text-align: center;
  color: $text-light;

  .empty-icon {
    font-size: 24px;
    margin-bottom: 8px;
  }
}

.orders-content {
  flex: 1;
  overflow-y: auto;
  padding: 10px;
}

.order-section {
  background: $bg-gray;
  border: 1px solid $border-color;
  margin-bottom: 12px;
  border-radius: 4px;
}

.section-header {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 10px;
  border-bottom: 1px solid $border-color;

  &.pickup {
    background: #fff3e0;
    border-color: #ffcc80;
  }

  &.carrying {
    background: #e3f2fd;
    border-color: #90caf9;
  }
}

.section-icon {
  font-size: 16px;
  color: $brand-blue;
}

.section-info {
  display: flex;
  flex-direction: column;
}

.section-title {
  font-weight: bold;
  font-size: 11px;
  color: $brand-blue;
}

.section-subtitle {
  font-size: 10px;
  color: $text-light;
}

.order-items {
  padding: 8px;
  max-height: 150px;
  overflow-y: auto;
}

.order-item {
  display: flex;
  justify-content: space-between;
  padding: 4px 6px;
  font-size: 10px;
  border-bottom: 1px dashed #ddd;

  &:last-child {
    border-bottom: none;
  }
}

.order-item-name {
  flex: 1;
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
  margin-right: 8px;
}

.order-item-price {
  color: $brand-orange;
  font-weight: bold;
}

.order-item-cancel {
  background: #cc0000;
  color: white;
  border: none;
  width: 16px;
  height: 16px;
  font-size: 10px;
  font-weight: bold;
  cursor: pointer;
  margin-left: 4px;
  border-radius: 2px;

  &:hover {
    background: #ff0000;
  }
}

.order-buttons {
  display: flex;
  gap: 4px;
}

.cancel-all-btn {
  flex: 1;
  padding: 8px;
  background: #cc0000;
  border: none;
  color: white;
  font-weight: bold;
  font-size: 9px;
  cursor: pointer;
  border-radius: 0 0 3px 0;

  &:hover {
    background: #ff0000;
  }
}

.waypoint-btn {
  flex: 1;
  padding: 8px;
  background: $brand-orange;
  border: none;
  color: white;
  font-weight: bold;
  font-size: 10px;
  cursor: pointer;
  border-radius: 0 0 3px 3px;

  &:hover {
    background: #e55a00;
  }

  &.delivery {
    background: $brand-green;

    &:hover {
      background: #2d8a2d;
    }
  }
}
</style>
