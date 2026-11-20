// Injected by test/preview-proxy.ps1 (-Driver) at the end of the page. Used by test/serve-empty.ps1, behind a server whose engine gives no output.
// Runs only at #selftest-emptyreply. It records each reply the page gets from /apply and /scene (status and text), puts the windows
// back as Undo does (placeBack), then applies the selected scene (applyScene), and dumps what the results line said after each.
// It does not wait on the previews: with a silent engine every preview fails, and that is not what this runs for.
(async function(){
  if(location.hash!=="#selftest-emptyreply")return;
  const replies=[],plainFetch=window.fetch;
  window.fetch=async(u,o)=>{const r=await plainFetch(u,o);
    if(u==="scene"||u==="apply"){const c=r.clone();replies.push({url:u,status:r.status,body:await c.text()})}
    return r};
  const sleep=()=>new Promise(r=>setTimeout(r,25));
  // The load settles when the status line says the scene is selected; that line is set after the previews, failed or not.
  for(let i=0;i<2400&&(!snap||isBusy||!/is selected/.test($("msg").textContent));i++)await sleep();
  const loaded=!!snap&&!isBusy&&/is selected/.test($("msg").textContent);
  const last=u=>{const m=replies.filter(x=>x.url===u);return m.length?m[m.length-1]:{status:0,body:""}};
  await placeBack([{id:1,app:"claude",title:"Draft release notes",x:0,y:0,w:100,h:100}]);
  const undo={...last("apply"),line:$("sum").textContent};
  await applyScene();
  const apply={...last("scene"),line:$("sum").textContent};
  dump({loaded,undo,apply});
})();
