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
consistently:

- `[Company Legal Name]` — the registered entity that operates Knot (e.g. `Knot, Inc.`
  or `Knot LLC`). Note this also appears in **ALL-CAPS** form (`[COMPANY LEGAL NAME]`)
  inside the all-caps Disclaimer and Limitation-of-Liability clauses of the Terms, so
  do a case-insensitive replace to catch both.
- `[Mailing Address]` — the entity's contact/mailing address.
- `[Governing-law State/Country]` — the jurisdiction whose law governs the Terms and
  where disputes are venued (e.g. `the State of Delaware, USA`).
- `[Effective Date]` — the date each document takes effect (set the same date on both,
  or per-document when you next revise).

The contact email is set to `privacy@knot-app.com` (the app already uses the
`knot-app.com` domain). Change it if you prefer a different address.

Quick check that nothing was missed — this matches only the four placeholder names, so
it won't fire on ordinary Markdown link labels like `[Privacy Policy](privacy-policy.md)`:

```bash
grep -rniE "\[(company legal name|mailing address|governing-law state/country|effective date)\]" \
  docs/legal/privacy-policy.md docs/legal/terms-of-service.md \
  docs/legal/privacy.html docs/legal/terms.html
```

It should print nothing once every placeholder has been replaced. (This README is
deliberately excluded — it *names* all four placeholders above, so globbing
`docs/legal/*.md` would always match itself and the check could never come back clean.)

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
