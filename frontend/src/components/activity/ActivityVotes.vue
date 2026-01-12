<template>
  <div class="space-y-4">
    <div
      v-if="votes.length === 0"
      class="text-center py-8 bg-gray-50 rounded-lg"
    >
      <Vote class="mx-auto h-12 w-12 text-blue-400" />
      <p class="text-gray-600">
        {{ t('components.activityVotes.noVotes') }}
      </p>
    </div>
    <div
      v-for="vote in votes"
      v-else
      :key="`${vote.definition_id}-${vote.voted_at}`"
      class="bg-white p-4 rounded-lg border hover:border-blue-300 transition-colors break-words"
    >
      <RouterLink
        :to="`/valsi/${vote.valsi_word}?highlight_definition_id=${vote.definition_id}`"
        class="block"
      >
        <div class="flex items-center gap-2 mb-2">
          <h3 class="text-lg font-semibold text-blue-700 break-words overflow-hidden">
            {{ vote.valsi_word }}
          </h3>
          <span
            class="text-sm px-2 py-0.5 rounded-full shrink-0"
            :class="vote.vote_value > 0 ? 'bg-green-100 text-green-700' : 'bg-red-100 text-red-700'"
          >
            {{ vote.vote_value > 0 ? '+1' : '-1' }}
          </span>
        </div>
        <div class="text-sm text-gray-600 mb-2 break-words overflow-hidden">
          {{ t('components.activityVotes.inLanguage', { language: vote.language }) }}
        </div>
        <div class="prose max-w-none mb-4 break-words overflow-hidden">
          <LazyMathJax :content="vote.definition" />
        </div>
        <div class="text-sm text-gray-500">
          {{ formatDate(vote.voted_at) }}
        </div>
      </RouterLink>
    </div>
  </div>
</template>

<script setup>
import { Vote } from 'lucide-vue-next';
import { useI18n } from 'vue-i18n';

import LazyMathJax from '@/components/LazyMathJax.vue';

const { t } = useI18n();

defineProps({
  votes: {
    type: Array,
    required: true
  },
  formatDate: {
    type: Function,
    required: true
  }
})
</script>
