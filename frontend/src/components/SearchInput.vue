<script setup>
import { Loader2, X } from 'lucide-vue-next'
import { useI18n } from 'vue-i18n'

const { t } = useI18n()

defineProps({
  modelValue: {
    type: String,
    default: ''
  },
  isLoading: {
    type: Boolean,
    default: false
  },
  placeholder: {
    type: String,
    default: '',
  }
})

defineEmits(['update:modelValue', 'clear'])
</script>

<template>
  <div class="relative flex-1">
    <input
      :value="modelValue"
      type="text"
      :placeholder="placeholder"
      class="input-field w-full min-w-[200px]"
      :class="{ 'pr-10': modelValue.length > 0 }"
      @input="$emit('update:modelValue', $event.target.value)"
    >
    <div class="absolute right-3 top-1">
      <Loader2
        v-if="isLoading"
        class="mt-1 h-4 w-4 text-gray-500 animate-spin"
      />
      <button
        v-else-if="modelValue"
        class="text-gray-400 hover:text-gray-600"
        @click="$emit('clear')"
      >
        <X class="mt-1 h-4 w-4" />
      </button>
    </div>
  </div>
</template>
