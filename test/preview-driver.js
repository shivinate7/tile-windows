// Injected by test/preview-proxy.ps1 (-Driver) at the end of the page. Used by the Apply-then-failed-preview case in test/run.ps1.
// Runs only at #selftest-applyfail. It logs every toast, applies the scene the proxy fails (Thursday Prep), and snapshots the toast and
// the Undo state the moment the Thursday Prep failure first shows in the status line after the Apply's Undo toast. Every later failed
// preview overwrites the status line, another scene's too, so the snapshot is what gets dumped, not the final line.
(async function(){
  if(location.hash!=="#selftest-applyfail")return;
  const toasts=[],plainToast=window.toast;
  window.toast=(text,kind,o)=>{toasts.push({text:String(text),undo:!!(o&&o.undo)});return plainToast(text,kind,o)};
  const sleep=()=>new Promise(r=>setTimeout(r,25)),FAILED=/^Preview failed for Thursday Prep/,MOVED=/^Moved /;
  // Waits for the load to settle: the page's own status line says the scene is selected, after its previews.
  for(let i=0;i<2400&&(!snap||isBusy||!/is selected/.test($("msg").textContent));i++)await sleep();
  const loaded=!!snap&&!isBusy&&/is selected/.test($("msg").textContent);
  selId="thursday-prep";render();
  // A failure line before the Apply's Undo toast is not the one under test, so it is not taken. The observer reads the line in the
  // microtask that follows its change, before any other preview runs.
  let shot=null;
  const takeShot=()=>{
    if(shot||!FAILED.test($("msg").textContent)||!toasts.some(t=>t.undo&&MOVED.test(t.text)))return;
    shot={failed:true,msg:$("msg").textContent,toasts:toasts.map(t=>({...t})),toastText:$("toastText").textContent,
      toastHidden:$("toast").hidden,undoHidden:$("toastUndo").hidden};
  };
  const watch=new MutationObserver(takeShot);
  watch.observe($("msg"),{childList:true,characterData:true,subtree:true});
  const applied=$("apply").onclick();
  for(let i=0;i<2400&&!shot;i++)await sleep();
  watch.disconnect();
  const out=shot||{failed:false,msg:$("msg").textContent,toasts:toasts.slice(),toastText:$("toastText").textContent,
    toastHidden:$("toast").hidden,undoHidden:$("toastUndo").hidden};
  dump({loaded,selId,...out});
  await applied;
})();
