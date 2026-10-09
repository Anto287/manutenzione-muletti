const bar=document.querySelector('#app-install');
const install=document.querySelector('#install-app');
const update=document.querySelector('#update-app');
const offline=document.querySelector('#offline-status');
const help=document.querySelector('#install-help');
const mode=window.matchMedia('(display-mode: standalone)');
let promptEvent=null,installed=false,waitingWorker=null,reloading=false;
const isStandalone=()=>installed||mode.matches||navigator.standalone===true;
function refresh(){
  install.hidden=isStandalone();update.hidden=!waitingWorker;offline.hidden=navigator.onLine;
  bar.hidden=install.hidden&&update.hidden&&offline.hidden;
}
window.addEventListener('beforeinstallprompt',event=>{event.preventDefault();promptEvent=event;refresh()});
window.addEventListener('appinstalled',()=>{installed=true;promptEvent=null;help.close();refresh()});
mode.addEventListener('change',refresh);
window.addEventListener('online',refresh);window.addEventListener('offline',refresh);
document.querySelector('#close-install-help').onclick=()=>help.close();
install.onclick=async()=>{
  if(promptEvent){
    const event=promptEvent;promptEvent=null;install.disabled=true;
    try{await event.prompt();await event.userChoice}catch{showHelp()}finally{install.disabled=false;refresh()}
  }else showHelp();
};
function showHelp(){
  const ios=/iPad|iPhone|iPod/.test(navigator.userAgent)||(navigator.platform==='MacIntel'&&navigator.maxTouchPoints>1);
  document.querySelector('#install-instructions').textContent=ios
    ?'Apri il sito in Safari, premi Condividi e scegli “Aggiungi alla schermata Home”, poi “Aggiungi”.'
    :/Android/.test(navigator.userAgent)
      ?'Apri il sito in Chrome o Samsung Internet. Dal menu ⋮ scegli “Installa app” oppure “Aggiungi alla schermata Home”. Se il comando non compare, ricarica il sito e riprova. Se stai usando il browser interno di un’altra app, apri il link nel browser del telefono.'
      :'In Chrome o Edge usa l’icona di installazione nella barra degli indirizzi oppure il menu “Installa LiftCare”. Su Mac, in Safari usa File → Aggiungi al Dock, se disponibile.';
  if(!help.open)help.showModal();
}
update.onclick=()=>{
  // Updates are explicit: never reload over a form the user is editing.
  if(document.querySelector('#editor')?.open||help.open){
    const toast=document.querySelector('#toast');toast.textContent='Salva o chiudi il modulo prima di aggiornare l’app.';toast.classList.add('show');
    setTimeout(()=>toast.classList.remove('show'),4000);return;
  }
  if(waitingWorker){reloading=true;update.disabled=true;waitingWorker.postMessage({type:'SKIP_WAITING'})}
};
refresh();
if('serviceWorker' in navigator&&window.isSecureContext){
  navigator.serviceWorker.addEventListener('controllerchange',()=>{if(reloading)window.location.reload()});
  navigator.serviceWorker.register(new URL('../sw.js',import.meta.url),{scope:new URL('../',import.meta.url).pathname,updateViaCache:'none'}).then(registration=>{
    const offerUpdate=()=>{if(registration.waiting&&navigator.serviceWorker.controller){waitingWorker=registration.waiting;refresh()}};
    offerUpdate();
    registration.addEventListener('updatefound',()=>{const worker=registration.installing;worker?.addEventListener('statechange',()=>{if(worker.state==='installed')offerUpdate()})});
    document.addEventListener('visibilitychange',()=>{if(document.visibilityState==='visible'&&navigator.onLine)registration.update().catch(()=>{})});
  }).catch(()=>{});
}
