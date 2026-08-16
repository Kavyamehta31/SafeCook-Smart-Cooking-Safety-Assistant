# SafeCook — Antigravity Project Context

## PROJECT
SafeCook — Smart Cooking Safety Assistant (Flutter, Android)
Physical hardware: Samsung Galaxy S23 FE + HC-05 Bluetooth stove sensor.

## STATUS
- Phase 0–3: Verified (voice, BT, recipe nav, step flow)
- Phase 4A: Verified (SafetyEngine, gas/distance alerts, hysteresis, TTS interruption)
- Phase 4B: Runtime bug fix in progress

## AUTHORITATIVE STATE OWNERS
| Concern | Owner |
|---------|-------|
| Conversation / session state | `SafeCookAgent` (singleton) |
| Cooking step index | `SafeCookSessionMemory` inside agent |
| Safety decisions | `SafeCookSafetyEngine` (deterministic) |
| Safety voice | `SafetyVoiceController` |
| Bluetooth hardware | Existing BT service / native layer |
| AI fallback | `AIProvider` (NOT authoritative) |

## SAFETY RULE
Safety-critical operations are NEVER delegated to or executed by an LLM.
AI-generated tool calls must pass through authoritative SafeCook handlers.

## ROUTING ARCHITECTURE
```
NLU → deterministic handler
    → local knowledge/context resolution
    → specific safety semantic routing (if query maps to a safety intent)
    → AIProvider (last resort for conversational queries only)
    → validate AI tool call → authoritative handler
```
`_isSafetyRelated()` must be a ROUTER, not a BLOCKER.

## AI PROVIDER
- Default: `LocalMockAIProvider` (offline, deterministic)
- Optional: `GeminiAIProvider` — requires `GEMINI_API_KEY` via secure runtime config
- Platform.environment does NOT work in released Android APKs
- Log `[SafeCook AI] provider=Gemini` ONLY when Gemini is actually configured

## TEST BASELINE
94 tests passing (as of Phase 4B end). Do not break any.

## DO NOT IMPLEMENT
Phase 5+ until explicitly approved.

## HC-05 DEVICE PRIORITY
1. Exact "hc-05" → 2. "hc05" → 3. contains "hc-05" → 4. contains "hc05" → 5. "stove" → 6. "sensor"
No blind fallback to first bonded device.

## GAS CALIBRATION
Raw ADC 50 → 0%, Raw ADC 900 → 100%.
Hysteresis: gas drop ≥3%, distance increase ≥2cm.
