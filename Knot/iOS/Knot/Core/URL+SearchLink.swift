//
//  URL+SearchLink.swift
//  Knot
//
//  A merchant handoff must open a real, dedicated purchase page — never a general
//  web-search, a shopping-results page, or an on-platform search/directory/listing
//  page (e.g. an Eventbrite "pastry class" results page). The recommendation pipeline
//  no longer produces such links, but a card generated before that fix can still
//  linger in a stale in-memory deck, a Saved card, or a notification/deep-link, and
//  re-serve its old listing URL. This guard neutralizes those at the tap.
//

import Foundation

extension URL {
    /// True when this URL is a search/shopping/directory-LISTING page rather than a
    /// real, dedicated merchant detail page. Mirrors the backend's
    /// `is_search_or_shopping_url` (app/agents/url_resolution.py) — keep the two in
    /// sync. Catches: a general search-engine host or subdomain (SEARCH_ENGINE_DOMAINS),
    /// the `tbm=shop` flag, a search-term query param (`q`/`query`/`search`/`find_desc`),
    /// a `/search`|`/results` path segment, and known on-platform directory prefixes
    /// (Eventbrite `/d/`,`/b/`; Amazon `/s`; Etsy `/c/`). The real Google stores
    /// (store./play.google.com), a merchant's own `search.<merchant>.com` subdomain, and
    /// detail paths (`/e/`, `/dp/`, `/listing/`) are unaffected.
    var isSearchOrShoppingLink: Bool {
        // Google Shopping (or any explicit shopping-tab flag), regardless of host casing.
        if absoluteString.lowercased().contains("tbm=shop") { return true }

        guard let rawHost = host?.lowercased() else { return false }
        let host = rawHost.hasPrefix("www.") ? String(rawHost.dropFirst(4)) : rawHost

        // Genuine merchant properties that live under a search-engine domain.
        if ["store.google.com", "play.google.com"].contains(host) { return false }

        // General search engines / their results and cache hosts — the bare domain or
        // any subdomain (www., cse., shopping., news., html., r.search., cn. …).
        let engines = [
            "google.com", "bing.com", "duckduckgo.com", "yahoo.com", "baidu.com",
            "ecosia.org", "startpage.com", "ask.com", "aol.com", "brave.com",
            "googleusercontent.com",
        ]
        if engines.contains(where: { host == $0 || host.hasSuffix("." + $0) }) { return true }

        // International Google/Bing search domains (google.co.uk, bing.de, …) and their
        // subdomains (news.google.co.uk, shopping.google.de) — matches the backend's
        // `google.`/`bing.` prefix plus `.google.`/`.bing.` interior-label checks.
        if host.hasPrefix("google.") || host.hasPrefix("bing.")
            || host.contains(".google.") || host.contains(".bing.") { return true }

        // On-platform search/directory/listing pages hosted on a legitimate commerce
        // domain — the host checks above can't see these, so inspect query + path.
        return isOnPlatformListingLink(host: host)
    }

    /// Query- and path-based detection for on-platform listing pages (mirrors the
    /// backend `_has_search_query_param` + `_is_listing_path`).
    private func isOnPlatformListingLink(host: String) -> Bool {
        let components = URLComponents(url: self, resolvingAgainstBaseURL: false)

        // Search-term query params on any host: ?q=, ?query=, ?search=, ?find_desc=
        // (blank values are ignored, matching parse_qs on the backend).
        let searchKeys: Set<String> = ["q", "query", "search", "find_desc"]
        if let items = components?.queryItems,
           items.contains(where: { searchKeys.contains($0.name.lowercased())
               && !($0.value ?? "").isEmpty }) {
            return true
        }

        // Whole-path-segment listing markers on any host: /search, /results.
        let path = (components?.path ?? "").lowercased()
        let segments = Set(path.split(separator: "/").map(String.init))
        if !segments.isDisjoint(with: ["search", "results"]) { return true }

        // Per-platform directory prefixes for listing pages with no query string.
        // Prefixes end with "/" and match the trailing-slash-normalized path, so `/d/`
        // won't match a `/dance-class` detail slug nor `/s/` a `/stores` page.
        let listingPrefixes: [(domain: String, prefixes: [String])] = [
            ("eventbrite.", ["/d/", "/b/"]),  // discovery / browse; detail is /e/
            ("amazon.", ["/s/"]),             // /s?k=… search; detail is /dp/ or /gp/
            ("etsy.com", ["/c/"]),            // category listing; detail is /listing/
        ]
        let normalizedPath = path.hasSuffix("/") ? path : path + "/"
        return listingPrefixes.contains { entry in
            host.contains(entry.domain)
                && entry.prefixes.contains { normalizedPath.hasPrefix($0) }
        }
    }
}
