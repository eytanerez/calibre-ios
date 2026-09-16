import Foundation
import XCTest
@testable import CalibreKit

final class CatalogCascadeTests: XCTestCase {
    @MainActor
    func testReferenceSuggestionsUseCatalogScopeAndReportTruncation() async throws {
        MockURLProtocol.setHandler { request in
            XCTAssertEqual(request.url?.path, "/catalog/cascade")
            let items = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!
            let query = Dictionary(uniqueKeysWithValues: items.map { ($0.name, $0.value ?? "") })
            XCTAssertEqual(query, ["level": "references", "brand": "Rolex", "model": "GMT-Master II", "q": "126"])
            return (200, Data(#"{"ok":true,"data":{"values":[{"value":"126710BLNR","brand":"Rolex","model":"GMT-Master II","reference":"126710BLNR"}],"total":4,"truncated":true,"omitted":3}}"#.utf8))
        }
        let store = CatalogStore(client: APIClient(configuration: mockConfiguration(), auth: nil))
        let response = try await store.cascade(CatalogCascadeQuery(level: .references, brand: " Rolex ", model: "GMT-Master II", text: "126"))
        XCTAssertEqual(response.values.first?.reference, "126710BLNR")
        XCTAssertTrue(response.truncated)
        XCTAssertEqual(response.total, 4)
        XCTAssertEqual(response.omitted, 3)
    }

    func testEachLevelOnlyCarriesItsParentScope() {
        let brand = CatalogCascadeQuery(level: .brands, brand: "old", model: "old", text: "Rol")
        XCTAssertEqual(Set(brand.queryItems.map(\.name)), ["level", "q"])
        let model = CatalogCascadeQuery(level: .models, brand: "Rolex", model: "old")
        XCTAssertEqual(Set(model.queryItems.map(\.name)), ["level", "q", "brand"])
        XCTAssertFalse(CatalogCascadeQuery(level: .models).canSearch)
        XCTAssertTrue(CatalogCascadeQuery(level: .brands).canSearch)
    }
}
