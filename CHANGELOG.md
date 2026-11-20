# Changelog

What changed in each release, from the point of view of someone using Sumi Write.
For the full commit history, see the git log.

中文版:[CHANGELOG.zh-CN.md](CHANGELOG.zh-CN.md)

## Unreleased

- The editing core (`core/`), the host↔backend service contract (`protocol/`) and the sync service (`sync/`) moved here from note.md with their history. The wire format is unchanged: pages written before the move sync and open as before.
- The sync service now carries its own pinned toolchain (Wrangler 3.114.17, Vitest 2.1.9, TypeScript 5.9.3) and reads Cloudflare credentials only from environment variables or the macOS Keychain; no file in the repository holds them.
- The plugin shell, its resources and three plugin-side scripts moved here from note.md into `apps/notemd-plugin/` with no behavior change; added an unsigned build artifact with a verification checklist.
