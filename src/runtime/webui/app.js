(() => {
'use strict';
const viewport=document.getElementById('viewport');
const log=document.getElementById('log');
const fxHost=document.getElementById('fx');
const scrollBottom=document.getElementById('scrollBottom');
const hostPost=(payload)=>{try{window.chrome?.webview?.postMessage(payload)}catch{}};

let pixiApp=null;
let hostFxPaused=false;
let visibilityFxPaused=document.hidden;
function syncFxPause(){
  if(!pixiApp)return;
  const paused=hostFxPaused||visibilityFxPaused;
  if(paused){
    if(pixiApp.ticker.started)pixiApp.ticker.stop();
  }else if(!pixiApp.ticker.started){
    pixiApp.ticker.start();
  }
}
document.addEventListener('visibilitychange',()=>{
  visibilityFxPaused=document.hidden;
  syncFxPause();
});

let scrollButtonFrame=0;
function updateScrollButton(){
  scrollButtonFrame=0;
  const scrollbarWidth=Math.max(0,viewport.offsetWidth-viewport.clientWidth);
  document.documentElement.style.setProperty('--scrollbar-width',scrollbarWidth+'px');
  const distance=Math.max(0,viewport.scrollHeight-viewport.scrollTop-viewport.clientHeight);
  const canScroll=viewport.scrollHeight>viewport.clientHeight+4;
  scrollBottom?.classList.toggle('visible',canScroll&&distance>120);
}
function scheduleScrollButton(){
  if(scrollButtonFrame)return;
  scrollButtonFrame=requestAnimationFrame(updateScrollButton);
}
viewport.addEventListener('scroll',scheduleScrollButton,{passive:true});
window.addEventListener('resize',scheduleScrollButton);
scrollBottom?.addEventListener('click',()=>{
  viewport.scrollTo({top:viewport.scrollHeight,behavior:'smooth'});
  setTimeout(()=>{
    viewport.scrollTop=viewport.scrollHeight;
    scheduleScrollButton();
  },360);
});
window.addEventListener('error',(e)=>hostPost({type:'jsError',message:String(e.message||e.error||'unknown error')}));
window.addEventListener('unhandledrejection',(e)=>hostPost({type:'jsError',message:String(e.reason||'unhandled rejection')}));

function classify(s){
  if(/^=== .+ ===\s*$/.test(s)) return 'banner';
  if(/^> /.test(s)) return 'command';
  if(/Done \([^)]+\)! For help, type "help"/i.test(s)) return 'ready';
  if(/\/WARN\]:/i.test(s)) return 'warn';
  if(/\/ERROR\]|\/FATAL\]|Exception|Caused by:/i.test(s) || /^(Ошибка:|Не удалось|Тайм-аут)/i.test(s)) return 'error';
  if(/logged in with entity id|joined the game|Player \[[^\]]+\] joined\./i.test(s)) return 'join';
  if(/left the game|lost connection:|disconnected\./i.test(s)) return 'leave';
  if(/Stopping the server|Stopping server|Saving players|Saving worlds|All dimensions are saved/i.test(s)) return 'save';
  if(/There are \d+ of a max of \d+ players online/i.test(s)) return 'info';
  return '';
}
function appendLine(text){
  const div=document.createElement('div');
  div.className='line '+classify(text);
  div.textContent=text.length?text:' ';
  log.appendChild(div);
}
function renderText(text){
  log.textContent='';
  const lines=String(text||'').replace(/\r/g,'').split('\n');
  for(const line of lines) appendLine(line);
}
window.setLogText=(text)=>{
  const atBottom=(viewport.scrollHeight-viewport.scrollTop-viewport.clientHeight)<28;
  renderText(text);
  if(atBottom) viewport.scrollTop=viewport.scrollHeight;
  scheduleScrollButton();
};
window.appendLog=(text)=>{
  const atBottom=(viewport.scrollHeight-viewport.scrollTop-viewport.clientHeight)<28;
  const existing=Array.from(log.children);
  let current='';
  if(existing.length){ current=existing[existing.length-1].textContent; log.removeChild(existing[existing.length-1]); }
  const combined=current+String(text||'').replace(/\r/g,'');
  const lines=combined.split('\n');
  for(const line of lines) appendLine(line);
  if(atBottom) viewport.scrollTop=viewport.scrollHeight;
  scheduleScrollButton();
};
window.clearLog=()=>{log.textContent=''; appendLine(''); viewport.scrollTop=0; scheduleScrollButton();};
window.__webLogReady=false;

if(window.chrome?.webview){
  window.chrome.webview.addEventListener('message',(event)=>{
    const m=event.data||{};
    if(m.type==='append') window.appendLog(m.text||'');
    else if(m.type==='set') window.setLogText(m.text||'');
    else if(m.type==='clear') window.clearLog();
    else if(m.type==='bottom') viewport.scrollTop=viewport.scrollHeight;
    else if(m.type==='fxPause'){
      hostFxPaused=String(m.text||'')==='1';
      syncFxPause();
    }
  });
}

(async()=>{
  const app=new PIXI.Application();
  await app.init({
    resizeTo:window,
    backgroundAlpha:0,
    antialias:true,
    autoDensity:true,
    resolution:Math.min(window.devicePixelRatio||1,2),
    preference:'webgl',
    powerPreference:'high-performance'
  });
  pixiApp=app;
  syncFxPause();
  app.canvas.style.position='absolute';
  app.canvas.style.inset='0';
  app.canvas.style.width='100%';
  app.canvas.style.height='100%';
  app.canvas.style.pointerEvents='none';
  fxHost.appendChild(app.canvas);

  const stage=new PIXI.Container();
  stage.blendMode='add';
  app.stage.addChild(stage);

  const causticCanvas=document.createElement('canvas');
  causticCanvas.width=causticCanvas.height=2;
  const causticCtx=causticCanvas.getContext('2d');
  causticCtx.fillStyle='#ffffff';
  causticCtx.fillRect(0,0,2,2);
  const causticSprite=new PIXI.Sprite(PIXI.Texture.from(causticCanvas));
  causticSprite.blendMode='add';
  stage.addChild(causticSprite);

  const causticVertex=EnergyLab.vertex;
  const causticFragment=EnergyLab.fragment;

  const causticFilter=new PIXI.Filter({
    glProgram:PIXI.GlProgram.from({
      vertex:causticVertex,
      fragment:causticFragment
    }),
    resources:{
      causticUniforms:{
        uTime:{value:0.0,type:'f32'},
        uHeight:{value:Math.max(1,app.screen.height),type:'f32'}
      }
    }
  });
  causticFilter.padding=0;
  causticSprite.filters=[causticFilter];

  const links=new PIXI.Graphics();
  links.blendMode='add';
  stage.addChild(links);

  const particlesLayer=new PIXI.Container();
  particlesLayer.blendMode='add';
  stage.addChild(particlesLayer);

  function makeGlowTexture(size=256){
    const c=document.createElement('canvas'); c.width=c.height=size;
    const ctx=c.getContext('2d');
    const g=ctx.createRadialGradient(size/2,size/2,0,size/2,size/2,size/2);
    g.addColorStop(0,'rgba(255,255,255,1)');
    g.addColorStop(.10,'rgba(255,255,255,.92)');
    g.addColorStop(.28,'rgba(255,255,255,.48)');
    g.addColorStop(.58,'rgba(255,255,255,.13)');
    g.addColorStop(1,'rgba(255,255,255,0)');
    ctx.fillStyle=g; ctx.fillRect(0,0,size,size);
    return PIXI.Texture.from(c);
  }
  const glowTexture=makeGlowTexture();

  const orange=0xbf7643, purple=0x7b5fa2;
  const rand=mulberry32(153);

  const particles=[];
  for(let i=0;i<72;i++){
    const fast=rand()>.62;
    const p={
      u:.04+rand()*.94,v:.04+rand()*.92,
      du:(rand()-.5)*(fast?.020:.011),
      dv:(rand()-.5)*(fast?.018:.0096),
      base:2.0+Math.pow(rand(),1.45)*7.6,
      phase:rand()*Math.PI*2,
      tint:rand()>.55?orange:purple,
      sprite:new PIXI.Sprite(glowTexture),
      core:new PIXI.Sprite(glowTexture)
    };
    p.sprite.anchor.set(.5);
    p.sprite.tint=p.tint;
    p.sprite.blendMode='add';
    p.core.anchor.set(.5);
    p.core.tint=0xffffff;
    p.core.blendMode='add';
    particlesLayer.addChild(p.sprite);
    particlesLayer.addChild(p.core);
    particles.push(p);
  }

  const smooth=(a,b,x)=>{let t=Math.max(0,Math.min(1,(x-a)/(b-a)));return t*t*(3-2*t)};
  const energyCycle=new EnergyLab.ParticleCycle(particles,app.screen.width,app.screen.height);
  app.ticker.maxFPS=60;
  // Read-only diagnostics, with no effect on the server control channel.
  window.__energyLab=Object.freeze({snapshot:()=>energyCycle.snapshot()});
  let firstFrameReported=false;
  let tickerErrorReported=false;

  app.ticker.add((ticker)=>{
    try {
    const dt=Math.min(.05,ticker.deltaMS/1000);
    const W=app.screen.width,H=app.screen.height;
    const scrollbarWidth=Math.max(0,viewport.offsetWidth-viewport.clientWidth);
    energyCycle.step(dt,W,H);
    const now=energyCycle.time;
    const sceneTime=now*1.75;
    const x0=W*.68, areaW=W-x0;

    // Single right-edge energy flame layer.
    // Use the same narrow strip as particle/barrier contact detection.
    const causticWidth=energyCycle.g.strip;
    const fxRight=W-scrollbarWidth;
    causticSprite.x=fxRight-causticWidth;
    causticSprite.y=0;
    causticSprite.width=causticWidth;
    causticSprite.height=H;
    causticFilter.resources.causticUniforms.uniforms.uTime=now;
    causticFilter.resources.causticUniforms.uniforms.uHeight=Math.max(1,H);

    for(const p of particles){
      const flare=energyCycle.flash(p);
      const thermalGain=.94+.06*p.temperature;
      const fade=Math.pow(smooth(.06,.96,p.u),1.85);
      const sizeScale=.15+.85*Math.pow(smooth(.02,.97,p.u),1.18);
      const heat=smooth(.30,.99,p.u);
      const twinkle=.95+.05*Math.sin(sceneTime*.24+p.phase);
      const px=x0+p.u*areaW-scrollbarWidth, py=p.v*H;
      const diameter=p.base*sizeScale*5.8*(1+.04*flare);
      const haloAlpha=Math.min(1,(.40+.40*heat)*fade*twinkle*(thermalGain+.20*flare));
      const coreDiameter=diameter*(.22+.18*heat)*(1+.08*flare);
      const coreAlpha=Math.min(1,(.10+.88*heat)*fade*twinkle*(thermalGain+.35*flare));

      p.sprite.x=px;p.sprite.y=py;
      p.sprite.width=p.sprite.height=diameter;
      p.sprite.alpha=haloAlpha;

      p.core.x=px;p.core.y=py;
      p.core.width=p.core.height=coreDiameter;
      p.core.alpha=coreAlpha;
    }

    links.clear();
    const linkLimit=Math.max(82,areaW*.31);
    const candidates=[];
    for(let i=0;i<particles.length;i++){
      const pa=particles[i],ax=x0+pa.u*areaW-scrollbarWidth,ay=pa.v*H;
      for(let j=i+1;j<particles.length;j++){
        const pb=particles[j],bx=x0+pb.u*areaW-scrollbarWidth,by=pb.v*H;
        const dist=Math.hypot(bx-ax,by-ay);
        if(dist<linkLimit)candidates.push({i,j,dist,ax,ay,bx,by});
      }
    }
    candidates.sort((m,n)=>m.dist-n.dist);
    const degree=new Uint8Array(particles.length);
    for(const edge of candidates){
      // At most four neighbours per particle: readable network, fewer accidental meshes.
      if(degree[edge.i]>=4||degree[edge.j]>=4)continue;
      const pa=particles[edge.i],pb=particles[edge.j];
      const af=Math.pow(smooth(.08,.97,pa.u),1.5);
      const bf=Math.pow(smooth(.08,.97,pb.u),1.5);
      const alpha=.38*(1-edge.dist/linkLimit)*Math.min(af,bf);
      if(alpha<=.006)continue;
      degree[edge.i]++;degree[edge.j]++;
      const color=(pa.tint===pb.tint)?pa.tint:0xa66f72;
      links.moveTo(edge.ax,edge.ay).lineTo(edge.bx,edge.by).stroke({width:2.6,color,alpha:alpha*.14});
      links.moveTo(edge.ax,edge.ay).lineTo(edge.bx,edge.by).stroke({width:1.05,color,alpha});
    }
    // Keep the native scrollbar visually clear even when halos touch the right edge.
    app.canvas.style.clipPath=scrollbarWidth>0?`inset(0 ${scrollbarWidth}px 0 0)`:'none';

    if(!firstFrameReported){
      firstFrameReported=true;
      hostPost({
        type:'frame',
        renderer:app.renderer?.constructor?.name||'unknown',
        canvasWidth:app.canvas.width,
        canvasHeight:app.canvas.height
      });
    }
    } catch(err) {
      if(!tickerErrorReported){
        tickerErrorReported=true;
        hostPost({type:'jsError',message:'ticker: '+String(err?.stack||err)});
      }
    }
  });

  window.__webLogReady=true;
  hostPost({
    type:'ready',
    renderer:app.renderer?.constructor?.name||'unknown',
    canvasWidth:app.canvas.width,
    canvasHeight:app.canvas.height
  });
})();

function mulberry32(a){return function(){let t=a+=0x6D2B79F5;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return((t^t>>>14)>>>0)/4294967296}}
})();