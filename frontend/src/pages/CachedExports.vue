<script setup>
import { File } from 'lucide-vue-next'
import { ref, onMounted } from 'vue'
import { useI18n } from 'vue-i18n'

import { listCachedExports, downloadCachedExport } from '@/api'
import { useSeoHead } from '@/composables/useSeoHead'
import { useError } from '@/composables/useError'

const { t, locale } = useI18n()

useSeoHead({ title: t('cachedExports.title') }, locale.value)

const exports = ref([])
const isLoading = ref(true)
const { showError } = useError()

const formatDate = (dateString) => {
  const date = new Date(dateString)
  return date.toLocaleDateString(locale.value, {
    year: 'numeric',
    month: 'long',
    day: 'numeric',
    hour: '2-digit',
    minute: '2-digit',
  })
}

const downloadExport = async (exportItem) => {
  try {
    const response = await downloadCachedExport(exportItem.language_tag, exportItem.format)

    // Create download link
    const url = window.URL.createObjectURL(new Blob([response.data]))
    const link = document.createElement('a')
    link.href = url
    link.setAttribute('download', exportItem.filename)
    document.body.appendChild(link)
    link.click()
    link.remove()
  } catch (err) {
    showError(err.response?.data?.error || t('cachedExports.downloadError'))
  }
}

onMounted(async () => {
  try {
    const response = await listCachedExports()
    exports.value = response.data
  } catch (err) {
    showError(err.response?.data?.error || t('cachedExports.loadError'))
    } finally {
      isLoading.value = false
    }
  })
</script>

<template>
  <h1 class="text-2xl font-bold text-gray-800 mb-6">
    {{ t('cachedExports.title') }}
  </h1>

  <div v-if="isLoading" class="flex justify-center py-8">
    <div class="animate-spin rounded-full h-8 w-8 border-b-2 border-blue-600" />
  </div>

  <div v-else>
    <div v-if="exports.length === 0" class="text-center py-12 bg-blue-50 rounded-lg border border-blue-100">
      <File class="mx-auto h-12 w-12 text-blue-400" />
      <p class="mt-4 text-gray-600">
        {{ t('cachedExports.noExports') }}
      </p>
    </div>

    <div v-else class="bg-white shadow-sm rounded-lg overflow-hidden">
      <div class="divide-y divide-gray-200">
        <div v-for="exportItem in exports" :key="`${exportItem.language_tag}-${exportItem.format}`"
          class="p-4 hover:bg-gray-50 cursor-pointer" @click="downloadExport(exportItem)">
          <div class="flex items-center justify-between">
            <div>
              <div class="font-medium text-gray-900">
                {{ exportItem.language_realname }} - {{ exportItem.format.toUpperCase() }}
              </div>
              <div class="text-sm text-gray-500">
                {{ formatDate(exportItem.created_at) }}
              </div>
            </div>
            <div class="text-sm text-gray-500">
              <button class="btn-get">
                {{ t('cachedExports.download') }}
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>

