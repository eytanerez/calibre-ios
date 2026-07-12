# P4 — Discover deck

First read Docs/specs/shared-rules.md. Your simulator: **iPhone 17**. Derived data: /tmp/dd-p4. Screenshots: scratchpad/p4/.

You own: Calibre/Features/Discover/ only. Replace P2's placeholder root in place.

Kit surface: CatalogStore.browse (view=card, sort popular), CommerceStore watchlist toggle, LocalSignals (pass-list + saved exclusion), AuthSession.require, Nuke ImagePrefetcher.

## The screen

**DiscoverScreen** (tab root) — full-screen card-stack browsing; the signature "its own thing" surface:

- **Stack**: ZStack of top 3 cards; card = large rounded (Radius.overlay) image-forward layout — watch photo fills ~70% (LazyImage, downsampled), bottom panel: Eyebrow brand·year, serif title, price (CalibreType.price), condition pill. Under-cards at scale 0.97/0.94, offset 10/20pt, slightly dimmed.
- **Feed**: DeckFeed model paging /listings (view=card, page_size=24, sort=popular), excluding LocalSignals passed ids and current watchlist ids; refill fetch when ≤8 unseen remain; loop pages until exhausted → warm EmptyState ("You've seen every watch currently live. Check Fresh Arrivals on Home.") with a Reset passes button.
- **Gesture physics** (DragGesture on top card): translation follows finger; rotation = width/20 clamped ±8°; SAVE affordance (top-left, success-tinted capsule) / PASS (top-right, muted capsule) fade in past 40% of commit threshold; commit at |x| > 0.35×width OR predicted end velocity > 800; fly-off 420ms Motion.ease along drag vector; below threshold snap back 220ms. Ease-out ONLY — zero bounce. Next card scales up in sync. Reduce Motion: crossfade instead of fly.
- **Haptics**: .armed (light) exactly once when crossing threshold per drag; .save (medium) on right commit; .pass (soft) on left commit. One haptic per gesture.
- **Actions**: right = save → session.require("Sign in to save watches you love") { watchlist add (optimistic) }; guest pass = local only. Left = pass → LocalSignals. Tap card → PDP route (router .listing(id) — zoom transition source on the card). Bottom control row: pass circle button, undo pill (visible 5s after last action, reverses save via watchlist remove or un-pass), save circle button — mirrors gestures for accessibility.
- **Prefetch**: ImagePrefetcher warms next 6 card images; stop on disappear.
- **Header**: minimal — "Discover" serif small + saved-count ticker chip (count animates via contentTransition(.numericText())).

## Verify
Guest: swipe passes persist (relaunch, same cards don't return), save triggers AuthGateSheet, after sign-in (iosbuyer.calibre@gmail.com / CalibreiOS123!) intent replays and the watch lands in the watchlist (confirm via GET /watchlist curl). Tap-through to PDP route works (PDP itself may still be a placeholder — that's fine, route must fire). Undo restores. Screenshots light+dark: deck resting, mid-drag with SAVE affordance visible, empty state. Read the screenshots and fix visual issues before finishing.
