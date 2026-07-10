# Recall — Product Requirements Document

| | |
|---|---|
| **Name** | Recall |
| **Author** | snandala@gmail.com |
| **Date** | 2026-07-05 |
| **Status** | Draft v1 |
| **Platform** | iOS (iPhone-first) |

---

## 1. Summary

Recall is a native iOS spaced-repetition flashcard app: a proven SRS **learning engine** wrapped in a **modern iOS interface**. It builds on the established open-source spaced-repetition model — notes/cards/templates, FSRS scheduling, and import of the widely-used `.apkg` / `.colpkg` deck format — while replacing the dated, power-user interfaces common in this space with a clean, native experience. It is **free for everyone**, supported by an optional tip jar.

**One-liner:** Proven spaced repetition. Native iOS. Free.

---

## 2. Background & Problem

Open-source spaced-repetition tools are the gold standard for serious learners, with a massive, devoted user base (medical students, language learners, professionals). But on iOS the experience has real gaps:

- The leading iOS option costs **$25** and carries a dated, utilitarian UI.
- That power comes with **steep complexity** that deters newcomers.
- iOS users are stuck between the paywall and awkward workarounds.

**Opportunity:** keep the trusted learning engine, ship a beautiful native iOS app, and make it free — funded by optional donations rather than a paywall.

---

## 3. Goals & Non-Goals

### Goals
- A native, modern iOS SRS app that **experienced users trust** and **newcomers find approachable**.
- **Faithful** data model + FSRS scheduling.
- **Frictionless migration** via `.apkg` / `.colpkg` import.
- **Free for everyone**, with near-zero hosting cost to the developer.

### Non-Goals (v1)
- Web or Android clients.
- Reverse-engineered compatibility with any third-party cloud-sync service.
- Custom card-template authoring.
- Shared-deck marketplace.

---

## 4. Target Users

**Experienced SRS users** — people already using open-source spaced-repetition tools who dislike the leading iOS app's UI or resent its $25 price.
- *Need:* trust (proven engine, import their existing decks) + polish.

**Complexity-averse newcomers** — want spaced repetition without a steep learning curve.
- *Need:* approachable onboarding + sensible defaults. *(Bundled starter decks come post-v1.)*

---

## 5. Product Principles

1. **Proven engine, redesigned UI.** The engine earns trust; the UI is the wedge.
2. **Offline-first.** Fully usable with no network; sync is invisible.
3. **Sensible defaults, advanced controls hidden but present.**
4. **Free, never nag, never gate.** Donations are optional and out of the way.
5. **No third-party trademarks.** The shipped product — app name, App Store listing, screenshots, keywords, and in-app copy — must contain **zero** references to any third-party flashcard app or its trademarks. Deck interop is described to users functionally ("import your existing decks"), never by brand name. *(Directly protects against App Store rejection.)*

---

## 6. Scope

### In scope — v1
- Decks + subdecks; hierarchical tags
- Note types: **Basic + Cloze** (fixed set)
- **FSRS** scheduling with per-deck retention target + daily new/review limits
- Study loop: **Again / Hard / Good / Easy**, tap-to-reveal, undo, optional swipe gestures
- **Field-based editor:** bold/italic/underline, cloze-deletion helper, image + audio insert, HTML source toggle
- Light card **search / browse** list
- **`.apkg` / `.colpkg` import** (+ SM-2 → FSRS history seeding)
- **CloudKit private-DB sync** (offline-first)
- Media: images, audio playback, **system TTS**
- Daily reminder notification + **home-screen due-count widget**
- **Lean stats:** review heatmap, due forecast, retention
- Optional **tip jar** (StoreKit 2)

### Out of scope — post-v1
- Bundled starter decks
- `.apkg` export
- Custom note types / template editor
- Full advanced query browser
- Audio recording
- iPad / Mac Catalyst
- Shared-deck marketplace
- Deep statistics

---

## 7. Functional Requirements

### 7.1 Decks & Organization
- Users can create, rename, nest (subdeck), and delete decks.
- Cards can carry one or more **hierarchical tags** independent of deck.
- Deck list shows per-deck **due / new** counts.

### 7.2 Notes, Cards & Note Types
- Data follows the proven open-source SRS model: a **Note** (fields) + a **Note Type** (fields + card templates) **generates one or more Cards**.
- v1 ships two fixed note types: **Basic** (Front/Back) and **Cloze**.
- Editing a note updates all cards generated from it.

### 7.3 Scheduling (FSRS)
- Every card is scheduled with **FSRS** across states: *new → learning → review → relearning*.
- Grading (Again/Hard/Good/Easy) produces the next interval per FSRS.
- Per-deck config: **desired retention (default 0.90)** + **daily new / review limits** (behind an Advanced screen).
- All reviews are logged to an append-only **review log**.

### 7.4 Study Loop
- Study a deck → card front renders → **tap to reveal** back → grade with 4 buttons.
- **Undo** is always available for the last action.
- Cards render in a **WKWebView** using the note type's HTML/CSS templates, with **MathJax** for LaTeX.

### 7.5 Editor
- Field-based editor matching the note type.
- Rich-text basics (bold/italic/underline), **cloze-deletion helper**, image + audio insertion, and an **HTML source toggle**.

### 7.6 Search / Browse
- A lightweight searchable list to find and edit cards. (Full advanced query browser is post-v1.)

### 7.7 Import
- Import **`.apkg` and `.colpkg`**: unzip, read embedded SQLite + media, map models → note types, notes, and cards.
- Convert existing **SM-2 history → seed FSRS** so scheduling continues sensibly.
- Handle **both** media formats: the legacy JSON media map **and** the newer zstd-compressed / protobuf media entries.

### 7.8 Sync
- **CloudKit private database**, offline-first, via **CKSyncEngine** (iOS 17+).
- Syncs notes, cards, decks, note types; media via **CKAsset**.
- Conflict resolution: **last-writer-wins per card**; review logs merge by append.
- Bills against each **user's own iCloud quota** → near-zero cost to developer.

### 7.9 Media & TTS
- Images and audio playback in cards.
- **System TTS** (AVSpeechSynthesizer) for reading fields aloud.
- Audio *recording* is post-v1.

### 7.10 Engagement
- **Daily reminder** local notification ("X cards due").
- **Home-screen widget** showing due count.

### 7.11 Statistics
- Review **heatmap** (calendar), **due forecast**, and **retention** — kept lean for v1.

### 7.12 Donations (Tip Jar)
- **StoreKit 2 in-app purchases**, **consumable** tiers: **$0.99 / $2.99 / $4.99 / $9.99**, located in Settings.
- A non-consumable **"Supporter" thank-you** (badge / alt app icon) is included.
- **Never gates features, never nags.** External donation links are avoided for App Store compliance.

---

## 8. Technical Architecture

| Concern | Decision |
|---|---|
| Language / UI | **Swift + SwiftUI** (native); UIKit/WebView where needed |
| Min OS | **iOS 17** |
| Form factor | iPhone-first; iPad / Mac Catalyst post-v1 |
| Persistence | **GRDB (SQLite)** — schema mirrors the proven SRS schema (collection, notes, cards, review log, decks, note types/templates/fields) |
| Card rendering | **WKWebView** (HTML/CSS/JS templates + MathJax) |
| Algorithm | **FSRS** (based on the open FSRS reference implementation, verified against published FSRS test vectors) |
| Sync | **CloudKit** private DB via **CKSyncEngine** |
| Payments | **StoreKit 2** (tip jar only) |
| Notifications / widget | UserNotifications, WidgetKit |
| Speech | AVSpeechSynthesizer |

**Data model:** `Collection → Deck (+subdecks) → Note (via Note Type) → Card → ReviewLog`.

---

## 9. Monetization

- **The app and all features are free**, including sync.
- Revenue is **optional donations** via an in-app tip jar: consumable tiers **$0.99 / $2.99 / $4.99 / $9.99**, plus a non-consumable **"Supporter" cosmetic** (badge / alt app icon).
- CloudKit's per-user quota model keeps hosting cost near zero, making "all free" sustainable.

---

## 10. Success Metrics

- **Activation:** % of new users who import or create a first deck **and** complete a first study session.
- **Retention:** D7 / D30 return rate; cards reviewed per active day.
- **Sync reliability:** sync success rate; conflict rate.
- **Quality:** crash-free session rate.
- **Support (secondary):** tip-jar conversion rate (never a primary target).

---

## 11. Risks & Mitigations

| Risk | Mitigation |
|---|---|
| **App Store rejection** for referencing a third-party app | Zero third-party brand references in name, listing, screenshots, keywords, or in-app copy; describe interop functionally. Review listing before submission. |
| **FSRS implementation correctness** | Unit-test against published FSRS test vectors in the scheduler phase. |
| **`.apkg` format drift** across exporter versions | Support both legacy JSON media maps and newer zstd/protobuf entries; test with real decks exported from multiple app versions. |
| **WKWebView flip latency** on rapid review | Reuse a single WebView instance; preload the next card. |
| **CloudKit sync complexity** | Use CKSyncEngine; keep conflict rules simple (LWW + append). |
| **iOS-only reach** | Accepted trade-off for v1 simplicity and zero-cost sync; revisit if cross-platform demand is strong. |

---

## 12. Roadmap

| Phase | Deliverable |
|---|---|
| **0 — Foundations** | SwiftUI app (iOS 17); GRDB schema; domain types + migrations |
| **1 — Scheduler** | FSRS engine (states, due queue, grading); unit tests vs vectors |
| **2 — Study loop** | Deck list → session → WKWebView renderer; tap-reveal, 4 buttons, undo |
| **3 — Notes & editing** | Field editor (Basic + Cloze), card generation, cloze helper, media insert, light search |
| **4 — Import** | `.apkg` / `.colpkg` importer + SM-2 → FSRS seeding |
| **5 — Sync** | CloudKit private-DB mirror via CKSyncEngine; media assets; offline-first |
| **6 — Engagement** | TTS, daily reminder, due widget, lean stats, tip jar + Supporter cosmetic |
| **7 — Ship** | Onboarding + sample content; App Store prep |

---

## 13. Open Questions / Deferred

All major v1 product decisions are resolved. Minor items to finalize during implementation:

- Depth of FSRS config surfaced in v1 (default desired retention set at **0.90**).
- Default daily reminder time.
- Onboarding flow for newcomers **without** bundled starter decks (bundled decks are post-v1).
