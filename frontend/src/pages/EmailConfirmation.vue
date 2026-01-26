<template>
  <!-- Loading State -->
  <LoadingSpinner v-if="isLoading">
    {{ t('emailConfirmation.loading') }}
  </LoadingSpinner>

  <!-- Success State -->
  <div v-else-if="success" class="text-center">
    <div class="bg-white p-8 rounded-lg shadow-sm border border-green-200">
      <div class="w-16 h-16 bg-green-100 rounded-full flex items-center justify-center mx-auto mb-4">
        <svg class="w-8 h-8 text-green-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2" d="M5 13l4 4L19 7" />
        </svg>
      </div>
      <h2 class="text-2xl font-bold text-gray-800 mb-2">
        {{ t('emailConfirmation.successTitle') }}
      </h2>
      <p class="text-gray-600 mb-6">
        {{ t('emailConfirmation.successMessage') }}
      </p>
      <div class="space-y-3">
        <RouterLink to="/" class="btn-get w-full block text-center">
          {{ t('emailConfirmation.goToHomepage') }}
        </RouterLink>
        <RouterLink to="/login" class="btn-create w-full block text-center">
          {{ t('emailConfirmation.logIn') }}
        </RouterLink>
      </div>
    </div>
  </div>

  <!-- Error State -->
  <div v-else-if="error" class="text-center">
    <div class="bg-white p-8 rounded-lg shadow-sm border border-red-200">
      <div class="w-16 h-16 bg-red-100 rounded-full flex items-center justify-center mx-auto mb-4">
        <svg class="w-8 h-8 text-red-600" fill="none" stroke="currentColor" viewBox="0 0 24 24">
          <path stroke-linecap="round" stroke-linejoin="round" stroke-width="2"
            d="M12 8v4m0 4h.01M21 12a9 9 0 11-18 0 9 9 0 0118 0z" />
        </svg>
      </div>
      <h2 class="text-2xl font-bold text-gray-800 mb-2">
        {{ t('emailConfirmation.failedTitle') }}
      </h2>
      <p class="text-red-600 mb-6">
        {{ error }} <!-- Keep error message as is, it's dynamic -->
      </p>
      <div class="space-y-3">
        <RouterLink to="/" class="btn-get w-full block text-center">
          {{ t('emailConfirmation.returnHome') }}
        </RouterLink>
        <button v-if="isExpired" class="btn-create w-full" :disabled="isRequestingToken" @click="requestNewToken">
          {{ isRequestingToken ? t('emailConfirmation.sending') : t('emailConfirmation.requestNewToken') }}
        </button>
      </div>
    </div>
  </div>

  <!-- Request Success Message -->
  <div v-if="requestSuccess" class="mt-4 p-4 bg-blue-50 text-blue-700 rounded-lg text-center">
    {{ t('emailConfirmation.requestSuccess') }}
  </div>
</template>

<script setup>
import { ref, onMounted, computed } from 'vue'
import { useI18n } from 'vue-i18n'
import { useRoute } from 'vue-router'

import { confirmEmail, resendConfirmation } from '@/api'
import LoadingSpinner from '@/components/LoadingSpinner.vue'
import { useSeoHead } from '@/composables/useSeoHead'

const { t, locale } = useI18n()

// State
const isLoading = ref(true)
const success = ref(false)
const error = ref('')
const isExpired = ref(false)
const isRequestingToken = ref(false)
const requestSuccess = ref(false)


const route = useRoute()

const pageTitle = computed(() => {
  if (isLoading.value) return t('emailConfirmation.loading')
  if (success.value) return t('emailConfirmation.successTitle')
  if (error.value) return t('emailConfirmation.failedTitle')
  return t('emailConfirmation.successTitle') // Default or fallback title
})

useSeoHead({ title: pageTitle }, locale.value)

const confirmEmailToken = async (token) => {
  try {
    const response = await confirmEmail(token)

    // Check for success field, or if response has message and no error, treat as success
    if (response.data.success === true || (response.data.message && !response.data.error)) {
      success.value = true
    } else {
      error.value = response.data.error || 'Failed to confirm email'
      isExpired.value = response.data.error?.includes('expired')
    }
  } catch (err) {
    // Handle HTTP error responses (4xx, 5xx)
    if (err.response?.data?.error) {
      error.value = err.response.data.error
      isExpired.value = err.response.data.error.includes('expired')
    } else {
      error.value = t('emailConfirmation.errorConfirming')
    }
  } finally {
    isLoading.value = false
  }
}

const requestNewToken = async () => {
  if (!route.query.email) {
    error.value = t('emailConfirmation.errorEmailRequired')
    return
  }

  isRequestingToken.value = true
  requestSuccess.value = false

  try {
    const response = await resendConfirmation(route.query.email)

    if (response.data.success) {
      requestSuccess.value = true
      isExpired.value = false
      error.value = ''
    } else {
      error.value = response.data.error || t('emailConfirmation.errorRequestingToken')
    }
  } catch (err) {
    if (err.response?.status === 429) {
      error.value = t('emailConfirmation.errorRateLimit')
    } else {
      error.value = t('emailConfirmation.errorRequestingToken')
    }
  } finally {
    isRequestingToken.value = false
  }
}

onMounted(() => {
  const token = route.query.token
  if (!token) {
    error.value = t('emailConfirmation.errorNoToken')
    isLoading.value = false
    return
  }

  confirmEmailToken(token)
})
</script>
