# Framework Gotchas

Non-obvious conventions per framework. Referenced from CLAUDE.md. Each framework's full conventions are in `modules/frameworks/{name}/conventions.md`.

All 21 share the same base structure. Non-obvious conventions only:

- **spring**: Kotlin variant = hexagonal arch, sealed interfaces, ports & adapters. `@Transactional` on use case impls only. `web` and `persistence` are independent choices.
- **react**: Typography via `style={{ fontSize }}` not Tailwind. Colors via tokens. Error Boundaries at route level.
- **embedded**: No `malloc`/`printf`/`float` in ISR. `volatile` for shared vars.
- **k8s**: `language: null`. Pin images to SHA.
- **swiftui**: `[weak self]` in stored closures. SPM over CocoaPods.
- **angular**: Standalone components, signals, OnPush, NgRx SignalStore.
- **nestjs**: Module DI, Pipes/Guards/Interceptors.
- **vue**: Composition API + `<script setup>`, Pinia, Nuxt auto-imports.
- **svelte**: Svelte 5 runes, standalone SPAs (distinct from SvelteKit).
