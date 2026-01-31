/**
 * Contact Images Helper
 * Manages contact avatar images with emotional states
 */

/**
 * Available contacts
 */
export const CONTACTS = {
  GRANDFATHER: 'grandfather',
  GHOST: 'ghost',
  IMPORT: 'import',
  MUSCLE: 'muscle',
  NOVA: 'nova',
  ROOK: 'rook',
  SHADOW: 'shadow',
  TECHIE: 'techie',
  VIPER: 'viper',
}

/**
 * Available emotional states
 */
export const EMOTIONS = {
  STANDARD: 'standard',
  HAPPY: 'happy',
  CONTENT: 'content',
  SAD: 'sad',
  ANGRY: 'angry',
  SEDUCTIVE: 'seductive', // Only available for nova and rook
}

/**
 * Get contact image URL
 * @param {string} contactId - Contact identifier (use CONTACTS constants)
 * @param {string} emotion - Emotional state (use EMOTIONS constants)
 * @returns {string} Image URL path
 */
export function getContactImage(contactId, emotion = EMOTIONS.STANDARD) {
  // Validate emotion availability for specific contacts
  if (emotion === EMOTIONS.SEDUCTIVE) {
    if (contactId !== CONTACTS.NOVA && contactId !== CONTACTS.ROOK) {
      console.warn(`Contact "${contactId}" doesn't have seductive emotion, using standard`)
      emotion = EMOTIONS.STANDARD
    }
  }

  return `/ui/images/contacts/${contactId}_${emotion}.png`
}

/**
 * Get all available emotions for a contact
 * @param {string} contactId - Contact identifier
 * @returns {string[]} Array of available emotion names
 */
export function getAvailableEmotions(contactId) {
  const baseEmotions = [
    EMOTIONS.STANDARD,
    EMOTIONS.HAPPY,
    EMOTIONS.CONTENT,
    EMOTIONS.SAD,
    EMOTIONS.ANGRY,
  ]

  if (contactId === CONTACTS.NOVA || contactId === CONTACTS.ROOK) {
    return [...baseEmotions, EMOTIONS.SEDUCTIVE]
  }

  return baseEmotions
}

/**
 * Preload contact images for better performance
 * @param {string} contactId - Contact to preload
 * @returns {Promise[]} Array of image load promises
 */
export function preloadContactImages(contactId) {
  const emotions = getAvailableEmotions(contactId)
  return emotions.map(emotion => {
    return new Promise((resolve, reject) => {
      const img = new Image()
      img.onload = () => resolve(img)
      img.onerror = reject
      img.src = getContactImage(contactId, emotion)
    })
  })
}
