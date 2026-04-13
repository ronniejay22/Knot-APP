import Foundation
import MapKit

/// Wraps `MKLocalSearchCompleter` to provide location autocomplete for city/state/zip queries.
///
/// Results are filtered to address-level completions only, which avoids POI noise.
/// When the user selects a completion, `resolve(_:)` performs an `MKLocalSearch`
/// to extract the structured city, state, and zip code.
@Observable
@MainActor
final class LocationSearchCompleter: NSObject {
    var results: [MKLocalSearchCompletion] = []
    var isSearching = false

    /// Resolved location after the user picks a completion.
    var selectedCity: String = ""
    var selectedState: String = ""
    var selectedZip: String = ""

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.resultTypes = .address
    }

    func search(query: String) {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            results = []
            isSearching = false
            return
        }
        isSearching = true
        completer.delegate = self
        completer.queryFragment = query
    }

    func resolve(_ completion: MKLocalSearchCompletion) async {
        let request = MKLocalSearch.Request(completion: completion)
        request.resultTypes = .address
        let search = MKLocalSearch(request: request)

        do {
            let response = try await search.start()
            if let placemark = response.mapItems.first?.placemark {
                selectedCity = placemark.locality ?? ""
                selectedState = placemark.administrativeArea ?? ""
                selectedZip = placemark.postalCode ?? ""
            }
        } catch {
            // Fall back to the completion's title/subtitle text
            selectedCity = completion.title
            selectedState = completion.subtitle
            selectedZip = ""
        }
    }

    func clear() {
        results = []
        isSearching = false
        selectedCity = ""
        selectedState = ""
        selectedZip = ""
    }
}

// MARK: - MKLocalSearchCompleterDelegate

extension LocationSearchCompleter: MKLocalSearchCompleterDelegate {
    nonisolated func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        nonisolated(unsafe) let updated = Array(completer.results)
        Task { @MainActor in
            self.results = updated
            self.isSearching = false
        }
    }

    nonisolated func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        Task { @MainActor in
            self.isSearching = false
        }
    }
}
