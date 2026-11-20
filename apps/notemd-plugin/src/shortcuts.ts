/**
 * Keyboard shortcut helpers, copied from note.md (commit e82e2f81) so the plugin
 * builds without importing note.md source. Function bodies are verbatim from:
 *   - plugins-src/shared/shortcuts.ts
 *   - src/lib/platform-sync.ts       (isApplePlatformSync)
 *   - src/lib/primary-modifier.ts    (hasPrimaryModifier)
 */

/**
 * True on Apple's WebKit (macOS WKWebView / iOS). Used where the answer is
 * needed before a promise can settle.
 */
export function isApplePlatformSync(): boolean {
  if (typeof navigator === 'undefined') return false
  // `navigator.platform` is deprecated but remains the most direct signal in
  // WKWebView; the user agent is the fallback and carries the same words.
  const legacy = (navigator as { platform?: string }).platform ?? ''
  const ua = navigator.userAgent ?? ''
  return /Mac|iPhone|iPad|iPod/i.test(legacy) || /Macintosh|iPhone|iPad|iPod/i.test(ua)
}

/** The application modifier; Super remains available to the Linux desktop. */
export function hasPrimaryModifier(event: { metaKey: boolean; ctrlKey: boolean }): boolean {
  return isApplePlatformSync() ? event.metaKey && !event.ctrlKey : event.ctrlKey && !event.metaKey
}

/** App-local shortcuts must not consume an IME action or another handler's event. */
export function shortcutEventBlocked(event: KeyboardEvent): boolean {
  return event.defaultPrevented || event.isComposing || event.keyCode === 229 || event.repeat
}

/** Cmd on Apple, Ctrl elsewhere; never claim the desktop's Super combinations. */
export function primaryShortcut(event: KeyboardEvent, key: string, shift = false): boolean {
  if (shortcutEventBlocked(event) || event.altKey || event.shiftKey !== shift) return false
  return hasPrimaryModifier(event) && event.key.toLowerCase() === key.toLowerCase()
}

export function primaryShortcutLabel(key: string, shift = false): string {
  return isApplePlatformSync()
    ? `${shift ? '⇧' : ''}⌘${key === 'Enter' ? '↵' : key.toUpperCase()}`
    : `Ctrl+${shift ? 'Shift+' : ''}${key}`
}

export function primaryShortcutAria(key: string, shift = false): string {
  return `${isApplePlatformSync() ? 'Meta' : 'Control'}+${shift ? 'Shift+' : ''}${key}`
}
