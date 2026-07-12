# P7 — Activity, Push, Support, You-tab

First read Docs/specs/shared-rules.md AND mobile-api.md (devices, push payload contract, support chat, watch requests, notification preferences, orders). Your simulator: **iPhone 16e**. Derived data: /tmp/dd-p7. Screenshots: scratchpad/p7/.

You own: Calibre/Features/Activity/, Orders/, Support/, Requests/, Profile/ + the push plumbing files in Calibre/App/ (PushCoordinator.swift, AppDelegate additions — coordinate: these are shared-adjacent; you are the ONLY track allowed to touch Calibre/App/ and ONLY for push registration/routing + replacing the Activity/You placeholder roots' wiring if needed). Test account: iosbuyer.calibre@gmail.com / CalibreiOS123!.

## Build

### 1. Activity tab root
SegmentedTabs: **Offers / Orders / Alerts**. Offers segment embeds the exported OffersListScreen from Features/Offers (do not rebuild). Badge counts on the tab icon (open offers needing action + undelivered orders).

### 2. Orders
- **OrdersListScreen**: stat tiles row (In progress / Delivered — quiet, not SaaS-y), search field (order #/title, debounced), status filter menu (human labels), paginated rows: thumb, title, order number + date, human status summary sentence, grand total serif, StatusBadge; actions contextual (Rate seller when delivered, View).
- **OrderDetailScreen** (route .order(id)): status hero (serif human headline per status — "Your watch is at authentication." / "It's on its way to you."); awaiting-wire banner w/ CountdownChip + wire instructions link; **ProgressCheckpoints** (Shipped to authentication → At authentication → Authentication complete → Shipped to you → Delivered) with animated fill; listing card; shipping address SpecList; **Authentication result card** when present (pass: success CalloutBand "Authenticated by our watchmakers" + notes; fail: destructive tone + "Our team will follow up by email"); **Shipment tracker** (carrier, tracking + copy, ShippingEvents timeline, link out to carrier); **Receipt** SpecList (price/shipping/card fee/tax/total); **Rate the seller** when delivered (StarRating input + comment ≤2000 → POST review; show submitted state after). Auto-refresh 60s while in transit. Buyer cancel button only in cancellable states (confirm dialog).

### 3. Alerts inbox
Local inbox of received push payloads (persist last 100 in a small store in your dir): rows (icon tile by category, title, body, relative time, unread dot), tap → deep-link route; "Mark all read". EmptyState ("Nothing yet. We'll nudge you the moment something needs you."). Populate from PushCoordinator (below) and — DEBUG — a generator button to inject samples.

### 4. Push plumbing
- AppDelegate adapter (UIApplicationDelegateAdaptor): registerForRemoteNotifications flow; UNUserNotificationCenter delegate: foreground pushes → ToastCenter toast with tap-through (never system banner in-app); background tap → route.
- **PushCoordinator**: pre-permission moment — a SheetScaffold shown at the first high-signal event (first save, offer sent, or listing submitted; NOT at launch): "Know the second the seller responds." + Enable / Not now (remember). On grant → device token → POST /account/devices {token, platform: "ios", environment: "sandbox"}; DELETE on logout. Payload contract: route string per mobile-api.md → parse to Route → AppRouter.open (cold-start stash until root ready).
- **Verify with simulated pushes**: xcrun simctl push <sim> com.buycalibre.calibre payload.json for each route type (offer/{id}, order/{id}, listing/{id}, support, alerts) — cold, background, foreground; confirm routing + inbox capture.

### 5. Support chat
**SupportChatScreen** (route .supportChat; entries: You tab row + "Contact us" spots): bubble thread (customer trailing/primary-tint, Calibre leading/card + "Calibre · {time}" caption), composer (TextField ≤4000, send button, Enter sends), poll every 20s while visible; **guest support works**: email capture field on first message ("So we can reply"), persist guest token (UserDefaults) per contract; signed-in uses the user thread. Header: "Message Calibre — we typically reply within a day."

### 6. Watch sourcing requests (buyer side)
**RequestsScreen** (You tab row): list (brand/model/ref/year/budget, Active/Sourced StatusBadge, "View match" when fulfilled → listing route, delete w/ confirm) + **New request** sheet (Brand required, Model, Reference, Year, Max budget, Notes → POST) with warm intro line ("Tell us what you're hunting. Sellers see open requests and list against them.").

### 7. You tab — real screens (replace P2 placeholder rows)
- **ProfileScreen**: header (AvatarInitial, @username, member since, email), stat tiles (Orders/Saved/Offers → routes). Sections: Login info (email/username display, Change password form w/ current+new+rules), Addresses (list, add/edit/delete forms, default shipping/billing toggles), **Payment method** (saved card display brand/last4/exp; Add/Replace via /billing/setup-intent → PaymentSheet setup mode w/ customerSession; Remove handles 409-active-holds with the backend's message), **Notification settings** (7 toggles bound to GET/PATCH /account/notification-preferences, optimistic w/ revert), Support chat row, About row (version, legal links to web), **Delete account** (destructive row → sheet explaining 30-day grace + POST /account/delete-request; if pending, show scheduled date + Cancel deletion button). Sign out (confirm).

## Verify
Live flows vs localhost:8000 as iosbuyer: orders list (may be empty unless P5 left orders — if empty, verify EmptyStates + create one order via the API path quickly if feasible, else screenshot empties), support chat round-trip (POST a message, verify GET shows it; admin reply optional — skip), requests create/delete, prefs toggles persist (re-GET), password change (change then change back), address CRUD, payment method add with 4242 via setup PaymentSheet, simulated pushes all 5 routes (cold/bg/fg), pre-permission sheet triggers once. Screenshots light+dark of every screen above. READ screenshots; fix issues before finishing.
