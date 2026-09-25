import MapKit
import RewoundDesign
import SwiftUI

// MARK: - The resolved address

/// A US street address resolved from an Apple Maps suggestion: the four
/// fields a pick fills in. Line 2 is never part of it; the apartment or suite
/// is the reader's to add.
struct SuggestedAddress: Equatable, Sendable {
    var line1: String
    var city: String
    /// Two letters, as every address form here stores it.
    var state: String
    var postalCode: String

    /// Where Rewound ships: the states and DC, and the territories USPS treats
    /// as states. MapKit gives each territory its own country code, and for
    /// those the code is also the two-letter state.
    static let shippableCountryCodes: Set<String> = ["US", "PR", "GU", "VI", "AS", "MP"]

    init(line1: String, city: String, state: String, postalCode: String) {
        self.line1 = line1
        self.city = city
        self.state = state
        self.postalCode = postalCode
    }

    /// Built from a map item's address parts. Nil when the place is outside
    /// the United States, or when Maps could not name its city or state;
    /// a half-filled address is worse than the one the reader was typing.
    init?(
        houseNumber: String?,
        street: String?,
        city: String?,
        region: String?,
        postalCode: String?,
        countryCode: String?,
        fallbackLine1: String
    ) {
        guard let country = countryCode?.uppercased(),
              Self.shippableCountryCodes.contains(country) else { return nil }

        let streetLine = [houseNumber, street]
            .compactMap { Self.cleaned($0) }
            .joined(separator: " ")
        let state = country == "US" ? USStateCode.code(for: region) : country

        guard let city = Self.cleaned(city), let state else { return nil }

        self.line1 = streetLine.isEmpty ? (Self.cleaned(fallbackLine1) ?? "") : streetLine
        self.city = city
        self.state = state
        self.postalCode = Self.cleaned(postalCode) ?? ""
    }

    private static func cleaned(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

/// US state and territory names to their postal codes. Maps normally names a
/// US state by its code already ("CA"); this is for the times it spells it
/// out ("California"), so the form never receives a name in a two-letter box.
enum USStateCode {
    static func code(for region: String?) -> String? {
        guard let region = region?.trimmingCharacters(in: .whitespacesAndNewlines),
              !region.isEmpty else { return nil }
        let upper = region.uppercased()
        if upper.count == 2, codes.contains(upper) { return upper }
        let key = region
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .replacingOccurrences(of: ".", with: "")
        return byName[key]
    }

    private static let byName: [String: String] = [
        "alabama": "AL", "alaska": "AK", "arizona": "AZ", "arkansas": "AR",
        "california": "CA", "colorado": "CO", "connecticut": "CT", "delaware": "DE",
        "district of columbia": "DC", "washington dc": "DC", "florida": "FL",
        "georgia": "GA", "hawaii": "HI", "idaho": "ID", "illinois": "IL",
        "indiana": "IN", "iowa": "IA", "kansas": "KS", "kentucky": "KY",
        "louisiana": "LA", "maine": "ME", "maryland": "MD", "massachusetts": "MA",
        "michigan": "MI", "minnesota": "MN", "mississippi": "MS", "missouri": "MO",
        "montana": "MT", "nebraska": "NE", "nevada": "NV", "new hampshire": "NH",
        "new jersey": "NJ", "new mexico": "NM", "new york": "NY",
        "north carolina": "NC", "north dakota": "ND", "ohio": "OH", "oklahoma": "OK",
        "oregon": "OR", "pennsylvania": "PA", "rhode island": "RI",
        "south carolina": "SC", "south dakota": "SD", "tennessee": "TN",
        "texas": "TX", "utah": "UT", "vermont": "VT", "virginia": "VA",
        "washington": "WA", "west virginia": "WV", "wisconsin": "WI", "wyoming": "WY",
        "puerto rico": "PR", "guam": "GU", "us virgin islands": "VI",
        "virgin islands": "VI", "american samoa": "AS", "northern mariana islands": "MP",
    ]

    private static let codes = Set(byName.values)
}

// MARK: - Suggestions

/// One Apple Maps suggestion, as the list prints it.
struct AddressSuggestion: Identifiable, Equatable {
    let title: String
    let subtitle: String

    var id: String { "\(title)\u{1F}\(subtitle)" }
}

/// Apple Maps address suggestions for one street field.
///
/// Free and keyless: `MKLocalSearchCompleter` for the list, `MKLocalSearch`
/// to resolve a pick into its parts. Neither asks for the reader's location,
/// so there is no permission prompt; the search is bounded to the United
/// States instead of to where the phone is. With no network the completer
/// fails, and the list simply stays empty.
@MainActor
@Observable
final class AddressSuggester: NSObject, @preconcurrency MKLocalSearchCompleterDelegate {
    private(set) var suggestions: [AddressSuggestion] = []
    private(set) var resolvingID: AddressSuggestion.ID?

    /// Made on the first query rather than with the suggester, because the
    /// view that owns this is re-initialised on every keystroke of the form
    /// around it and a completer per render would be thrown away each time.
    @ObservationIgnored private var completer: MKLocalSearchCompleter?
    @ObservationIgnored private var completions: [AddressSuggestion.ID: MKLocalSearchCompletion] = [:]

    /// Fewer than this and Maps is guessing from a house number.
    static let minimumQueryLength = 3
    static let maximumSuggestions = 4

    /// The fifty states, DC and Puerto Rico, with Alaska and Hawaii. Suggestions
    /// outside it are not offered at all (`regionPriority = .required`); the
    /// box takes in some of Canada and Mexico, which the country check on the
    /// list and on the resolved place then turns away.
    private static let unitedStates = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 45, longitude: -117.5),
        span: MKCoordinateSpan(latitudeDelta: 56, longitudeDelta: 110)
    )

    func update(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= Self.minimumQueryLength else {
            clear()
            return
        }
        makeCompleterIfNeeded().queryFragment = trimmed
    }

    func clear() {
        completer?.cancel()
        suggestions = []
        completions = [:]
    }

    /// The pick, as the four fields it fills. Nil when Maps could not resolve
    /// it (offline, or a place outside the United States).
    func resolve(_ suggestion: AddressSuggestion) async -> SuggestedAddress? {
        guard let completion = completions[suggestion.id] else { return nil }
        resolvingID = suggestion.id
        defer { resolvingID = nil }

        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address
        guard let response = try? await MKLocalSearch(request: request).start(),
              let placemark = response.mapItems.first?.placemark else { return nil }

        return SuggestedAddress(
            houseNumber: placemark.subThoroughfare,
            street: placemark.thoroughfare,
            city: placemark.locality ?? placemark.subAdministrativeArea,
            region: placemark.administrativeArea,
            postalCode: placemark.postalCode,
            countryCode: placemark.isoCountryCode,
            fallbackLine1: suggestion.title
        )
    }

    private func makeCompleterIfNeeded() -> MKLocalSearchCompleter {
        if let completer { return completer }
        let completer = MKLocalSearchCompleter()
        completer.delegate = self
        completer.resultTypes = .address
        completer.pointOfInterestFilter = .excludingAll
        completer.region = Self.unitedStates
        completer.regionPriority = .required
        self.completer = completer
        return completer
    }

    // MARK: MKLocalSearchCompleterDelegate

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        var kept: [AddressSuggestion] = []
        var byID: [AddressSuggestion.ID: MKLocalSearchCompletion] = [:]
        for completion in completer.results {
            guard !Self.namesForeignCountry(completion.subtitle) else { continue }
            let suggestion = AddressSuggestion(title: completion.title, subtitle: completion.subtitle)
            guard byID[suggestion.id] == nil else { continue }
            kept.append(suggestion)
            byID[suggestion.id] = completion
            if kept.count == Self.maximumSuggestions { break }
        }
        completions = byID
        suggestions = kept
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        suggestions = []
        completions = [:]
    }

    // MARK: Country check

    /// Maps ends a suggestion's subtitle with its country, in the reader's
    /// language ("Toronto, ON, Canada"). A subtitle ending in any country but
    /// the US and its territories is dropped before it is offered.
    nonisolated static func namesForeignCountry(_ subtitle: String) -> Bool {
        guard let last = subtitle.split(separator: ",").last else { return false }
        let name = last.trimmingCharacters(in: .whitespaces).lowercased()
        return foreignCountryNames.contains(name)
    }

    private nonisolated static let foreignCountryNames: Set<String> = {
        let locale = Locale.current
        var names: Set<String> = []
        for region in Locale.Region.isoRegions {
            let code = region.identifier
            guard code.count == 2, !SuggestedAddress.shippableCountryCodes.contains(code),
                  let name = locale.localizedString(forRegionCode: code) else { continue }
            names.insert(name.lowercased())
        }
        return names
    }()
}

// MARK: - The field

/// The street line of an address form, with Apple Maps suggestions under it
/// while the reader types. Picking one fills this line and hands the city,
/// state and ZIP to the form; line 2 is left alone.
///
/// The field underneath is the ordinary `RewoundTextField` with the
/// `.addressLine1` kind, so the keyboard's own address AutoFill keeps working
/// beside the suggestions.
struct AddressStreetField: View {
    let label: String
    @Binding var text: String
    var placeholder: String = ""
    var error: String?
    /// Called with the resolved address after line 1 has been filled.
    let onSelect: (SuggestedAddress) -> Void

    @State private var suggester = AddressSuggester()
    @FocusState private var focused: Bool
    /// What this field last wrote into itself, so the fill does not
    /// immediately search for the address that was just picked.
    @State private var filled: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Space.s) {
            RewoundTextField(label, text: $text, placeholder: placeholder, error: error, kind: .addressLine1)
                .focused($focused)

            if focused, !suggester.suggestions.isEmpty {
                suggestionList
                    .transition(.opacity)
            }
        }
        .animation(Motion.easeFast, value: suggester.suggestions)
        .animation(Motion.easeFast, value: focused)
        .onChange(of: text) { _, newValue in
            // Only typing searches. A form filling the line itself (a saved
            // address, the beta fill) happens with the field unfocused.
            guard focused, newValue != filled else { return }
            filled = nil
            suggester.update(query: newValue)
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { suggester.clear() }
        }
    }

    private var suggestionList: some View {
        VStack(spacing: 0) {
            ForEach(Array(suggester.suggestions.enumerated()), id: \.element.id) { index, suggestion in
                if index > 0 {
                    Rectangle()
                        .fill(Color.rewound.border)
                        .frame(height: 1)
                        .padding(.leading, Space.m + 22)
                }
                suggestionRow(suggestion)
            }
        }
        .background(
            Color.rewound.card,
            in: RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.box, style: .continuous)
                .strokeBorder(Color.rewound.border, lineWidth: 1)
        )
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Address suggestions")
    }

    private func suggestionRow(_ suggestion: AddressSuggestion) -> some View {
        Button {
            pick(suggestion)
        } label: {
            HStack(spacing: Space.m) {
                Image(systemName: "mappin.and.ellipse")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Color.rewound.mutedForeground)
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(suggestion.title)
                        .font(RewoundType.bodyMedium)
                        .foregroundStyle(Color.rewound.foreground)
                        .fixedSize(horizontal: false, vertical: true)
                    if !suggestion.subtitle.isEmpty {
                        Text(suggestion.subtitle)
                            .font(RewoundType.caption)
                            .foregroundStyle(Color.rewound.mutedForeground)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if suggester.resolvingID == suggestion.id {
                    ProgressView()
                        .controlSize(.small)
                        .tint(Color.rewound.mutedForeground)
                }
            }
            .multilineTextAlignment(.leading)
            .padding(.horizontal, Space.m)
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: Space.touchTarget, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableStyle())
        .disabled(suggester.resolvingID != nil)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Fills in the street, city, state and ZIP")
    }

    private func pick(_ suggestion: AddressSuggestion) {
        Task {
            guard let address = await suggester.resolve(suggestion) else {
                // Offline, or a place Rewound cannot ship to: the list goes
                // and what the reader typed stays.
                suggester.clear()
                return
            }
            Haptics.shared.play(.selection)
            filled = address.line1
            text = address.line1
            suggester.clear()
            onSelect(address)
        }
    }
}
