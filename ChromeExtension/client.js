export function localEndpoint(value = "http://127.0.0.1:4789") {
  const url = new URL(value);
  if (url.protocol !== "http:" || url.hostname !== "127.0.0.1" || url.username || url.password || url.pathname !== "/" || url.search || url.hash) {
    throw new Error("服务地址必须是 http://127.0.0.1:端口");
  }
  return url.origin;
}

export async function sendWord(word, config, fetcher = fetch) {
  const base = localEndpoint(config.endpoint);
  if (!config.token?.trim()) throw new Error("请先填写桌宠配对码。");
  let response;
  try {
    response = await fetcher(base + "/v1/vocabulary", {
      method: "POST", headers: {"content-type": "application/json", "Authorization": "Bearer " + config.token.trim()},
      body: JSON.stringify(word), signal: AbortSignal.timeout(5000), credentials: "omit"
    });
  } catch {
    return {offline: true};
  }
  const body = await response.json().catch(() => ({}));
  if (!response.ok || body.ok !== true) throw new Error(body.error || "收藏失败（" + response.status + "）");
  return {offline: false, word: body.word};
}

export async function lookupWord(word, config, fetcher = fetch) {
  const base = localEndpoint(config.endpoint);
  if (!config.token?.trim()) throw new Error("先点工具栏里的 PetPetKnows，完成一次桌宠配对。");
  let response;
  try {
    response = await fetcher(base + "/v1/vocabulary/lookup", {
      method: "POST", headers: {"content-type": "application/json", Authorization: "Bearer " + config.token.trim()},
      body: JSON.stringify({word, allowAI: config.cloudLookup === true}),
      signal: AbortSignal.timeout(65000), credentials: "omit"
    });
  } catch { return {offline: true, word}; }
  const body = await response.json().catch(() => ({}));
  if (!response.ok || !body.ok) throw new Error(body.error || "查询失败，请重试。");
  return {...body, offline: false};
}
