import {parseCopiedEntry, lookupDraft} from "./parse.js";
const $ = id => document.getElementById(id);
let currentWord;
let revision = 0;
function status(text, error = false) { $("status").textContent = text; $("status").dataset.error = String(error); }
async function request(message) {
  const result = await chrome.runtime.sendMessage(message);
  if (!result?.ok) throw new Error(result?.error || "扩展连接失败");
  return result;
}
function show(word) {
  currentWord = word; $("result").hidden = false; $("word-title").textContent = word.term;
  $("phonetic").textContent = [word.phoneticUK && "UK " + word.phoneticUK, word.phoneticUS && "US " + word.phoneticUS].filter(Boolean).join(" · ");
  $("meaning").textContent = word.meaning || "本地词典暂未收录";
  $("example").textContent = word.example || ""; $("translation").textContent = word.exampleTranslation || "";
  $("hint").textContent = word.hint || ""; $("submit").disabled = false; $("submit").textContent = "收藏到桌宠";
}
async function lookup(word) {
  const version = ++revision;
  $("lookup").disabled = true; status("正在查找释义…");
  try {
    const result = await request({type: "lookup", word});
    if (version !== revision) return;
    show(result.word || word);
    status(result.warning || (result.offline ? "桌宠未连接，可以先收藏，稍后自动送达。" : !currentWord.meaning ? "可在下方开启 DeepSeek 自动补全。" : ""), !!result.warning);
  } catch (error) { if (version === revision) { show(word); status(error.message, true); } }
  finally { if (version === revision) $("lookup").disabled = false; }
}
async function refresh() {
  const result = await request({type: "status"});
  $("endpoint").value = result.config.endpoint; $("token").value = result.config.token;
  $("cloud").checked = result.config.cloudLookup === true; $("pairing").open = !result.config.token;
  $("connection").textContent = result.config.token ? "已配对" : "未配对";
  $("pending-title").textContent = "待发送 " + result.pending.length + " 条"; $("pending-items").replaceChildren();
  for (const item of result.pending) {
    const row = document.createElement("div"); row.className = "pending-item";
    const label = document.createElement("span"); label.textContent = item.word.term + (item.error ? " · " + item.error : "");
    const remove = document.createElement("button"); remove.textContent = "移除";
    remove.onclick = () => request({type: "discard", id: item.id}).then(refresh).catch(e => status(e.message, true));
    row.append(label, remove); $("pending-items").append(row);
  }
}
$("lookup-form").onsubmit = event => {
  event.preventDefault(); const term = $("term").value.trim();
  if (term) lookup(lookupDraft(term, currentWord));
};
$("term").addEventListener("input", () => {
  revision++; currentWord = undefined; $("result").hidden = true; $("lookup").disabled = false; status("");
});
$("save-config").onclick = async () => {
  try {
    await request({type: "config", config: {endpoint: $("endpoint").value, token: $("token").value, cloudLookup: $("cloud").checked}});
    await refresh(); $("pairing").open = false; status("配对设置已保存");
    if (currentWord) await lookup(currentWord);
  } catch (error) { status(error.message, true); }
};
$("submit").onclick = async () => {
  if (!currentWord) return; $("submit").disabled = true;
  try {
    const result = await request({type: "submit", word: currentWord});
    $("submit").textContent = result.offline ? "已暂存" : "已收藏";
    status(result.offline ? "桌宠开启后自动送达。" : "已加入生词本，按复习计划出现。");
    await chrome.storage.session.remove("toolbarDraft"); await refresh();
  } catch (error) { $("submit").disabled = false; status(error.message, true); }
};
$("parse").onclick = () => {
  revision++; $("lookup").disabled = false;
  const word = parseCopiedEntry($("copied").value, $("term").value.trim());
  if (!word.term) { status("未找到单词。", true); return; }
  show({language: "en", meaning: "", ...word}); status("");
};
$("retry").onclick = async () => { try { const result = await request({type: "retry"}); await refresh(); status("剩余待发送 " + result.count + " 条"); } catch (error) { status(error.message, true); } };
try {
  await refresh(); const {toolbarDraft} = await chrome.storage.session.get("toolbarDraft");
  if (toolbarDraft) { $("term").value = toolbarDraft.term; await lookup(toolbarDraft); }
} catch (error) { status(error.message, true); }
