(function(){
  const cur = document.getElementById('wb_current');
  const nxt = document.getElementById('wb_next');
  document.getElementById('focusCurrent').addEventListener('click', ()=>{
    cur.classList.add('focus'); nxt.classList.remove('focus');
  });
  document.getElementById('focusNext').addEventListener('click', ()=>{
    nxt.classList.add('focus'); cur.classList.remove('focus');
  });
})();
