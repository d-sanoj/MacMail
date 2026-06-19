# GmailBox

GmailBox is a native macOS Gmail client scaffold built with Swift, SwiftUI, AppKit where needed, URLSession, local OAuth token files, and a local SQLite cache.

It is not a web wrapper and does not embed gmail.com. The UI follows Gmail-like workflows while using original styling and system symbols.

## Current state

- Native SwiftPM macOS app named `GmailBox`
- Three-column Gmail-like layout
- Multi-account account model and account switcher
- Google OAuth installed-app service using browser login and localhost callback
- Local OAuth token storage per Gmail account
- Gmail API client skeleton for labels, threads, messages, search, modify, and send
- SQLite cache store for accounts, labels, threads, messages, and sync state
- Sample data for first launch and offline UI development

## Setup

Read `GOOGLE_API_SETUP.md`, then replace:

`Sources/GmailBox/Config/GoogleOAuthClient.json`

with the OAuth desktop-client JSON downloaded from Google Cloud Console.

## Build

```bash
swift build
```

## Run

```bash
./script/build_and_run.sh
```
