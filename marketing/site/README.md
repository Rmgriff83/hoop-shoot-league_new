# rossgriffus.com: the Hoop Shoot League pages

Static pages for the App Store listing's URLs (drafted 2026-11-06). There is
no build step: upload `hoop-shoot/` to the site root as it is.

| URL | File | Used as |
|---|---|---|
| `https://rossgriffus.com/hoop-shoot/` | `hoop-shoot/index.html` (+ `img/`) | Marketing URL |
| `https://rossgriffus.com/hoop-shoot/support/` | `hoop-shoot/support/index.html` | Support URL (required) |
| `https://rossgriffus.com/hoop-shoot/privacy/` | `hoop-shoot/privacy/index.html` | Privacy Policy URL (required) |
| `https://rossgriffus.com/app-ads.txt` | (from AdMob, below) | AdMob's seller check |

## Before uploading

1. Replace every `CONTACT_EMAIL` (in privacy and support) with the address
   players should write to. It is public on the pages and in the listing.
2. After launch, change the landing page's "Coming soon" button to the App
   Store link (and Apple's badge, if you want it).

## If the site is a builder (WordPress / Squarespace / Wix …)

Make three pages at those paths and paste in the text between `<main>` and
`</main>`. The builder's own styling replaces the inline CSS. The URL is
what matters: it must match what you enter in App Store Connect, and it
must load without a login.

## app-ads.txt

AdMob → Apps → your iOS app → **app-ads.txt** gives one line like:

```
google.com, pub-XXXXXXXXXXXXXXXX, DIRECT, f08c47fec0942fa0
```

Save it as a plain-text file at the **root** of the domain:
`https://rossgriffus.com/app-ads.txt` (not under `/hoop-shoot/`). The
listing's Marketing URL must be on the same domain, because AdMob finds the
file through the App Store listing's developer website. AdMob can take a
day or so to verify it after the app is live.

## Screenshots used here

`hoop-shoot/img/*.jpg` are the captioned App Store screenshots at 430
wide. The full-size ones for App Store Connect are in
`marketing/trailer/store/` (gitignored; `python3 -I tools/trailer/store_shots.py`
re-makes them).
