import Foundation

/// `{page, page_size, total, total_pages}` — `total` is null when the caller
/// passed `include_total=false`; `total_pages` only appears on order lists.
public struct Pagination: Codable, Sendable {
    public let page: Int
    public let pageSize: Int
    public let total: Int?
    public let totalPages: Int?

    public init(page: Int, pageSize: Int, total: Int? = nil, totalPages: Int? = nil) {
        self.page = page
        self.pageSize = pageSize
        self.total = total
        self.totalPages = totalPages
    }
}

/// Generic `{results, pagination}` page envelope used by `/listings`,
/// `/buyer/orders` and `/account/sales`.
public struct PageResponse<T: Codable & Sendable>: Codable, Sendable {
    public let results: [T]
    public let pagination: Pagination

    public init(results: [T], pagination: Pagination) {
        self.results = results
        self.pagination = pagination
    }
}
