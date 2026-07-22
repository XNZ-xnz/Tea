# Tea 🍵

> **Work in progress — not yet usable.** Nothing to download here yet; watch the repo for the first release.

**Tea** is a free, open-source macOS app that runs Windows Steam games on Apple Silicon Macs — one-click install, one-click play.

It manages a fully automated [Wine](https://www.winehq.org) environment under the hood: installs Windows Steam into it, translates DirectX to Metal (via [DXMT](https://github.com/3Shain/dxmt), or Apple's D3DMetal if you import the Game Porting Toolkit yourself), and gets out of your way. Think "open-source CrossOver gaming mode with a Proton-style out-of-the-box experience" — no terminal, no jargon.

## Status

Early development. Roadmap: engine core → graphics backends → Steam integration → GUI → compatibility database → v1.0 release.

## Principles

- **No third-party binaries in this repo or its releases.** Wine builds and DXMT are downloaded at runtime from their official releases (HTTPS, pinned versions, SHA256-verified). Apple's D3DMetal is never downloaded or distributed — you import your own Game Porting Toolkit copy. Windows Steam comes straight from Valve's official installer URL.
- **Your Steam credentials are untouchable.** Login happens exclusively inside Steam's own window. Tea never reads, stores, or automates it.
- **No telemetry.** Diagnostics are generated locally and submitted only by you, after you've read them.
- **No fabricated compatibility data.** Every compatibility claim carries a source: a first-party test report or linked community evidence.

## License

[GPL-3.0](LICENSE). Tea stands on the shoulders of the Wine/Whisky/Mythic ecosystem and gratefully credits prior art where code is adapted.

Tea is not affiliated with Valve, Apple, or any game publisher. All product names are used solely to describe compatibility facts.
