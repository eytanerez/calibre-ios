import SwiftUI

/// Display-only data the card needs — CalibreKit models map into this.
public struct ListingCardModel: Identifiable, Hashable, Sendable {
    public let id: String
    public let brand: String
    public let year: String?
    public let title: String
    public let reference: String?
    public let priceText: String
    public let condition: String?
    public let watcherCount: Int?
    public let imageURL: URL?

    public init(
        id: String,
        brand: String,
        year: String? = nil,
        title: String,
        reference: String? = nil,
        priceText: String,
        condition: String? = nil,
        watcherCount: Int? = nil,
        imageURL: URL? = nil
    ) {
        self.id = id
        self.brand = brand
        self.year = year
        self.title = title
        self.reference = reference
        self.priceText = priceText
        self.condition = condition
        self.watcherCount = watcherCount
        self.imageURL = imageURL
    }
}

/// The marketplace grid card: square image on a quiet well, eyebrow brand
/// line, medium title, serif price. Borders define the card; the watch is
/// the hero. Image loading is injected so CalibreDesign stays UI-only.
public struct ListingCard<ImageContent: View>: View {
    let model: ListingCardModel
    @ViewBuilder let image: (URL?) -> ImageContent

    public init(model: ListingCardModel, @ViewBuilder image: @escaping (URL?) -> ImageContent) {
        self.model = model
        self.image = image
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            ZStack(alignment: .topLeading) {
                image(model.imageURL)
                    .aspectRatio(1, contentMode: .fill)
                    .frame(maxWidth: .infinity)
                    .background(Color.calibre.secondary.opacity(0.5))
                    .clipped()
                    .clipShape(RoundedRectangle(cornerRadius: Radius.card, style: .continuous))

                if let condition = model.condition {
                    ConditionPill(condition)
                        .padding(Space.s)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Eyebrow([model.brand, model.year].compactMap(\.self).joined(separator: " · "))
                Text(model.title)
                    .font(CalibreType.bodyMedium)
                    .foregroundStyle(Color.calibre.foreground)
                    .lineLimit(1)
                if let reference = model.reference {
                    Text("Ref. \(reference)")
                        .font(CalibreType.caption)
                        .foregroundStyle(Color.calibre.mutedForeground)
                        .lineLimit(1)
                }
                HStack(alignment: .firstTextBaseline) {
                    Text(model.priceText)
                        .font(CalibreType.price)
                        .foregroundStyle(Color.calibre.foreground)
                    Spacer()
                    if let watchers = model.watcherCount, watchers > 0 {
                        Label("\(watchers)", systemImage: "eye")
                            .font(CalibreType.caption)
                            .foregroundStyle(Color.calibre.mutedForeground)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .padding(.top, 1)
            }
            .padding(.horizontal, 2)
        }
    }
}

#Preview("Listing card", traits: .sizeThatFitsLayout) {
    ListingCard(model: .init(
        id: "1",
        brand: "Rolex",
        year: "2019",
        title: "Submariner Date",
        reference: "116610LN",
        priceText: "$12,400",
        condition: "Very Good",
        watcherCount: 14
    )) { _ in
        Image(systemName: "clock")
            .resizable()
            .scaledToFit()
            .padding(40)
            .foregroundStyle(Color.calibre.placeholder)
    }
    .frame(width: 180)
    .padding()
    .background(Color.calibre.background)
}
