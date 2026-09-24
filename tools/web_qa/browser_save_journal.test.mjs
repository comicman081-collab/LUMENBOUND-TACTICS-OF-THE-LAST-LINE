import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import vm from 'node:vm';

const gd = readFileSync(new URL('../../godot/autoload/browser_save_journal.gd', import.meta.url), 'utf8');
const source = gd.match(/const SCRIPT := """([\s\S]*?)"""/)[1];
function harness(storage = new Map(), fail = false) {
  const context = {window: {}, localStorage: {
    getItem: key => storage.get(key) ?? null,
    setItem: (key, value) => {if (fail) throw {name: 'QuotaExceededError'}; storage.set(key, value);},
    removeItem: key => storage.delete(key),
  }};
  vm.runInNewContext(source, context);
  return context.window.__lumenboundSaveJournal;
}

test('the acknowledged transaction survives an immediate new page context', () => {
  const storage = new Map(), write = harness(storage);
  assert.equal(write('write', 'production', 'skill-level-1'), 'ok');
  assert.equal(write('write', 'production', 'skill-level-2'), 'ok');
  const reload = harness(storage);
  assert.equal(reload('read', 'production'), 'skill-level-2');
  assert.equal(reload('backup', 'production'), 'skill-level-1');
});
test('a failed write preserves the previous committed transaction', () => {
  const storage = new Map();
  harness(storage)('write', 'production', 'paid-state');
  assert.equal(harness(storage, true)('write', 'production', 'next-state'), 'QuotaExceededError');
  assert.equal(harness(storage)('read', 'production'), 'paid-state');
});
test('sandbox writes and resets leave the production journal intact', () => {
  const storage = new Map(), journal = harness(storage);
  journal('write', 'production', 'player-state');
  journal('write', 'qa-session', 'test-state');
  journal('clear', 'qa-session');
  assert.equal(journal('read', 'production'), 'player-state');
  assert.equal(journal('read', 'qa-session'), '');
});
test('unreadable or unsupported journals permit the existing file recovery path', () => {
  for (const value of ['bad JSON', 'null', '{"version":99,"current":"wrong"}']) {
    assert.equal(harness(new Map([['production', value]]))('read', 'production'), '');
  }
});
