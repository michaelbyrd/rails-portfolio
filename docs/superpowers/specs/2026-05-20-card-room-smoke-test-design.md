# Card Room Smoke Test Design

**Date:** 2026-05-20
**Scope:** Integration smoke test — 1 human player vs 1 bot, 2 full hands, full channel stack

## What This Tests

End-to-end flow through `CardRoomChannel` → `Table` → `Games::NlHoldem` → `BotActionJob` / `NextHandJob`. Confirms the pieces assembled during the debugging session work together correctly under realistic play conditions.

## File

`spec/channels/card_room_smoke_spec.rb`

## Setup

- `subscribe` as the human player (`session_id: 'human_session'`)
- Send `join_seat` then `add_bot` via `perform :receive`
- Channel auto-starts the hand via `Table#add_bot → start_hand!`

## Helpers

**`drive_to_hand_over`** — loops up to 50 iterations:
- Reloads table state each iteration
- Breaks on `street == 'hand_over'`
- Bot's turn → `BotActionJob.perform_now(table.slug, current_pos)`
- Human's turn → `perform :receive` with `call` or `check` depending on current bet

**`deal_next_hand`** — calls `NextHandJob.perform_now(table.slug)`, reloads table

## Individual Tests

| # | Description | Key assertion |
|---|---|---|
| 1 | Auto-starts after seating 1 player + 1 bot | `status == 'playing'`, `street == 'pre_flop'` |
| 2 | Both players receive hole cards | human and bot seats each have 2 cards |
| 3 | Hand completes and pot is awarded | `street == 'hand_over'`, `pot == 0` |
| 4 | Chip total is conserved across 2 hands | `seats.sum(:stack)` equals initial total |
| 5 | Dealer button advances between hands | `dealer_position` differs hand 1 vs hand 2 |
| 6 | Public stream broadcasts have masked opponent cards | all occupied seats in broadcast have `['??','??']` |
| 7 | Human's personal stream contains real hole cards | personal stream broadcast shows human's actual cards |

## Bot Turn Driving

Manual `BotActionJob.perform_now` (not job queue drain). Transparent, fast, deterministic. BotActionJob's `with_lock` guard handles any double-call edge cases cleanly.

## Human Turn Actions

Always `call` if facing a bet, `check` otherwise. Deterministic, exercises the call/check paths, avoids fold-and-done scenarios that end hands too quickly to test street progression.

## Out of Scope

- Channel error paths (invalid action, missing table)
- Multi-player scenarios
- ReleaseSeatJob / disconnect handling
