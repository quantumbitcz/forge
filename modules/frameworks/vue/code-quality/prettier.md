# Vue + prettier

> Extends `modules/code-quality/prettier.md` with Vue-specific integration.
> Generic prettier conventions (installation, `.prettierrc`, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev prettier @prettier/plugin-xml
# Vue SFC formatting (handles <template>, <script setup>, <style>)
# Prettier natively supports .vue files since v2 — no extra plugin needed
# For Tailwind class ordering in Vue:
npm install --save-dev prettier-plugin-tailwindcss
```

**`.prettierrc` for Vue:**
```json
{
  "semi": false,
  "singleQuote": true,
  "printWidth": 120,
  "tabWidth": 2,
  "trailingComma": "es5",
  "vueIndentScriptAndStyle": true
}
```

## Framework-Specific Patterns

### `vueIndentScriptAndStyle`

Setting `vueIndentScriptAndStyle: true` indents the content of `<script>` and `<style>` blocks relative to the SFC root — matches the Vue community default:

```vue
<!-- vueIndentScriptAndStyle: true -->
<script setup lang="ts">
  const count = ref(0);
</script>

<style scoped>
  .counter { font-size: 1.5rem; }
</style>
```

### Block ordering with Prettier + ESLint

Prettier handles visual formatting; `eslint-plugin-vue`'s `vue/block-order` rule enforces `<script>` → `<template>` → `<style>` block order. These don't conflict — both run independently.

### `singleQuote` in Vue SFCs

The Vue community defaults to single quotes in `<script setup>` (following the JavaScript convention) and double quotes in `<template>` HTML attributes. Prettier's `singleQuote: true` applies to JS/TS blocks only; HTML attributes always use double quotes regardless.

## Additional Dos

- Include `.vue` in Prettier's glob: `prettier --write "src/**/*.{ts,vue,css,scss}"`.
- Use `vueIndentScriptAndStyle: true` to match the Vue community style guide recommendation.

## Additional Don'ts

- Don't configure `htmlWhitespaceSensitivity: "ignore"` for Vue templates — it strips meaningful inline whitespace in rendered text nodes.
- Don't run Prettier and a Vue formatter (e.g., Volar format) in pre-commit — pick one formatter to avoid conflicts.
