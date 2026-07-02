//
//  URL+SearchLink.swift
//  Knot
//
//  A merchant handoff must open a real, dedicated purchase page — never a general
//  web-search or shopping-results page. The recommendation pipeline no longer
//  produces such links, but a card generated before that fix can still linger in a
//  stale in-memory deck, a Saved card, or a notification/deep-link, and re-serve its
//  old `google.com/search?tbm=shop&q=…` URL. This guard neutralizes those at the tap.
//

import Foundation

extension URL {
    /// True when this URL is a general web-search or shopping-results page (e.g. a
    /// Google/Bing results page or Google Shopping) rather than a real merchant page.
    /// Mirrors the backend's search-engine rejection (SEARCH_ENGINE_DOMAINS): the bare
    /// engine domain or any subdomain of it, plus the `tbm=shop` shopping flag. The
    /// real Google stores (store./play.google.com) are allow-listed, and a merchant's
    /// own on-site search (search.<merchant>.com) is unaffected.
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
        return host.hasPrefix("google.") || host.hasPrefix("bing.")
            || host.contains(".google.") || host.contains(".bing.")
    }
}
