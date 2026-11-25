import test from "node:test";
import assert from "node:assert/strict";

async function harness(fetcher) {
  const state = {config: {endpoint: "http://127.0.0.1:4789", token: "fixture", cloudLookup: true}, pending: []};
  let listener;
  const event = () => ({addListener() {}});
  globalThis.chrome = {
    runtime: {id: "fixture-extension", getURL: path => "chrome-extension://fixture-extension/" + path,
      onInstalled: event(), onStartup: event(), onMessage: {addListener(fn) {listener = fn;}}},
    contextMenus: {create() {}, onClicked: event()}, alarms: {create() {}, onAlarm: event()},
    storage: {local: {async get(key) {return {[key]: state[key]};}, async set(value) {Object.assign(state, value);}}}
  };
  globalThis.fetch = fetcher;
  await import("../background.js?case=" + crypto.randomUUID());
  const extension = {id: "fixture-extension", url: "chrome-extension://fixture-extension/capture.html"};
  const content = {id: "fixture-extension", url: "https://example.org", tab: {id: 1}};
  return {state, content, async send(message, sender = extension) {
    return new Promise((resolve, reject) => {
      if (!listener(message, sender, resolve)) reject(Error("denied"));
    });
  }};
}

test("content scripts cannot obtain pairing config, tokens or queue contents", async () => {
  const h = await harness(async () => {throw Error("must not fetch");});
  for (const type of ["status", "config", "retry", "discard"]) await assert.rejects(h.send({type}, h.content), /denied/);
  assert.equal((await h.send({type: "status"})).config.token, "fixture");
});

test("offline queue preserves different contexts and deduplicates only exact captures", async () => {
  const h = await harness(async () => {throw Error("offline");});
  const first = {term: "word", language: "en", example: "First sentence."};
  const second = {...first, example: "Second sentence."};
  for (const word of [first, second, first]) assert.equal((await h.send({type: "submit", word}, h.content)).offline, true);
  assert.equal(h.state.pending.length, 2);
  assert.deepEqual(h.state.pending.map(item => item.word.example), ["First sentence.", "Second sentence."]);
});

test("failed optional AI lookup does not block delivering the original queued word", async () => {
  const writes = [];
  const h = await harness(async (url, options) => {
    if (url.endsWith("/lookup")) return {ok: false, json: async () => ({error: "provider unavailable"})};
    writes.push(JSON.parse(options.body)); return {ok: true, json: async () => ({ok: true})};
  });
  h.state.pending = [{id: "queued", word: {term: "new", language: "en", meaning: ""}, needsLookup: true}];
  assert.equal((await h.send({type: "retry"})).count, 0);
  assert.equal(writes.length, 1); assert.equal(writes[0].term, "new");
});
