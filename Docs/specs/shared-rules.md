# Shared rules for all Calibre iOS feature-track agents

Repo: /Users/eytanerez/Documents/GitHub/ios (git; committed baseline includes design system, CalibreKit, shell + auth). Backend contract: /Users/eytanerez/Documents/GitHub/Backend/docs/mobile-api.md. Local backend: http://localhost:8000 (live, seeded, real Stripe TEST keys). Test account: iosbuyer.calibre@gmail.com / iosbuyer / CalibreiOS123!.

## Ownership & no-collision rules (multiple agents work this repo concurrently)
- You own ONLY the Feature directories named in your spec. Never edit: Calibre/App/, Features/Auth/, Features/Onboarding/, Packages/* (CalibreKit + CalibreDesign are read-only APIs to you), project.yml, xcconfigs, other tracks' Feature dirs.
- If you need a route destination wired in the shared router, DON'T edit shared files — export your screen publicly, name it exactly as your spec says, and note it in your final message; the orchestrator wires destinations after you land.
- If CalibreKit lacks an endpoint/model you need: add a NEW file under Packages/CalibreKit/Sources/CalibreKit/Models/ or extend a store via a NEW Swift file with an `extension` (never modify existing kit files), matching kit conventions, with a decode test if a fixture exists. List every kit addition in your final message.
- New app files are picked up by regenerating the project: run `Scripts/bootstrap.sh` (it is concurrency-locked). Never run bare `xcodegen`.
- Do NOT commit. Leave work in the tree.

## Build/run (avoid clashing with other agents)
- Always: DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
- Build with YOUR OWN derived data dir and YOUR OWN simulator (named in your spec):
  xcodebuild -project Calibre.xcodeproj -scheme Calibre -destination 'platform=iOS Simulator,name=<YOUR SIM>' -derivedDataPath /tmp/dd-<track> -quiet build
- Boot/install/launch/screenshot only YOUR simulator (xcrun simctl boot "<YOUR SIM>" etc., then target it by name/udid — never "booted", which is ambiguous with parallel sims).

## Design bar (non-negotiable)
- Tokens/components only: CalibreType, Color.calibre.*, Space/Radius/Elevation, Motion.ease (160/220/420ms, ease-out only, no springs/bounce), Haptics.shared vocabulary, existing components (ListingCard, SearchField, FilterChip, SheetScaffold, Toast, EmptyState, SkeletonShimmer, CountdownChip, TimelineRow, ProgressCheckpoints, StatusBadge, SpecList, CalloutBand, StarRating, PriceRangeSlider, PhotoSlotRing, CalibreTextField, SegmentedTabs, AvatarInitial…). No raw hex, no system-blue defaults, no .animation(.spring).
- Serif (Playfair) for titles and prices only, never uppercase; Eyebrow is the only uppercase.
- Every screen: loading state (skeletons, not spinners, where content has shape), empty state (EmptyState with warm copy), error state (backend message via toast or inline; retry affordance). 44pt touch targets. Dynamic Type one size up must not break. Reduce Motion: no positional animation.
- UX copy: complete human sentences, warm, unhurried, no exclamation points ("12 listings created, 2 need attention" energy).
- Guest gating: any signed-in-only action goes through `session.require(reason:action:)` — never a dead button, never a naked error.
- Images: NukeUI LazyImage with downsampling sized to the container; square wells on Color.calibre.secondary.opacity(0.5).

## Verification bar (your final message must report all)
1. Build green with your derivedDataPath.
2. CalibreKit tests still pass: xcodebuild test -only-testing:CalibreKitTests (same destination/derived data).
3. Simulator walkthrough of YOUR flows against the live backend, light AND dark (xcrun simctl ui <sim> appearance dark), screenshots with descriptive names into /private/tmp/claude-501/-Users-eytanerez-Documents-GitHub/85e90eda-b4a4-4bd0-a53f-b7f3945a6dc9/scratchpad/<track>/.
4. READ your screenshots (Read tool) and confirm they look right — spacing, theming, real data rendering. Fix what looks wrong before finishing.
5. Final message: files created (paths), kit additions, screens finished vs deferred, screenshot list, deviations + why, and exact names of exported screens the orchestrator must wire into routes.
