const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync('index.html', 'utf8').match(/<script>([\s\S]*?)<\/script>/)[1];
function setup(initial = {}, options = {}) {
  const storage = new Map(Object.entries(initial));
  const elements = {};
  class Target {
    constructor(){ this.listeners = {}; this.style = {}; this.classList = {add(){}, remove(){}}; this.value = ''; this.children = []; this.textContent = ''; }
    addEventListener(name, fn){ (this.listeners[name] ||= []).push(fn); }
    async emit(name, event = {}){ for(const fn of this.listeners[name] || []) await fn(event); }
    setAttribute(name, value){ this[name] = value; }
    append(...children){ this.children.push(...children); }
    replaceChildren(...children){ this.children = children; }
  }
  const audio = new Target();
  Object.assign(audio, {currentTime: 0, duration: NaN, paused: true, ended: false, loads: 0,
    pause(){ this.paused = true; this.emit('pause'); },
    load(){ this.loads++; this.error = null; this.currentTime = 0; },
    play(){ this.paused = false; this.emit('play'); return Promise.resolve(); }
  });
  const document = new Target();
  document.documentElement = new Target();
  document.createElement = tag => Object.assign(new Target(), {tagName: tag});
  document.getElementById = id => elements[id] ||= new Target();
  vm.runInNewContext(source, {
    Audio: function(){return audio;}, document, window: new Target(), navigator: {}, URL, AbortController, clearTimeout,
    localStorage: {getItem: key => storage.get(key) ?? null, setItem: (k,v) => storage.set(k,v), removeItem: k => storage.delete(k)},
    setTimeout(){}, fetch: options.fetch || (async () => ({ok: true, json: async () => ({files: [{name: 'part two.mp3', format: 'MP3'}], metadata: {title: 'Book'}})}))
  });
  return {audio, elements, storage, document};
}
const tick = () => new Promise(resolve => setImmediate(resolve));
test('duration toggles to remaining and updates during playback', async () => {
  const {audio, elements} = setup();
  audio.duration = 120; audio.currentTime = 30;
  await audio.emit('durationchange'); assert.equal(elements.dur.textContent, '2:00');
  await elements.dur.emit('click'); assert.equal(elements.dur.textContent, '−1:30 left');
  audio.currentTime = 60; await audio.emit('timeupdate'); assert.equal(elements.dur.textContent, '−1:00 left');
  await elements.dur.emit('click'); assert.equal(elements.dur.textContent, '2:00');
});
test('reopening restores the link and preserves position until metadata arrives', async () => {
  const url = 'https://archive.org/download/book/part%20two.mp3';
  const {audio, elements, storage} = setup({'earmark::lastLink': url, 'archpos::book::part two.mp3': '42'});
  await tick(); assert.equal(elements.url.value, url); assert.equal(audio.src, url);
  await audio.emit('pause'); assert.equal(storage.get('archpos::book::part two.mp3'), '42');
  audio.duration = 100; await audio.emit('loadedmetadata'); assert.equal(audio.currentTime, 42);
});
test('node links keep the exact recording and migrate encoded position keys', async () => {
  const {audio, elements} = setup({'archpos::book::part%20two.mp3': '35'});
  elements.url.value = 'https://ia601608.us.archive.org/19/items/book/part%20two.mp3';
  await elements.loadBtn.emit('click');
  assert.equal(audio.src, 'https://archive.org/download/book/part%20two.mp3');
  audio.duration = 100; await audio.emit('loadedmetadata'); assert.equal(audio.currentTime, 35);
});
test('retry reloads synchronously and retains position', async () => {
  const {audio, elements} = setup();
  elements.url.value = 'https://example.com/audio.mp3'; await elements.loadBtn.emit('click');
  audio.duration = 100; await audio.emit('loadedmetadata'); audio.currentTime = 55;
  audio.error = {code: 2}; await elements.play.emit('click');
  assert.equal(audio.loads, 2); assert.equal(audio.paused, false);
  await audio.emit('loadedmetadata'); assert.equal(audio.currentTime, 55);
});
test('details links resolve through the stable download endpoint', async () => {
  const {audio, elements} = setup();
  elements.url.value = 'https://archive.org/details/book'; await elements.loadBtn.emit('click');
  assert.equal(audio.src, 'https://archive.org/download/book/part%20two.mp3');
});
test('both entry points remain identical', () => assert.equal(fs.readFileSync('index.html','utf8'), fs.readFileSync('earmark.html','utf8')));

const savedLibrary = app => JSON.parse(app.storage.get('earmark::library::v1'));
function descendants(element){ return [element, ...element.children.flatMap(descendants)]; }
function findControl(app, text){ return descendants(app.elements.libraryList).find(e => e.tagName === 'button' && e.textContent === text); }
test('pasted links persist before loading and duplicate pastes are deduplicated', async () => {
  const app = setup();
  const event = {clipboardData: {getData: () => 'https://example.com/episode.mp3'}};
  await app.elements.url.emit('paste', event); await app.elements.url.emit('paste', event);
  assert.equal(savedLibrary(app).entries.length, 1);
  assert.equal(app.audio.loads, 0);
  const reopened = setup(Object.fromEntries(app.storage));
  assert.equal(savedLibrary(reopened).entries[0].url, event.clipboardData.getData());
  assert.ok(findControl(reopened, 'Load'));
});
test('folder moves and manual names survive reloading audio and reopening app', async () => {
  const app = setup();
  app.elements.url.value = 'https://example.com/episode.mp3'; await app.elements.loadBtn.emit('click');
  app.elements.folderName.value = 'Favorites'; await app.elements.addFolder.emit('click');
  let controls = descendants(app.elements.libraryList);
  const selector = controls.find(e => e.tagName === 'select'); selector.value = 'Favorites'; await selector.emit('change');
  controls = descendants(app.elements.libraryList);
  const inputs = controls.filter(e => e.tagName === 'input');
  inputs[0].value = 'Episode One'; inputs[1].value = 'My Show'; await findControl(app, 'Save names').emit('click');
  await findControl(app, 'Load').emit('click');
  assert.equal(app.elements.title.textContent, 'Episode One'); assert.equal(app.elements.sub.textContent, 'My Show');
  const reopened = setup(Object.fromEntries(app.storage)); await tick();
  assert.equal(savedLibrary(reopened).entries[0].folder, 'Favorites');
  assert.equal(reopened.elements.title.textContent, 'Episode One');
});
test('Archive metadata groups shows and preserves the episode title', async () => {
  const app = setup({}, {fetch: async () => ({ok: true, json: async () => ({files: [{name: 'ep.mp3', title: 'The First Episode', album: 'Example Show', format: 'MP3'}], metadata: {title: 'Collection'}})})});
  app.elements.url.value = 'https://archive.org/details/example'; await app.elements.loadBtn.emit('click');
  const entry = savedLibrary(app).entries[0];
  assert.equal(entry.folder, 'Example Show'); assert.equal(entry.title, 'The First Episode');
  assert.equal(app.elements.sub.textContent, 'Example Show');
  await findControl(app, 'Delete folder').emit('click');
  assert.equal(savedLibrary(app).entries[0].folder, '');
  await findControl(app, 'Load').emit('click');
  assert.equal(savedLibrary(app).entries[0].folder, '');
});
test('deleting the current link does not resurrect it on restart', async () => {
  const app = setup(); app.elements.url.value = 'https://example.com/episode.mp3'; await app.elements.loadBtn.emit('click');
  await findControl(app, 'Delete').emit('click');
  assert.equal(savedLibrary(app).entries.length, 0); assert.equal(app.storage.has('earmark::lastLink'), false);
  const reopened = setup(Object.fromEntries(app.storage)); await tick();
  assert.equal(reopened.audio.loads, 0); assert.equal(savedLibrary(reopened).entries.length, 0);
});
test('deleting a link during metadata loading prevents it being restored', async () => {
  let finish;
  const app = setup({}, {fetch: () => new Promise(resolve => { finish = resolve; })});
  app.elements.url.value = 'https://archive.org/details/example'; const pending = app.elements.loadBtn.emit('click');
  await findControl(app, 'Delete').emit('click');
  finish({ok: true, json: async () => ({files: [{name: 'ep.mp3', format: 'MP3'}]})});
  await pending;
  assert.equal(savedLibrary(app).entries.length, 0); assert.equal(app.audio.loads, 0);
});
test('failed metadata keeps the link saved for retry', async () => {
  const app = setup({}, {fetch: async () => {throw new Error('Offline');}});
  app.elements.url.value = 'https://archive.org/details/example'; await app.elements.loadBtn.emit('click');
  assert.equal(savedLibrary(app).entries.length, 1); assert.equal(app.audio.loads, 0);
});

 test('remaining-time preference survives reopening', async () => {
  const app = setup();
  await app.elements.dur.emit('click');
  const reopened = setup(Object.fromEntries(app.storage));
  reopened.audio.duration = 120;
  await reopened.audio.emit('durationchange');
  assert.equal(reopened.elements.dur.textContent, '−2:00 left');
 });
 test('a temporarily unavailable seek is retried when playback becomes ready', async () => {
  const url = 'https://example.com/episode.mp3';
  const app = setup({'earmark::lastLink': url, ['archpos::' + url]: '42'});
  await tick();
  let position = 0, seekReady = false;
  Object.defineProperty(app.audio, 'currentTime', {
    get(){ return position; },
    set(value){ if(!seekReady) throw new Error('Not ready'); position = value; }
  });
  app.audio.duration = 100;
  await app.audio.emit('loadedmetadata');
  await app.audio.emit('pause');
  assert.equal(app.storage.get('archpos::' + url), '42');
  seekReady = true;
  await app.audio.emit('canplay');
  assert.equal(position, 42);
 });
 test('Play reloads an empty media resource without requiring the link again', async () => {
  const app = setup();
  app.elements.url.value = 'https://example.com/episode.mp3';
  await app.elements.loadBtn.emit('click');
  app.audio.duration = 100;
  await app.audio.emit('loadedmetadata');
  app.audio.currentTime = 55;
  app.audio.readyState = 0;
  await app.elements.play.emit('click');
  assert.equal(app.audio.loads, 2);
  assert.equal(app.audio.paused, false);
  await app.audio.emit('loadedmetadata');
  assert.equal(app.audio.currentTime, 55);
 });

test('sample CloudFront MP3 loads directly and survives reopening', async () => {
  const url = 'https://d3ctxlq1ktw2nl.cloudfront.net/staging/2021-7-19/213635671-32000-2-0b2c7ddfc1a111e3.mp3';
  const app = setup({}, {fetch: async () => {throw new Error('Direct audio must not need metadata');}});
  await app.elements.url.emit('paste', {clipboardData: {getData: () => url}});
  app.elements.url.value = url;
  await app.elements.loadBtn.emit('click');
  assert.equal(app.audio.src, url);
  assert.equal(savedLibrary(app).entries.length, 1);
  const reopened = setup(Object.fromEntries(app.storage));
  await tick();
  assert.equal(reopened.audio.src, url);
});

test('dark mode is the default and an explicit light preference survives reopening', async () => {
  const app = setup();
  assert.equal(app.document.documentElement['data-theme'], 'dark');
  assert.equal(app.elements.themeToggle['aria-pressed'], 'true');
  assert.equal(app.elements.themeToggle.textContent, '☀');
  assert.equal(app.elements.themeToggle['aria-label'], 'Switch to light mode');
  await app.elements.themeToggle.emit('click');
  assert.equal(app.document.documentElement['data-theme'], 'light');
  assert.equal(app.elements.themeToggle.textContent, '☾');
  assert.equal(app.elements.themeToggle['aria-label'], 'Switch to dark mode');
  const reopened = setup(Object.fromEntries(app.storage));
  assert.equal(reopened.document.documentElement['data-theme'], 'light');
  await reopened.elements.themeToggle.emit('click');
  assert.equal(reopened.document.documentElement['data-theme'], 'dark');
});
