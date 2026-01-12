<template>
  <button :class="buttonClasses">
    <slot name="icon">
      <CirclePlus :class="iconClasses" />
    </slot>
    <span>{{ label }}</span>
  </button>
</template>

<script setup>
  import { CirclePlus } from 'lucide-vue-next'

  defineProps({
    label: {
      type: String,
      required: true,
    },
    buttonClasses: {
      type: String,
      default: 'btn-aqua-green',
    },
    iconClasses: {
      type: String,
      default: 'h-4 w-4'
    }
  })
</script>

<style scoped>
  button {
    @apply inline-flex items-center gap-2 w-auto md:flex-none;
  }
</style>
