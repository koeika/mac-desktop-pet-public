import test from "node:test";
import assert from "node:assert/strict";
import {readFileSync} from "node:fs";

const root = new URL("../", import.meta.url);
const manifest = JSON.parse(readFileSync(new URL("manifest.json", root), "utf8"));

test("toolbar and extension management declare the selected reading-cat icons", () => {
  for (const size of [16, 32, 48, 128]) {
    const name = `icons/reading-cat-${size}.png`;
    assert.equal(manifest.icons?.[size], name);
    assert.equal(manifest.action.default_icon?.[size], name);
    const png = readFileSync(new URL(name, root));
    assert.deepEqual(png.subarray(0, 8), Buffer.from([137, 80, 78, 71, 13, 10, 26, 10]));
    assert.equal(png.readUInt32BE(16), size);
    assert.equal(png.readUInt32BE(20), size);
    assert.equal(png[25], 6, "Icons retain RGBA transparency");
  }
});

test("popup uses the same selected logo without changing its dimensions", () => {
  const html = readFileSync(new URL("capture.html", root), "utf8");
  assert.match(html, /<img src="icons\/reading-cat-128\.png"[^>]*width="34" height="34"/);
});
