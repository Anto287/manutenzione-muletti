# LiftCare — Manutenzione muletti, auto e trattori

Gestionale web in italiano, utilizzabile da desktop e smartphone. Non richiede servizi a pagamento o dipendenze npm.

## Funzioni
- Anagrafica mezzi: categoria (muletto, auto, trattore), codice flotta, marca/modello, targa, matricola/telaio, alimentazione e contatore in ore o chilometri. Le auto propongono i chilometri; muletti e trattori propongono le ore.
- Aggiornamento progressivo del contatore ore o chilometri; filtro per categoria nella flotta e nello scadenziario.
- Piani personalizzati: tagliandi, olio, filtri aria, aria condizionata/abitacolo, gasolio, olio, carburante e idraulici, ingrassaggio, batterie, catene e forche; codice ricambio per piano.
- Scadenze per ore/chilometri e/o mesi: conta la prima soglia raggiunta. Preavviso entro 30 giorni o entro il minore tra il 10% dell’intervallo e 50 ore / 1.000 km, secondo il contatore.
- Registrazione di più lavori nello stesso intervento, con data, contatore, tecnico, costo totale e note.
- Foto allegate a note e ricambi: fino a 6 per intervento, da galleria o fotocamera; anteprima e rimozione prima del salvataggio, visualizzazione e download nello storico. Compressione automatica (lato massimo 1280 px, fino a 160 KB per foto). Foto comprese nel backup JSON; il CSV contiene solo i dati testuali.
- Storico permanente degli interventi, anche se il piano viene eliminato.
- Backup/ripristino JSON validato e storico esportabile in CSV per Excel.

## Avvio
Richiede Node.js 22 o superiore.

```sh
npm start
```
Apri http://localhost:3000. `npm test` verifica la logica delle scadenze, dei backup e della migrazione dei dati della versione precedente. `npm run build` genera `dist/` per qualunque hosting statico.

## Primo utilizzo
Registrati, conferma l’email e accedi. Gli utenti ordinari devono essere approvati dall’admin; il precedente archivio può essere migrato con **Importa archivio di questo browser**.

1. Apri **Mezzi** e aggiungi un muletto, un’auto o un trattore con il contatore attuale.
2. Apri **Piani manutenzione** e imposta gli intervalli prescritti dal manuale del mezzo. Inserisci data e valore del contatore dell’ultimo intervento; per un mezzo nuovo usa i valori iniziali.
3. Aggiorna periodicamente il contatore ore/km.
4. Registra i lavori eseguiti: le scadenze dei piani selezionati si ricalcolano dalla nuova data e dal nuovo valore del contatore.
5. Esporta regolarmente un backup JSON.

Per le auto sono suggeriti anche filtro abitacolo, freni e distribuzione; per i trattori olio trasmissione e controllo PTO.

Nessun intervallo tecnico è preimpostato: usare le indicazioni del costruttore e dell’officina. I suggerimenti del campo intervento sono nomi, non piani universali.

## Compatibilità e aggiornamento
Gli archivi e i backup della versione 1 vengono migrati automaticamente alla versione 2: ogni vecchio mezzo resta un muletto con contatore ore, e piani, ricambi, costi e storico vengono conservati. La chiave di archivio del browser rimane `liftcare-v1`, per ritrovare i dati sullo stesso indirizzo. La migrazione avviene su una copia al momento dell’importazione nel cloud.

Ogni mezzo usa un solo contatore: ore oppure km. Non sono convertiti automaticamente. L’unità può essere scelta alla creazione e modificata solo finché il mezzo non ha piani né storico; dopo, resta fissa per non reinterpretare i valori già registrati.

## Dati e limiti
Il sito usa il backend Supabase online. Per iniziare crea un account con la tua email e conferma la registrazione, poi accedi. Un account resta bloccato finché l’admin non lo approva. L’admin è assegnato solo all’indirizzo verificato configurato privatamente nel database; il primo visitatore non diventa admin. Dal pulsante **Approva utenti** l’admin può approvare e revocare. Le API dati richiedono una sessione ancora attiva e approvazione attuale; in assenza di queste rispondono 401. Il logout invalida anche l’accesso dati del token già emesso. Le foto sono protette anche dalle policy Storage. Le autorizzazioni si leggono dal database, non da metadati modificabili dagli utenti. Ogni account conserva un archivio separato.

Indicatore dello spazio foto del progetto, avviso all’80%, blocco preventivo al limite di 1 GB e controllo server sui caricamenti. La quota include tutti gli utenti; nessun upgrade o pagamento è attivato dall’app.

Mezzi, piani e storico sono salvati su PostgreSQL; le foto sono file privati in Storage, compressi a massimo 160 KB e 6 per intervento. Il frontend invia soltanto una chiave pubblica: nessuna chiave service_role, password o credenziale admin è pubblicata. I token restano in sessionStorage della scheda, vengono rinnovati prima della scadenza e rimossi con Esci. I dati si aggiornano all’accesso, dopo un salvataggio, con **Aggiorna dal cloud** e ogni minuto quando non è aperto un modulo. Il salvataggio richiede connessione; non esiste una coda offline.

Il precedente archivio localStorage non viene cancellato né caricato automaticamente. Accedi e usa **Importa archivio di questo browser** oppure un backup JSON: il cloud deve essere vuoto. I dati vengono importati in una transazione; le foto vengono caricate separatamente. Se un upload fallisce conserva il backup originale. L’esportazione online comprende le foto; richiede rete. Le notifiche email all’admin usano una coda privata, un worker Supabase e Resend. Il worker è attivo, ma **l’invio resta disattivato finché non viene configurata una chiave Resend**. L’admin può inserirla da **Notifiche email**: viene cifrata in Supabase Vault, mai esportata nel backup o salvata nel browser. Invio automatico quando la richiesta viene registrata, con riprova ogni ora e massimo 5 tentativi. La chiave non viene restituita al frontend. Per notificare soltanto l’admin con il mittente di prova, l’account Resend deve usare la stessa email dell’admin; per inviare a destinatari diversi serve un dominio verificato. Anche la consegna delle email di conferma dipende dalla configurazione Auth; il mittente Supabase predefinito ha restrizioni per gli indirizzi destinatari. Non si attivano servizi a pagamento.


Il progetto contiene una configurazione GitHub Actions pronta per GitHub Pages. Dopo il caricamento, in **Settings → Pages → Build and deployment → Source** seleziona **GitHub Actions**, quindi esegui il workflow `GitHub Pages` se il primo tentativo precedeva l’attivazione. Il frontend è pubblico, ma dati e foto richiedono login e approvazione dell’admin.

## Struttura
- `src/domain.js`: calcolo scadenze, registrazione interventi e validazione backup.
- `src/app.js`: interfaccia, gestione archivio e import/export.
- `src/style.css`: layout responsive.
- `test/domain.test.js`: verifiche della logica di manutenzione.

Licenza MIT.
