# Workbench Chrome adapter

An unpacked Manifest V3 adapter for the Workbench Mac app. Saved resources in Workbench owns the destinations; each Chrome profile explicitly pairs under a name you choose. This adapter stores no passwords and does not sign in, change credentials, read page content, or establish that a persona is authenticated.

## Try the development build

1. Install the matching Workbench development app and enable **Chrome connection** in **Saved resources**.
2. In the intended Chrome profile, open `chrome://extensions`, enable **Developer mode**, choose **Load unpacked**, and select this `BrowserExtension` folder. Repeat for each profile you want to pair.
3. Pin Workbench, open its popup, type a profile name such as **Manager profile**, and select **Connect profile**.
4. Open the intended demo tab. In Workbench’s popup, expand **Save or update this tab**, type an audience-safe label such as **Manager**, and review the exact address. For a new site, choose **Allow this site**; Chrome closes the popup for its permission prompt. Reopen Workbench and finish **Save destination**. Your temporary draft survives, and no save runs after a denied prompt. Already-allowed sites save directly.
5. Choose a destination from any connected profile or Workbench’s Saved resources. Workbench routes it to its paired profile. Keep that profile open and connected.

When a tenant’s subdomain changes, open its new tab in the intended profile, select its existing destination under **Save or update this tab**, review the old and new addresses, and select **Update to this tab**. The existing destination ID is retained. Another profile cannot update it.

The stable unpacked ID is `ajafaiojgpdgmeblldllnhhfnafiiieo`; native host `com.ethdawg.workbench.browser` must allow exactly that extension origin. The manifest contains only a public key for stable identity, not a signing secret or published Web Store package.

## What activation means

The adapter remembers a destination’s tab only for the current browser session. It accepts that tab while it remains in the exact saved origin, including scheme and port. After a restart or stale binding it considers only tabs matching the saved address, ignoring query parameters and fragments. One match is focused; no match opens the saved address; multiple matches ask you to update from the right tab. It never navigates or closes an unrelated tab. An existing tab may have navigated within its tenant after being saved.

Chrome optional host grants are scheme-and-hostname patterns. The adapter enforces the narrower exact origin during every tab decision. A new subdomain requires a new explicit grant when saving or updating. Incognito is excluded. Names and addresses are rendered as text. Page titles are never copied into destination names. Native errors use a fixed message allowlist.

Success verifies Chrome’s tab-active and window-focused flags. It does not verify page rendering, authentication, or meeting capture. A timeout can be uncertain: check Chrome before activating again. Chrome does not offer an atomic read-and-focus operation, so a concurrent user navigation can lead to a failed final verification after a focus request has already occurred.

## State and connection

- `chrome.storage.local`: `profileID`, `profileName`, `paired` only. Never `storage.sync`.
- `chrome.storage.session`: `destinationTabs`, mapping destination UUID to current session tab ID and saved URL. Runtime IDs never enter durable storage.
- `chrome.storage.session`: a permission-step `saveDraft`, checked against its tab/address and a 15-minute expiry when reopening. It is an editable draft, not queued work.
- Native connection: one `connectNative` port per paired profile; version 1 UUID messages, 64 KiB packet ceiling, accepted hello before commands, at most 20 pending requests, 15-second request deadline. Focus has an 8-second deadline and accepts an optional native `expiresAt` timestamp no more than 10 seconds ahead.
- Disconnect: fail pending requests, abort in-flight focus, and schedule one reconnect alarm after 30 seconds. A paired profile reconnects on startup or worker restart. Activation is never automatically retried.

## Verification

Run `node --test BrowserExtension/tests/*.test.js` from the repository root. No npm install or runtime dependencies are needed. Tests use deterministic Chrome API fakes for URL handling, tab selection, permissions, duplicate tabs, focus verification, navigation and cancellation races, wire correlation, disconnects, timeouts, size limits and manifest/popup boundaries.

These tests do not establish live Chrome/native integration. Dogfood the matching native host with synthetic profiles and pages before distribution, including two profiles, browser restart, closed tabs, duplicate URLs, minimized windows, permission refusal and a tenant subdomain update.
