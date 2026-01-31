<template>
  <bng-dialog
    :open="open"
    :modal="true"
    @close="handleClose"
    class="contact-dialog"
  >
    <div class="dialog-container">
      <!-- Contact Avatar -->
      <div class="contact-avatar">
        <img
          :src="currentAvatar"
          :alt="`${contactName} - ${currentEmotion}`"
          class="avatar-image"
        />
        <div class="contact-name">{{ contactName }}</div>
      </div>

      <!-- Dialog Content -->
      <div class="dialog-content">
        <div class="dialog-text" v-html="dialogText"></div>

        <!-- Choice buttons if provided -->
        <div v-if="choices && choices.length > 0" class="dialog-choices">
          <bng-button
            v-for="(choice, index) in choices"
            :key="index"
            @click="handleChoice(choice)"
            class="choice-button"
          >
            {{ choice.label }}
          </bng-button>
        </div>

        <!-- Continue button if no choices -->
        <div v-else class="dialog-actions">
          <bng-button @click="handleClose" accent>
            {{ continueLabel }}
          </bng-button>
        </div>
      </div>
    </div>
  </bng-dialog>
</template>

<script setup>
import { computed, ref, watch } from 'vue'
import { getContactImage, EMOTIONS } from '../../utils/contactImages'

const props = defineProps({
  open: {
    type: Boolean,
    default: false
  },
  contactId: {
    type: String,
    required: true
  },
  contactName: {
    type: String,
    required: true
  },
  emotion: {
    type: String,
    default: EMOTIONS.STANDARD,
    validator: (value) => Object.values(EMOTIONS).includes(value)
  },
  dialogText: {
    type: String,
    required: true
  },
  choices: {
    type: Array,
    default: null
    // Format: [{ label: 'Accept', value: 'accept' }, { label: 'Decline', value: 'decline' }]
  },
  continueLabel: {
    type: String,
    default: 'Continue'
  }
})

const emit = defineEmits(['close', 'choice'])

const currentEmotion = ref(props.emotion)

// Computed avatar URL
const currentAvatar = computed(() => {
  return getContactImage(props.contactId, currentEmotion.value)
})

// Watch for emotion changes (can be used for dynamic emotion changes during dialog)
watch(() => props.emotion, (newEmotion) => {
  currentEmotion.value = newEmotion
})

const handleClose = () => {
  emit('close')
}

const handleChoice = (choice) => {
  emit('choice', choice)
  handleClose()
}
</script>

<style scoped lang="scss">
.contact-dialog {
  :deep(.dialog-backdrop) {
    background: rgba(0, 0, 0, 0.85);
  }

  :deep(.dialog-content) {
    max-width: 900px;
    width: 90vw;
    background: linear-gradient(135deg, rgba(20, 20, 30, 0.95), rgba(10, 10, 20, 0.95));
    border: 2px solid rgba(100, 150, 255, 0.3);
    border-radius: 12px;
    padding: 0;
    overflow: hidden;
  }
}

.dialog-container {
  display: flex;
  gap: 2rem;
  padding: 2rem;
  min-height: 400px;

  @media (max-width: 768px) {
    flex-direction: column;
    gap: 1rem;
  }
}

.contact-avatar {
  flex-shrink: 0;
  display: flex;
  flex-direction: column;
  align-items: center;
  gap: 1rem;
  padding: 1rem;
  background: rgba(0, 0, 0, 0.3);
  border-radius: 8px;

  .avatar-image {
    width: 200px;
    height: 200px;
    object-fit: cover;
    border-radius: 8px;
    border: 3px solid rgba(100, 150, 255, 0.5);
    box-shadow: 0 4px 20px rgba(0, 0, 0, 0.5);

    @media (max-width: 768px) {
      width: 150px;
      height: 150px;
    }
  }

  .contact-name {
    font-size: 1.2rem;
    font-weight: bold;
    color: rgba(100, 150, 255, 1);
    text-transform: uppercase;
    letter-spacing: 0.1em;
  }
}

.dialog-content {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 1.5rem;

  .dialog-text {
    flex: 1;
    font-size: 1.1rem;
    line-height: 1.6;
    color: rgba(255, 255, 255, 0.9);
    padding: 1rem;
    background: rgba(0, 0, 0, 0.2);
    border-radius: 8px;
    border-left: 4px solid rgba(100, 150, 255, 0.5);
  }

  .dialog-choices {
    display: flex;
    flex-direction: column;
    gap: 0.75rem;

    .choice-button {
      width: 100%;
      justify-content: flex-start;
      padding: 1rem 1.5rem;
      font-size: 1rem;

      &:hover {
        background: rgba(100, 150, 255, 0.2);
        border-color: rgba(100, 150, 255, 0.8);
      }
    }
  }

  .dialog-actions {
    display: flex;
    justify-content: flex-end;
  }
}
</style>
