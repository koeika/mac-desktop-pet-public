import {localEndpoint, sendWord, lookupWord} from "./client.js";

let tail = Promise.resolve();
function serialized(operation) {
  const next = tail.then(operation, operation);
  tail = next.catch(() => {});
  return next;
}
chrome.runtime.onInstalled.addListener(() => {
  chrome.contextMenus.create({id: "capture-word", title: "加入 PetPetKnows 生词本", contexts: ["selection"]});
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
  const word = {
    term: info.selectionText?.trim().slice(0, 120) || "", language: "en", meaning: "", example,
    sourceURL: /^https?:/.test(info.pageUrl || "") ? info.pageUrl : "", sourceTitle: tab?.title || ""
  };
  try { await chrome.tabs.sendMessage(tab.id, {type: "show-capture", word}); }
  catch {
    await chrome.storage.session.set({toolbarDraft: word});
    await chrome.action.openPopup().catch(() => chrome.action.setBadgeText({text: "+1", tabId: tab.id}));
  }
});
async function config() {
  return (await chrome.storage.local.get("config")).config || {endpoint: "http://127.0.0.1:4789", token: ""};
}
async function retryQueue() {
  const {pending = []} = await chrome.storage.local.get("pending");
  const settings = await config();
  const remaining = [];
  for (const item of pending) {
    try {
      let word = item.word;
      if (item.needsLookup) {
        try {
          const result = await lookupWord(word, settings);
          if (result.offline) { remaining.push(item); continue; }
          word = result.word;
        } catch { /* Saving the original capture must not depend on an optional AI provider. */ }
      }
      if ((await sendWord(word, settings)).offline) remaining.push({...item, word});
    }
    catch (error) { remaining.push({...item, error: error.message}); }
  }
  await chrome.storage.local.set({pending: remaining});
  return remaining.length;
}
chrome.alarms.onAlarm.addListener(alarm => {
  if (alarm.name === "retry") serialized(retryQueue).catch(() => {});
});
chrome.runtime.onMessage.addListener((message, sender, reply) => {
  const extensionPage = sender.url?.startsWith(chrome.runtime.getURL(""));
  const contentPage = sender.tab && /^https?:\/\//.test(sender.url || "");
  if (sender.id !== chrome.runtime.id || (!extensionPage && !contentPage)) return;
  if (!extensionPage && !["lookup", "submit"].includes(message.type)) return;
  if (message.type === "lookup") {
    config().then(settings => lookupWord(message.word, settings))
      .then(result => reply({ok: true, ...result}), error => reply({ok: false, error: error.message}));
    return true;
  }
  serialized(async () => {
    if (message.type === "status") {
      return {config: await config(), pending: (await chrome.storage.local.get("pending")).pending || []};
    }
    if (message.type === "config") {
      const endpoint = localEndpoint(message.config.endpoint);
      const token = message.config.token.trim();
      if (!token) throw new Error("配对码不能为空。");
      await chrome.storage.local.set({config: {endpoint, token, cloudLookup: message.config.cloudLookup === true}});
      return {};
    }
    if (message.type === "submit") {
      const result = await sendWord(message.word, await config());
      if (result.offline) {
        const {pending = []} = await chrome.storage.local.get("pending");
        if (!pending.some(item => JSON.stringify(item.word) === JSON.stringify(message.word))) {
          if (pending.length >= 200) throw new Error("待发送已达 200 条，请先启动桌宠并重试。");
          pending.push({id: crypto.randomUUID(), word: message.word, needsLookup: !message.word.meaning, at: new Date().toISOString()});
        }
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
