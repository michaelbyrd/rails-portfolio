# Card Room Design

**Date:** 2026-05-19
**Status:** Approved

## Overview

A real-time multiplayer poker mini-app hosted within the portfolio Rails app. Players visit a table, click a seat, enter a name, and play No Limit Hold'em against other humans or manually-added bots. No accounts, no real money — a fun portfolio demo.

## Architecture

Follows the existing mini-app pattern (mirrors `AudioController` / `CtciController`):

| Layer | Detail |
|---|---|
| Controller | `CardRoomController` with `layout 'card_room'` |
| Views | `app/views/card_room/index.html.erb`, `show.html.erb` |
| Layout | `app/views/layouts/card_room.html.erb` |
| Model | `Table` — slug, name, game_type, max_seats, state (JSON) |
| Channel | `CardRoomChannel` — one subscription per table, keyed by slug |
| Stimulus | `card_room_controller.js` — UI interactions and channel messaging |
| Routes | `GET /card_room` → index, `GET /card_room/:slug` → table |
| Game Engines | `app/models/games/nl_holdem.rb` (and others later) |

All game logic is server-authoritative. Clients send actions; the server validates, mutates state, and broadcasts.

## Data Model

### `tables` table

| Column | Type | Notes |
|---|---|---|
| `slug` | string | unique, auto-generated |
| `name` | string | e.g. "Table 1" |
| `game_type` | string | `"nl_holdem"`, `"pl_omaha"`, `"five_card_funk"` |
| `max_seats` | integer | default 6, configurable |
| `state` | json | all game state (see below) |

### State JSON structure

```json
{
  "status": "waiting",
  "street": "pre_flop",
  "hand_number": 1,
  "dealer_position": 0,
  "current_position": 2,
  "current_bet": 20,
  "min_raise": 40,
  "pot": 30,
  "community_cards": ["Kh", "7s", "2d"],
  "last_action": { "player": "Alice", "action": "raise", "amount": 40 },
  "seats": [
    {
      "position": 0,
      "name": "Alice",
      "stack": 980,
      "bet": 20,
      "hole_cards": ["Ah", "Kd"],
      "status": "active",
      "is_bot": false,
      "session_id": "x7f2k"
    }
  ]
}
```

`hole_cards` are filtered per subscriber in `CardRoomChannel` — each player only receives their own hole cards, all others are omitted.

`session_id` is a random token stored in the browser's `sessionStorage`, used to identify a returning player without authentication.

## Game Engine Pattern

Game-specific logic lives in engine classes under `app/models/games/`:

```
app/models/games/
  nl_holdem.rb
  pl_omaha.rb        # future
  five_card_funk.rb  # future, rules TBD
```

Each engine is responsible for:
- Number of hole cards to deal
- Betting rules (no-limit, pot-limit)
- Hand evaluation
- Valid actions given current state

`Table` delegates to the appropriate engine via `game_type`. Adding a new game means adding a new engine class — no changes to the channel or controller.

## Tables

Tables are seeded via `db/seeds.rb` — persistent, always active, no creation flow needed. The index page lists all tables grouped by game type. Initial seed: 2–3 NL Hold'em tables.

## Entry Flow

1. Player visits `/card_room` — sees a list of tables with seat availability
2. Player clicks a table → `/card_room/:slug`
3. Table view shows seats around the felt. Empty seats have a "Sit Down" affordance; occupied seats show the player name and stack
4. Player clicks an empty seat → name prompt modal → submits → joins that seat
5. Players who don't click a seat are **spectators** — they see the full table (community cards, pot, stacks, actions) but never hole cards
6. When 2+ players are seated the first hand starts automatically
7. Players joining mid-hand sit out until the next hand

## Seat & Disconnect Behavior

- Each seat tracks `session_id` to identify the browser
- If a player's ActionCable connection drops and doesn't reconnect within 30 seconds, their seat is freed
- No bot fills the freed seat automatically — the seat simply becomes available

## Bots

- `Games::Bot` is a plain Ruby class that takes current game state and returns an action
- Pre-flop: hand strength from a lookup table (pocket pairs, suited connectors, etc.)
- Post-flop: simple made-hand ranker (pair, two pair, flush, etc.)
- Decision: strong → bet/raise, medium → call, weak → fold with occasional bluff
- Bots act after a 1–2 second delay so play feels natural
- Bots are added **manually** — a seated player or spectator clicks "Add Bot" on an empty seat
- No automatic seat filling

## UI

### Table view
- Green felt in the center with community cards, pot total, and dealer button (D chip)
- Up to 6 seats arranged around the table
- Your seat (bottom-center by convention) shows your hole cards face-up; all others face-down
- Active seat (waiting for action) highlighted with a colored border
- Action bar at the bottom when it's your turn: **Fold** / **Check or Call** / **Raise** (with bet input)

### Index view
- Tables listed by game type
- Each table shows name, seats taken / max seats, current status (waiting / hand in progress)

## State Machine

```
waiting
  └─(2+ players seated)──► pre_flop
                               └─(betting round complete)──► flop
                                                               └─► turn
                                                                     └─► river
                                                                           └─► showdown
                                                                                 └─(3s delay)──► hand_over
                                                                                                    └─(2+ players remain)──► pre_flop
any street ──(all but one fold)──► hand_over
```

## Testing

- Unit tests on game engine: dealing, hand evaluation, bet validation, state transitions
- Unit tests on bot decision logic
- No channel/integration tests in initial implementation
