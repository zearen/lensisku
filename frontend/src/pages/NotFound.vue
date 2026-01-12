<template>
  <div class="text-center py-20">
    <h1 class="text-4xl font-bold mb-4">404 - Page Not Found</h1>
    <p class="text-gray-600 mb-8">The page you're looking for doesn't exist.</p>
    <RouterLink 
      to="/" 
      class="btn-aqua-blue px-6 py-2 text-lg"
    >
      Return Home
    </RouterLink>
  </div>
</template>

<script setup>
import { RouterLink } from 'vue-router';
</script>
