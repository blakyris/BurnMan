<p align="center">
  <img src="BurnMan/Assets.xcassets/AppIcon.appiconset/icon_256_1x.png" width="128" height="128" alt="BurnMan icon">
  <br>
  <strong style="font-size: 2em;">BurnMan</strong>
  <br>
  <em>Open source burning software for the Mac</em>
</p>

---

## Why?

Every CD/DVD burning app on macOS is either abandonware, closed-source, overpriced, or all three. I got tired of dealing with clunky, proprietary software just to burn a disc — so I decided to build my own.

BurnMan is a native macOS app built with SwiftUI that wraps powerful open-source tools (cdrdao, ffmpeg, dvd+rw-tools) in a clean, modern interface. It's designed for macOS 26 (Tahoe) with Liquid Glass.

> **This project is a work in progress.** Things may break, features are still being added, and the API is not stable. Contributions and feedback are welcome!

## Requirements

- **macOS 26** (Tahoe) or later
- **Xcode 26** or later
- A USB CD/DVD burner

## Getting Started

```bash
git clone https://github.com/YOUR_USERNAME/BurnMan.git
cd BurnMan
chmod +x setup.sh
./setup.sh
```

The setup script will install dependencies (cdrdao, XcodeGen) via Homebrew, generate the Xcode project, and open it for you.

Then in Xcode: select the **BurnMan** scheme, choose **My Mac**, and hit `⌘R`.

## License

This project is licensed under the **GNU General Public License v3.0** — see the [LICENSE](LICENSE) file for details.
