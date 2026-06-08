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
    "  bind();\n" ++
    "}\n" ++
    "\n" ++
    "/* Apply a stream op to a sw-stream container: append/prepend a node,\n" ++
    "   delete one by sw-key, or reset — no full re-render. */\n" ++
    "function applyStream(m){\n" ++
    "  var c=document.getElementById(m.id);\n" ++
    "  if(!c)return;\n" ++
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
    "  bind();\n" ++
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
    "    else if(verb==='toggle-class')el.classList.toggle(arg)})\n" ++
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
    "         scrollHeight:el.scrollHeight,clientHeight:el.clientHeight})})})\n" ++
    "}\n" ++
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
