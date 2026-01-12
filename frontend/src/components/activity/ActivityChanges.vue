<template>
  <div>
    <!-- Days selector for changes tab -->
    <div class="flex flex-wrap justify-start items-center my-2 gap-2">
      <div class="flex items-center gap-2 w-full sm:w-auto">
        <label class="text-sm text-gray-600">{{ t('recentChanges.showChangesForLast') }}</label>
        <input 
          v-model.number="localDays"
          type="number"
          min="1"
          max="365"
          class="input-field"
          @input="handleDaysInput"
        >
        <label class="text-sm text-gray-600">{{ t('recentChanges.days') }}</label>
      </div>
    </div>

    <div v-if="groupedChanges.length">
      <div
        v-for="(group, index) in groupedChanges"
        :key="index"
        class="mb-8"
      >
        <h3 class="text-base font-semibold text-gray-700 mb-4 pt-4 border-t">
          {{ formatDate(group.date) }}
        </h3>
        <div class="space-y-3">
          <RecentChangeItem
            v-for="change in group.changes"
            :key="change.time"
            :change="change"
          />
        </div>
      </div>
    </div>
    <div
      v-else
      class="text-center py-8 bg-gray-50 rounded-lg border border-gray-200"
    >
      <p class="text-sm text-gray-600">
        {{ t('recentChanges.noChangesFound', { days: days }) }}
      </p>
    </div>
  </div>
</template>

<script setup>
import { ref, watch, onUnmounted } from 'vue'
import { useI18n } from 'vue-i18n'

import RecentChangeItem from '@/components/RecentChangeItem.vue'

const { t } = useI18n()

const props = defineProps({
  groupedChanges: {
    type: Array,
    required: true
  },
  days: {
    type: Number,
    required: true
  },
  formatDate: {
    type: Function,
    required: true
  }
})

const emit = defineEmits(['update:days'])

const localDays = ref(props.days)
let debounceTimer = null

function clearDebounceTimer() {
  if (debounceTimer) {
    clearTimeout(debounceTimer)
    debounceTimer = null
  }
}

const handleDaysInput = () => {
  clearDebounceTimer()
  
  // Capture current value to check in timeout
  const currentValue = localDays.value
  
  debounceTimer = setTimeout(() => {
    // Only emit if value hasn't changed (to prevent race conditions)
    if (localDays.value === currentValue) {
      const value = parseInt(localDays.value)
      if (!isNaN(value) && value >= 1 && value <= 365) {
        emit('update:days', value)
      } else {
        // Optionally reset to a valid value or the prop value if invalid
        localDays.value = props.days 
      }
    }
    debounceTimer = null
  }, 300)
}

// Watch for external changes to the 'days' prop
watch(() => props.days, (newVal) => {
  // Clear any pending timeout when prop changes externally
  clearDebounceTimer()
  localDays.value = newVal
})

// Cleanup timer on unmount
onUnmounted(() => {
  clearDebounceTimer()
})
</script>
