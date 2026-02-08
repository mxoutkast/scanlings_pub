# Scanlings

Camera-driven creature creator + competitive auto-battler (Supercell-style clarity).

**Locked stack:** Godot **4.2 LTS** (Android client) + TypeScript (backend on Render).

## What it is
Scan real-world objects to generate cute/cool collectible creatures. Creatures are **archetype-first** (readability) and battle via a **turn-based server-simulated auto-battler**. Fusion uses a second scan to evolve a creature and can unlock a passive (Star Power/Gadget).

## Key docs
- Product / design: [`PRD_GDD.md`](./PRD_GDD.md)
- Architecture overview: [`ARCHITECTURE.md`](./ARCHITECTURE.md)
- Backend API contract: [`API_SPEC.md`](./API_SPEC.md)
- MVP enforcement knobs (Sacred 8, catalogs): [`BACKEND_CONFIG.md`](./BACKEND_CONFIG.md)
- Archetypes (Sacred 8 + future): [`ARCHETYPES.md`](./ARCHETYPES.md)
- MVP boundaries: [`MVP_SCOPE.md`](./MVP_SCOPE.md)
- MVP catalog (single source of truth): [`MVP_CATALOG.json`](./MVP_CATALOG.json)
- Maintenance / anti-drift: [`MAINTENANCE.md`](./MAINTENANCE.md)
- Demo script: [`DEMO_SCRIPT.md`](./DEMO_SCRIPT.md)
- End-to-end API example: [`E2E_EXAMPLE.md`](./E2E_EXAMPLE.md)
- Silhouette + passive catalogs: [`SILHOUETTES_AND_PASSIVES.md`](./SILHOUETTES_AND_PASSIVES.md)
- Telegraph system + cue library: [`TELEGRAPH_SYSTEM.md`](./TELEGRAPH_SYSTEM.md), [`TELEGRAPH_CUE_LIBRARY.md`](./TELEGRAPH_CUE_LIBRARY.md)
- Art pipeline (Virtual Vinyl + masks + prompts):
  - [`ART_PIPELINE_VIRTUAL_VINYL.md`](./ART_PIPELINE_VIRTUAL_VINYL.md)
  - [`MASK_ASSET_SPEC.md`](./MASK_ASSET_SPEC.md)
  - [`PROMPT_TEMPLATES.md`](./PROMPT_TEMPLATES.md)

## Status
Docs-first design phase. Backend scaffold exists locally (not pushed unless needed).
