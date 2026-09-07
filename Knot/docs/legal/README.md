# Knot legal documents

This folder contains Knot's **Privacy Policy** and **Terms of Service**, plus
ready-to-publish web versions.

| File | Purpose |
| --- | --- |
| `privacy-policy.md` | Source-of-truth Privacy Policy (Markdown) |
| `terms-of-service.md` | Source-of-truth Terms of Service (Markdown) |
| `privacy.html` | Standalone, self-contained web page for the Privacy Policy |
| `terms.html` | Standalone, self-contained web page for the Terms of Service |

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
so both pages must be hosted somewhere real before submitting.

Both HTML files are fully self-contained (inline CSS, no external assets, no scripts),
so they drop onto any static host. Given the repo is public, **GitHub Pages is the
zero-cost option that needs no domain**: enable Pages on `ronniejay22/Knot-APP` and the
files are served straight out of `docs/`. Netlify, Cloudflare Pages, and an S3/Cloudflare
bucket all work equally well. A Google Drive or Docs link is *possible* but a known App
Review friction point — reviewers want a directly viewable page, not a PDF wrapped in a
Drive viewer that may prompt a mobile app-open.

**Whatever host is chosen, two things must line up:**

1. **The cross-links.** Each page links the other with the site-absolute paths `/terms`
   and `/privacy`, which only resolve when the pages sit at a **domain root**. On a host
   that serves from a subdirectory (GitHub Pages project sites do: `/Knot-APP/…`), change
   the two `href`s to relative (`terms.html` / `privacy.html`) or configure rewrites.
   This is also why the pages don't cross-link correctly when opened over `file://`.
2. **The in-app links must point at the same place.** They are hardcoded in two Swift
   files — see below.

## Outstanding: the knot-app.com references

These are live references to a domain we do not control, and each needs to change before
release:

| File | Reference | Problem |
| --- | --- | --- |
| `iOS/Knot/Features/Settings/SettingsView.swift` | `knot-app.com/terms`, `/privacy` | Sends users and App Review to a stranger's site |
| `iOS/Knot/Features/Onboarding/Steps/OnboardingPaywallView.swift` | `knot-app.com/terms`, `/privacy` | Same, on the screen where 3.1.2 requires reachable terms |
| `iOS/Knot/Core/Constants.swift` | `baseURL = https://api.knot-app.com` | **`api.knot-app.com` does not resolve** — a release build cannot reach the backend at all |
| `iOS/Knot/Knot.entitlements` | `applinks:api.knot-app.com` | Universal Links bound to a domain we cannot serve an AASA from |
| `backend/app/core/config.py` | `APP_DOMAIN` default `api.knot-app.com` | AASA + web-fallback are generated for that host |

The first two are what block *these documents* from being publishable. The rest are a
separate, launch-blocking infrastructure problem: acquiring a domain (or moving to the
deployment's own hostname) resolves all five at once.

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
