import { ref, unref, computed } from 'vue'
import { useHead } from '@vueuse/head'
import { useI18n } from 'vue-i18n'


type MetaTag = {
  name?: string
  property?: string
  content: string
  key?: string
}

type SeoConfig = {
  title: string | ReturnType<typeof ref<string>>
  meta?: MetaTag[]
}

export function useSeoHead(config: SeoConfig) {
  const i18n = useI18n()
  const baseTitle = computed(() => i18n.t('seo.baseTitle'))

  const resolvedTitle = computed(() => {
    const title = unref(config.title)
    return title ? `${title} | ${baseTitle.value}` : baseTitle.value
  })

  const ogTags = computed<MetaTag[]>(() => [
    { property: 'og:title', content: resolvedTitle.value },
    { property: 'og:site_name', content: baseTitle.value },
    { property: 'og:type', content: 'website' }
  ])

  const metaTags = computed(() => [
    ...ogTags.value,
    ...(config.meta || [])
  ])

  useHead({
    title: resolvedTitle,
    meta: metaTags,
    htmlAttrs: {
      lang: i18n.locale.value
    }
  })

  // Fallback for direct title manipulation
  if (typeof document !== 'undefined') {
    document.title = resolvedTitle.value
  }
}