# Changelog

Corrector follows its single source of truth: the version shown in the app's
footer comes from `Sources/CorrectorAppCore/Release.swift`, and the release
notes in the hover panel are the same list as the one below.

## 5.1.2 — beta

[Download](https://github.com/pedrolastiko/Corrector/releases/tag/v5.1.2-beta)
(universal binary, Apple silicon and Intel).

### New

- **A settings window**, at ⌘,. Five tabs: general, dictionary, rules,
  shortcut and updates. The personal dictionary, the muted rules and the
  applications ⌥⌘C refuses to act in were already stored — they simply had no
  interface, and could only be read back with `defaults`.
- **Corrector can update itself**, through Sparkle. A build carrying an update
  feed and a public key checks for new versions and installs them. A build
  without them reports that it has no feed rather than offering a button that
  cannot work.

### Fixed

- **Adding a word to the dictionary and muting a rule are no longer one-way
  doors.** Both buttons wrote to a store nothing could read back, so a wrong
  click could not be undone from inside the app. Both are now reversible in
  the settings window, and the document is re-checked immediately.

### Note on dependencies

Sparkle is the project's first external dependency, and it is confined to the
app target: the libraries and the test suite still fetch nothing, so
`swift test` works offline. `swift build` now needs the network once.

---

## 0.5.1 — beta

[Download](https://github.com/pedrolastiko/Corrector/releases/tag/v0.5.1-beta)
(universal binary, Apple silicon and Intel).

### New

- **A button in the toolbar clears the document**, beside Copy. Disabled while
  the document is already empty.
- **The clear can be taken back for thirty seconds.** The same button turns
  into an undo arrow and puts the text back. This is not a convenience: text
  replaced programmatically never enters the text view's own undo stack, so
  ⌘Z does not undo a clear and nothing else would have.
- **Corrector can open at login**, from the menu-bar menu. The setting lives
  with macOS, in System Settings → General → Login Items, so it can be revoked
  without the app running and the menu always shows what the system actually
  reports — including the state where macOS has the registration but is
  waiting for your approval.

---

## 0.5 — beta

First public release —
[download](https://github.com/pedrolastiko/Corrector/releases/tag/v0.5.0-beta)
(universal binary, Apple silicon and Intel).

The build is ad-hoc signed and not notarised, so the first launch needs a
right-click → **Open** → **Open**.

### What it does

- Checks spelling, grammar, punctuation, typography, clarity, engagement,
  style and inclusive language, with seven rule plugins per language.
- English and French, both for the checks and for the interface, chosen
  independently of each other.
- Three ways in: a window with suggestions reviewed card by card, two entries
  in the right-click **Services** menu, and **⌥⌘C** to correct the selection
  wherever the cursor happens to be.
- A command-line front end sharing every module with the app: `corrector check`,
  `fix`, `stats` and `demo`, with `--json` for machines.
- No network, no account, no telemetry. Everything is computed on the machine.

### New

- **⌥⌘C replaces text through the Accessibility API** when the application
  allows it, so the change lands in that application's own undo stack and the
  clipboard is never borrowed. The clipboard round trip remains as a fallback,
  because it is the one road that works everywhere.
- **The shortcut refuses to act in password fields**, checking
  `AXSecureTextField` as both a role and a subrole because toolkits disagree
  about which one it is, and in a default list of applications: keychains,
  password managers, terminals.
- **The shortcut applies spelling and punctuation only.** It acts on text
  nobody is watching, in a document Corrector cannot show you, so it is held to
  the rules that cannot be a matter of opinion. The Services menu keeps the
  wider set, because there you are looking at what you selected.

### Fixed

- **Correcting a selection no longer capitalises it or appends a full stop.**
  A selection is a fragment, not a sentence, and the rules that reason about
  sentence boundaries were reliably wrong about it.
- **The dialect you choose is now actually used for spelling.** It was being
  accepted in the toolbar and then dropped before it reached the checker, so
  British and American spellings were treated alike.
- **A missing regional dictionary no longer reports a clean document.** An
  uninstalled language returns an empty result, which is indistinguishable from
  having found nothing wrong; checking now falls back to the base language
  instead of silently passing everything.

### Known limits

- The global shortcut needs Accessibility permission. Everything else does not.
- The denylist behind the shortcut has no editing interface yet; adding an
  application means `defaults write`.
- The whole document is re-checked on each debounced keystroke rather than
  incrementally.
