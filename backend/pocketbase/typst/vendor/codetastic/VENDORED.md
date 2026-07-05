Vendored copy of the `codetastic` Typst package (used here only for its
`qrcode()` function, on the case-report PDF, federfall-gdp8).

- Source: https://github.com/jneug/typst-codetastic
- Version: 0.2.2 (`typst.toml`)
- License: MIT, (c) 2023 Jonas Neugebauer (see `LICENSE`)
- Vendored (not fetched via `@preview/codetastic` at compile time) so PDF
  generation never depends on the Typst package registry being reachable from
  inside the container — same reasoning as the pinned Flutter SDK / the
  checksum-verified PocketBase binary fetch in the root `Dockerfile`.

Files here are an unmodified copy of everything the upstream repo ships
(minus `manual.typ`/`manual.pdf`/`assets/`, which its own `typst.toml`
`exclude` list drops from the published package too). To bump the version,
re-fetch all files from the same repo at the new tag and diff before
committing.
