module Client

# The embedded diff-protocol browser client — bundled as a sw string
# so the framework ships standalone (no swarmrt C-side dependency on
# its bundled live_js builtin). LiveView.page() embeds js() in a
# <script> tag inside the dead-render HTML.

export [js]

fun js() {
    "(function(){\n" ++
    "\n" ++
    "/* Minimal morphdom: patch existing DOM in-place from a new node. */\n" ++
    "function morph(f,t){\n" ++
    "  if(f.nodeType!==t.nodeType||f.nodeName!==t.nodeName){\n" ++
    "    f.parentNode.replaceChild(t.cloneNode(true),f);return}\n" ++
    "  if(f.nodeType===3||f.nodeType===8){\n" ++
    "    if(f.nodeValue!==t.nodeValue)f.nodeValue=t.nodeValue;return}\n" ++
    "  if(f.nodeType===1){\n" ++
    "    /* sw-keep: element is client-managed (dialogs, popovers, etc.)\n" ++
    "       — don't touch its attributes or its children on a diff. */\n" ++
    "    if(t.hasAttribute&&t.hasAttribute('sw-keep'))return;\n" ++
    "    var i,a=t.attributes;\n" ++
    "    for(i=0;i<a.length;i++)\n" ++
    "      if(f.getAttribute(a[i].name)!==a[i].value)\n" ++
    "        f.setAttribute(a[i].name,a[i].value);\n" ++
    "    a=f.attributes;\n" ++
    "    for(i=a.length-1;i>=0;i--)\n" ++
    "      if(!t.hasAttribute(a[i].name))f.removeAttribute(a[i].name);\n" ++
    "    /* Don't stomp a focused input's value mid-type. */\n" ++
    "    if(f.nodeName==='INPUT'||f.nodeName==='TEXTAREA'){\n" ++
    "      if(document.activeElement!==f&&f.value!==t.getAttribute('value'))\n" ++
    "        if(t.hasAttribute('value'))f.value=t.getAttribute('value')}\n" ++
    "    /* sw-stream containers are managed by stream ops — leave their\n" ++
    "       children untouched during a diff render. */\n" ++
    "    if(t.hasAttribute&&t.hasAttribute('sw-stream'))return;\n" ++
    "    var fc=Array.prototype.slice.call(f.childNodes);\n" ++
    "    var tc=Array.prototype.slice.call(t.childNodes);\n" ++
    "    for(i=0;i<tc.length;i++){\n" ++
    "      if(i<fc.length)morph(fc[i],tc[i]);\n" ++
    "      else f.appendChild(tc[i].cloneNode(true))}\n" ++
    "    while(f.childNodes.length>tc.length)f.removeChild(f.lastChild)}\n" ++
    "}\n" ++
    "\n" ++
    "/* LiveView client state: the two halves of every render. */\n" ++
    "var ws,retries=0,statics=[],dynamics=[];\n" ++
    "\n" ++
    "/* Stitch statics + dynamics into HTML, then morph #live-root. */\n" ++
    "function render(){\n" ++
    "  var html=statics.length?statics[0]:'';\n" ++
    "  for(var i=0;i<dynamics.length;i++)\n" ++
    "    html+=(dynamics[i]==null?'':dynamics[i])+(statics[i+1]==null?'':statics[i+1]);\n" ++
    "  var root=document.getElementById('live-root');\n" ++
    "  if(!root)return;\n" ++
    "  var tmp=document.createElement('div');\n" ++
    "  tmp.innerHTML=html;\n" ++
    "  var fc=Array.prototype.slice.call(root.childNodes);\n" ++
    "  var tc=Array.prototype.slice.call(tmp.childNodes),i;\n" ++
    "  for(i=0;i<tc.length;i++){\n" ++
    "    if(i<fc.length)morph(fc[i],tc[i]);\n" ++
    "    else root.appendChild(tc[i])}\n" ++
    "  while(root.childNodes.length>tc.length)root.removeChild(root.lastChild);\n" ++
    "  bind();autoscroll();\n" ++
    "}\n" ++
    "\n" ++
    "/* Scroll any [sw-autoscroll] containers to the bottom. Called after\n" ++
    "   every render and after stream appends so chat/feed stay pinned. */\n" ++
    "function autoscroll(){\n" ++
    "  document.querySelectorAll('[sw-autoscroll]').forEach(function(el){\n" ++
    "    el.scrollTop=el.scrollHeight})}\n" ++
    "\n" ++
    "/* Apply a stream op to a sw-stream container: append/prepend a node,\n" ++
    "   delete one by sw-key, or reset — no full re-render. */\n" ++
    "function applyStream(m){\n" ++
    "  var c=document.getElementById(m.id);\n" ++
    "  if(!c)return;\n" ++
    "  /* sw-canvas containers: draw/clear ink on a lazily-created canvas. */\n" ++
    "  if(m.op==='draw'||(m.op==='reset'&&c.hasAttribute('sw-canvas'))){\n" ++
    "    var cv=c.querySelector('canvas');\n" ++
    "    if(!cv){cv=document.createElement('canvas');cv.width=1600;cv.height=900;\n" ++
    "      cv.style.cssText='position:absolute;top:0;left:0;width:100%;height:100%';\n" ++
    "      c.appendChild(cv)}\n" ++
    "    var g=cv.getContext('2d');\n" ++
    "    if(m.op==='reset'){g.clearRect(0,0,cv.width,cv.height);return}\n" ++
    "    g.lineCap='round';g.lineWidth=4;\n" ++
    "    (m.segs||[]).forEach(function(s){\n" ++
    "      g.strokeStyle=s[4];g.beginPath();\n" ++
    "      g.moveTo(s[0]*cv.width,s[1]*cv.height);\n" ++
    "      g.lineTo(s[2]*cv.width,s[3]*cv.height);g.stroke()});\n" ++
    "    return}\n" ++
    "  /* upsert: replace the sw-key'd child in place, else append. */\n" ++
    "  if(m.op==='upsert'){\n" ++
    "    var t2=document.createElement('div');t2.innerHTML=m.html;\n" ++
    "    var nn=t2.firstChild;if(!nn)return;\n" ++
    "    nn._t=Date.now();\n" ++
    "    var old=c.querySelector('[sw-key=\"'+m.key+'\"]');\n" ++
    "    if(old)c.replaceChild(nn,old);else c.appendChild(nn);\n" ++
    "    return}\n" ++
    "  if(m.op==='reset'){c.innerHTML='';return}\n" ++
    "  if(m.op==='delete'){\n" ++
    "    var d=c.querySelector('[sw-key=\"'+m.key+'\"]');\n" ++
    "    if(d)d.parentNode.removeChild(d);return}\n" ++
    "  var tmp=document.createElement('div');\n" ++
    "  tmp.innerHTML=m.html;\n" ++
    "  var node=tmp.firstChild;\n" ++
    "  if(!node)return;\n" ++
    "  if(m.op==='prepend')c.insertBefore(node,c.firstChild);\n" ++
    "  else c.appendChild(node);\n" ++
    "  bind();autoscroll();\n" ++
    "}\n" ++
    "\n" ++
    "/* Reconnecting toast — injected into <body>, not #live-root, so\n" ++
    "   diffs don't touch it. */\n" ++
    "var _toast=null;\n" ++
    "function showReconnecting(){\n" ++
    "  if(_toast)return;\n" ++
    "  _toast=document.createElement('div');\n" ++
    "  _toast.id='sw-reconnect';\n" ++
    "  _toast.style.cssText='position:fixed;bottom:1.2rem;left:50%;transform:translateX(-50%);'" ++
    "+'background:#1e1e1e;color:#e6e6e6;padding:.5rem 1.25rem;border-radius:9999px;'" ++
    "+'font-size:.8rem;font-family:sans-serif;box-shadow:0 2px 12px rgba(0,0,0,.5);z-index:9999';\n" ++
    "  _toast.textContent='reconnecting...';\n" ++
    "  document.body.appendChild(_toast)}\n" ++
    "function hideReconnecting(){\n" ++
    "  if(_toast){_toast.parentNode&&_toast.parentNode.removeChild(_toast);_toast=null}}\n" ++
    "\n" ++
    "/* WebSocket connection with exponential backoff. */\n" ++
    "function connect(){\n" ++
    "  var proto=location.protocol==='https:'?'wss:':'ws:';\n" ++
    "  ws=new WebSocket(proto+'//'+location.host+'/live/ws');\n" ++
    "  ws.onopen=function(){retries=0;hideReconnecting();\n" ++
    "    ws.send(JSON.stringify({t:'join',p:location.pathname}))};\n" ++
    "  ws.onmessage=function(e){\n" ++
    "    var msg;\n" ++
    "    try{msg=JSON.parse(e.data)}catch(err){return}\n" ++
    "    if(msg.t==='m'){\n" ++
    "      statics=msg.s||[];dynamics=msg.d||[];render()}\n" ++
    "    else if(msg.t==='d'){\n" ++
    "      var c=msg.c||{},k;\n" ++
    "      for(k in c)dynamics[parseInt(k,10)]=c[k];\n" ++
    "      render()}\n" ++
    "    else if(msg.t==='s'){applyStream(msg)}\n" ++
    "    else if(msg.t==='patch'){history.pushState({},'',msg.p)}\n" ++
    "  };\n" ++
    "  ws.onclose=function(){\n" ++
    "    showReconnecting();\n" ++
    "    var delay=Math.min(1000*Math.pow(2,retries++),30000);\n" ++
    "    setTimeout(connect,delay)};\n" ++
    "  ws.onerror=function(){};\n" ++
    "}\n" ++
    "\n" ++
    "/* Send an event to the server. */\n" ++
    "function send(n,v){\n" ++
    "  if(ws&&ws.readyState===1)\n" ++
    "    ws.send(JSON.stringify({t:'e',n:n,v:v||{}}))\n" ++
    "}\n" ++
    "\n" ++
    "/* Live navigation: change the URL, ask the server to re-mount. */\n" ++
    "function navTo(path,push){\n" ++
    "  if(push!==false)history.pushState({},'',path);\n" ++
    "  if(ws&&ws.readyState===1)ws.send(JSON.stringify({t:'nav',p:path}))\n" ++
    "}\n" ++
    "window.onpopstate=function(){navTo(location.pathname,false)};\n" ++
    "\n" ++
    "/* Client-side JS commands: sw-js=\"verb:selector[:arg]\" runs on a\n" ++
    "   click with no server round-trip. */\n" ++
    "function runJs(cmd){\n" ++
    "  var p=cmd.split(':'),verb=p[0],sel=p[1],arg=p[2];\n" ++
    "  if(!sel)return;\n" ++
    "  document.querySelectorAll(sel).forEach(function(el){\n" ++
    "    if(verb==='toggle')el.style.display=(el.style.display==='none'?'':'none');\n" ++
    "    else if(verb==='show')el.style.display='';\n" ++
    "    else if(verb==='hide')el.style.display='none';\n" ++
    "    else if(verb==='add-class')el.classList.add(arg);\n" ++
    "    else if(verb==='remove-class')el.classList.remove(arg);\n" ++
    "    else if(verb==='toggle-class')el.classList.toggle(arg);\n" ++
    "    /* tab:panel-id — activate a tab panel and its trigger button.\n" ++
    "       Hides all siblings with [sw-tab-panel], shows the target;\n" ++
    "       removes ui-tab-active from all [sw-tab], adds to the caller. */\n" ++
    "    else if(verb==='tab'){\n" ++
    "      var panel=document.getElementById(sel);\n" ++
    "      if(!panel)return;\n" ++
    "      var panels=panel.parentNode.querySelectorAll('[sw-tab-panel]');\n" ++
    "      panels.forEach(function(p){p.style.display='none'});\n" ++
    "      panel.style.display='';\n" ++
    "      var tabs=document.querySelectorAll('[sw-tab=\"'+sel+'\"]');\n" ++
    "      document.querySelectorAll('[sw-tab]').forEach(function(t){\n" ++
    "        t.classList.remove('ui-tab-active')});\n" ++
    "      tabs.forEach(function(t){t.classList.add('ui-tab-active')})}})\n" ++
    "}\n" ++
    "\n" ++
    "/* Collect sw-value-* attributes off an element. */\n" ++
    "function getVals(el){\n" ++
    "  var v={};\n" ++
    "  Array.prototype.forEach.call(el.attributes,function(a){\n" ++
    "    if(a.name.indexOf('sw-value-')===0)\n" ++
    "      v[a.name.slice(9)]=a.value});\n" ++
    "  return v\n" ++
    "}\n" ++
    "\n" ++
    "/* A form element's fields -> {name: value} map. */\n" ++
    "function formData(el){\n" ++
    "  var v={};new FormData(el).forEach(function(val,k){v[k]=val});return v\n" ++
    "}\n" ++
    "\n" ++
    "/* Debounce a handler by sw-debounce=\"ms\" on the element. */\n" ++
    "function deb(el,fn){\n" ++
    "  var ms=parseInt(el.getAttribute('sw-debounce')||'0',10);\n" ++
    "  if(!ms)return fn;\n" ++
    "  var t;return function(e){clearTimeout(t);t=setTimeout(function(){fn(e)},ms)}\n" ++
    "}\n" ++
    "\n" ++
    "/* (Re)bind event handlers after each render. */\n" ++
    "function bind(){\n" ++
    "  document.querySelectorAll('[sw-click]').forEach(function(el){\n" ++
    "    el.onclick=function(e){e.preventDefault();\n" ++
    "      send(el.getAttribute('sw-click'),getVals(el))}});\n" ++
    "  document.querySelectorAll('[sw-link]').forEach(function(el){\n" ++
    "    el.onclick=function(e){e.preventDefault();\n" ++
    "      navTo(el.getAttribute('sw-link'))}});\n" ++
    "  document.querySelectorAll('[sw-js]').forEach(function(el){\n" ++
    "    el.onclick=function(e){e.preventDefault();\n" ++
    "      runJs(el.getAttribute('sw-js'))}});\n" ++
    "  document.querySelectorAll('[sw-submit]').forEach(function(el){\n" ++
    "    el.onsubmit=function(e){e.preventDefault();\n" ++
    "      send(el.getAttribute('sw-submit'),formData(el))}});\n" ++
    "  document.querySelectorAll('[sw-change]').forEach(function(el){\n" ++
    "    el.onchange=function(){\n" ++
    "      send(el.getAttribute('sw-change'),\n" ++
    "        el.tagName==='FORM'?formData(el):el.value)}});\n" ++
    "  document.querySelectorAll('[sw-input]').forEach(function(el){\n" ++
    "    el.oninput=deb(el,function(){\n" ++
    "      send(el.getAttribute('sw-input'),el.value)})});\n" ++
    "  document.querySelectorAll('[sw-keyup]').forEach(function(el){\n" ++
    "    el.onkeyup=deb(el,function(e){\n" ++
    "      send(el.getAttribute('sw-keyup'),{key:e.key,value:el.value})})});\n" ++
    "  document.querySelectorAll('[sw-keydown]').forEach(function(el){\n" ++
    "    el.onkeydown=function(e){\n" ++
    "      send(el.getAttribute('sw-keydown'),{key:e.key,value:el.value})}});\n" ++
    "  document.querySelectorAll('[sw-blur]').forEach(function(el){\n" ++
    "    el.onblur=function(){\n" ++
    "      send(el.getAttribute('sw-blur'),el.value||getVals(el))}});\n" ++
    "  document.querySelectorAll('[sw-focus]').forEach(function(el){\n" ++
    "    el.onfocus=function(){\n" ++
    "      send(el.getAttribute('sw-focus'),el.value||getVals(el))}});\n" ++
    "  document.querySelectorAll('[sw-scroll]').forEach(function(el){\n" ++
    "    el.onscroll=deb(el,function(){\n" ++
    "      send(el.getAttribute('sw-scroll'),\n" ++
    "        {scrollTop:el.scrollTop,scrollLeft:el.scrollLeft,\n" ++
    "         scrollHeight:el.scrollHeight,clientHeight:el.clientHeight})})});\n" ++
    "  /* sw-pointer=\"evt\": normalized (0..1) pointer events, throttled.\n" ++
    "     Sends {k:'down'|'draw'|'move'|'up', x, y}. */\n" ++
    "  document.querySelectorAll('[sw-pointer]').forEach(function(el){\n" ++
    "    if(el._swp)return;el._swp=1;\n" ++
    "    var ev=el.getAttribute('sw-pointer'),last=0,down=false;\n" ++
    "    function pos(e){var r=el.getBoundingClientRect();\n" ++
    "      return {x:Math.min(1,Math.max(0,(e.clientX-r.left)/r.width)),\n" ++
    "              y:Math.min(1,Math.max(0,(e.clientY-r.top)/r.height))}}\n" ++
    "    el.onpointerdown=function(e){down=true;\n" ++
    "      try{el.setPointerCapture(e.pointerId)}catch(x){}\n" ++
    "      var p=pos(e);send(ev,{k:'down',x:p.x,y:p.y})};\n" ++
    "    el.onpointermove=function(e){var n=Date.now();if(n-last<25)return;last=n;\n" ++
    "      var p=pos(e);send(ev,{k:down?'draw':'move',x:p.x,y:p.y})};\n" ++
    "    el.onpointerup=function(e){if(!down)return;down=false;\n" ++
    "      var p=pos(e);send(ev,{k:'up',x:p.x,y:p.y})}});\n" ++
    "  /* sw-enter: fire event when Enter is pressed (no form wrapper needed). */\n" ++
    "  document.querySelectorAll('[sw-enter]').forEach(function(el){\n" ++
    "    el.onkeydown=function(e){\n" ++
    "      if(e.key==='Enter'&&!e.shiftKey){\n" ++
    "        e.preventDefault();\n" ++
    "        send(el.getAttribute('sw-enter'),el.value||getVals(el))}}})\n" ++
    "}\n" ++
    "\n" ++
    "/* sw-ttl=\"ms\": drop stream children not refreshed within ms\n" ++
    "   (ephemeral things like remote cursors). */\n" ++
    "setInterval(function(){\n" ++
    "  var now=Date.now();\n" ++
    "  document.querySelectorAll('[sw-ttl]').forEach(function(c){\n" ++
    "    var ttl=parseInt(c.getAttribute('sw-ttl'),10);\n" ++
    "    Array.prototype.slice.call(c.children).forEach(function(k){\n" ++
    "      if(k._t&&now-k._t>ttl)c.removeChild(k)})})},1000);\n" ++
    "\n" ++
    "connect();\n" ++
    "\n" ++
    "/* Heartbeat — keeps the session's idle timer alive and lets the\n" ++
    "   server reap half-open connections. */\n" ++
    "setInterval(function(){\n" ++
    "  if(ws&&ws.readyState===1)ws.send(JSON.stringify({t:'hb'}))},30000);\n" ++
    "\n" ++
    "})();\n"
}
