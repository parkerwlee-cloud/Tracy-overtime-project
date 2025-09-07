const $ = (sel, el=document) => el.querySelector(sel);

function startClock(){
  const el = document.getElementById('clock');
  if(!el) return;
  const pad = n => String(n).padStart(2,'0');
  const tick = ()=>{
    const d = new Date();
    el.textContent = `${pad(d.getHours())}:${pad(d.getMinutes())}`;
  };
  tick(); setInterval(tick, 15_000);
}

function confirmSubmit(form){
  const btn = form.querySelector('button[type=submit]');
  if(btn?.dataset.locked) return false;
  if(btn) { btn.dataset.locked = '1'; btn.textContent = 'Working…'; }
  return true;
}

window.addEventListener('load', ()=>{ startClock(); });
