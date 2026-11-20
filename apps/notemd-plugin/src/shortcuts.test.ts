import { afterEach, describe, expect, it, vi } from 'vitest'
import { primaryShortcut, shortcutEventBlocked } from './shortcuts'

function ev(init: Partial<KeyboardEvent>): KeyboardEvent {
  return { key: 's', metaKey: false, ctrlKey: false, shiftKey: false, altKey: false,
    isComposing: false, keyCode: 0, repeat: false, defaultPrevented: false, ...init } as KeyboardEvent
}
function platform(value: string, ua = '') {
  vi.stubGlobal('navigator', { platform: value, userAgent: ua })
}

afterEach(() => vi.unstubAllGlobals())

describe('shortcuts', () => {
  it('primaryShortcut_mac_requires_meta_without_ctrl', () => {
    platform('MacIntel')
    expect(primaryShortcut(ev({ metaKey: true, key: 's' }), 's')).toBe(true)
    expect(primaryShortcut(ev({ metaKey: true, ctrlKey: true, key: 's' }), 's')).toBe(false)
  })
  it('primaryShortcut_other_requires_ctrl_without_meta', () => {
    platform('Linux x86_64')
    expect(primaryShortcut(ev({ ctrlKey: true, key: 'S' }), 's')).toBe(true)
    expect(primaryShortcut(ev({ ctrlKey: true, metaKey: true, key: 's' }), 's')).toBe(false)
  })
  it('blocked_events_never_match', () => {
    platform('Linux x86_64')
    for (const flag of [{ isComposing: true }, { keyCode: 229 }, { repeat: true }, { defaultPrevented: true }]) {
      const e = ev({ ctrlKey: true, ...flag })
      expect(shortcutEventBlocked(e)).toBe(true)
      expect(primaryShortcut(e, 's')).toBe(false)
    }
  })
  it('shift_and_alt_must_match_exactly', () => {
    platform('Linux x86_64')
    expect(primaryShortcut(ev({ ctrlKey: true, shiftKey: true }), 's')).toBe(false)
    expect(primaryShortcut(ev({ ctrlKey: true, shiftKey: true }), 's', true)).toBe(true)
    expect(primaryShortcut(ev({ ctrlKey: true, altKey: true }), 's')).toBe(false)
  })
})
