# Backend LiftCare — gestione macchinari

Backend Supabase PostgreSQL + Auth + Storage. Non richiede un server Node acceso; la REST API viene generata da Supabase. Il sito GitHub Pages resta compatibile. **Questa aggiunta non attiva la sincronizzazione dell'interfaccia esistente**: `src/backend.js` è l'adattatore pronto per il collegamento; `src/app.js` continua a salvare localmente finché non viene integrato il login e il flusso cloud.

## Attivazione

1. Crea un progetto **Free** sul tuo account Supabase, scegliendo una regione europea. Non attivare piani a pagamento.
2. Esegui il file `supabase/migrations/202610060001_liftcare.sql` nel SQL Editor, una volta, su un progetto nuovo. In alternativa applicalo con la CLI Supabase. La migrazione è transazionale e non cancella dati esistenti.
3. In Authentication crea il tuo utente con email e password. Per un gestionale privato disabilita le registrazioni pubbliche. Ogni utente ha un archivio indipendente; la condivisione della flotta tra utenti diversi non è inclusa.
4. Recupera Project URL e **publishable key** (oppure la vecchia anon key). Non inserire mai service_role, secret key, password database o credenziali utente nella repository.
5. Collega l'adattatore all'interfaccia e configura login/logout, rinnovo sessione, indicazione del salvataggio cloud e gestione degli errori prima di utilizzare il backend come archivio principale.

## Dati e operazioni

| Risorsa REST | Operazioni | Contenuto |
| --- | --- | --- |
| `/rest/v1/machines` | GET, POST, PATCH, DELETE | Muletti, auto, trattori; targa, matricola, alimentazione, ore/km |
| `/rest/v1/maintenance_plans` | GET, POST, PATCH, DELETE | Intervalli, mesi, ricambi, ultimo lavoro |
| `/rest/v1/service_records` | GET | Storico con copia dei nomi e ricambi al momento del lavoro |
| `/rest/v1/rpc/record_service` | POST | Registra il lavoro e aggiorna mezzo e piani nella stessa transazione |
| `/storage/v1/.../liftcare-photos` | Upload, elenco, URL temporaneo, cancellazione | Foto private collegate a un intervento |

Tutte le richieste dati richiedono la sessione utente. RLS isola i proprietari; chiavi esterne composte impediscono collegamenti a mezzi di un altro account. Il contatore non diminuisce; i km sono interi; l'unità resta bloccata quando ci sono piani o storico. Un mezzo con piani o storico non può essere cancellato. Lo storico è immutabile via API: eliminare un piano non elimina i lavori eseguiti. La registrazione rifiuta date future, piani duplicati o estranei e lavori precedenti all'ultimo lavoro del piano. Le date sono valutate in Europe/Rome.

```js
import {LiftCareBackend} from '../src/backend.js';
const api = new LiftCareBackend({url:'https://PROJECT.supabase.co',publishableKey:'PUBLIC_KEY'});
await api.signIn(email,password);
const machine = await api.saveMachine({name:'TR-01',type:'tractor',model:'Trattore',unit:'h',reading:120});
const plan = await api.savePlan({machine_id:machine.id,name:'Filtro gasolio',interval:250,months:12,last_reading:120,last_date:'2026-10-06'});
const service = await api.recordService({machineId:machine.id,planIds:[plan.id],date:'2026-10-06',reading:125});
// Utilizzare la compressione già presente in src/photos.js prima dell'upload.
await api.uploadPhoto(service.id,1,compressedJpegBlob);
const temporaryUrl = await api.signedPhotoUrl(service.id,1);
```

## Foto, spazio e limiti

Le immagini non sono Base64 nel database: sono file privati, organizzati `UUID_utente/ID_intervento/slot.jpg`. Limite per file 160.000 byte, formati JPEG/PNG/WebP, slot da 1 a 6. La compressione esistente usa un lato massimo di 1280 px. Il nome del file identifica lo slot; il nome originale non è conservato dal backend. Un URL firmato dura cinque minuti. Un upload fallito non annulla il lavoro già registrato: può essere riprovato nello stesso slot. Non sono permessi overwrite.

Il piano Free attualmente include 500 MB di database e 1 GB di file **per progetto**, condivisi da tutti gli utenti. Non è una quota infinita. Non si attiva automaticamente un piano a pagamento. Indicatore di spazio, avviso all'80% e blocco preventivo richiedono un'integrazione ulteriore; non sono implementati da questo adattatore. La quota effettiva viene applicata dal servizio. Per i consumi complessivi utilizzare la dashboard Supabase. Eventuali altre policy Storage già presenti sul progetto vanno controllate: le policy permissive si combinano con OR.

## Migrazione e backup

L'archivio locale non viene toccato. Gli ID testuali delle tabelle accettano gli identificativi già esistenti. Per migrare servono mappatura `vehicles → machines`, `tasks → maintenance_plans`, importazione transazionale dello storico e caricamento separato delle foto; **l'importazione dei vecchi backup non è ancora implementata**. Non caricare backup privati nella repository pubblica. Il piano Free non include backup automatici e può andare in pausa dopo una settimana di inattività. Conservare esportazioni del database e copie dei file Storage: il solo dump SQL non include le foto.

## Verifica

`npm test` esegue anche i test dell'adattatore REST. `node backend/check-database.mjs` verifica la migrazione e i controlli usando PostgreSQL WASM (PGlite); richiede `@electric-sql/pglite` in un ambiente di test, senza dipendenze aggiunte al sito. Lo Storage mock nei test verifica le policy SQL, non sostituisce una prova di upload sul vero servizio Supabase. Dopo l'attivazione eseguire una prova con due utenti e una richiesta non autenticata, oltre a upload, firma e cancellazione delle foto.
