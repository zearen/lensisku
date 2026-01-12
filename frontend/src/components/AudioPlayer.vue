<template>
  <div class="inline-flex items-center gap-2">
    <button
      class="btn-get"
      :disabled="isLoading"
      @click="togglePlay"
    >
      <PauseCircle
        v-if="isPlaying"
        class="w-4 h-4"
      />
      <Loader
        v-else-if="isLoading"
        class="w-4 h-4 animate-spin"
      />
      <PlayCircle
        v-else
        class="w-4 h-4"
      />
    </button>
  </div>
</template>

<script setup>
  import { PlayCircle, PauseCircle, Loader } from 'lucide-vue-next';
  import { ref, onMounted, onBeforeUnmount } from 'vue';
  import { useI18n } from 'vue-i18n';

  import { useError } from '@/composables/useError';

  const { showError, clearError } = useError();
  const { t } = useI18n();
  const props = defineProps({
    url: {
      type: String,
      required: true,
    },
  })

  const isPlaying = ref(false)
  const isLoading = ref(false)
  const audio = ref(null)

  const CACHE_SIZE = 20
  const CACHE_KEY = 'audioCache'

  const validateBlobUrl = async (url) => {
    try {
      const response = await fetch(url)
      return response.ok
    } catch {
      return false
    }
  }

  const loadCacheFromStorage = async () => {
    if (typeof window === 'undefined') return;

    try {
      const cached = localStorage.getItem(CACHE_KEY)
      const cache = cached ? new Map(JSON.parse(cached)) : new Map()

      // Validate all blob URLs in cache
      for (const [key, value] of cache.entries()) {
        if (!(await validateBlobUrl(value.blob))) {
          cache.delete(key)
        }
      }

      return cache
    } catch {
      return new Map()
    }
  }

  const saveCacheToStorage = (cache) => {
    if (typeof window === 'undefined') return;

    try {
      const entries = Array.from(cache.entries())
      localStorage.setItem(CACHE_KEY, JSON.stringify(entries))
    } catch (e) {
      console.error('Error saving to localStorage:', e)
    }
  }

  const cleanCache = (cache) => {
    if (cache.size > CACHE_SIZE) {
      const entries = Array.from(cache.entries())
      const sortedEntries = entries.sort((a, b) => a[1].lastAccessed - b[1].lastAccessed)
      while (cache.size > CACHE_SIZE) {
        const [oldestKey] = sortedEntries.shift()
        const oldBlob = cache.get(oldestKey)?.blob
        if (oldBlob) {
          URL.revokeObjectURL(oldBlob)
        }
        cache.delete(oldestKey)
      }
      saveCacheToStorage(cache)
    }
  }

  const loadAudio = async () => {
    const cache = await loadCacheFromStorage()
    const cacheEntry = cache.get(props.url)

    if (cacheEntry && (await validateBlobUrl(cacheEntry.blob))) {
      const blob = await fetch(cacheEntry.blob).then((r) => r.blob())
      audio.value = new Audio(URL.createObjectURL(blob))
      cache.set(props.url, {
        blob: cacheEntry.blob,
        lastAccessed: Date.now(),
      })
      saveCacheToStorage(cache)
      return
    }

    isLoading.value = true
    clearError()

    try {
      const response = await fetch(props.url)
      if (!response.ok) throw new Error('Failed to load audio')

      const blob = await response.blob()
      const blobUrl = URL.createObjectURL(blob)

      audio.value = new Audio(blobUrl)
      audio.value.addEventListener('ended', handleEnded)

      cleanCache(cache)
      cache.set(props.url, {
        blob: blobUrl,
        lastAccessed: Date.now(),
      })
      saveCacheToStorage(cache)
    } catch (e) {
      console.error('Error loading audio:', e)
      showError(t('audioPlayer.loadError'))
    } finally {
      isLoading.value = false
    }
  }

  const togglePlay = async () => {
    if (!audio.value) {
      await loadAudio()
    }

    if (!audio.value) return

    if (isPlaying.value) {
      audio.value.pause()
      isPlaying.value = false
    } else {
      try {
        await audio.value.play()
        isPlaying.value = true
      } catch (e) {
        console.error('Error playing audio:', e)
        showError(t('audioPlayer.playError'))
      }
    }
  }

  const handleEnded = () => {
    isPlaying.value = false
  }

  onMounted(() => {
    if (audio.value) {
      audio.value.addEventListener('ended', handleEnded)
    }
  })

  onBeforeUnmount(() => {
    if (audio.value) {
      audio.value.removeEventListener('ended', handleEnded)
      URL.revokeObjectURL(audio.value.src)
    }
  })

  defineExpose({
    play: togglePlay,
  })
</script>
