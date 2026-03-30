# Vue + eslint

> Extends `modules/code-quality/eslint.md` with Vue-specific integration.
> Generic eslint conventions (flat config, TypeScript setup, CI integration) are NOT repeated here.

## Integration Setup

```bash
npm install --save-dev eslint eslint-plugin-vue vue-eslint-parser typescript-eslint
```

**`eslint.config.js` for Vue + TypeScript:**
```js
import tseslint from "typescript-eslint";
import pluginVue from "eslint-plugin-vue";
import vueParser from "vue-eslint-parser";

export default tseslint.config(
  ...tseslint.configs.recommendedTypeChecked,
  ...pluginVue.configs["flat/recommended"],
  {
    files: ["**/*.vue"],
    languageOptions: {
      parser: vueParser,
      parserOptions: {
        parser: tseslint.parser,
        project: "./tsconfig.json",
        extraFileExtensions: [".vue"],
      },
    },
  },
  {
    rules: {
      "vue/component-api-style": ["error", ["script-setup"]],   // enforce <script setup>
      "vue/define-macros-order": ["error", { order: ["defineOptions", "defineProps", "defineEmits", "defineExpose"] }],
      "vue/block-order": ["error", { order: ["script", "template", "style"] }],
    },
  }
);
```

## Framework-Specific Patterns

### `<script setup>` enforcement

`vue/component-api-style: ["error", ["script-setup"]]` bans Options API and Composition API without `<script setup>`. New components must use the Composition API + `<script setup>` syntax:

```vue
<!-- BAD — Options API -->
<script>
export default { data() { return { count: 0 } } }
</script>

<!-- GOOD -->
<script setup lang="ts">
const count = ref(0);
</script>
```

### Composition API rules

`eslint-plugin-vue` includes rules for Composition API patterns:

```js
rules: {
  "vue/no-ref-as-operand": "error",        // prevents `if (myRef)` instead of `if (myRef.value)`
  "vue/prefer-import-from-vue": "error",   // use `import { ref } from 'vue'` not from sub-packages
  "vue/require-typed-ref": "error",        // require typed refs: ref<string>('')
}
```

### Essential vs. recommended presets

Use `flat/recommended` (superset of `flat/essential`) for new projects. For legacy codebases, start with `flat/essential` and incrementally enable rules.

## Additional Dos

- Enable `vue/block-order` to enforce `<script>` before `<template>` before `<style>` — consistent block order improves readability.
- Use `vue/define-macros-order` to standardize `defineProps`/`defineEmits` order within `<script setup>`.

## Additional Don'ts

- Don't mix `vue/component-api-style: ["error", ["composition"]]` with `["script-setup"]` — pick one style across the project.
- Don't skip `extraFileExtensions: [".vue"]` in `parserOptions` — TypeScript-aware rules won't process `.vue` SFC blocks without it.
