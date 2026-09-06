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

## Before publishing: fill in these placeholders

Search all four documents for square-bracketed placeholders and replace them
consistently. **Two remain:**

- `[Company Legal Name]` — the registered entity that operates Knot (e.g. `Knot, Inc.`
  or `Knot LLC`). Note this also appears in **ALL-CAPS** form (`[COMPANY LEGAL NAME]`)
  inside the all-caps Disclaimer and Limitation-of-Liability clauses of the Terms, so
  do a case-insensitive replace to catch both.
- `[Effective Date]` — the date each document takes effect (set the same date on both,
  or per-document when you next revise).

**Already resolved:**

- **Mailing address — deliberately omitted.** Contact is email-only. A postal address is
  not required by Apple's review, and CCPA/CPRA lets a business operating exclusively
  online with a direct customer relationship offer an email address alone for privacy
  requests. Add one back if Knot ships to the **EU/UK** — GDPR expects the controller's
  postal contact details, and the EU DSA trader rules publish a name/address/phone/email
  on the App Store listing anyway, so it stops being private at that point.
- **Governing law — set to `the United States`** in Terms §16. ⚠️ **This should name a
  state.** US contract law is state law, so "the laws of the United States" leaves a
  court to work out which body of law applies, and "the courts of the United States"
  designates no particular venue — an exclusive-jurisdiction clause that names the whole
  country does not really select a forum. Replace both occurrences with a specific state
  (normally where you live or where the entity is formed, e.g. `the State of Texas, USA`)
  before relying on the clause.

The contact email is set to `privacy@knot-app.com` (the app already uses the
`knot-app.com` domain). Change it if you prefer a different address.

Quick check that nothing was missed — this matches only the remaining placeholder names,
so it won't fire on ordinary Markdown link labels like `[Privacy Policy](privacy-policy.md)`:

```bash
grep -rniE "\[(company legal name|effective date)\]" \
  docs/legal/privacy-policy.md docs/legal/terms-of-service.md \
  docs/legal/privacy.html docs/legal/terms.html
```

It should print nothing once every placeholder has been replaced. (This README is
deliberately excluded — it *names* the placeholders above, so globbing `docs/legal/*.md`
would always match itself and the check could never come back clean.)

## Publishing to the web

The iOS app hardcodes **`https://knot-app.com/terms`** and
**`https://knot-app.com/privacy`** in **two** places — the **About** section of the
Settings screen (`iOS/Knot/Features/Settings/SettingsView.swift`) and the onboarding
paywall (`iOS/Knot/Features/Onboarding/Steps/OnboardingPaywallView.swift`), where App
Review expects the subscription terms to be reachable before purchase. Host the HTML
files so those exact paths resolve — App Store submission also requires a working
Privacy Policy URL:

- Serve `terms.html` at `https://knot-app.com/terms`
- Serve `privacy.html` at `https://knot-app.com/privacy`

Both HTML files are fully self-contained (inline CSS, no external assets), so they can
be dropped onto any static host — including a Vercel static deployment for the
`knot-app.com` root domain, GitHub Pages, or an S3/Cloudflare bucket. If your host
serves files by extension, either configure clean-URL rewrites (`/terms` →
`/terms.html`) or rename the files to extension-less objects with an
`text/html` content type.

The two pages cross-link each other using the canonical root paths `/terms` and
`/privacy` (the same URLs the app uses), so publish them at the domain root as above.
When previewing locally from the filesystem, view each page on its own — the
cross-links point at site-absolute paths and won't resolve over `file://`.

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
