export interface WikiArticle {
  title: string
  extract: string
  pageid: number
  canonicalurl: string
  url?: string
  thumbnail?: {
    source: string
    width: number
    height: number
  }
}
