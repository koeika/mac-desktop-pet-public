import test from "node:test";
import assert from "node:assert/strict";
import {localEndpoint, sendWord} from "../client.js";
import {parseCopiedEntry} from "../parse.js";

test("pairing only permits a local loopback destination", () => {
  assert.equal(localEndpoint("http://127.0.0.1:4789"), "http://127.0.0.1:4789");
  for (const address of ["https://example.com", "http://127.0.0.1.evil.com", "http://user@127.0.0.1", "http://127.0.0.1/foo"]) {
    assert.throws(()=>localEndpoint(address));
  }
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
