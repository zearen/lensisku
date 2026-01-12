<template>
  <button
    class="inline-flex items-center justify-center btn-empty"
    :title="title"
    @click.stop="copyToClipboard"
  >
    <ClipboardCopy class="w-4 h-4" />
  </button>

  <ToastFloat
    :show="showToast"
    :message="toastMessage"
    :type="toastType"
    @close="showToast = false"
  />
</template>

<script setup>
  import { ClipboardCopy } from 'lucide-vue-next'
  import { ref } from 'vue'

  import ToastFloat from './ToastFloat.vue'

  const props = defineProps({
    content: {
      type: String,
      required: true,
    },
    title: {
      type: String,
      default: 'Copy to clipboard',
    },
  })

  const emit = defineEmits(['copied', 'error'])

  const showToast = ref(false)
  const toastMessage = ref('')
  const toastType = ref('success')

  const copyToClipboard = async () => {
    try {
      await navigator.clipboard.writeText(props.content)
      showToast.value = true
      toastMessage.value = 'Copied to clipboard!'
      toastType.value = 'success'
      emit('copied')
    } catch (err) {
      console.error('Failed to copy:', err)
      showToast.value = true
      toastMessage.value = t('components.error.failedToCopy')
      toastType.value = 'error'
      emit('error', err)
    }
  }
</script>
