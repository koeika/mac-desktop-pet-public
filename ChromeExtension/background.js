import {localEndpoint, sendWord} from "./client.js";

let tail = Promise.resolve();
function serialized(operation) {
  const next = tail.then(operation, operation);
  tail = next.catch(() => {});
  return next;
}
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({id: "capture-word", title: "加入 Whisky&Cling 生词本", contexts: ["selection"]});
  chrome.alarms.create("retry", {periodInMinutes: 2});
});
chrome.runtime.onStartup.addListener(() => chrome.alarms.create("retry", {periodInMinutes: 2}));
chrome.contextMenus.onClicked.addListener(async (info, tab) => {
  if (info.menuItemId !== "capture-word") return;
  let example = "";
  try {
    const results = await chrome.scripting.executeScript({
      target: {tabId: tab.id, frameIds: [info.frameId || 0]},
      func: () => window.getSelection()?.anchorNode?.parentElement?.innerText?.slice(0, 1800) || ""
    });
    example = results[0]?.result || "";
  } catch { /* Restricted pages still allow saving the selected word and link. */ }
  const id = crypto.randomUUID();
  await chrome.storage.session.set({[id]: {
    term: info.selectionText?.trim().slice(0, 120) || "", language: "en", meaning: "", example,
    sourceURL: /^https?:/.test(info.pageUrl || "") ? info.pageUrl : "", sourceTitle: tab?.title || ""
  }});
  await chrome.tabs.create({url: chrome.runtime.getURL("capture.html?draft=" + id)});
});
async function config() {
  return (await chrome.storage.local.get("config")).config || {endpoint: "http://127.0.0.1:4789", token: ""};
}
async function retryQueue() {
  const {pending = []} = await chrome.storage.local.get("pending");
  const settings = await config();
  const remaining = [];
  for (const item of pending) {
    try { if ((await sendWord(item.word, settings)).offline) remaining.push(item); }
    catch (error) { remaining.push({...item, error: error.message}); }
  }
  await chrome.storage.local.set({pending: remaining});
  return remaining.length;
}
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === "retry") serialized(retryQueue).catch(() => {});
});
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  if (sender.id !== chrome.runtime.id || !sender.url?.startsWith(chrome.runtime.getURL(""))) return;
  serialized(async () => {
    if (message.type === "status") {
      return {config: await config(), pending: (await chrome.storage.local.get("pending")).pending || []};
    }
    if (message.type === "config") {
      const endpoint = localEndpoint(message.config.endpoint);
      const token = message.config.token.trim();
      if (!token) throw new Error("配对码不能为空。");
      await chrome.storage.local.set({config: {endpoint, token}});
      return {};
    }
    if (message.type === "submit") {
      const result = await sendWord(message.word, await config());
      if (result.offline) {
        const {pending = []} = await chrome.storage.local.get("pending");
        if (pending.length >= 200) throw new Error("待发送已达 200 条，请先启动桌宠并重试。");
        pending.push({id: crypto.randomUUID(), word: message.word, at: new Date().toISOString()});
        await chrome.storage.local.set({pending});
      }
      return result;
    }
    if (message.type === "retry") return {count: await retryQueue()};
    if (message.type === "discard") {
      const {pending = []} = await chrome.storage.local.get("pending");
      await chrome.storage.local.set({pending: pending.filter(item => item.id !== message.id)});
      return {};
    }
    throw new Error("未知操作");
  }).then(result => reply({ok: true, ...result}), error => reply({ok: false, error: error.message}));
  return true;
});
