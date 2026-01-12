import { getProfileImage } from '@/api'

// Use regular Map instead of ref
const avatarCache = new Map()
// Track in-flight requests
const pendingRequests = new Map()

export const useAvatarStore = () => {
  const checkProfileImage = async (username) => {
    // Return cached result if available
    if (avatarCache.has(username)) {
      return avatarCache.get(username)
    }

    // Return existing promise if request is pending
    if (pendingRequests.has(username)) {
      return pendingRequests.get(username)
    }

    // Create new request promise
    const requestPromise = (async () => {
      try {
        const response = await fetch(getProfileImage(username, { cached: true }))
        const hasAvatar = response.ok
        avatarCache.set(username, hasAvatar)
        return hasAvatar
      } catch (error) {
        // Don't cache failed requests
        console.error(`Failed to fetch avatar for ${username}:`, error)
        return false
      } finally {
        pendingRequests.delete(username)
      }
    })()

    // Store the pending request
    pendingRequests.set(username, requestPromise)
    return requestPromise
  }

  const getProfileImageUrl = (username) => {
    return getProfileImage(username, { cached: true })
  }

  return {
    checkProfileImage,
    getProfileImageUrl,
    // Only expose cache for testing/debugging
    _avatarCache: avatarCache,
  }
}
