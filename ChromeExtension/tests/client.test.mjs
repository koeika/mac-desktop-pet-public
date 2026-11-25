import test from "node:test";
import assert from "node:assert/strict";
import {localEndpoint, sendWord, lookupWord} from "../client.js";
import {parseCopiedEntry, lookupDraft} from "../parse.js";

test("pairing only permits a local loopback destination", () => {
  assert.equal(localEndpoint("http://127.0.0.1:4789"), "http://127.0.0.1:4789");
  for (const address of ["https://example.com", "http://127.0.0.1.evil.com", "http://user@127.0.0.1", "http://127.0.0.1/foo"]) {
    assert.throws(()=>localEndpoint(address));
  }
});

test("lookup is read-only, paired and cloud enrichment is opt-in", async () => {
  for (const consent of [false, true]) {
    const word = {term: "allocate", example: "We allocate time.", sourceURL: "https://example.org"};
    const result = await lookupWord(word, {token: "fixture", cloudLookup: consent}, async (url, options) => {
      assert.equal(url, "http://127.0.0.1:4789/v1/vocabulary/lookup");
      assert.equal(options.headers.Authorization, "Bearer fixture");
      assert.deepEqual(JSON.parse(options.body), {word, allowAI: consent});
      return {ok: true, json: async () => ({ok: true, word: {...word, meaning: "分配"}, source: "dictionary", saved: false})};
    });
    assert.equal(result.word.meaning, "分配"); assert.equal(result.saved, false);
  }
  await assert.rejects(lookupWord({term: "word"}, {token: "fixture"}, async () => ({ok: false, json: async () => ({error: "配对错误"})})), /配对错误/);
  assert.equal((await lookupWord({term: "word"}, {token: "fixture"}, async () => { throw Error("offline"); })).offline, true);
});
test("an acknowledged write carries pairing and the complete vocabulary payload", async () => {
  const word = {term:"inherently", meaning:"adv. 本质上", phoneticUK:"/ɪnˈhɪərəntli/", sourceURL:"https://example.org"};
  const result = await sendWord(word,{token:"fixture",endpoint:"http://127.0.0.1:4789"}, async(url,options)=>{
    assert.equal(url,"http://127.0.0.1:4789/v1/vocabulary");
    assert.equal(options.headers.Authorization,"Bearer fixture");
    assert.deepEqual(JSON.parse(options.body),word);
    return {ok:true,json:async()=>({ok:true,word})};
  });
  assert.equal(result.offline,false);
});
test("optional enrichment warnings preserve local word data and actionable diagnostics", async () => {
  const word = {term: "coherent", meaning: "连贯的", example: "A coherent explanation helps."};
  const warning = "DeepSeek HTTP 402：API 账户余额不足";
  const result = await lookupWord(word, {token: "fixture", cloudLookup: true}, async () => ({ok: true, json: async () => ({ok: true, word, warning, source: "dictionary", saved: false})}));
  assert.deepEqual(result.word, word);
  assert.equal(result.warning, warning);
  assert.equal(result.source, "dictionary");
  assert.equal(result.offline, false);
});
test("retry preserves original capture context and changing the term starts a fresh draft", () => {
  const original = {term: "inherently", meaning: "本质上", example: "The system is inherently flawed.", sourceURL: "https://example.org/article", sourceTitle: "Article", phoneticUS: "/test/"};
  const retry = lookupDraft("inherently", original);
  assert.deepEqual(retry, original);
  assert.notEqual(retry, original);
  assert.deepEqual(lookupDraft("allocate", original), {term: "allocate", language: "en", meaning: ""});
  assert.deepEqual(lookupDraft("これ", undefined), {term: "これ", language: "ja", meaning: ""});
});
test("offline requests can queue, but bad pairing and invalid words remain errors",async()=>{
  const settings={token:"fixture"};
  assert.deepEqual(await sendWord({term:"word"},settings,async()=>{throw Error("offline");}),{offline:true});
  for(const code of [400,401,500]){
    await assert.rejects(sendWord({term:"word"},settings,async()=>({ok:false,status:code,json:async()=>({error:"rejected"})})),/rejected/);
  }
  await assert.rejects(sendWord({term:"word"},{token:""}),/配对码/);
});
test("copied translation keeps explicit IPA and definition, with no invented content",()=>{
  assert.deepEqual(parseCopiedEntry("inherently\nUS /ɪnˈherəntli/ · UK /ɪnˈhɪərəntli/\nadv. 本质上；固有地","inherently"),{
    term:"inherently",phoneticUS:"/ɪnˈherəntli/",phoneticUK:"/ɪnˈhɪərəntli/",meaning:"adv. 本质上；固有地"
  });
  assert.deepEqual(parseCopiedEntry("random webpage instructions","word"),{term:"word"});
  const split = parseCopiedEntry("inherently\nadv.\n本质上；固有地\nThe system is inherently flawed.\n这个系统本质上存在缺陷。","inherently");
  assert.equal(split.meaning,"adv. 本质上；固有地");
  assert.equal(split.example,"The system is inherently flawed.");
  assert.equal(split.exampleTranslation,"这个系统本质上存在缺陷。");
});
