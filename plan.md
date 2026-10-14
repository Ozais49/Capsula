# Universal Bookmark & Personal Content Library — Product Plan

## 1. Project Status

**Stage:** Product planning / brainstorming converted into an implementation-ready specification.

**Important:** This document is a plan for Codex. Do not start implementing features merely because they are described here. Implementation should begin only after the relevant phase is explicitly approved.

**Initial platforms:**
- Android
- Web

**Primary development environment:**
- Visual Studio Code
- Minimal Android development setup
- Git
- Flutter/Dart
- Firebase initially

---

# 2. Product Vision

Build a universal personal bookmark and content library that lets a user:

1. Save links from anywhere.
2. Receive links directly through the Android Share Target.
3. Import an existing bookmark library from browsers and bookmark services such as Raindrop.
4. Organize bookmarks independently by source, tags, and collections.
5. Read supported web content inside the application through an integrated reader.
6. Open the original URL in the user's default browser whenever desired.
7. Synchronize the same library across Android and Web.
8. Start with Firebase while keeping the storage layer replaceable as the application grows.

The product should not be thought of as only a "bookmark folder app".

The intended model is:

> **Capture → Import → Organize → Read → Sync**

---

# 3. Core Product Principles

## 3.1 Saving must be extremely low friction

The primary Android workflow should be:

`Any Android app → Share → Our App → Save → Done`

The user should not be required to choose a folder, tag, or collection before saving.

New items should normally enter an **Inbox**.

---

## 3.2 Source and organization are independent

A source is metadata, not a folder.

For example:

```text
Bookmark
  URL: https://reddit.com/...
  Source: Reddit
  Tags: AI, Research
  Collections: AI Research
  Status: Inbox
```

Do NOT model "Reddit" as a folder.

The same bookmark should be discoverable through multiple dimensions:

- Source
- Tags
- Collections
- Search
- Reading status
- Import origin

---

## 3.3 Firebase is an implementation choice, not the domain model

The application should not tightly couple business logic to Firebase.

Use a repository/data-access abstraction so the backend can later move from:

`Firebase → own API/PostgreSQL/other storage`

without rewriting the core application.

---

## 3.4 Capture first, organization later

The application should optimize for:

> Save now, organize later.

The user should never be blocked from saving because metadata extraction or categorization is slow.

---

# 4. Target Platforms

## 4.1 Android — First-class platform

Android is a core platform, not merely a companion app.

Required capabilities:

- Android Share Target
- Save shared URLs
- Detect source/application where practical
- Local cached library
- Firebase synchronization
- Search
- Tags
- Collections
- Inbox
- Integrated reader
- Open original URL in default browser

Potential future capabilities:

- Browser extension integration
- Clipboard URL detection
- Offline reader
- Share content other than URLs

---

## 4.2 Web — First-class platform

The web application should provide:

- Authentication
- Bookmark library
- Inbox
- Source views
- Tags
- Collections
- Search
- Bookmark details
- Reader
- Import
- Add URL manually
- Open original URL

A browser extension is **not required for the initial MVP**, but the architecture should leave room for it.

---

# 5. Capture Requirements

## 5.1 Android Share Target

The application must register as an Android share target.

Example:

```text
Reddit
  ↓
Share
  ↓
Bookmark App
  ↓
Save
```

Initial target types:

- HTTP URLs
- HTTPS URLs
- Text containing URLs where practical

The app should work with links shared from:

- Reddit
- Instagram
- YouTube
- Facebook
- X
- TikTok
- Telegram
- Chrome
- Other Android applications

Do not build source-specific integrations unless they are actually necessary.

Prefer Android's standard sharing mechanisms.

---

## 5.2 Source Detection

The application should attempt to identify the content source.

Examples:

```text
reddit.com       → Reddit
instagram.com    → Instagram
youtube.com      → YouTube
github.com       → GitHub
x.com             → X
amazon.*         → Amazon
other domains    → Website
```

Source detection should primarily be based on URL/domain and other reliable metadata.

Do not depend on the originating Android application's package name unless necessary.

The detected source should be stored as metadata.

---

# 6. Bookmark Data Model — Conceptual

The exact schema can be refined during technical design, but the conceptual model should contain at least:

```text
Bookmark
- id
- userId
- url
- canonicalUrl
- title
- description
- thumbnail/image
- source
- sourceDomain
- createdAt
- updatedAt
- readingStatus
- archived
- metadata
```

Additional concepts:

## Tags

User-defined labels.

Examples:

```text
AI
Programming
Travel
Interesting
Buy
Read Later
```

A bookmark can have multiple tags.

## Collections

User-defined groups.

Examples:

```text
AI Research
Japan Trip
Programming Resources
Home Ideas
```

A bookmark can belong to multiple collections if desired by the final UX.

## Origin / Import Metadata

Keep provenance separately from content source.

Example:

```text
Content source:
  Reddit

Imported from:
  Raindrop

Imported at:
  2026-10-05
```

This distinction is important.

A Reddit URL imported from Raindrop is:

- Content source = Reddit
- Import origin = Raindrop

---

# 7. Inbox

Newly captured/imported bookmarks should have an Inbox state.

Example:

```text
Inbox
  ├── 12 Reddit links
  ├── 5 YouTube links
  ├── 8 Websites
  └── 3 Instagram links
```

The user can later:

- Tag
- Add to collection
- Mark as read
- Archive
- Delete

Do not force organization at capture time.

---

# 8. Reading States

The initial conceptual states should support:

```text
Saved
Read Later
Reading
Read
Archived
```

The exact UX can be simplified for MVP.

The important requirement is that reading status is independent from source, tags, and collections.

---

# 9. Integrated Reader

The app should provide an in-app reading experience for supported web content.

Desired workflow:

```text
Bookmark
  ↓
Open
  ↓
Integrated Reader
  ↓
Read content
  ↓
Open in Browser
```

The user must always have a clear option to leave the app and open the original URL in the default browser.

---

## 9.1 Reader is NOT simply "everything in a WebView"

The long-term goal is content extraction / reader mode:

```text
Original URL
   ↓
Fetch / resolve content
   ↓
Extract main content
   ↓
Remove unnecessary page chrome
   ↓
Render clean reader view
```

However, not every URL is an article.

Content should be handled according to type.

Example conceptual behavior:

| Content | Preferred behavior |
|---|---|
| Article | Reader mode |
| Blog | Reader mode |
| Documentation | Reader mode / original |
| Reddit | Content preview / original |
| YouTube | Video/content view |
| Instagram | Preview / original |
| GitHub | Content-aware view / original |
| Amazon | Product preview / original |
| Arbitrary webpage | WebView/fallback |
| Login-required page | Open browser |

Reader extraction quality should not block bookmark saving.

---

# 10. Import System

Import must be a first-class product capability.

## 10.1 Browser imports

Target sources:

- Chrome
- Firefox
- Edge
- Safari
- Other browsers where practical

Prefer supporting standard browser-export formats where possible.

HTML bookmark import should be a generic fallback.

---

## 10.2 Bookmark service imports

Initial target:

- Raindrop

Potential future targets:

- Pocket
- Pinboard
- Other bookmark managers

Do not build dozens of service-specific integrations during MVP.

---

## 10.3 Generic imports

Support common portable formats where practical:

- HTML bookmarks
- CSV
- JSON
- OPML where relevant

Provide a mapping step for generic formats.

Example:

```text
Imported field → App field

url        → URL
title      → Title
folder     → Collection
tags       → Tags
created_at → Created date
```

---

## 10.4 Import Preview

Never blindly import a large library.

Example:

```text
Import Preview

1,247 bookmarks found

1,182 new
43 duplicates
22 invalid URLs

[Import]
[Cancel]
```

The import flow should eventually support:

- Duplicate detection
- Invalid URL detection
- Mapping
- Collection/folder preservation where possible
- Tag preservation where possible
- Import provenance

---

# 11. Duplicate Detection

The application should recognize duplicate URLs.

Example:

```text
User saves:
https://example.com/article

Existing:
https://example.com/article/
```

The system should attempt canonical URL comparison.

Potential future behavior:

```text
Already saved

Saved 3 months ago
Source: Reddit
Tags: AI, Research
```

Do not implement aggressive content-level duplicate merging in the first version unless technically justified.

Start with URL/canonical-URL based duplicate detection.

---

# 12. Search

Search is a core requirement.

Users should be able to search:

- Title
- URL/domain
- Source
- Tags
- Collections
- Description/metadata where available

Future capability:

- Full-text reader content search
- Semantic/AI search

Do not make semantic search an MVP dependency.

---

# 13. Source Views

The UI should allow views such as:

```text
All
Inbox
Reddit
YouTube
Instagram
GitHub
Websites
```

These are filtered views, not separate folders/databases.

A bookmark may appear in:

```text
Reddit
AI
AI Research
Inbox
Search results
```

simultaneously.

---

# 14. Organization

Initial organization mechanisms:

### Source
Automatically detected.

### Tags
User-defined, many-to-many.

### Collections
User-defined grouping.

### Reading status
Saved / Reading / Read / Archived.

### Inbox
Recently captured/imported items awaiting organization.

Avoid excessive folder hierarchy in the initial product.

---

# 15. Sync Requirements

The same account should expose the same library on:

```text
Android ↔ Cloud ↔ Web
```

Initial backend:

- Firebase Authentication
- Firestore
- Firebase Storage if required for assets
- Cloud Functions only where needed

Requirements:

- User isolation
- Secure authentication
- Consistent IDs
- Created/updated timestamps
- Conflict handling
- Retry behavior
- Local caching on Android
- Reasonable offline tolerance

The exact offline-first strategy should be designed before implementation rather than improvised inside UI code.

---

# 16. Storage Abstraction

Create a logical repository boundary.

Conceptually:

```text
UI
 ↓
Application/domain layer
 ↓
Repository interfaces
 ↓
Firebase implementation
```

Do not spread Firebase SDK calls throughout UI/business logic.

Future possibility:

```text
Repository
   ├── Firebase
   ├── REST API
   ├── PostgreSQL-backed API
   └── Other provider
```

The first implementation only needs Firebase.

---

# 17. Firebase Data Isolation

Every user's bookmark data must be isolated.

The security model should assume:

> A client must never be trusted to choose another user's userId.

Firebase security rules must enforce ownership based on the authenticated identity.

Before implementation, explicitly design and test:

- Read authorization
- Write authorization
- Update authorization
- Delete authorization
- Collection membership authorization
- Tag authorization
- Import authorization
- Any shared/public data

Security rules are part of the product requirements, not an afterthought.

---

# 18. Android Technical Direction

## Recommended initial stack

Use:

**Flutter + Dart**

Reason:

- Android and Web can share substantial application code.
- Strong Visual Studio Code support.
- Relatively minimal developer setup.
- Good fit for a single developer building an Android + Web product.
- Native Android capabilities can still be accessed when required.
- Firebase has Flutter support.
- Android Share Target can be implemented through Android platform integration/plugins.

If Android Share Target behavior proves insufficient through an existing Flutter package, use a small native Android integration rather than abandoning the cross-platform architecture.

---

# 19. Minimal Development Environment

The target developer environment is:

- Windows/macOS/Linux as supported by Flutter
- Visual Studio Code
- Flutter SDK
- Dart SDK (bundled with Flutter)
- Android SDK
- Android SDK Platform Tools
- Android build tools required by the selected Flutter version
- Java/JDK version required by the selected Flutter/Android toolchain
- Git

Avoid installing Android Studio unless it is actually needed for SDK/device management.

The goal is:

> **VS Code as the primary IDE, command-line Android tooling where practical.**

---

# 20. Android Setup Requirement

The setup documentation must eventually provide a clean sequence for:

1. Install Git.
2. Install Flutter SDK.
3. Add Flutter to PATH.
4. Install Visual Studio Code.
5. Install Flutter and Dart VS Code extensions.
6. Install Android command-line SDK tooling.
7. Configure:
   - Android SDK
   - Platform Tools
   - Build Tools
   - Android platform
   - Command-line tools
8. Configure Java/JDK compatible with the selected Flutter/Gradle toolchain.
9. Accept Android SDK licenses.
10. Run:

```bash
flutter doctor
```

11. Resolve all required Android/Flutter issues.
12. Create/configure an Android emulator OR connect a physical Android device.
13. Verify:

```bash
flutter devices
```

14. Create a minimal Flutter project.
15. Run it on Android.
16. Run the same project on Web.

Do not add unnecessary tooling.

---

# 21. Development Tooling Principle

Before adding any dependency, ask:

> Is this required for the product, or is it merely convenient?

Prefer:

- Official Flutter/Dart tooling
- Official Firebase packages
- Small, well-maintained dependencies
- Platform APIs where appropriate

Avoid dependency sprawl.

---

# 22. Initial UX

## Android home screen

Possible structure:

```text
┌─────────────────────────────┐
│ Search                  🔍  │
├─────────────────────────────┤
│ Inbox                   12  │
│                             │
│ All                         │
│ Reddit                      │
│ YouTube                     │
│ Instagram                   │
│ Websites                    │
│                             │
│ Collections                 │
│  AI Research                │
│  Programming                │
│  Travel                     │
├─────────────────────────────┤
│ Home  Search  Collections  │
└─────────────────────────────┘
```

This is illustrative, not a fixed UI design.

---

# 23. Save Flow

The ideal save flow is extremely short.

```text
User is in Reddit
      ↓
Share
      ↓
Bookmark App
      ↓
URL captured
      ↓
Bookmark created
      ↓
Inbox
      ↓
Optional metadata enrichment
```

Metadata enrichment must not prevent the initial save.

---

# 24. Bookmark Detail

Conceptually:

```text
Title

Source: Reddit
example.com

Tags:
[AI] [Research]

Collection:
AI Research

Status:
Read Later

----------------------------

Reader / Content

----------------------------

Open in Browser ↗
```

---

# 25. Import Flow

```text
Settings / Import
        ↓
Select source
        ↓
Select file / authenticate
        ↓
Parse
        ↓
Preview
        ↓
Detect duplicates
        ↓
Map fields if necessary
        ↓
Import
        ↓
Show result
```

Example result:

```text
Import complete

1,182 imported
43 duplicates skipped
22 invalid URLs
```

---

# 26. Error Handling Requirements

The application should gracefully handle:

- Invalid URLs
- Deleted pages
- Unreachable URLs
- Private/login-required pages
- Metadata extraction failure
- Reader extraction failure
- Network failure
- Firebase failure
- Duplicate bookmarks
- Import format errors
- Partially completed imports
- Sync conflicts

A failed reader extraction must NOT mean the bookmark is lost.

Fallback:

> Open original URL in browser.

---

# 27. Privacy & Security

The application contains potentially sensitive personal browsing/bookmark data.

Requirements:

- Per-user data isolation
- Secure authentication
- Strict Firebase security rules
- HTTPS/network security
- No unnecessary collection of user data
- Avoid logging full private URLs unnecessarily
- Do not expose bookmark data through public Firebase rules
- Treat imported bookmark data as private by default

Future requirements may include:

- Data export
- Account deletion
- Full library deletion
- Encryption strategy
- Self-hosted backend

---

# 28. MVP Scope

The MVP should include:

## Android

- Authentication
- Android Share Target
- Save URL
- Source detection
- Inbox
- Bookmark list
- Search
- Tags
- Collections
- Reading status
- Bookmark details
- Integrated basic reader
- Open in default browser
- Firebase sync

## Web

- Authentication
- Library
- Inbox
- Source views
- Search
- Tags
- Collections
- Bookmark details
- Reader
- Open original URL
- Manual URL save

## Import

At minimum:

- Browser HTML bookmark import
- Raindrop import if practical for the first release
- Duplicate detection
- Import preview
- Import provenance

---

# 29. Explicitly Out of MVP

Do not automatically expand the first implementation into:

- AI auto-tagging
- Semantic search
- Social features
- Shared collections
- Recommendations
- Public profiles
- Browser extension
- Desktop native application
- iOS
- Advanced offline reader
- Full content archival
- Complex source-specific integrations
- Automatic summarization
- AI categorization
- Self-hosted backend

These can be evaluated after the core workflow is reliable.

---

# 30. Suggested Development Phases

## Phase 0 — Environment

Goal:

> Developer can build/run Android and Web from VS Code.

Deliverables:

- Flutter installed
- Android SDK configured
- Physical device or emulator working
- Web target working
- Git repository initialized
- Basic project builds successfully

---

## Phase 1 — Foundation

Goal:

> Establish architecture without building the entire product.

Deliverables:

- Project structure
- Routing/navigation
- Theme/design system foundation
- Firebase configuration
- Authentication
- Repository abstraction
- Environment/configuration strategy

---

## Phase 2 — Bookmark Core

Goal:

> Save and view bookmarks.

Deliverables:

- Bookmark model
- Bookmark repository
- Create bookmark
- List bookmarks
- Bookmark detail
- Delete/archive
- Source detection
- Basic search
- Firebase persistence

---

## Phase 3 — Android Share Target

Goal:

> Make the app useful from any Android application.

Deliverables:

- Android Share Target
- Receive URLs
- Handle shared text containing URLs
- Save directly to Inbox
- Handle duplicate URLs
- Source detection
- Error handling

This phase is critical.

---

## Phase 4 — Organization

Deliverables:

- Tags
- Collections
- Inbox
- Reading status
- Source views
- Filters
- Search improvements

---

## Phase 5 — Reader

Deliverables:

- Reader screen
- Content extraction strategy
- Article rendering
- Image handling
- Fallback behavior
- Open in default browser
- Reader failure handling

The reader must never prevent the bookmark itself from being saved.

---

## Phase 6 — Import

Deliverables:

- HTML import
- Import preview
- Duplicate detection
- Mapping
- Provenance
- Raindrop importer
- Import result reporting

---

## Phase 7 — Web

Deliverables:

- Web authentication
- Library
- Search
- Organization
- Reader
- Manual URL capture
- Import interface where practical

---

## Phase 8 — Hardening

Focus on:

- Security rules
- Data isolation
- Sync correctness
- Error handling
- Performance
- Large libraries
- Importing thousands of bookmarks
- Accessibility
- UX refinement
- Testing
- Backup/export strategy

---

# 31. Testing Requirements

Testing should cover at least:

## Unit tests

- URL canonicalization
- Source detection
- Duplicate detection
- Import parsing
- Field mapping
- Repository behavior

## Integration tests

- Firebase authentication
- Bookmark CRUD
- User isolation
- Sync
- Import

## Android tests

- Share target
- URL extraction
- Multiple Android apps
- Invalid share payloads
- No-network behavior

## Web tests

- Authentication
- Bookmark creation
- Search
- Reader
- Organization

## Security tests

Explicitly attempt:

```text
User A → read User B's bookmarks
User A → modify User B's bookmark
User A → delete User B's bookmark
```

All must fail.

---

# 32. Large Library Considerations

The design should not assume a user has only 100 bookmarks.

Plan for:

- Thousands of bookmarks
- Potentially tens/hundreds of thousands over time
- Pagination
- Incremental synchronization
- Efficient search
- Efficient source filtering
- Efficient tag filtering
- Import batches

Do not load the entire library into memory on every screen.

---

# 33. Future Architecture Direction

Potential long-term architecture:

```text
                    ┌─────────────┐
                    │ Android App │
                    └──────┬──────┘
                           │
                    ┌──────▼──────┐
                    │ Application │
                    │ / Domain    │
                    └──────┬──────┘
                           │
                  Repository interfaces
                           │
              ┌────────────┴────────────┐
              │                         │
       Firebase implementation    Future API/backend
```

The UI should depend on application/domain abstractions rather than directly on Firebase.

---

# 34. Product Decisions That Must Remain Flexible

Do not prematurely lock down:

- Exact Firebase schema
- Exact reader extraction provider
- Exact search technology
- Exact import implementation for every service
- Exact UI layout
- AI functionality
- Offline synchronization algorithm
- Future backend
- Browser extension architecture

The plan defines requirements and direction, not every implementation detail.

---

# 35. Codex Working Instructions

When implementation begins, Codex should follow these principles:

1. **Do not implement the entire product in one pass.**
2. Work phase-by-phase.
3. Before coding a phase, inspect the existing repository and current state.
4. Do not invent requirements that are not present in this plan or explicitly approved later.
5. Prefer simple architecture over premature abstraction.
6. Keep Firebase behind repository/data-access boundaries.
7. Keep domain concepts independent:
   - Bookmark
   - Source
   - Tag
   - Collection
   - Reading status
   - Import origin
8. Do not model source as a folder.
9. Saving a bookmark must remain independent from reader extraction.
10. Reader failure must never delete or invalidate a saved bookmark.
11. Preserve imported metadata and provenance where possible.
12. Treat user bookmark data as private.
13. Never weaken Firebase security rules merely to make development easier.
14. Add tests for security-sensitive and data-integrity behavior.
15. Avoid unnecessary third-party dependencies.
16. Keep Android and Web behavior consistent where practical.
17. Use native Android integration only where Flutter abstractions are insufficient.
18. Keep the project buildable after every meaningful change.
19. Do not introduce AI functionality unless explicitly requested.
20. Do not implement out-of-MVP features without explicit approval.
21. When committing, do not mention or hint at AI assistance in commit messages, PR descriptions, or code comments. Do not add `Co-Authored-By` trailers or any AI attribution lines.

---

# 36. Definition of Success

The first meaningful product milestone is:

> A user installs the Android app, logs in, shares a link from Reddit/Instagram/YouTube/Chrome, the bookmark is saved immediately into their Inbox, synchronized to Firebase, appears on the Web application, can be organized with tags/collections, can be read inside the app when supported, and can be opened in the default browser at any time.

The second major milestone is:

> A user can import their existing bookmark library from a browser/Raindrop without losing useful organization or provenance.

If those two workflows are excellent, the core product is working.

---

# 37. Product Summary

The application is a:

> **Universal personal bookmark and content library for Android and Web.**

Its core capabilities are:

```text
SAVE
  ↓
IMPORT
  ↓
ORGANIZE
  ↓
READ
  ↓
SYNC
```

with the central principle:

> **Save anything from anywhere, organize it independently of its source, and read it without being forced to leave the app.**
