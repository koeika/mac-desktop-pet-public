import {parseCopiedEntry} from "./parse.js";
const ids = ["term", "language", "phoneticUK", "phoneticUS", "meaning", "example", "exampleTranslation", "hint", "sourceURL", "sourceTitle"];
const $ = id => document.getElementById(id);
const draftID = new URL(location.href).searchParams.get("draft");
function status(text, error = false) { $("status").textContent = text; $("status").dataset.error = String(error); }
async function request(message) {
  const result = await chrome.runtime.sendMessage(message);
  if (!result?.ok) throw new Error(result?.error || "扩展连接失败");
  return result;
}
function fill(word) { for (const id of ids) if (word[id]) $(id).value = word[id]; }
async function refresh() {
  const result = await request({type:"status"});
  $("endpoint").value = result.config.endpoint;
  $("token").value = result.config.token;
  $("pairing").open = !result.config.token;
  $("pending-title").textContent = "待发送 " + result.pending.length + " 条";
  $("pending-items").replaceChildren();
  for (const item of result.pending) {
    const row = document.createElement("div");row.className = "pending-item";
    const label = document.createElement("span");label.textContent = item.word.term + (item.error ? " · " + item.error : "");
    const remove = document.createElement("button");remove.textContent = "移除";
    remove.onclick = () => request({type:"discard", id:item.id}).then(refresh).catch(e=>status(e.message,true));
    row.append(label,remove);$("pending-items").append(row);
  }
}
$("save-config").onclick = async () => {
  try {await request({type:"config", config:{endpoint:$("endpoint").value,token:$("token").value}});status("配对设置已保存");$("pairing").open=false;}
  catch(error){status(error.message,true);}
};
$("capture-form").onsubmit = async event => {
  event.preventDefault();$("submit").disabled = true;
  try {
    const word = Object.fromEntries(ids.map(id=>[id,$(id).value.trim()]));
    const result = await request({type:"submit",word});
    status(result.offline ? "桌宠暂未连接，已保存在待发送队列，启动桌宠后自动重试。" : "已加入桌宠词本" + (word.meaning ? "，将按复习计划出现。" : "，请在配置中心补充释义后开始复习。"));
    if (draftID) await chrome.storage.session.remove(draftID);
    await refresh();
  } catch(error){status(error.message,true);}
  finally{$("submit").disabled=false;}
};
$("parse").onclick = () => {fill(parseCopiedEntry($("copied").value, $("term").value)); status("已提取可识别字段，请核对后保存；语境说明可粘贴到对应字段。");};
$("retry").onclick = async()=>{try{const result=await request({type:"retry"});await refresh();status("剩余待发送 " + result.count + " 条");}catch(error){status(error.message,true);}};
try {await refresh();if(draftID){const stored=await chrome.storage.session.get(draftID);fill(stored[draftID]||{});}}
catch(error){status(error.message,true);}
