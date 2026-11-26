(() => {
  if (globalThis.__whiskyclingSelectionInstalled) return;
  globalThis.__whiskyclingSelectionInstalled = true;
  const host = document.createElement("div");
  host.id = "whiskycling-capture";
  host.style.cssText = "all:initial;font:14px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#232729;position:fixed;z-index:2147483646;display:none;";
  const root = host.attachShadow({mode: "closed"});
  const selectionButtonSize = 24;
  const style = document.createElement("style");
  style.textContent = `
    :host{color-scheme:light;font:14px -apple-system,BlinkMacSystemFont,'Segoe UI',sans-serif;color:#232729;letter-spacing:0}
    *{box-sizing:border-box;letter-spacing:0}button{font:inherit;cursor:pointer;color:inherit}button:focus-visible{outline:2px solid #597c76;outline-offset:3px}
    .dot{appearance:none;position:relative;width:24px;height:24px;min-width:0;min-height:0;padding:0;margin:0;border:0;border-radius:50%;background:transparent;display:grid;place-items:center;line-height:1}
    .dot::before{content:"";position:absolute;inset:2px;border:1.5px solid white;border-radius:50%;background:#e87f73;box-shadow:0 1px 5px #0002}
    .plus{position:relative;width:8px;height:8px;pointer-events:none}
    .plus::before,.plus::after{content:"";position:absolute;left:50%;top:50%;transform:translate(-50%,-50%);background:white;border-radius:1px}
    .plus::before{width:8px;height:1.5px}.plus::after{width:1.5px;height:8px}
    .card{width:min(348px,calc(100vw - 24px));max-height:min(480px,calc(100vh - 32px));overflow:auto;background:#fff;border:1px solid #d8dfdc;border-radius:8px;box-shadow:0 8px 30px #14262020;padding:18px}
    header{display:flex;gap:10px;align-items:center;border-bottom:1px solid #edf0ee;padding-bottom:12px;margin-bottom:15px}.brand{font-size:12px;font-weight:700;color:#566963;flex:1}
    .close{border:0;background:none;font-size:22px;line-height:24px;padding:0 3px}.term{font-size:24px;font-weight:750;margin:0 0 7px;overflow-wrap:anywhere}.phonetic{font-size:12px;color:#71807b;line-height:1.6}
    .meaning{font-size:15px;line-height:1.7;margin:14px 0;color:#283c35;white-space:pre-line}.example{font-size:13px;line-height:1.7;border-left:2px solid #b4c8bd;padding-left:12px;margin:12px 0;white-space:pre-line}
    .translation{display:block;color:#71807b;margin-top:5px}.hint{font-size:12px;color:#79817d;line-height:1.6;margin:8px 0}.status{font-size:12px;color:#71807b;line-height:1.6;margin:10px 0;white-space:pre-line}
    .actions{display:flex;gap:8px;margin-top:14px}.save{flex:1;background:#254f43;color:white;border:0;border-radius:6px;padding:10px;font-weight:650}.retry{border:1px solid #d8dfdc;background:white;border-radius:6px;padding:9px 12px}
    button:disabled{cursor:default;opacity:.6}.source{font-size:11px;color:#8b9590;margin-top:10px}
    @media(prefers-reduced-motion:no-preference){.dot:hover{transform:scale(1.07);transition:transform .12s}}
  `;
  root.append(style);
  document.documentElement.append(host);
  let selected, range, opened = false, revision = 0, timer;
  const node = (tag, className, text) => {
    const element = document.createElement(tag); element.className = className;
    if (text !== undefined) element.textContent = text;
    return element;
  };
  async function request(message) {
    const response = await chrome.runtime.sendMessage(message);
    if (!response?.ok) throw Error(response?.error || "扩展已更新，请刷新网页后再试。");
    return response;
  }
  function clear() { for (const child of [...root.children]) if (child !== style) child.remove(); }
  function hide() { revision++; opened = false; host.style.display = "none"; }
  function place(card = false) {
    const rect = range?.getBoundingClientRect() || {left: innerWidth / 2, bottom: 100};
    const width = card ? Math.min(348, innerWidth - 24) : selectionButtonSize;
    host.style.left = Math.max(12, Math.min(innerWidth - width - 12, rect.left - (card ? 0 : selectionButtonSize + 6))) + "px";
    host.style.top = Math.max(12, Math.min(innerHeight - (card ? host.getBoundingClientRect().height : selectionButtonSize) - 12, rect.bottom + 8)) + "px";
  }
  function selection() {
    const current = window.getSelection();
    const element = current?.anchorNode?.parentElement;
    if (!current?.rangeCount || current.isCollapsed || !element ||
        element.closest("input,textarea,[contenteditable=true],[contenteditable='']") || host.contains(element)) return;
    const term = current.toString().trim();
    if (!term || term.length > 120 || term.split(/\s+/).length > 6 || !/[\p{L}]/u.test(term)) return;
    if (selected?.term === term && opened) return;
    revision++; opened = false; range = current.getRangeAt(0).cloneRange();
    // Only the selected sentence is collected; never scan the whole page or other extension UIs.
    const paragraph = element.innerText || element.textContent || "";
    const sentences = paragraph.match(/[^.!?。！？\n]+[.!?。！？]?/g) || [];
    const sentence = sentences.find(text => text.includes(term)) || term;
    selected = {term, language: /[ぁ-んァ-ン一-龯]/.test(term) ? "ja" : "en", meaning: "",
      example: sentence.trim() === term ? undefined : sentence.trim().slice(0, 500), sourceURL: location.origin + location.pathname, sourceTitle: document.title.slice(0, 200)};
    clear();
    const dot = node("button", "dot"); dot.type = "button"; dot.title = "查询并收藏到 PetPetKnows";
    const plus = node("span", "plus"); plus.setAttribute("aria-hidden", "true"); dot.append(plus);
    dot.setAttribute("aria-label", "查询并收藏 " + term);
    dot.addEventListener("click", event => { if (event.isTrusted) open(selected); });
    root.append(dot); host.style.display = "block"; place();
  }
  async function open(word) {
    const version = ++revision; selected = word; opened = true; clear();
    const card = node("section", "card"); card.setAttribute("role", "dialog"); card.setAttribute("aria-label", "PetPetKnows 生词卡");
    const header = node("header", ""); header.append(node("span", "brand", "PetPetKnows"));
    const close = node("button", "close", "×"); close.setAttribute("aria-label", "关闭生词卡"); close.onclick = event => { if (event.isTrusted) hide(); }; header.append(close);
    const term = node("h2", "term", word.term), phonetic = node("div", "phonetic"), meaning = node("p", "meaning");
    const example = node("p", "example"), hint = node("p", "hint"), status = node("p", "status", "正在查找释义…"); status.setAttribute("role", "status");
    const actions = node("div", "actions"), save = node("button", "save", "收藏到桌宠"), retry = node("button", "retry", "重试");
    const source = node("div", "source"); retry.hidden = true; actions.append(save, retry);
    card.append(header, term, phonetic, meaning, example, hint, status, actions, source); root.append(card);
    host.style.display = "block"; place(true); let currentWord = {...word};
    save.disabled = true;
    save.onclick = async event => {
      if (!event.isTrusted) return;
      save.disabled = true;
      try {
        const result = await request({type: "submit", word: currentWord});
        if (version !== revision) return;
        save.textContent = result.offline ? "已暂存" : "已收藏";
        status.textContent = result.offline ? "桌宠开启后自动送达。" : "已加入生词本，按复习计划出现。";
      } catch (error) { if (version === revision) {status.textContent = error.message; save.disabled = false;} }
    };
    async function lookup() {
      status.textContent = "正在查找释义…"; retry.hidden = true;
      try {
        const result = await request({type: "lookup", word});
        if (version !== revision) return;
        currentWord = result.word || word;
        phonetic.textContent = [currentWord.phoneticUK && "UK " + currentWord.phoneticUK, currentWord.phoneticUS && "US " + currentWord.phoneticUS].filter(Boolean).join(" · ");
        meaning.textContent = currentWord.meaning || "本地词典暂未收录";
        example.replaceChildren(); if (currentWord.example) example.append(document.createTextNode(currentWord.example));
        if (currentWord.exampleTranslation) example.append(node("span", "translation", currentWord.exampleTranslation));
        example.hidden = !currentWord.example;
        hint.textContent = currentWord.hint || ""; hint.hidden = !currentWord.hint;
        status.textContent = result.warning || (result.offline ? "桌宠未连接，可先收藏，稍后自动送达。" : !currentWord.meaning || (currentWord.example && !currentWord.exampleTranslation) ? "可在插件配对面板开启 DeepSeek，自动补全释义和例句译文。" : "");
        retry.hidden = !result.warning;
        source.textContent = result.source === "deepseek" ? "DeepSeek 自动补全" : result.source === "dictionary" ? "来自本地词典" : result.source === "notebook" ? "来自你的生词本" : "";
        save.disabled = false; save.textContent = result.saved ? "已收藏 · 更新语境" : "收藏到桌宠";
        place(true);
      } catch (error) {
        if (version !== revision) return;
        status.textContent = error.message; retry.hidden = false; save.disabled = false; save.textContent = "先收藏单词"; place(true);
      }
    }
    retry.onclick = event => { if (event.isTrusted) lookup(); }; await lookup();
  }
  host.addEventListener("pointerdown", event => event.stopPropagation());
  host.addEventListener("mousedown", event => { if (event.composedPath().some(item => item instanceof HTMLButtonElement)) event.preventDefault(); });
  document.addEventListener("pointerdown", event => { if (!event.composedPath().includes(host)) hide(); }, true);
  document.addEventListener("mouseup", event => { if (event.isTrusted && !event.composedPath().includes(host)) { clearTimeout(timer); timer = setTimeout(selection, 120); } });
  document.addEventListener("keyup", event => { if (!event.isTrusted) return; if (event.key === "Escape") hide(); else if (event.shiftKey) { clearTimeout(timer); timer = setTimeout(selection, 120); } });
  window.addEventListener("resize", () => { if (host.style.display !== "none") place(opened); });
  document.addEventListener("scroll", event => { if (!event.composedPath().includes(host)) hide(); }, true);
  chrome.runtime.onMessage.addListener(message => { if (message.type === "show-capture") { range = null; open(message.word); } });
})();
