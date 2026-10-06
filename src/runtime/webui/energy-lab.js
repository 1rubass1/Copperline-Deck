/* GPU Lab only. Procedural right-edge energy and persistent particle circulation. */
(function(root,factory){
  'use strict';
  const api=factory();
  if(typeof module==='object' && module.exports) module.exports=api;
  else root.EnergyLab=api;
})(typeof globalThis!=='undefined'?globalThis:this,function(){
'use strict';
const clamp=(x,a,b)=>Math.max(a,Math.min(b,x));
const mix=(a,b,t)=>a+(b-a)*t;
const smooth=(a,b,x)=>{const t=clamp((x-a)/(b-a),0,1);return t*t*(3-2*t);};
function random(seed){return function(){let t=seed+=0x6D2B79F5;t=Math.imul(t^t>>>15,t|1);t^=t+Math.imul(t^t>>>7,t|61);return((t^t>>>14)>>>0)/4294967296;};}
const settings=Object.freeze({
  // Width and contact share this one geometry; motion speeds are field widths/second.
  stripMin:25,stripMax:25,stripFraction:0.065,
  chargeMin:4.5,chargeMax:10.0,
  outwardMin:0.018,outwardMax:0.028,
  returnMin:0.010,returnMax:0.016,
  driftScale:0.55,
  turnMin:0.075,turnMax:0.32,
  launchPulseSeconds:0.62,entryPulseSeconds:0.48,
  maxFrameStep:0.05,maxSubstep:1/120
});
function geometry(width,height){
  const W=Math.max(1,width),H=Math.max(1,height);
  // A narrow right-edge accent; preserve the existing particle field and right anchor.
  const strip=Math.min(W,clamp(W*settings.stripFraction,settings.stripMin,settings.stripMax));
  return {width:W,height:H,x0:W*0.68,area:W*0.32,strip,ratio:strip/(W*0.32)};
}
function reachAt(y,t){
  // Stable light volume: no moving flame front or temporary holes.
  return 0.78;
}
function insideBarrier(p,g,t){
  const d=(1-p.u)/g.ratio;
  // Charge within the dense part of the glow, not in its faint outer fade.
  return d>=0 && d<reachAt(p.v*g.height/88,t)-0.30;
}
function pulse(age,duration){
  if(age<0||age>=duration)return 0;
  return smooth(0,0.11,age)*(1-smooth(0.14,duration,age));
}
// Each particle wanders around a different full-height location. Unlike integrating
// a biased vertical velocity, this bounded motion cannot migrate to the centre.
function verticalTarget(p,height,t){
  const H=Math.max(1,height),overscanPx=Math.min(42,Math.max(22,H*0.045));
  const low=-overscanPx/H,high=1+overscanPx/H;
  const home=low+(high-low)*p.verticalHome;
  const radius=Math.min(0.055,p.verticalRadius/H,(home-low)*0.82,(high-home)*0.82);
  const a=t*p.verticalFrequency+p.verticalPhase;
  const b=t*p.verticalFrequency*1.618+p.verticalPhase*1.37;
  return {
    position:home+radius*(0.64*Math.sin(a)+0.36*Math.sin(b)),
    velocity:radius*p.verticalFrequency*(0.64*Math.cos(a)+0.36*1.618*Math.cos(b))
  };
}
class ParticleCycle{
  constructor(particles,width,height,seed=80421){
    this.particles=particles;this.rand=random(seed);this.time=0;
    this.g=geometry(width,height);
    this.stats={entries:0,launches:0,returns:0,completedCycles:0,minDwell:Infinity,maxDwell:0,invalidLaunches:0};
    for(const p of particles){
      p.vx=0;p.vy=0;p.state='return';p.stateAge=0;p.dwell=0;
      p.entryAge=99;p.launchAge=99;p.temperature=0.25;
      p.cycles=0;p.cycleStarted=false;
      this.plan(p);
      // Start in different phases without an opening flash or a synchronized burst.
      if(insideBarrier(p,this.g,0)){
        p.state='charge';p.dwell=this.rand()*p.chargeDuration;
        p.temperature=0.78;
      }else if(this.rand()<0.55){
        p.state='out';p.leftTarget=Math.min(p.leftTarget,Math.max(0.04,p.u-0.12));
        p.vx=-p.outSpeed*0.45;p.temperature=mix(0.1,0.7,p.u);
      }else p.vx=p.returnSpeed*0.45;
    }
    // Separate random stream preserves all existing horizontal flight/dwell choices.
    // Sorted, jittered strata avoid rows while retaining particles near BOTH edges.
    const vr=random(seed^0x3c6ef372);
    const ordered=[...particles].sort((a,b)=>a.v-b.v);
    ordered.forEach((p,i)=>{
      // Extend the simulated field beyond the visible canvas. Off-screen nodes remain
      // clipped by the WebGL canvas, but their links can naturally cross the edge.
      p.verticalHome=(i+0.22+0.56*vr())/ordered.length;
      p.verticalRadius=18+22*vr();
      p.verticalFrequency=0.06+0.06*vr();
      p.verticalPhase=vr()*Math.PI*2;
      const y=verticalTarget(p,this.g.height,0);
      // Initial placement only, before the first render. Never reset positions in step().
      p.v=y.position;p.vy=y.velocity;
    });
  }
  plan(p){
    const r=this.rand;
    p.dockDepth=0.11+r()*0.25;
    p.chargeDuration=mix(settings.chargeMin,settings.chargeMax,r());
    p.leftTarget=mix(settings.turnMin,settings.turnMax,r());
    p.outSpeed=mix(settings.outwardMin,settings.outwardMax,r());
    p.returnSpeed=mix(settings.returnMin,settings.returnMax,r());
    p.bend=(r()-0.5)*0.023;
  }
  flash(p){return Math.min(1,pulse(p.launchAge,settings.launchPulseSeconds)+0.22*pulse(p.entryAge,settings.entryPulseSeconds));}
  step(delta,width,height){
    if(!Number.isFinite(delta)||delta<=0)return;
    this.g=geometry(width,height);
    let remaining=Math.min(settings.maxFrameStep,delta);
    while(remaining>1e-8){
      const h=Math.min(remaining,settings.maxSubstep);remaining-=h;this.time+=h;
      const g=this.g,t=this.time;
      for(const p of this.particles){
        p.stateAge+=h;p.entryAge+=h;p.launchAge+=h;
        const inside=insideBarrier(p,g,t);
        const dock=clamp(1-g.ratio*p.dockDepth,0.55,0.9985);
        let wantedX=0,relax=0.85,targetHeat=0.18;
        if(p.state==='return'){
          wantedX=Math.min(p.returnSpeed,Math.max(0,(dock-p.u)*0.20));
          relax=1.05;
          if(inside){
            p.state='charge';p.stateAge=0;p.dwell=0;p.entryAge=0;
            p.chargeDuration=mix(settings.chargeMin,settings.chargeMax,this.rand());
            this.stats.entries++;
            if(p.cycleStarted){p.cycles++;this.stats.completedCycles++;p.cycleStarted=false;}
          }
        }
        if(p.state==='charge'){
          // Stay within the lit source and drift gently while waiting an independent time.
          wantedX=clamp((dock+Math.sin(t*0.26+p.phase)*Math.min(0.006,g.ratio*0.06,0.999-dock)-p.u)*0.20,-0.018,0.028);
          relax=1.05;targetHeat=0.86;
          if(inside)p.dwell+=h;
          if(p.dwell>=p.chargeDuration && inside){
            p.state='out';p.stateAge=0;p.launchAge=0;p.temperature=1;
            p.cycleStarted=true;
            p.leftTarget=mix(settings.turnMin,settings.turnMax,this.rand());
            p.outSpeed=mix(settings.outwardMin,settings.outwardMax,this.rand());
            p.bend=(this.rand()-0.5)*0.023;
            this.stats.launches++;
            this.stats.minDwell=Math.min(this.stats.minDwell,p.dwell);
            this.stats.maxDwell=Math.max(this.stats.maxDwell,p.dwell);
            if(!insideBarrier(p,g,t))this.stats.invalidLaunches++;
          }
        }
        if(p.state==='out'){
          // Continuous velocity, never a teleport or an instantaneous wall reflection.
          wantedX=-Math.min(p.outSpeed,Math.max(0.004,(p.u-p.leftTarget)*0.30));
          relax=1.05;targetHeat=Math.exp(-p.stateAge/7.0);
          if(p.u<=p.leftTarget+0.033 && p.stateAge>1){
            p.state='return';p.stateAge=0;this.stats.returns++;
            p.dockDepth=0.11+this.rand()*0.25;
            p.returnSpeed=mix(settings.returnMin,settings.returnMax,this.rand());
            // Retain the current negative velocity: it eases into the return on later steps.
          }
        }
        const vertical=verticalTarget(p,g.height,t);
        // Track an individual moving target with continuous velocity; no central pull.
        const wantedY=clamp(vertical.velocity+(vertical.position-p.v)*0.45,-0.018,0.018);
        p.vx+=(wantedX-p.vx)*(1-Math.exp(-h/relax));
        p.vy+=(wantedY-p.vy)*(1-Math.exp(-h/0.90));
        p.u+=p.vx*h;p.v+=p.vy*h;
        // Last-resort bounds also protect resize and malformed frame delta cases.
        if(p.u<0.02){p.u=0.02;p.vx=Math.max(0,p.vx);}
        if(p.u>0.9995){p.u=0.9995;p.vx=Math.min(0,p.vx);}
        const over=Math.min(42,Math.max(22,g.height*0.045))/Math.max(1,g.height);
        if(p.v< -over){p.v=-over;p.vy=Math.max(0,p.vy);}
        if(p.v>1+over){p.v=1+over;p.vy=Math.min(0,p.vy);}
        p.temperature+=(targetHeat-p.temperature)*(1-Math.exp(-h/1.3));
      }
    }
  }
  snapshot(){
    const states={charge:0,out:0,return:0};
    for(const p of this.particles)states[p.state]++;
    const ys=this.particles.map(p=>p.v).sort((a,b)=>a-b),bins=Array(10).fill(0);
    for(const y of ys)if(y>=0&&y<=1)bins[Math.min(9,Math.floor(y*10))]++;
    const vertical=ys.length?{
      topInsetPx:ys[0]*this.g.height,bottomInsetPx:(1-ys[ys.length-1])*this.g.height,
      maxGapPx:Math.max(0,...ys.slice(1).map((v,i)=>(v-ys[i])*this.g.height)),bins
    }:null;
    return {version:'energy-cycle-7-72particles-halfspeed',time:this.time,states,stats:{...this.stats},geometry:{...this.g},vertical};
  }
}
const vertex=`
  in vec2 aPosition;
  out vec2 vTextureCoord;
  uniform vec4 uOutputFrame;
  uniform vec4 uOutputTexture;
  void main(void){
    vec2 position=aPosition*uOutputFrame.zw+uOutputFrame.xy;
    position.x=position.x*(2.0/uOutputTexture.x)-1.0;
    position.y=position.y*(2.0*uOutputTexture.z/uOutputTexture.y)-uOutputTexture.z;
    gl_Position=vec4(position,0.0,1.0);
    // Procedural coordinates cover the actual strip, not a padded filter texture.
    vTextureCoord=aPosition;
  }
`;
const fragment=`
  in vec2 vTextureCoord;
  uniform float uTime;
  uniform float uHeight;
  void main(void){
    vec2 uv=vTextureCoord;
    float d=clamp(1.0-uv.x,0.0,1.0);
    float y=uv.y*uHeight/140.0;
    float t=uTime;

    // Unequal, overlapping pools: all transitions stay broad and continuous.
    float drift=y+0.28*sin(y*1.17-t*0.43)+0.09*sin(y*3.21+t*0.29);
    float poolA=0.5+0.5*sin(drift*2.80-t*1.24-d*2.50
                          +0.63*sin(y*1.93+t*0.41));
    float poolB=0.5+0.5*sin(drift*6.20+t*0.87-d*3.10+1.70);
    float poolC=0.5+0.5*sin(y*10.90-t*0.68+d*1.70+0.45*sin(y*2.40-t*0.23));
    float flow=0.52*poolA+0.31*poolB+0.17*poolC;
    float highlight=smoothstep(0.35,0.82,flow);
    float tintWave=0.5+0.5*sin(y*2.40-t*0.57+d*1.80);
    float breath=0.94+0.04*sin(t*0.93)+0.02*sin(t*0.47+1.30);

    // Stronger local width variation, still wholly inside the same 25px canvas.
    // A dim continuous bed prevents blank gaps between the bright moving pools.
    float swell=clamp(0.77+0.16*sin(drift*2.30-t*1.21+0.40*sin(y*0.91+t*0.31))
                         +0.09*sin(y*5.90+t*0.79)+0.05*sin(y*11.20-t*0.53),0.50,1.0);
    float q=d/swell;
    float changing=exp(-q*q*0.85)*(1.0-smoothstep(0.10,1.0,q));
    float bed=exp(-d*d*1.90)*(1.0-smoothstep(0.08,1.0,d));
    float coverage=0.20*bed+0.80*changing;
    float rootSpan=0.95+0.38*sin(y*4.30-t*0.95+0.55*sin(y*1.20+t*0.28));
    float source=exp(-d*d*(38.0/rootSpan));
    float innerBloom=exp(-q*q*5.0);
    // Separate caustic root: a narrow ridge that meanders 1-4 px from the edge.
    // The broad 25 px light remains the crown; only this inner ridge oscillates.
    float rootWave=0.045
      +0.055*(0.5+0.5*sin(y*5.4-t*1.10+0.48*sin(y*1.7+t*0.36)))
      +0.040*(0.5+0.5*sin(y*10.8+t*0.72));
    float ridge=exp(-(d-rootWave)*(d-rootWave)*620.0);
    float edgeBed=exp(-d*d*300.0)*0.32;
    float rootGlow=max(ridge,edgeBed);
    float rootPulse=0.90+0.10*sin(y*5.1-t*1.35+0.35*sin(y*1.6+t*0.42));

    // Same copper family as the shell buttons: base, pressed and hover accents.
    // Compress intensity as a scalar, not per channel: strong light stays orange.
    vec3 copper=vec3(191.0,118.0,67.0)/255.0;
    vec3 deepCopper=vec3(166.0,98.0,55.0)/255.0;
    vec3 litCopper=vec3(224.0,151.0,91.0)/255.0;
    vec3 tint=mix(deepCopper,copper,0.50+0.22*tintWave);
    float energy=(0.50+1.10*highlight+0.28*flow+0.12*innerBloom
                  +source*(0.32+0.90*highlight))*breath;
    float intensity=1.0-exp(-energy*1.30);
    float warmPeak=source*(0.22+0.34*highlight);
    vec3 light=mix(tint,litCopper,warmPeak)*intensity;
    vec3 rootColor=vec3(1.0,0.82,0.66);
    light+=rootColor*(rootGlow*rootPulse*0.62);
    light=min(light,vec3(1.0));
    float alpha=max(0.93*coverage,rootGlow*0.78);
    gl_FragColor=vec4(light*alpha,alpha);
  }
`;
return {settings,geometry,reachAt,insideBarrier,ParticleCycle,vertex,fragment};
});
