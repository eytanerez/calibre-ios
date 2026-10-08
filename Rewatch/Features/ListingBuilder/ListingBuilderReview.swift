import RewatchDesign
import RewatchKit
import SwiftUI

/// The last step: the listing exactly as a buyer will see it in the app,
/// built from the answers and the photos on the phone, with the same pieces
/// the listing page uses (gallery, buy box, the details table, the Condition
/// section, the seller's notes). Tapping a part opens its question and comes
/// straight back. At the bottom sit the full payout and "Approve and submit";
/// a slim bar pinned under it all keeps "You make $X · Approve" in reach.
struct BuilderReviewStep: View {
    let model: ListingBuilderModel
    let onApprove: () -> Void

    @State private var showsGuide = false

    private var listing: Listing? { BuilderPreviewListing.make(from: model) }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xl) {
            if let listing {
                section(.photos, label: "photos") {
                    ListingGallery(
                        images: listing.images.map(\.url),
                        condition: listing.condition?.overall
                    ) { _ in
                        model.edit(.photos)
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))
                }

                VStack(alignment: .leading, spacing: Space.xl) {
                    buyBox(listing)

                    CalloutBand(
                        icon: "checkmark.shield",
                        title: "Authenticated by Rewatch",
                        message: "Examined at WPB Watch Co in West Palm Beach, Florida, before it ships, with a 1-year mechanical warranty."
                    )

                    section(.condition, label: "condition") {
                        QuickSpecRow(listing: listing)
                    }

                    section(.watch, label: "details") {
                        VStack(alignment: .leading, spacing: Space.m) {
                            Text("The details")
                                .font(RewatchType.sectionTitle)
                                .foregroundStyle(Color.rewatch.foreground)
                            ListingDetailsTable(rows: ListingDetailRows.rows(for: listing))
                        }
                    }

                    if ListingConditionSection.hasContent(listing) {
                        section(.condition, label: "condition") {
                            ListingConditionSection(listing: listing, showsGuide: $showsGuide)
                        }
                        Button("Change the history answers") { model.edit(.history) }
                            .font(RewatchType.bodySemiBold)
                            .foregroundStyle(Color.rewatch.primaryDeep)
                            .frame(minHeight: Space.touchTarget)
                    }

                    notes(listing)
                }
            }

            payout
        }
    }

    // MARK: The buyer's page

    private func buyBox(_ listing: Listing) -> some View {
        VStack(alignment: .leading, spacing: Space.s) {
            section(.watch, label: "watch") {
                VStack(alignment: .leading, spacing: Space.s) {
                    Eyebrow(eyebrow(listing))
                    Text(listing.model ?? listing.title)
                        .font(RewatchType.title)
                        .foregroundStyle(Color.rewatch.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            section(.price, label: "price") {
                VStack(alignment: .leading, spacing: Space.s) {
                    RollingMoney(value: model.answers.price, font: RewatchType.priceLarge)
                        .foregroundStyle(Color.rewatch.foreground)
                    Text("Final price may include tax and shipping. See breakdown below.")
                        .font(RewatchType.caption)
                        .foregroundStyle(Color.rewatch.mutedForeground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if let terms = listing.returns {
                section(.returns, label: "returns") {
                    Label {
                        Text(terms.summary ?? "Sold without returns")
                            .font(RewatchType.label)
                            .foregroundStyle(Color.rewatch.foreground)
                    } icon: {
                        Image(systemName: terms.accepted ? "arrow.uturn.backward" : "xmark.circle")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(Color.rewatch.mutedForeground)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func notes(_ listing: Listing) -> some View {
        let text = SellerNotes(listing.description).text
        section(.box, label: "notes") {
            VStack(alignment: .leading, spacing: Space.m) {
                Text("From the seller")
                    .font(RewatchType.sectionTitle)
                    .foregroundStyle(Color.rewatch.foreground)
                Text(text.isEmpty ? "No notes. Tap to add anything buyers should know." : text)
                    .font(RewatchType.body)
                    .foregroundStyle(text.isEmpty ? Color.rewatch.mutedForeground : Color.rewatch.secondaryForeground)
                    .lineSpacing(6)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func eyebrow(_ listing: Listing) -> String {
        var parts: [String] = []
        if let brand = listing.brand, !brand.isEmpty { parts.append(brand) }
        if let reference = listing.referenceNumber, !reference.isEmpty { parts.append("Ref. \(reference)") }
        return parts.joined(separator: " \u{00B7} ")
    }

    /// A part of the page that opens its question when tapped, with a small
    /// "Change" chip so the seller can see it does.
    private func section<Content: View>(_ step: BuilderStep, label: String, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture {
                Haptics.shared.play(.selection)
                model.edit(step)
            }
            .overlay(alignment: .topTrailing) {
                Button {
                    Haptics.shared.play(.selection)
                    model.edit(step)
                } label: {
                    Text("Change")
                        .font(RewatchType.sans(.semiBold, 12, relativeTo: .caption))
                        .foregroundStyle(Color.rewatch.foreground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.rewatch.background.opacity(0.95), in: Capsule())
                        .overlay(Capsule().strokeBorder(Color.rewatch.border))
                        .frame(minWidth: Space.touchTarget, minHeight: Space.touchTarget)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableStyle())
                .padding(step == .photos ? Space.s : 0)
                .accessibilityLabel("Change the \(label)")
            }
            .accessibilityAction(named: "Change the \(label)") { model.edit(step) }
    }

    // MARK: The seller's money and the approve

    private var payout: some View {
        VStack(alignment: .leading, spacing: Space.l) {
            Text("Your payout")
                .font(RewatchType.sectionTitle)
                .foregroundStyle(Color.rewatch.foreground)

            BuilderPayoutBreakdown(model: model, review: true)
                .onTapGesture { model.edit(.price) }

            if let title = model.answers.vaultWatchTitle, model.answers.vaultWatchID != nil {
                BuilderNote(emphasized: false) {
                    (Text("From your Vault").font(RewatchType.bodySemiBold)
                        + Text(": \(title). This sale is added to that watch\u{2019}s passport.").font(RewatchType.body))
                        .foregroundStyle(Color.rewatch.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(spacing: Space.s) {
                Button(action: onApprove) {
                    BusyLabel(title: approveLabel, busy: model.isSubmitting)
                }
                .onScrollVisibilityChange(threshold: 0.01) { visible in
                    model.inlineApproveVisibilityChanged(visible)
                }
                .onDisappear { model.inlineApproveVisibilityChanged(false) }
                .buttonStyle(.rewatch(.primary, fullWidth: true))
                .disabled(model.isSubmitting)
                .accessibilityIdentifier("builder.approve")

                Group {
                    if let error = model.sendError, error.step == .review {
                        Text(error.message)
                            .foregroundStyle(Color.rewatch.destructive)
                    } else if model.isSubmitting {
                        Text("You can leave the app: the photos keep uploading.")
                            .foregroundStyle(Color.rewatch.mutedForeground)
                    } else {
                        Text("Rewatch checks every listing before it goes live.")
                            .foregroundStyle(Color.rewatch.mutedForeground)
                    }
                }
                .font(RewatchType.caption)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
            }
        }
    }

    private var approveLabel: String {
        switch model.submitPhase {
        case .uploading(let done, let total): "Uploading photos, \(min(done + 1, total)) of \(total)\u{2026}"
        case .sending: "Sending for review\u{2026}"
        case .preparing: "Getting it ready\u{2026}"
        case nil: "Approve and submit"
        }
    }
}

/// The slim bar pinned to the bottom of the review: what the seller makes,
/// and Approve.
struct BuilderApproveBar: View {
    let model: ListingBuilderModel
    let onApprove: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Mounted below the screen, then slid up, so the same motion can take it
    /// away again when the inline button comes into view.
    @State private var entered = false

    private var hidden: Bool { !entered || model.approveBarHidden }

    private var figure: Decimal? { model.estimatedPayout ?? model.keep }

    /// While it waits on photos, the bar says how far they are.
    private var barLabel: String {
        switch model.submitPhase {
        case .uploading(let done, let total): "Photos \(done) of \(total)"
        case .sending: "Sending"
        default: "Approve"
        }
    }

    var body: some View {
        HStack(spacing: Space.m) {
            VStack(alignment: .leading, spacing: 0) {
                Text(model.estimatedPayout != nil ? "You make" : "You keep")
                    .font(RewatchType.caption)
                    .foregroundStyle(Color.rewatch.mutedForeground)
                RollingMoney(value: figure, font: RewatchType.price)
                    .foregroundStyle(Color.rewatch.foreground)
            }
            .accessibilityElement(children: .combine)
            Spacer(minLength: Space.m)
            Button(action: onApprove) {
                BusyLabel(title: barLabel, busy: model.isSubmitting)
                    .padding(.horizontal, Space.l)
                    .contentTransition(.numericText())
                    .animation(Motion.easeFast, value: barLabel)
            }
            .buttonStyle(.rewatch(.primary))
            .disabled(model.isSubmitting)
            .accessibilityIdentifier("builder.approve.bar")
        }
        .padding(.horizontal, Space.margin)
        .padding(.vertical, Space.s)
        .background(.regularMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(Color.rewatch.border).frame(height: 1)
        }
        // Stays mounted and keeps its room in the inset either way, so the
        // page under it never moves; while hidden it cannot be reached.
        .offset(y: hidden && !reduceMotion ? 120 : 0)
        .opacity(hidden ? 0 : 1)
        .allowsHitTesting(!hidden)
        .accessibilityHidden(hidden)
        .animation(reduceMotion ? .easeOut(duration: 0.2) : Motion.ease(0.38), value: hidden)
        .onAppear { entered = true }
    }
}

/// The listing a buyer will see, made from the builder's answers and photos
/// so the listing page's own pieces can draw it. Goes through the API decoder,
/// as a server payload would, so every field means what it means there.
enum BuilderPreviewListing {
    @MainActor
    static func make(from model: ListingBuilderModel) -> Listing? {
        let answers = model.answers
        let names = model.identity
        let grades = BuilderRules.partGrades(answers)
        var json: [String: Any] = [
            "id": model.listingID ?? "builder-preview",
            "listing_number": 0,
            "seller_id": "builder-preview-seller",
            "title": SellListingBody.title(brand: names.brand, model: names.model, reference: names.reference),
            "brand": names.brand,
            "model": names.model,
            "reference_number": names.reference,
            "description": answers.notes.trimmingCharacters(in: .whitespacesAndNewlines),
            "price": "\(answers.price ?? 0)",
            "currency": "USD",
            "status": "pending_review",
            "box_papers": answers.box && answers.papers,
            "box_included": answers.box,
            "papers_included": answers.papers,
            "booklets_included": answers.booklets,
            "condition_notes": SellListingBody.conditionNotesPayload(BuilderRules.visibleConditionNotes(answers)),
        ]
        if let grade = answers.grade {
            var condition: [String: String] = ["overall": grade]
            for part in BuilderRules.parts { condition[part.rawValue] = grades[part] ?? grade }
            json["condition"] = condition
        }
        if let year = Int(answers.year), BuilderRules.isFourDigits(answers.year) {
            json["production_year"] = year
        }
        var history: [String: Any] = [:]
        if let polish = answers.polish { history["polish"] = polish }
        if let originality = answers.originality {
            history["originality"] = originality
            let note = ConditionNote.normalized(answers.replaced)
            if originality == "replaced", !note.isEmpty { history["replaced_parts_note"] = note }
        }
        if let service = answers.serviceHistory {
            history["service_history"] = service
            if service == "serviced", let year = Int(answers.serviceYear) { history["last_service_year"] = year }
        }
        if !history.isEmpty { json["history"] = history }
        if let returns = answers.returns {
            var terms: [String: Any] = ["accepted": returns != .none]
            if let hours = returns.hours { terms["window_hours"] = hours }
            json["returns"] = terms
        }
        if let specs = model.watch?.specs, let encoded = try? specsJSON(specs) {
            json["specs"] = encoded
        }
        json["images"] = galleryURLs(model).map(\.absoluteString)

        guard let data = try? JSONSerialization.data(withJSONObject: json) else { return nil }
        return try? APIClient.makeDecoder(origin: nil).decode(Listing.self, from: data)
    }

    /// The photos in the order a buyer's gallery shows them: the six angles
    /// front first, then the extras.
    @MainActor
    static func galleryURLs(_ model: ListingBuilderModel) -> [URL] {
        var urls: [URL] = []
        for category in BuilderRules.uploadOrder {
            guard let slot = model.slot(category) else { continue }
            if let name = slot.fileName { urls.append(model.photoURL(name)) } else if let remote = slot.remoteURL { urls.append(remote) }
        }
        for extra in model.extras.sorted(by: { $0.sortIndex < $1.sortIndex }) {
            if let name = extra.fileName { urls.append(model.photoURL(name)) } else if let remote = extra.remoteURL { urls.append(remote) }
        }
        return urls
    }

    private static func specsJSON(_ specs: ListingSpecs) throws -> Any {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        return try JSONSerialization.jsonObject(with: encoder.encode(specs))
    }
}
