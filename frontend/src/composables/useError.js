import { ref, provide, inject } from 'vue'

const ERROR_KEY = Symbol('error')

export function provideError() {
  const error = ref(null)
  const showError = (message, details = null) => {
    error.value = { message, details }
  }
  const clearError = () => {
    error.value = null
  }

  provide(ERROR_KEY, {
    error,
    showError,
    clearError,
  })

  return {
    error,
    showError,
    clearError,
  }
}

export function useError() {
  const context = inject(ERROR_KEY)
  if (!context) {
    throw new Error('useError must be used within a component that has called provideError')
  }
  return context
}
