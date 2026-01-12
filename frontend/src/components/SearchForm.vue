<template>
  <div class="search-form max-w-3xl mx-auto">
    <div class="flex flex-col sm:flex-row gap-2 sm:gap-0">
      <Select v-model="mode" :options="modes" option-label="name" :placeholder="$t('searchForm.selectSearchMode')"
        class="!shadow-none w-full h-10 sm:w-56 !rounded-full sm:!rounded-l-full sm:!rounded-r-none"
        @update:model-value="onModeChange">
        <template #value="slotProps">
          <div v-if="slotProps.value" class="flex items-center gap-2">
            <component :is="slotProps.value.icon" class="h-4 w-4" :class="slotProps.value.color" />
            {{ slotProps.value.name }}
          </div>
          <span v-else>
            {{ slotProps.placeholder }}
          </span>
        </template>
        <template #option="slotProps">
          <div class="flex items-center gap-2">
            <component :is="slotProps.option.icon" class="h-4 w-4" :class="slotProps.option.color" />
            {{ slotProps.option.name }}
          </div>
        </template>
        <template #dropdownicon>
          <ChevronDown class="h-4 w-4" />
        </template>
      </Select>
      <div class="relative flex-1">
        <input ref="searchInput" v-model="query" :placeholder="getPlaceholder"
          :class="`input-field w-full text-base h-10 border border-slate-300 sm:rounded-l-none focus:ring-2 hover:z-[100] border-l-0 hover:border-l focus:border-l ${query ? 'pr-10' : ''}`"
          @input="handleInput">
        <div class="absolute right-3 top-1/2 transform -translate-y-1/2 flex items-center">
          <div v-if="isSearching" class="animate-spin rounded-full h-5 w-5 border-b-2 border-blue-500" />
          <button v-else-if="query"
            class="text-gray-400 hover:text-gray-600 hover:bg-gray-100 transition-colors duration-200 p-1 rounded-full"
            @click="clearInput">
            <X class="h-4 w-4" />
          </button>
        </div>
      </div>
    </div>
  </div>
</template>

<script setup>
import { Book, Search, Mail, List, ChevronDown, Waves, X } from 'lucide-vue-next'
import Select from 'primevue/select'
import { ref, computed, watch, onBeforeUnmount } from 'vue'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

const modes = ref([
  { name: t('searchForm.modes.dictionary'), value: 'dictionary', icon: Book, color: 'text-blue-500' },
  { name: t('searchForm.modes.semantic'), value: 'semantic', icon: Search, color: 'text-green-500' },
  { name: t('searchForm.modes.comments'), value: 'comments', icon: Waves, color: 'text-purple-500' },
  { name: t('searchForm.modes.messages'), value: 'messages', icon: Mail, color: 'text-orange-500' },
  { name: t('searchForm.modes.muplis'), value: 'muplis', icon: List, color: 'text-teal-500' }
]);

const props = defineProps({
  initialQuery: {
    type: String,
    default: '',
  },
  initialMode: {
    type: String,
    default: 'dictionary',
  }
})

const emit = defineEmits(['search'])

const searchInput = ref(null)
const query = ref(props.initialQuery)
const mode = ref(modes.value.find(m => m.value === props.initialMode) || modes.value[0])
const isSearching = ref(false)
let searchTimeout = null

const getPlaceholder = computed(() => {
  switch (mode.value?.value) {
    case 'messages':
      return t('searchForm.placeholder.messages')
    case 'muplis':
      return t('searchForm.placeholder.muplis')
    case 'dictionary':
      return t('searchForm.placeholder.dictionary')
    case 'semantic':
      return t('searchForm.placeholder.semantic')
    case 'comments':
      return t('searchForm.placeholder.comments')
    default:
      return t('searchForm.placeholder.default')
  }
})

function clearSearchTimeout() {
  if (searchTimeout) {
    window.clearTimeout(searchTimeout)
    searchTimeout = null
  }
}

function handleInput() {
  // Clear any pending timeout to prevent stale searches
  clearSearchTimeout()
  
  // Capture current query value to check in timeout
  const currentQuery = query.value
  
  isSearching.value = true
  searchTimeout = window.setTimeout(() => {
    // Only emit if query hasn't changed (to prevent race conditions)
    // and if it's not empty (unless it was explicitly cleared)
    if (query.value === currentQuery) {
      emitSearch()
    }
    isSearching.value = false
    searchTimeout = null
  }, 300)
}

function emitSearch() {
  emit('search', { query: query.value, mode: mode.value.value })
}

function clearInput() {
  // Clear any pending timeout first to prevent it from firing after clearing
  clearSearchTimeout()
  query.value = ''
  isSearching.value = false
  emit('search', { query: '', mode: mode.value.value })
  focusInput()
}

function onModeChange() {
  // Clear any pending timeout when mode changes to prevent stale searches
  clearSearchTimeout()
  isSearching.value = false
  emit('search', { query: query.value, mode: mode.value.value})
}

watch(
  () => props.initialQuery,
  (newValue) => {
    // Clear any pending timeout when query changes externally
    clearSearchTimeout()
    isSearching.value = false
    query.value = newValue
  }
)

watch(
  () => props.initialMode,
  (newValue) => {
    const newMode = modes.value.find(m => m.value === newValue)
    if (newMode) {
      // Clear any pending timeout when mode changes externally
      clearSearchTimeout()
      isSearching.value = false
      mode.value = newMode
    }
  }
)

// Clean up timeout on component unmount
onBeforeUnmount(() => {
  clearSearchTimeout()
})

function focusInput() {
  searchInput.value?.focus()
}

defineExpose({
  focusInput
})
</script>
