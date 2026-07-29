# Offline third-party resources

| Package | Version | File | SHA256 | License |
| --- | --- | --- | --- | --- |
| markdown-it | 14.1.0 | `vendor/markdown-it-14.1.0.min.js` | `38c70a1e7ca91ab40e2d9e6e60129851a717ed1c7d4acbbdd41bf9503791cf68` | MIT, `vendor/markdown-it-14.1.0-LICENSE` |
| markdown-it-footnote | 4.0.0 | `vendor/markdown-it-footnote-4.0.0.min.js` | `d6fee58a3b56c5742fa18f3e01f1d317cc99975683ebd39c9195cb2aff0c2e42` | MIT, `vendor/markdown-it-footnote-4.0.0-LICENSE` |

Both files are vendored from their npm release tarballs. They are bundled with the application and no runtime network request is permitted by `index.html`'s CSP.
