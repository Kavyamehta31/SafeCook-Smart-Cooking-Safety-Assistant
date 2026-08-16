# SafeCook Copilot Instructions

## PROJECT

SafeCook is a Flutter Android smart cooking safety assistant combining:

- voice interaction
- recipe guidance
- Bluetooth HC-05 stove/sensor hardware
- gas sensing
- chef-to-vessel distance sensing
- deterministic safety intelligence
- conversational AI

## CURRENT ARCHITECTURE

These are the authoritative components in SafeCook:

- SafeCookAgent → authoritative conversation and session control
- SafeCookSessionMemory → authoritative cooking step index and session state
- SafeCookSafetyEngine → authoritative safety decisions
- SafetyVoiceController → safety voice presentation and interruption
- Bluetooth implementation → authoritative hardware connection and state
- AIProvider → conversational/general-knowledge layer only

## SAFETY PRINCIPLE

AI is never authoritative over:

- gas safety
- chef-to-vessel distance
- SafetyEngine state
- Bluetooth
- cooking session lifecycle
- recipe step index
- hardware actions
- safety-critical actions

AI-generated tool calls must pass through authoritative SafeCook handlers.

## DEVELOPMENT PRINCIPLE

Prefer:

- deterministic command → deterministic handler

Over:

- LLM interpretation

Use AI only when deterministic routing cannot resolve the request.

## CODE QUALITY

When modifying code:

- preserve existing behavior
- make targeted changes
- do not rewrite entire files unnecessarily
- do not create duplicate state owners
- do not remove working hardware functionality
- do not introduce unnecessary dependencies
- keep architecture modular

## TESTING

Before considering work complete:

- flutter analyze
- flutter test
- flutter build apk --debug

Existing tests must not be weakened or deleted.
Test observable behavior rather than implementation details.

## SECURITY

- Never commit API keys.
- Never place API keys in Dart source, ANTIGRAVITY.md, README.md, GitHub, or logs.
- Never print secrets.

## GIT SAFETY

Never run:

- git reset --hard
- git restore .
- git clean -fd

unless the user explicitly requests it.
Never discard existing uncommitted work.

## PHASE CONTROL

- Do not implement future phases unless explicitly requested.
- When a task is scoped to a specific phase, remain within that phase.

## TOKEN EFFICIENCY

- Read ANTIGRAVITY.md before large exploration.
- Inspect only relevant files.
- Prefer targeted edits.
- Do not repeatedly reread the entire repository.
- Do not create unnecessary subagents.
- Do not repeatedly run expensive full-suite verification after every tiny edit.
- Keep progress reports concise.
