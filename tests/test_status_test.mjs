// The watcher is an extension, but its routing must not need an LLM or a nest.
// Invoke its scan through /test-status; no sleep or watcher timing is involved.
import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, readFileSync, writeFileSync, rmSync, watch } from 'node:fs';
import { spawnSync } from 'node:child_process';
import { tmpdir } from 'node:os';
import { join } from 'node:path';

async function fixture(t) {
  const dir = mkdtempSync(join(tmpdir(), 'xmode-status-test-'));
  const previous = process.env.XDG_RUNTIME_DIR;
  process.env.XDG_RUNTIME_DIR = dir;
  t.after(() => {
    if (previous === undefined) delete process.env.XDG_RUNTIME_DIR;
    else process.env.XDG_RUNTIME_DIR = previous;
    rmSync(dir, { recursive: true, force: true });
  });
  const module = await import('../.pi/extensions/test-status.ts?fixture=' + encodeURIComponent(dir));
  const handlers = {}, commands = {}, messages = [], entries = [], notices = [];
  module.default({
    on: (name, fn) => { handlers[name] = fn; },
    registerCommand: (name, command) => { commands[name] = command; },
    sendMessage: (message, options) => messages.push({ message, options }),
    appendEntry: (customType, data) => entries.push({ customType, data }),
  });
  const file = join(dir, 'session.jsonl');
  writeFileSync(file, JSON.stringify({ type: 'session', id: 'this-session' }) + '\n');
  const ctx = { hasUI: true, sessionManager: { getSessionFile: () => file },
    ui: { notify: (...args) => notices.push(args), setStatus: () => {} } };
  await handlers.session_start({}, ctx);
  t.after(() => handlers.session_shutdown({}, ctx));
  return {
    dir, messages, entries, notices,
    async publish(body, session = 'this-session') {
      writeFileSync(join(dir, 'xmode-test-routing.log.status'), `session: ${session}\nlog: ${dir}/xmode-test-routing.log\n${body}\n`);
      await commands['test-status'].handler('', ctx);
    },
  };
}
const green = 'routing: finished\n== all ok\nexit: 0\nok: 12  FAIL: 0  WARN: 0  NOT RUN: 0';

test('confirmed green run is visible but never wakes the main model', async t => {
  const f = await fixture(t);
  await f.publish(green);
  assert.equal(f.messages.filter(m => m.options?.triggerTurn).length, 0,
    'a passing test receipt must not spend a main-model turn');
  assert.ok(f.entries.length > 0 || f.messages.length > 0, 'the green receipt must remain visible/durable');
});
test('red run wakes exactly once with the original evidence', async t => {
  const f = await fixture(t);
  const red = 'routing: finished\n== nest failed\nexit: 1\nok: 11  FAIL: 1  WARN: 0  NOT RUN: 0\n  integration/example_test';
  await f.publish(red);
  await f.publish(red);
  assert.equal(f.messages.length, 1);
  assert.equal(f.messages[0].options.triggerTurn, true);
  assert.match(f.messages[0].message.content, /integration\/example_test/);
});
test('missing exit evidence is unknown, not green', async t => {
  const f = await fixture(t);
  await f.publish(green.replace('exit: 0\n', ''));
  assert.equal(f.messages[0]?.options.triggerTurn, true);
});
test('warnings, missing scenarios, nonzero exit and missing summary cannot be quiet', async t => {
  for (const [from, to] of [['WARN: 0', 'WARN: 1'], ['NOT RUN: 0', 'NOT RUN: 1'], ['exit: 0', 'exit: 1'], ['== all ok', '== unit']]) {
    const f = await fixture(t);
    await f.publish(green.replace(from, to));
    assert.equal(f.messages[0]?.options.triggerTurn, true, `${from} -> ${to}`);
  }
});
test('zero recognized checks cannot be quiet', async t => {
  const f = await fixture(t);
  await f.publish(green.replace('ok: 12', 'ok: 0'));
  assert.equal(f.messages[0]?.options.triggerTurn, true);
});
test('async runner records the actual exit even when the log says nest ok', async t => {
  const dir = mkdtempSync(join(tmpdir(), 'xmode-exit-test-'));
  t.after(() => rmSync(dir, { recursive: true, force: true }));
  const path = join(dir, 'xmode-test-exit-evidence.log.status');
  // Wait on the file publication event, never on a guessed sleep or timeout.
  let observer;
  const receipt = new Promise(resolve => {
    observer = watch(dir, () => {
      try {
        const text = readFileSync(path, 'utf8');
        observer.close();
        resolve(text);
      } catch { /* no complete receipt published yet */ }
    });
  });
  t.after(() => observer.close());
  const start = spawnSync('bash', [new URL('./async.sh', import.meta.url).pathname,
    'run', 'exit-evidence', 'bash', '-c', 'printf "== nest ok\\n  ok example_test\\n"; exit 7'], {
    env: { ...process.env, XDG_RUNTIME_DIR: dir, PI_SESSION_ID: 'exit-session' }, encoding: 'utf8',
  });
  assert.equal(start.status, 0, start.stderr);
  const text = await receipt;
  assert.match(text, /^session: exit-session$/m);
  assert.match(text, /^exit: 7$/m);
  assert.match(text, /^== nest ok$/m);
  assert.match(text, /^ok: 1  FAIL: 0  WARN: 0  NOT RUN: 0$/m);
});
test('another session never wakes this model', async t => {
  const f = await fixture(t);
  await f.publish(green.replace('exit: 0', 'exit: 1'), 'another-session');
  assert.equal(f.messages.length, 0);
  assert.equal(f.entries.length, 0);
});
