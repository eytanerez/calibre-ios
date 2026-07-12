# P5 — Checkout + Offers (the money track)

First read Docs/specs/shared-rules.md AND /Users/eytanerez/Documents/GitHub/Backend/docs/mobile-api.md sections on /checkout/payment-intent, /orders/from-payment-intent, offers, and CustomerSessions. Your simulator: **iPhone 17 Pro Max**. Derived data: /tmp/dd-p5. Screenshots: scratchpad/p5/.

You own: Calibre/Features/Checkout/, Calibre/Features/Offers/. StripePaymentSheet SPM product is already linked to the app target.

Kit surface: CommerceStore (offers create/confirm-hold/cancel/respond, addresses CRUD, orders), models Offer/Order/Address. You may add kit files per shared rules for: checkout payment-intent call, from-payment-intent call, wire create-intent/reservation.

## Flows

### 1. CheckoutFlow (fullScreenCover; entry `.checkout(listingID, offerID?)`)
Warm, unhurried, 3 steps in one NavigationStack with a slim progress eyebrow (Shipping → Payment → Review):
1. **Shipping**: address radio cards from /account/addresses (default-shipping preselected, "Default" badge); "Use a different address" expands inline CalibreTextField form (full name, street, apt, city, state, ZIP, country default US, phone) → POST, auto-select. No addresses → form directly.
2. **Method**: two selectable cards — **Card or Apple Pay** ("Pay instantly. A 3% card processing cost applies." — show the $ amount once breakdown known) vs **Wire transfer** ("No card processing cost. Your watch is reserved for 24 hours."). Fee difference shown in dollars.
3. **Review & pay** (card path): POST /checkout/payment-intent {listing_id, shipping_address_id, offer_id?} → breakdown card (SpecList: watch price [or "Your accepted offer" when offer_id], shipping, card processing, tax, serif Total) + listing mini-card + trust CalloutBand ("Your watch is inspected at our authentication center before it ships"). PaymentSheet configured with: customer(id, customerSessionClientSecret), applePay(merchantId "merchant.com.buycalibre.calibre", country US) — wrap so missing Apple Pay entitlement degrades silently to cards, returnURL "calibre://stripe-redirect", appearance mapped from tokens (cream/ink/chocolate or dark equivalents, Radius.control corners, Geist font via UIFont). "Pay {total}" primary button presents the sheet.
   - .completed → poll POST /orders/from-payment-intent {payment_intent_id} (retry ~15s, treat conflict/exists as success) with a quiet "Confirming your order…" state → **SuccessMoment**: full-screen cream/ink moment — watch image scales in 420ms, serif "It's yours.", order number caption, Haptics .paymentSuccess, one primary "View your order" (route .order(id)) + ghost "Keep browsing". No confetti — restraint.
   - .canceled → back to review silently. .failed → inline destructive message with Stripe's text + retry.
4. **Wire path**: create wire intent (existing /checkout/create-intent {payment_method:"wire"} contract) → WireInstructionsScreen: serif total, SpecList rows (Bank, Routing, Account, SWIFT/IBAN, Reference/memo emphasized with CalloutBand "Include the reference or your transfer can't be matched"), copy button per row (Haptics .selection, toast "Copied"), 24h CountdownChip, "I've sent the wire" primary → POST /checkout/wire-reservation → order detail route with awaiting-wire state.

### 2. MakeOfferSheet (SheetScaffold, large detent; entry `.makeOffer(listingID)`)
1. Listing mini-card; serif amount display; decimal keypad field prefilled with list price (editable, currency prefix, live serif rendering via contentTransition numericText); optional message to seller (≤1000); consent row: exact copy "I authorize a $250 hold on my card. If the seller accepts and I back out or miss the payment window, Calibre may charge this hold." + required toggle.
2. "Continue — authorize the $250 hold" → POST /listings/{id}/offers → PaymentSheet on hold client_secret (customer + customerSession from response; card/Apple Pay). On completed → POST /offers/{id}/confirm-hold → in-sheet success state: "Offer sent. {seller} has 24 hours to respond." + .success haptic + Done. On failure/cancel: offer stays hold_pending — show retry + "Cancel offer" (POST /offers/{id}/cancel).
3. If an open offer already exists for this listing (create returns the conflict error) → show OfferDetail instead.

### 3. OfferDetailScreen (route `.offer(offerID)`)
- Header: listing mini-card, StatusBadge (map every status to human words: Waiting on the seller / The seller countered / Accepted — payment due / Paid / Declined / Withdrawn / Expired / Hold not completed / Deposit charged), CountdownChip on live deadlines.
- **Negotiation timeline**: TimelineRow per negotiation_history round (buyer trailing/primary-tinted, seller leading/accent), serif amounts, messages, relative times.
- Context actions by status (buyer side): countered → Accept {amount} (primary; PATCH accepted... per contract the buyer accepting a counter: PATCH /offers/{id} status accepted) / Counter (inline amount + message form; PATCH countered) / Decline; accepted_pending_payment → Pay now (route .checkout(listingID, offerID)) + Back out (confirmationDialog restating the hold-capture consequence, then cancel endpoint); pending_seller → Cancel offer. Hold status caption ("$250 hold authorized · released after payment").
- Works for the seller side too when offer.seller is me (Accept → confirmationDialog "The listing is reserved and {buyer} has 24 hours to pay." / Counter / Decline) — the Sell track links here.

### 4. OffersListScreen (exported for Activity tab; route `.offers`)
Segmented (SegmentedTabs): Sent / Received. Rows: listing thumb, amount serif, StatusBadge, CountdownChip, latest message preview. Swipe actions: leading Accept (received+pending), trailing Decline/Cancel (confirm). Tap → OfferDetail. EmptyStates per segment ("You haven't made any offers yet. Found a watch you love? Start the conversation.").

## E2E verification (the bar is a real purchase)
Backend has REAL Stripe test keys. Start webhook forwarding first:
  stripe listen --forward-to localhost:8000/webhooks/stripe   (background; verify "Ready" in output; the stripe CLI is installed and logged in — if it needs login, report and continue without it, webhooks also arrive via from-payment-intent polling)
Sign in as iosbuyer.calibre@gmail.com / CalibreiOS123!. Pick any active listing (GET /listings?page_size=1).
1. Card checkout with test card 4242 4242 4242 4242 (any future exp, any CVC, any ZIP) through PaymentSheet in the simulator → SuccessMoment → verify order exists (GET /buyer/orders) and listing went sold.
2. 3DS card 4000 0025 0000 3155 → complete the challenge → success.
3. Offer on another listing: $250 hold with 4242 → confirm-hold → offer pending_seller (verify via GET /account/offers). Cancel it → hold released.
4. Wire path: create → instructions screen renders bank details → "I've sent the wire" → order awaiting_wire (then cancel the order to free the listing: POST /orders/{id}/cancel).
Screenshots light+dark: checkout shipping, method, review w/ breakdown, PaymentSheet presented, SuccessMoment, wire instructions, offer sheet w/ consent, offer detail w/ countdown + timeline, offers list. READ them; fix visual issues. Do not leave test orders in ambiguous states — cancel what you can.
