# Venomancer Assistant

A World of Warcraft addon for Ascension's custom Venomancer class, built for the **Conquest of Azeroth** realm. Organized by form — Spider, Beetle, Weaver, and Vizier each get their own tab, tracker(s), and drag position — plus buff tracking, a venom bar, and a shared mana bar. Everything's draggable, fully configurable, and lockable all at once from a single title-bar button.

## Features

### Spider Form
- **Brood Marks** — tracks your Spider Form stacking buff. Max 5.
- Only shows while Spider Form is active (or while previewing/positioning).
- Configurable icon size, spacing, scale, and growth direction (Right / Left / Up / Down).
- **Early Warning tier**, independent from max-stack effects — get alerted before you actually cap out, with its own threshold and effect set.
- **Max Stack effects**: glow border, pulse/scale bounce, color flash, particle burst, screen-edge flash, and sound — mix and match. Early Warning and Max Stacks each get their own color for the pip/particle effects *and* a separate color for the screen-edge flash specifically.
- Optional "sustain" mode on either tier keeps effects repeating until stacks clear, instead of firing once.
- Dedicated **Preview** buttons on the Early Warning and Max Stacks tabs — each previews at that tab's actual configured threshold, running through the real trigger logic so you see exactly what it'll really look like.

### Beetle Form
- **Exposed Flesh** — tracks the Beetle Form stacking debuff. Max 10. Same tracker engine and options as Brood Marks, on its own sub-tab, with its own independent position/lock/scale.
- **Beetle Defenses** — a cooldown/buff watcher for Harden, Regrow Exoskeleton, Vile Sting, Expulsion, and **Carapace Regeneration** (a stacking buff, up to 3 — shown as a live stack-count badge on its icon).
  - Icon mode (OmniCC-compatible cooldown swipes, with an optional countdown toggle for OmniCC users) or Bar mode (fill/drain).
  - **Grouped** positioning (one drag handle, laid out in a row/column) or **Ungrouped** (each ability gets its own independent drag handle and saved position) — switch anytime, nothing is lost either way.
  - **Multi-mob warning**: tints the Carapace Regeneration icon (and optionally plays a sound) when you're in combat, at or above a configurable number of recent attackers, and Carapace Regeneration isn't currently stacked. Mob count is approximated from the combat log (anything that's hit you in the last few seconds) — there's no reliable way to count nearby-but-not-attacking mobs in this client, so treat it as a close approximation, not an exact pull count.
  - Per-context visibility (solo / party / raid / battleground), each independently toggleable.
- A single master **Enable Beetle Form tracking** switch turns both Exposed Flesh and Beetle Defenses off at once, without losing either one's individual settings.

### Weaver Form / Vizier Form
- Placeholder tabs — nothing's been mapped out mechanically for these yet, so there's no tracker behind them. They only appear in the sidebar once the corresponding form is actually learned, and stay in sync if you respec mid-session (no `/reload` needed).

### Buff Tracking
- **Tome of Ahn'kahet** — tracks the proc talent's buff as its own icon with a cooldown swipe and countdown (toggleable, for OmniCC users who'd otherwise see it twice). Only shown while the buff is actually active, except while unlocked for positioning.
- **Buff Alerts** — three independently configurable uptime alerts:
  - **Missing Venom** — fewer than 2 known venoms currently applied.
  - **Missing Pheromone** — no Pheromone buff active.
  - **Envenomed Weapons** — that buff isn't active.
  
  Each can show as a small icon, on-screen text (own color, border color, size — all draggable), a sound cue, or any combination.

### Venom Bar
- Global — not tied to any one form, since venom application isn't form-locked.
- Automatically scans your spellbook for known Venom spells, cross-checked against known venom spell IDs for reliability — no hardcoded list, so new ones show up on their own.
- **Left-click** a venom to set it as your 1st selection, **right-click** for your 2nd.
- **Keybind** (Key Bindings → Venomancer Assistant → *Apply Selected Venom*) applies your 1st selection, then your 2nd on the next press — alternating with each press.
- **Middle-click** the apply button to cast Remove Venoms directly.
- Minimize to a single button that shows whichever selection is next up, or expand to see and reselect from the full row.
- Growth direction: Right / Left / Up / Down, same as the trackers.

### Mana Bar
- Beetle/Spider/Weaver/Vizier Form all hide your normal mana bar — this shows automatically whenever any of them is active, so it doesn't need a separate copy per form.
- Per-context visibility (solo / party / raid / battleground), low-mana color threshold, numbers/percent/both display.

### Everything Else
- **Master Lock** button in the title bar — locks or unlocks every tracker, bar, and alert at once, overriding their individual states, and updates every "Locked" checkbox across every tab to match immediately.
- Minimap button (toggleable) for quick access to options.
- Custom-styled scrollbar, buttons, and dropdowns throughout — no default Blizzard chrome.
- General tab has a copyable link to this repo for bug reports/feature requests.

## Installation

1. Download the latest release (or clone this repo).
2. Delete any existing `VenomancerAssistant` folder in `Interface\AddOns` first if updating from an older version.
3. Extract/copy the `VenomancerAssistant` folder into your `Interface\AddOns` directory.
4. Restart WoW or `/reload` if it's already running.

## Usage

Open the options panel by clicking the minimap button. There are no slash commands — everything lives in that panel, organized by tab.

### Keybind

Set your Apply Venom keybind under **Key Bindings → Venomancer Assistant** in the standard WoW keybinding UI. No default key is set — bind whatever's comfortable.

## Configuration Notes

- **Brood Marks max (5) and Exposed Flesh max (10)** are fixed, not adjustable — these come directly from the in-game tooltips.
- The **Warning threshold** sliders are intentionally capped below their tracker's max, so an "early" warning can't accidentally overlap with the max-stack effects.
- Settings are stored per-module — each tracker, the Venom Bar, Beetle Defenses, Tome, Buff Alerts, and the Mana Bar each have their own independent position, lock, and scale, even when using Beetle Defenses' Grouped mode for the abilities within it.

## Known Limitations

This addon targets Ascension's custom client, which differs from standard WotLK API in a few places (e.g. `GetSpellTexture` instead of `GetSpellBookItemTexture`). It's been adjusted for the differences found so far, but if you hit an in-game Lua error, please open an issue with the error text — these client-specific quirks are usually a one-line fix once identified.

- Applying a venom works by casting the spell directly via a secure button, the same as clicking it in your spellbook. Changing your venom *selection* while in combat won't take effect until combat ends — that's a hard WoW restriction on secure frames, not a bug.
- The multi-mob warning's attacker count is a combat-log approximation (see Beetle Form above) — it can't detect mobs that haven't attacked you yet.
- Weaver Form and Vizier Form have no tracked mechanics yet — the tabs exist purely so they're ready to fill in once that content is mapped out.

## Contributing

Issues and pull requests welcome. If you're reporting a bug, the in-game Lua error text (if any) is the most useful thing you can include.

## Credits

Made by Falliia ~ Rexxar (Conquest of Azeroth). Iterated extensively based on real in-game testing and feedback.
