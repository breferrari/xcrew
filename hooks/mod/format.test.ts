import { expect, test } from 'claude-code/testing'
import { gauge, remaining } from './format'

test('a gauge is heavy cells for the part done and light cells for the rest, to half a cell', () => {
  expect(gauge(0, 8)).toEqual({ done: '', rest: '────────' })
  expect(gauge(0.5, 8)).toEqual({ done: '━━━━', rest: '────' })
  expect(gauge(0.56, 8)).toEqual({ done: '━━━━╸', rest: '───' })
})

test('anything started shows a sliver, and past the end the gauge stays full', () => {
  expect(gauge(0.01, 8)).toEqual({ done: '╸', rest: '───────' })
  expect(gauge(1.4, 8)).toEqual({ done: '━━━━━━━━', rest: '' })
})

test('the time left is an estimate until the usual time passes, then it counts how far over', () => {
  expect(remaining(21_000, 36_000)).toEqual({ text: '~0:15 left', isOver: false })
  expect(remaining(52_000, 44_000)).toEqual({ text: '0:08 over', isOver: true })
})
