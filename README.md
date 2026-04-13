# X for macOS (Unofficial)

An **unofficial macOS desktop app** for X (Twitter), built as a lightweight native wrapper.

Modified based on project [alexcding/gemini-desktop-mac](https://github.com/alexcding/gemini-desktop-mac).

> **Disclaimer:**
> This project is **not affiliated with, endorsed by, or sponsored by X Corp**.
> "X" and "Twitter" are trademarks of **X Corp**.
> This app does not modify, scrape, or redistribute X content — it simply loads the official website.

---

## Features

- Native macOS desktop experience with unified titlebar
- Lightweight WebKit wrapper
- Safari 17.6 user agent
- Camera & microphone support
- Reset website data (cookies, cache, sessions)

---

## System Requirements

- **macOS 12.0** (Monterey) or later

---

## Build from Source

```bash
cd x-desktop-mac
sh build.sh
open build/X.app
```

---

## Project Structure

```
App/            App lifecycle and delegate
Coordinators/   Navigation and window coordination
Views/          SwiftUI views (main window, settings)
WebKit/         WKWebView wrapper, view model, user scripts
Utils/          Shared constants and types
Resources/      Assets, icons, Info.plist
```

---

## License

Open source — see repository for details.
