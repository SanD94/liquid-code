# Agent Guidance

## Priorities

1. Preserve predictable session lifecycle behavior before adding features.
2. Prefer bounded output and saved artifacts over verbose inline responses.
3. Keep the protocol stable across backends.
4. Treat manifests, checkpoints, and logs as first-class product artifacts.

## Milestone Discipline

- Build in milestone order from `docs/liquid-code-bdd.md`.
- Do not skip health, eval, shutdown, and manifest reliability to chase advanced features.
- Keep server behavior explicit and debuggable rather than clever or self-modifying.
- When a runtime has large outputs, summarize the shape and point callers to artifacts.

## Implementation Style

- Favor small, inspectable scripts and server templates.
- Keep backend-specific behavior behind the shared contract in `protocol/CONTRACT.md`.
- Session directories must be self-contained enough to inspect failures after the runtime exits.
