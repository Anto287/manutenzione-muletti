# Backend LiftCare

LiftCare è collegato al progetto Supabase `tkugxpgljwcnndjsmhjq`. Organizzazione e progetto usano il piano Free verificato; nessuna configurazione dell’app attiva piani a pagamento. GitHub Pages ospita il frontend; Supabase fornisce PostgreSQL, Auth, REST API, Storage e il worker email. Non serve un server Node acceso.

## Accesso

1. Crea l’account dall’interfaccia e conferma l’email.
2. Solo l’indirizzo admin configurato nella tabella privata `admin_emails` ottiene automaticamente il ruolo admin dopo conferma.
3. Gli altri account rimangono in attesa finché l’admin li approva da **Approva utenti**. Ogni account ha un archivio indipendente; non è una flotta condivisa.
4. Login, conferma email, token scaduti, sessioni revocate e approvazione sono controllati dal server. Le API dati rispondono 401 se la sessione non è attiva o l’account non è approvato. Le operazioni riservate agli admin rispondono 403 agli utenti ordinari.

Le autorizzazioni sono in tabelle private, non in `user_metadata`. Ogni richiesta dati applica un controllo preliminare e RLS. Le foto applicano RLS separatamente. Un utente revocato non può continuare a usare il token precedente; dopo logout la sessione viene verificata nella tabella Auth e non è più valida per i dati.

Il frontend contiene soltanto una chiave pubblica. Le credenziali di servizio e le password non sono pubblicate. La sessione del browser è in `sessionStorage`, si rinnova e viene rimossa con **Esci**. La sicurezza dipende anche dall’account dell’admin e del progetto: questi controlli non equivalgono a una garanzia di invulnerabilità.

## API

| Risorsa | Operazioni | Protezione |
| --- | --- | --- |
| `machines` | GET, POST, PATCH, DELETE | Sessione, approvazione, proprietario |
| `maintenance_plans` | GET, POST, PATCH, DELETE | Sessione, approvazione, proprietario |
| `service_records` | GET | Storico immutabile, proprietario |
| `record_service` | POST RPC | Registra storico e aggiorna mezzo/piani in una transazione |
| `import_archive` | POST RPC | Importazione transazionale in archivio vuoto |
| `access_status` | POST RPC | Stato del solo account autenticato, anche in attesa |
| `list_access_requests`, `set_user_approval` | POST RPC | Solo admin |
| `photo_usage`, `photo_inventory` | POST RPC | Solo utenti approvati; inventario limitato al proprietario |
| `email_status`, `configure_email` | POST RPC | Solo admin; nessuna lettura della chiave |
| Storage `liftcare-photos` | Upload, download privato, cancellazione | Sessione, approvazione, proprietario, piano gratuito |

I contatori non possono diminuire; i chilometri sono interi. L’unità resta bloccata in presenza di piani o storico. I riferimenti composti impediscono collegamenti a mezzi di altri utenti. Lo storico mantiene nomi e ricambi anche dopo eliminazione del piano.

## Foto e migrazione

Le immagini sono file privati, non Base64 nel database: `UUID_utente/ID_intervento/slot.jpg`. Fino a 6 foto per intervento, massimo 160.000 byte ciascuna, JPEG/PNG/WebP; compressione nel browser con lato massimo 1280 px. Il contatore mostra l’uso Storage del progetto; avviso all’80%, blocco preventivo a 1.000.000.000 byte. Gli inserimenti vengono serializzati dal server e i file ancora privi di metadata vengono conteggiati conservativamente a 160 KB. Nessun upgrade automatico viene richiesto dall’app.

L’inventario delle foto usa una sola RPC, senza scaricare immagini in panoramica. I download avvengono soltanto aprendo una galleria o esportando il backup. Il vecchio archivio locale non viene cancellato. **Importa archivio di questo browser** oppure **Importa backup** trasferiscono prima i dati testuali, poi le foto. Se un upload fallisce conserva il backup originale; un intervento già registrato non viene duplicato per riprovare le foto. Il backup online JSON comprende le foto; CSV contiene solo dati testuali. Non esiste coda offline.

## Notifiche email attive

Il worker `access-email` è distribuito su Supabase. Le richieste confermate entrano in una coda privata; un webhook avvia l’invio e un job orario riprova fino a 5 volte. Non vengono invocate API email finché non esiste una configurazione.

La chiave di un account **Resend Free** è già configurata sul progetto online; l’admin può sostituirla da **Notifiche email**. Il test di invio è stato consegnato all’admin. La chiave è cifrata in Supabase Vault; non viene restituita al browser, scritta nei backup o inserita nel repository. Il mittente di prova `onboarding@resend.dev` può inviare soltanto all’indirizzo con cui è stato creato l’account Resend: usa la stessa email admin. Per inviare a destinatari diversi serve un dominio verificato. Le notifiche qui descritte sono esclusivamente per l’admin; non includono le email di conferma Auth.

Il worker usa autenticazione personalizzata con un token casuale generato sul server e custodito in Vault: `verify_jwt=false` permette il webhook, ma token assenti o errati vengono respinti. La RPC che verifica il token e legge la chiave è eseguibile esclusivamente da `service_role`. Sono applicati limiti conservativi di tentativi sotto le soglie Free (80 al giorno, 2.500 al mese), con chiavi di idempotenza per limitare duplicazioni nei retry.

**Le email di conferma degli account sono gestite separatamente da Supabase Auth.** Il mittente predefinito Supabase può inviare soltanto agli indirizzi del team autorizzato. Per registrare utenti esterni serve configurare SMTP personalizzato; Resend richiede un dominio verificato per quei destinatari. Nessun dominio o piano viene acquistato automaticamente. Le impostazioni Auth e SMTP non sono modificabili attraverso le funzioni disponibili della connessione Supabase.

## Verifica e distribuzione

- `npm test`: logica dominio, adapter REST e collegamento cloud.
- `npm run build`: sito statico in `dist/`.
- `backend/check-live-access.sql`: verifica server su utenti di prova in transazione, con rollback integrale: bootstrap admin, blocco utenti in attesa, impossibilità di auto-approvazione, isolamento, transazioni e revoca.
- `backend/check-database.mjs`: verifica offline dello schema iniziale con PGlite.

Le migrazioni sono versionate in `backend/supabase/migrations`. La configurazione admin rimane privata nel database. Dopo modifiche di schema verificare anche gli advisor Supabase. RLS senza policy sulle tabelle private è intenzionale: i client non hanno accesso diretto.


### Conferma dell’account admin senza SMTP personalizzato

La migrazione `admin_registration_email` aggiunge un limite privato per gli invii e una RPC eseguibile solo da `service_role`. L’Edge Function `registration-email` è pubblica perché avvia la registrazione: verifica input, origine browser, destinatario nella lista admin e limite server di 5 tentativi/giorno con 60 secondi tra richieste. Non concede accesso ai dati. Genera il token con l’API admin `generate_link` di Supabase Auth e lo invia con Resend solo all’admin, mai nella risposta HTTP. Il client riceve `supported:false` per gli altri indirizzi e usa il flusso signup standard.

Il link contiene `token_hash` nel frammento dell’URL; `src/auth.js` rimuove subito il frammento e usa `/auth/v1/verify`. La sessione viene accettata solo dopo verifica. Email confermata e indirizzo nella lista privata restano necessari per il bootstrap admin. Il mittente di prova è utilizzabile nel progetto attuale perché il test al destinatario admin è stato consegnato. Le conferme a utenti esterni restano un percorso separato che richiede SMTP e dominio verificato.

Entrambi i worker sono pubblicati; la chiave `sending_access` è configurata in Vault e non è versionata. Non sono stati acquistati domini né attivati piani a pagamento.


## Scadenze e promemoria gratuiti con Gmail

`vehicle_deadlines` contiene revisione, bollo e assicurazione con data esplicita, note e consenso per scadenza. RLS verifica proprietario, approvazione e sessione attiva. I backup v2 precedenti rimangono compatibili; quelli nuovi includono scadenze e preferenza email.

Il cron `liftcare-deadline-reminders` controlla ogni 15 minuti: dalla prima esecuzione delle 9:00 Europe/Rome genera al massimo un riepilogo al giorno per account, alle soglie 30, 7, 1, 0 e -7 giorni. Se una scadenza viene inserita già dentro una finestra, il primo riepilogo usa la soglia corrente. Il rinnovo della data, la disattivazione e la revoca dell’account annullano gli avvisi in coda. Il destinatario è sempre letto da Supabase Auth, mai dal modulo della scadenza.

Per attivare l’invio senza dominio a pagamento: l’admin Gmail apre **Account e backup → Notifiche email**, attiva la verifica in due passaggi Google, genera una password per app chiamata LiftCare e la inserisce nel modulo. Usare esclusivamente la password per app; mai la password normale o segreti nella chat. Il valore viene cifrato in Vault e non compare nello stato, nei backup, nei log o nella repository. Il collegamento invia una prova all’account admin; ogni utente può richiedere la propria prova e disattivare i promemoria. Nessuna credenziale Gmail è inclusa nel progetto o impostata automaticamente.

Il worker `deadline-email` usa SMTP Gmail su TLS porta 465. La connessione al server è stata verificata; la prova di autenticazione e consegna richiede la configurazione Gmail. HTML e testo sono inclusi, senza tracker, allegati o pubblicità. SPF/DKIM per il mittente Gmail sono gestiti da Google; il recapito nella posta in arrivo non è garantibile. Eventuali rifiuti permanenti interrompono il retry; esiti SMTP incerti e crash non vengono reinviati automaticamente per evitare duplicati. Il riepilogo e le credenziali sono visibili solo al worker autenticato con token privato + service role. Un controllo SMTP autenticato separato non prende in carico i messaggi.

Lo stesso Gmail configurato abilita le conferme degli account esterni nel worker `registration-email`, senza necessità di un dominio personalizzato o di modificare SMTP Auth. L’admin resta tenuto ad approvare ogni nuovo utente. Senza Gmail rimane il percorso Resend di prova per l’admin, con il flusso Supabase standard per gli altri indirizzi.

Il budget server è condiviso: 50 tentativi/24 ore per Gmail, al massimo 20 conferme, al massimo 5 conferme/giorno/indirizzo con attesa di 60 secondi. Le credenziali non vengono esposte ai destinatari. I messaggi restano in coda se il budget è esaurito. Nessun servizio a pagamento viene attivato.

`backend/check-deadlines.sql` verifica in rollback isolamento, revoca, config Vault, riepiloghi, deduplicazione, rinnovo, opt-out, quote condivise e importazione dei backup. `npm test` include template e gestione dei fallimenti dei worker.
