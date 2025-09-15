(function(){
  const modal = document.getElementById('signupModal');
  const nameInput = document.getElementById('name_input');
  const empSel = document.getElementById('employee_select');
  const slotIdInput = document.getElementById('slot_id');
  const msg = document.getElementById('signupMsg');

  let roster = [];
  fetch('/api/roster').then(r=>r.json()).then(data=>{ roster = data; });

  function openModal(slotId){
    slotIdInput.value = slotId;
    nameInput.value = '';
    empSel.innerHTML = '';
    msg.textContent = '';
    modal.showModal();
  }

  function filterRoster(q){
    q = (q||'').toLowerCase();
    const res = roster.filter(r => r.name.toLowerCase().includes(q));
    empSel.innerHTML = '';
    res.forEach(r => {
      const opt = document.createElement('option');
      opt.value = r.id;
      opt.textContent = r.tag;
      empSel.appendChild(opt);
    });
  }

  document.querySelectorAll('.btn-sign').forEach(btn => {
    btn.addEventListener('click', (e)=>{
      const slotId = e.target.closest('.slot').dataset.slot;
      openModal(slotId);
    });
  });

  nameInput.addEventListener('input', ()=> filterRoster(nameInput.value));

  document.getElementById('confirmBtn').addEventListener('click', async (e)=>{
    e.preventDefault();
    const slot_id = parseInt(slotIdInput.value, 10);
    const employee_id = parseInt(empSel.value || '0', 10);
    if(!employee_id){ msg.textContent='Select your name from the roster.'; return; }
    const res = await fetch('/api/signup', {method:'POST', headers:{'Content-Type':'application/json'}, body: JSON.stringify({slot_id, employee_id})});
    const body = await res.json();
    if(res.ok){
      msg.textContent = body.was_bump ? 'Assigned (bumped prior holder).' : 'Signed up!';
      setTimeout(()=>{ window.location.reload(); }, 600);
    }else{
      msg.textContent = body.error || 'Error.';
    }
  });

  document.getElementById('cancelBtn').addEventListener('click', (e)=>{
    e.preventDefault();
    modal.close();
  });

  const currentSec = document.getElementById('current');
  const nextSec = document.getElementById('next');
  document.querySelectorAll('input[name="week_view"]').forEach(r => {
    r.addEventListener('change', ()=>{
      const v = document.querySelector('input[name="week_view"]:checked').value;
      if(v==='current'){ currentSec.classList.add('focus'); nextSec.classList.remove('focus'); }
      else { nextSec.classList.add('focus'); currentSec.classList.remove('focus'); }
    });
  });
})();
