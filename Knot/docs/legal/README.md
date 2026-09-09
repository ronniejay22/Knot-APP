# Knot legal documents

This folder contains Knot's **Privacy Policy** and **Terms of Service**, plus
ready-to-publish web versions.

| File | Purpose |
| --- | --- |
| `privacy-policy.md` | Source-of-truth Privacy Policy (Markdown) |
| `terms-of-service.md` | Source-of-truth Terms of Service (Markdown) |
| `privacy.html` | Standalone, self-contained web page for the Privacy Policy |
| `terms.html` | Standalone, self-contained web page for the Terms of Service |
| `build-pdfs.sh` | Renders both HTML pages to PDF (headless Chrome) for Drive hosting |

> ⚠️ **These are drafts, not legal advice.** They were written to accurately reflect
> what the Knot app and backend actually do, and they are a solid starting point — but
> laws vary by jurisdiction and by App Store / Play Store requirements. Have a
> qualified attorney review both documents before you publish or rely on them.

## Current values (no placeholders remain)

All four bracketed placeholders have been resolved. What they became, and what to revisit:

- **Operating party — `Ronald Jones Jr`**, the individual operating Knot as a sole
  proprietor (there is no LLC). This is the definition every `we` / `us` / `our` in both
  documents resolves to, and it is named outright in the Terms' Limitation-of-Liability
  and Indemnification clauses. **If an entity is later formed, replace it everywhere**
  (case-insensitively — the liability clause carries an ALL-CAPS `RONALD JONES JR`) and
  bump the effective date.
- **Effective date — `September 6, 2026`**, the same on all four documents. Bump it on
  any substantive revision.
- **Mailing address — deliberately omitted.** Contact is email-only. A postal address is
  not required by Apple's review, and CCPA/CPRA lets a business operating exclusively
  online with a direct customer relationship offer an email address alone for privacy
  requests. Add one back if Knot ships to the **EU/UK** — GDPR expects the controller's
  postal contact details, and the EU DSA trader rules publish a name/address/phone/email
  on the App Store listing anyway, so it stops being private at that point.
- **Governing law — `the State of California, USA`** in Terms §16, where the operator
  lives. The venue sentence names "the state and federal courts located in" that state,
  which is the correct construction for a state-level choice. Note that California
  consumer protections are largely non-waivable, which is why §16 keeps a carve-out
  preserving a consumer's right to sue locally — a forum clause that ignores that is
  more likely to be struck than honored.

The contact email is **`knottheapp@gmail.com`**. **It must actually receive mail** —
with the postal address gone it is the only contact channel in either document, and it
is where GDPR/CCPA rights requests are directed. It is deliberately *not* an
`@knot-app.com` address: **that domain is owned by a third party** (registered through
GMO, resolving to an unrelated host whose TLS certificate does not even match the name).
If a domain is acquired later, move the address to it and update both policies.

Check that no placeholder was reintroduced (this pattern deliberately excludes the
ordinary Markdown link labels `[Privacy Policy]` / `[Terms of Service]`):

```bash
grep -rniE "\[(company legal name|mailing address|governing-law state/country|effective date)\]" \
  docs/legal/privacy-policy.md docs/legal/terms-of-service.md \
  docs/legal/privacy.html docs/legal/terms.html
```

It should print nothing. (This README is deliberately excluded from the paths — it
*names* the placeholders above, so globbing `docs/legal/*.md` would always match itself
and the check could never come back clean.)

## Publishing to the web

> ⛔ **`knot-app.com` is NOT ours.** The domain is registered to a third party
> (GMO nameservers, resolving to `160.251.148.124`, with a TLS certificate that does not
> match the hostname). Nothing may be published there, and every hardcoded reference to
> it is a bug, not a configuration step. See "Outstanding: the knot-app.com references"
> below.

App Store submission requires a **publicly reachable Privacy Policy URL**, and Guideline
3.1.2 additionally expects the subscription Terms to be reachable *before* purchase —
so both documents must be hosted somewhere real before submitting.

### Current plan: PDFs on Google Drive

`./build-pdfs.sh` renders both HTML pages to PDF with headless Chrome. The HTML stays the
source of truth — the script renders a temporary copy and never edits the originals.

```bash
# proof render (cross-links between the two PDFs will be dead)
./build-pdfs.sh

# real render, once both Drive links exist
./build-pdfs.sh ./build "<privacy-drive-url>" "<terms-drive-url>"
```

**Three things have to be true or the documents are not actually published:**

1. **Sharing must be "Anyone with the link".** A Drive file defaults to private. An App
   Store Privacy Policy URL that prompts for a Google sign-in is a rejection — the
   reviewer cannot open it. This has to be set by hand in the Drive UI; it is not
   something the file inherits.
2. **Re-render with both URLs before publishing.** Each page cross-links the other with
   the site-absolute paths `/privacy` and `/terms`, which resolve only at a domain root
   and are therefore dead inside a standalone PDF. Passing both URLs to the script
   rewrites them to point at each other on Drive.
3. ~~**The in-app links must point at the same two URLs.**~~ **Done in Step 19.40** — all
   four call sites in `SettingsView.swift` (lines 301/311) and `OnboardingPaywallView.swift`
   (lines 113/114) now open the Drive URLs. Re-point them again if the files are ever
   replaced rather than overwritten, because a new upload gets a new file ID.

**Re-run the script and re-upload whenever the documents change.** A PDF on Drive is a
copy, not a view: unlike a hosted HTML page, editing the Markdown here does not update
what a user or reviewer sees. This is the main cost of the Drive route.

### If a domain is acquired later

Both HTML files are self-contained (inline CSS, no external assets, no scripts), so they
drop onto any static host — Vercel, Netlify, Cloudflare Pages, S3, or GitHub Pages (free,
and the repo is already public). Serving the HTML directly is strictly better than PDFs:
the pages update in place, `/privacy` and `/terms` resolve natively, and there is no
viewer chrome between the reviewer and the text. Note that a GitHub Pages *project* site
serves from a subdirectory (`/Knot-APP/…`), so the site-absolute cross-links would need
to become relative there.

## Outstanding: the knot-app.com references

These are live references to a domain we do not control, and each needs to change before
release. The two that pointed users and App Review at that domain — the About rows in
`SettingsView.swift` and the paywall fine print in `OnboardingPaywallView.swift` — were
repointed at the Drive PDFs in **Step 19.40** and are no longer listed here. What remains
is infrastructure:

| File | Reference | Problem |
| --- | --- | --- |
| `iOS/Knot/Core/Constants.swift` | `baseURL = https://api.knot-app.com` | **`api.knot-app.com` does not resolve** — a release build cannot reach the backend at all |
| `iOS/Knot/Knot.entitlements` | `applinks:api.knot-app.com` | Universal Links bound to a domain we cannot serve an AASA from |
| `backend/app/core/config.py` | `APP_DOMAIN` default `api.knot-app.com` | AASA + web-fallback are generated for that host |

These three are a separate, launch-blocking infrastructure problem, independent of the
policies: acquiring a domain (or moving to the deployment's own hostname) resolves all
three at once, and would also make the Drive PDF route unnecessary.

## Keeping the docs accurate

If you change what data Knot collects, which third-party providers or AI models it
uses, the authentication methods, the deletion/retention behavior, or the monetization
model, update **both** the Markdown and the matching HTML so they stay in sync with the
product and with what the App Store privacy "nutrition label" declares.

### Subscription terms are load-bearing

Terms **§10 (Subscriptions and billing)** states the plan names, lengths, and prices
verbatim. Its single source of truth is `iOS/Knot/Knot.storekit` (and, once they exist,
the matching products in App Store Connect) — currently `com.knot.premium.annual`
($59.99/yr) and `com.knot.premium.monthly` ($9.99/mo), each with a 7-day free trial.

**If a price, period, trial length, or plan changes, §10 must change with it.** App
Review Guideline 3.1.2 requires the linked EULA/Terms to disclose the subscription's
title, length, content, price per period, that it auto-renews, and how to cancel — a
Terms that disagrees with what StoreKit is selling is a review rejection, not a typo.
