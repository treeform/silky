const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');

class Target {
  listeners = [];

  addEventListener(type, callback, options = {}) {
    this.listeners.push({type, callback, options});
  }

  dispatch(event, capture) {
    for (const listener of this.listeners) {
      if (event.stopped) {
        break;
      }
      if (listener.type === event.type &&
          !!listener.options.capture === capture &&
          !listener.options.signal?.aborted) {
        listener.callback(event);
      }
    }
  }
}

const document = new Target();
const canvas = new Target();
const runtime = {document, AbortController};
vm.createContext(runtime);
vm.runInContext(fs.readFileSync(
  'src/silky/internal/browsers.js', 'utf8'
), runtime);

let editable = false;
let cancelKeydown = true;
let modifiers = 0;
let events = [];

canvas.addEventListener('keydown', event => {
  events.push(['down', event.key, modifiers]);
  if (cancelKeydown) {
    event.preventDefault();
  }
}, {capture: true});
canvas.addEventListener('keyup', event => {
  events.push(['up', event.key, modifiers]);
}, {capture: true});
canvas.addEventListener('keypress', event => {
  if (editable) {
    events.push(['rune', event.key, modifiers]);
  }
}, {capture: true});

function install() {
  runtime.installSilkyBrowserInputs(canvas, rune => {
    if (!editable) {
      return false;
    }
    events.push(['rune', String.fromCodePoint(rune), modifiers]);
    return true;
  }, value => { modifiers = value; });
}

function send(type, key, properties = {}) {
  const event = {
    target: canvas,
    type,
    key,
    defaultPrevented: false,
    stopped: false,
    preventDefault() { this.defaultPrevented = true; },
    stopImmediatePropagation() { this.stopped = true; },
    getModifierState(name) { return name === 'AltGraph' && this.altGraph; },
    ...properties
  };
  document.dispatch(event, true);
  event.target.dispatch(event, true);
  document.dispatch(event, false);
  assert.equal(modifiers, 0);
}

install();
send('keydown', 'w');
send('keyup', 'w');
assert.deepEqual(events.map(event => event[0]), ['down', 'up']);

console.log('Testing characters from cancelled browser keydown events');
editable = true;
events = [];
for (const key of ['w', 'é', '界', '😀', ' ']) {
  send('keydown', key);
  send('keypress', key);
  send('keyup', key);
}
assert.equal(events.filter(event => event[0] === 'rune')
  .map(event => event[1]).join(''), 'wé界😀 ');

console.log('Testing captured modifiers and shortcut character suppression');
events = [];
send('keydown', 'a', {metaKey: true});
send('keyup', 'a', {metaKey: true});
send('keydown', 'a', {ctrlKey: true});
send('keydown', 'A', {shiftKey: true});
send('keydown', '@', {ctrlKey: true, altKey: true, altGraph: true});
send('keydown', 'Dead', {altKey: true});
send('keydown', '界', {isComposing: true});
assert.deepEqual(events.filter(event => event[0] === 'rune'), [
  ['rune', 'A', 18], ['rune', '@', 53]
]);
assert.deepEqual(events.slice(0, 3), [
  ['down', 'a', 24], ['up', 'a', 24], ['down', 'a', 17]
]);

console.log('Testing repeated presses and normal keypress compatibility');
events = [];
send('keydown', 'w');
send('keydown', 'w', {repeat: true});
send('keyup', 'w');
cancelKeydown = false;
send('keydown', 'x');
send('keypress', 'x');
send('keyup', 'x');
assert.equal(events.filter(event => event[0] === 'rune')
  .map(event => event[1]).join(''), 'wwx');

console.log('Testing listener replacement and unrelated DOM targets');
install();
events = [];
cancelKeydown = true;
send('keydown', 'x');
send('keyup', 'x');
assert.equal(events.filter(event => event[0] === 'rune').length, 1);
events = [];
const unrelated = new Target();
send('keydown', 'y', {target: unrelated});
assert.deepEqual(events, []);

console.log('All browser input adapter tests passed');
