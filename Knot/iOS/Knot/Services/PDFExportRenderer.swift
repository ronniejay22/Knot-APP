//
//  PDFExportRenderer.swift
//  Knot
//
//  Created on February 16, 2026.
//  Step 11.3: Renders a DataExportResponse as a styled PDF document
//  using WKWebView HTML-to-PDF conversion.
//

import Foundation
import WebKit

/// Renders a user data export as a branded PDF document.
///
/// Builds an HTML string with embedded CSS from a `DataExportResponse`,
/// loads it into an off-screen `WKWebView`, and uses `createPDF()` to
/// produce the final PDF data. Light theme with pink accent headers
/// for print-friendly output.
@MainActor
final class PDFExportRenderer: NSObject, WKNavigationDelegate {

    private var webView: WKWebView?
    private var continuation: CheckedContinuation<Void, Never>?

    /// Renders the export data as a styled PDF.
    ///
    /// - Parameter export: The decoded data export from the backend.
    /// - Returns: Raw PDF data ready to be written to a file.
    func renderPDF(from export: DataExportResponse) async throws -> Data {
        let html = buildHTML(from: export)

        let config = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), configuration: config)
        webView.navigationDelegate = self
        self.webView = webView

        webView.loadHTMLString(html, baseURL: nil)

        // Wait for the page to finish loading
        await withCheckedContinuation { (cont: CheckedContinuation<Void, Never>) in
            self.continuation = cont
        }

        let pdfConfig = WKPDFConfiguration()
        pdfConfig.rect = CGRect(x: 0, y: 0, width: 612, height: 792) // US Letter at 72 DPI

        let pdfData = try await webView.pdf(configuration: pdfConfig)

        self.webView = nil
        return pdfData
    }

    // MARK: - WKNavigationDelegate

    nonisolated func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }

    nonisolated func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        Task { @MainActor in
            continuation?.resume()
            continuation = nil
        }
    }

    // MARK: - HTML Builder

    private func buildHTML(from export: DataExportResponse) -> String {
        var html = """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <style>
        * { box-sizing: border-box; }
        body {
            font-family: -apple-system, 'Helvetica Neue', sans-serif;
            color: #1a1a1a;
            margin: 0;
            padding: 40px 48px;
            font-size: 13px;
            line-height: 1.5;
        }
        .header {
            text-align: center;
            margin-bottom: 32px;
            padding-bottom: 20px;
            border-bottom: 2px solid #FF2D55;
        }
        .header h1 {
            font-size: 28px;
            color: #FF2D55;
            margin: 0 0 4px 0;
            letter-spacing: -0.5px;
        }
        .header .subtitle {
            color: #888;
            font-size: 12px;
        }
        h2 {
            color: #FF2D55;
            font-size: 16px;
            margin: 28px 0 12px 0;
            padding-bottom: 6px;
            border-bottom: 1px solid #FFD6E0;
        }
        .info-grid {
            display: grid;
            grid-template-columns: 140px 1fr;
            gap: 6px 16px;
            margin: 8px 0 16px 0;
        }
        .info-label {
            color: #888;
            font-size: 12px;
            font-weight: 600;
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }
        .info-value {
            font-size: 13px;
        }
        .tags {
            display: flex;
            flex-wrap: wrap;
            gap: 6px;
            margin: 8px 0 16px 0;
        }
        .tag {
            display: inline-block;
            background: #FFF0F3;
            color: #FF2D55;
            border-radius: 12px;
            padding: 3px 12px;
            font-size: 12px;
            font-weight: 500;
        }
        .tag.muted {
            background: #F5F5F5;
            color: #666;
        }
        table {
            width: 100%;
            border-collapse: collapse;
            margin: 8px 0 20px 0;
            font-size: 12px;
        }
        th {
            background: #FFF0F3;
            color: #FF2D55;
            text-align: left;
            padding: 8px 10px;
            font-weight: 600;
            font-size: 11px;
            text-transform: uppercase;
            letter-spacing: 0.3px;
        }
        td {
            padding: 7px 10px;
            border-bottom: 1px solid #F0F0F0;
            vertical-align: top;
        }
        tr:last-child td { border-bottom: none; }
        .empty {
            color: #999;
            font-style: italic;
            margin: 8px 0 20px 0;
        }
        .badge {
            display: inline-block;
            padding: 2px 8px;
            border-radius: 8px;
            font-size: 11px;
            font-weight: 500;
        }
        .badge.used { background: #E8F5E9; color: #2E7D32; }
        .badge.unused { background: #F5F5F5; color: #999; }
        .badge.sent { background: #E8F5E9; color: #2E7D32; }
        .badge.pending { background: #FFF3E0; color: #E65100; }
        .badge.failed { background: #FFEBEE; color: #C62828; }
        .footer {
            margin-top: 40px;
            padding-top: 16px;
            border-top: 1px solid #EEE;
            text-align: center;
            color: #BBB;
            font-size: 11px;
        }
        </style>
        </head>
        <body>
        """

        // Header
        html += """
        <div class="header">
            <h1>Knot</h1>
            <div class="subtitle">Data Export &middot; \(escapeHTML(formatDate(export.exportedAt)))</div>
        </div>
        """

        // Account Info
        html += "<h2>Account</h2>"
        html += "<div class=\"info-grid\">"
        html += infoRow("Email", export.user.email ?? "Not set")
        html += infoRow("Account Created", formatDate(export.user.createdAt ?? ""))
        html += "</div>"

        // Partner Profile
        if let vault = export.partnerVault {
            html += buildVaultSection(vault)
        }

        // Milestones
        if !export.milestones.isEmpty {
            html += buildMilestonesSection(export.milestones)
        }

        // Hints
        if !export.hints.isEmpty {
            html += buildHintsSection(export.hints)
        }

        // Recommendations
        if !export.recommendations.isEmpty {
            html += buildRecommendationsSection(export.recommendations)
        }

        // Feedback
        if !export.feedback.isEmpty {
            html += buildFeedbackSection(export.feedback)
        }

        // Notifications
        if !export.notifications.isEmpty {
            html += buildNotificationsSection(export.notifications)
        }

        // Footer
        html += """
        <div class="footer">
            Generated by Knot &middot; \(escapeHTML(formatDate(export.exportedAt)))
        </div>
        </body>
        </html>
        """

        return html
    }

    // MARK: - Section Builders

    private func buildVaultSection(_ vault: ExportVault) -> String {
        var html = "<h2>Partner Profile</h2>"
        html += "<div class=\"info-grid\">"
        html += infoRow("Partner Name", vault.partnerName)
        if let months = vault.relationshipTenureMonths {
            html += infoRow("Together", formatTenure(months))
        }
        if let status = vault.cohabitationStatus {
            html += infoRow("Living Situation", formatSnakeCase(status))
        }
        let location = [vault.locationCity, vault.locationState, vault.locationCountry]
            .compactMap { $0 }
            .joined(separator: ", ")
        if !location.isEmpty {
            html += infoRow("Location", location)
        }
        html += "</div>"

        // Interests
        if !vault.interests.isEmpty {
            html += "<h2>Interests</h2>"
            html += "<div class=\"tags\">"
            for interest in vault.interests {
                html += "<span class=\"tag\">\(escapeHTML(interest))</span>"
            }
            html += "</div>"
        }

        // Dislikes
        if !vault.dislikes.isEmpty {
            html += "<h2>Dislikes</h2>"
            html += "<div class=\"tags\">"
            for dislike in vault.dislikes {
                html += "<span class=\"tag muted\">\(escapeHTML(dislike))</span>"
            }
            html += "</div>"
        }

        // Vibes
        if !vault.vibes.isEmpty {
            html += "<h2>Aesthetic Vibes</h2>"
            html += "<div class=\"tags\">"
            for vibe in vault.vibes {
                html += "<span class=\"tag\">\(escapeHTML(formatSnakeCase(vibe)))</span>"
            }
            html += "</div>"
        }

        // Love Languages
        if !vault.loveLanguages.isEmpty {
            html += "<h2>Love Languages</h2>"
            html += "<div class=\"info-grid\">"
            let sorted = vault.loveLanguages.sorted { $0.priority < $1.priority }
            for ll in sorted {
                let label = ll.priority == 1 ? "Primary" : "Secondary"
                html += infoRow(label, formatSnakeCase(ll.language))
            }
            html += "</div>"
        }

        // Budgets
        if !vault.budgets.isEmpty {
            html += "<h2>Budget Ranges</h2>"
            html += "<table><tr><th>Occasion</th><th>Range</th></tr>"
            for budget in vault.budgets {
                let min = formatPrice(cents: budget.minAmount, currency: budget.currency)
                let max = formatPrice(cents: budget.maxAmount, currency: budget.currency)
                html += "<tr><td>\(escapeHTML(formatSnakeCase(budget.occasionType)))</td>"
                html += "<td>\(escapeHTML(min)) – \(escapeHTML(max))</td></tr>"
            }
            html += "</table>"
        }

        return html
    }

    private func buildMilestonesSection(_ milestones: [ExportMilestone]) -> String {
        var html = "<h2>Milestones</h2>"
        html += "<table><tr><th>Name</th><th>Date</th><th>Type</th><th>Recurrence</th></tr>"
        for m in milestones {
            html += "<tr>"
            html += "<td>\(escapeHTML(m.milestoneName))</td>"
            html += "<td>\(escapeHTML(formatMilestoneDate(m.milestoneDate)))</td>"
            html += "<td>\(escapeHTML(formatSnakeCase(m.milestoneType)))</td>"
            html += "<td>\(escapeHTML(formatSnakeCase(m.recurrence)))</td>"
            html += "</tr>"
        }
        html += "</table>"
        return html
    }

    private func buildHintsSection(_ hints: [ExportHint]) -> String {
        var html = "<h2>Hints (\(hints.count))</h2>"
        html += "<table><tr><th>Hint</th><th>Source</th><th>Status</th><th>Date</th></tr>"
        for h in hints {
            let source = h.source == "text_input" ? "Text" : "Voice"
            let status = h.isUsed
                ? "<span class=\"badge used\">Used</span>"
                : "<span class=\"badge unused\">Unused</span>"
            html += "<tr>"
            html += "<td>\(escapeHTML(h.hintText))</td>"
            html += "<td>\(escapeHTML(source))</td>"
            html += "<td>\(status)</td>"
            html += "<td>\(escapeHTML(formatDate(h.createdAt)))</td>"
            html += "</tr>"
        }
        html += "</table>"
        return html
    }

    private func buildRecommendationsSection(_ recs: [ExportRecommendation]) -> String {
        var html = "<h2>Recommendations (\(recs.count))</h2>"
        html += "<table><tr><th>Title</th><th>Type</th><th>Merchant</th><th>Price</th><th>Date</th></tr>"
        for r in recs {
            let price = r.priceCents.map { formatPrice(cents: $0, currency: "USD") } ?? "—"
            html += "<tr>"
            html += "<td>\(escapeHTML(r.title))</td>"
            html += "<td>\(escapeHTML(formatSnakeCase(r.recommendationType)))</td>"
            html += "<td>\(escapeHTML(r.merchantName ?? "—"))</td>"
            html += "<td>\(escapeHTML(price))</td>"
            html += "<td>\(escapeHTML(formatDate(r.createdAt)))</td>"
            html += "</tr>"
        }
        html += "</table>"
        return html
    }

    private func buildFeedbackSection(_ feedback: [ExportFeedback]) -> String {
        var html = "<h2>Feedback (\(feedback.count))</h2>"
        html += "<table><tr><th>Action</th><th>Rating</th><th>Notes</th><th>Date</th></tr>"
        for f in feedback {
            let rating = f.rating.map { "\($0)/5" } ?? "—"
            html += "<tr>"
            html += "<td>\(escapeHTML(formatSnakeCase(f.action)))</td>"
            html += "<td>\(escapeHTML(rating))</td>"
            html += "<td>\(escapeHTML(f.feedbackText ?? "—"))</td>"
            html += "<td>\(escapeHTML(formatDate(f.createdAt)))</td>"
            html += "</tr>"
        }
        html += "</table>"
        return html
    }

    private func buildNotificationsSection(_ notifications: [ExportNotification]) -> String {
        var html = "<h2>Notifications (\(notifications.count))</h2>"
        html += "<table><tr><th>Scheduled</th><th>Days Before</th><th>Status</th><th>Sent</th></tr>"
        for n in notifications {
            let statusClass = n.status == "sent" ? "sent" : (n.status == "failed" ? "failed" : "pending")
            let status = "<span class=\"badge \(statusClass)\">\(escapeHTML(formatSnakeCase(n.status)))</span>"
            html += "<tr>"
            html += "<td>\(escapeHTML(formatDate(n.scheduledFor)))</td>"
            html += "<td>\(n.daysBefore) days</td>"
            html += "<td>\(status)</td>"
            html += "<td>\(escapeHTML(n.sentAt.map { formatDate($0) } ?? "—"))</td>"
            html += "</tr>"
        }
        html += "</table>"
        return html
    }

    // MARK: - Helpers

    private func infoRow(_ label: String, _ value: String) -> String {
        "<span class=\"info-label\">\(escapeHTML(label))</span><span class=\"info-value\">\(escapeHTML(value))</span>"
    }

    private func formatDate(_ isoString: String) -> String {
        guard !isoString.isEmpty else { return "—" }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: isoString) {
            return dateDisplayFormatter.string(from: date)
        }
        // Try without fractional seconds
        formatter.formatOptions = [.withInternetDateTime]
        if let date = formatter.date(from: isoString) {
            return dateDisplayFormatter.string(from: date)
        }
        return isoString
    }

    private func formatMilestoneDate(_ dateString: String) -> String {
        // Format: "2000-03-15" → "March 15"
        let parts = dateString.split(separator: "-")
        guard parts.count >= 3,
              let month = Int(parts[1]),
              let day = Int(parts[2]) else { return dateString }

        let monthNames = ["", "January", "February", "March", "April", "May", "June",
                          "July", "August", "September", "October", "November", "December"]
        guard month >= 1, month <= 12 else { return dateString }
        return "\(monthNames[month]) \(day)"
    }

    private func formatPrice(cents: Int, currency: String) -> String {
        let amount = Double(cents) / 100.0
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = currency
        if cents % 100 == 0 {
            formatter.maximumFractionDigits = 0
        }
        return formatter.string(from: NSNumber(value: amount)) ?? "$\(amount)"
    }

    private func formatTenure(_ months: Int) -> String {
        let years = months / 12
        let remaining = months % 12
        if years == 0 { return "\(remaining) month\(remaining == 1 ? "" : "s")" }
        if remaining == 0 { return "\(years) year\(years == 1 ? "" : "s")" }
        return "\(years) year\(years == 1 ? "" : "s"), \(remaining) month\(remaining == 1 ? "" : "s")"
    }

    private func formatSnakeCase(_ string: String) -> String {
        string
            .replacingOccurrences(of: "_", with: " ")
            .split(separator: " ")
            .map { $0.prefix(1).uppercased() + $0.dropFirst().lowercased() }
            .joined(separator: " ")
    }

    private func escapeHTML(_ string: String) -> String {
        string
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private var dateDisplayFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }
}
