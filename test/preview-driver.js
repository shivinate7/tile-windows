// Injected by test/preview-proxy.ps1 (-Driver) at the end of the page. Used by the Apply-then-failed-preview case in test/run.ps1.
// Runs only at #selftest-applyfail. It logs every toast, applies the scene the proxy fails (Thursday Prep), and reports the toast
// the moment the failed preview names itself in the status line. The toast is read then, before any timer can hide it.
(async function(){
  if(location.hash!=="#selftest-applyfail")return;
  const toasts=[],plainToast=window.toast;
  window.toast=(text,kind,o)=>{toasts.push({text:String(text),undo:!!(o&&o.undo)});return plainToast(text,kind,o)};
  const sleep=()=>new Promise(r=>setTimeout(r,25)),FAILED=/^Preview failed for Thursday Prep/;
  // Waits for the load to settle: the page's own status line says the scene is selected, after its previews.
  for(let i=0;i<2400&&(!snap||isBusy||!/is selected/.test($("msg").textContent));i++)await sleep();
  const loaded=!!snap&&!isBusy&&/is selected/.test($("msg").textContent);
  selId="thursday-prep";render();
  const applied=$("apply").onclick();
  for(let i=0;i<2400&&!FAILED.test($("msg").textContent);i++)await sleep();
  dump({loaded,failed:FAILED.test($("msg").textContent),selId,toasts,undoHidden:$("toastUndo").hidden,toastHidden:$("toast").hidden,
    toastText:$("toastText").textContent,msg:$("msg").textContent});
  await applied;
})();
