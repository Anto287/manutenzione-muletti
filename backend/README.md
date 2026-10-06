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

## Notifiche email: predisposte, chiave mancante

Il worker `access-email` è distribuito su Supabase. Le richieste confermate entrano in una coda privata; un webhook avvia l’invio e un job orario riprova fino a 5 volte. Non vengono invocate API email finché non esiste una configurazione.

L’admin configura la chiave di un account **Resend Free** da **Notifiche email**. La chiave è cifrata in Supabase Vault; non viene restituita al browser, scritta nei backup o inserita nel repository. Il mittente di prova `onboarding@resend.dev` può inviare soltanto all’indirizzo con cui è stato creato l’account Resend: usa la stessa email admin. Per inviare a destinatari diversi serve un dominio verificato. Le notifiche qui descritte sono esclusivamente per l’admin; non includono le email di conferma Auth.

Il worker usa autenticazione personalizzata con un token casuale generato sul server e custodito in Vault: `verify_jwt=false` permette il webhook, ma token assenti o errati vengono respinti. La RPC che verifica il token e legge la chiave è eseguibile esclusivamente da `service_role`. Sono applicati limiti conservativi di tentativi sotto le soglie Free (80 al giorno, 2.500 al mese), con chiavi di idempotenza per limitare duplicazioni nei retry.

**Le email di conferma degli account sono gestite separatamente da Supabase Auth.** Il mittente predefinito Supabase può inviare soltanto agli indirizzi del team autorizzato. Per registrare utenti esterni serve configurare SMTP personalizzato; Resend richiede un dominio verificato per quei destinatari. Nessun dominio o piano viene acquistato automaticamente. Le impostazioni Auth e SMTP non sono modificabili attraverso le funzioni disponibili della connessione Supabase.

## Verifica e distribuzione

- `npm test`: logica dominio, adapter REST e collegamento cloud.
- `npm run build`: sito statico in `dist/`.
- `backend/check-live-access.sql`: verifica server su utenti di prova in transazione, con rollback integrale: bootstrap admin, blocco utenti in attesa, impossibilità di auto-approvazione, isolamento, transazioni e revoca.
- `backend/check-database.mjs`: verifica offline dello schema iniziale con PGlite.

Le migrazioni sono versionate in `backend/supabase/migrations`. La configurazione admin rimane privata nel database. Dopo modifiche di schema verificare anche gli advisor Supabase. RLS senza policy sulle tabelle private è intenzionale: i client non hanno accesso diretto.
