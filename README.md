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
1. Apri **Mezzi** e aggiungi un muletto, un’auto o un trattore con il contatore attuale.
2. Apri **Piani manutenzione** e imposta gli intervalli prescritti dal manuale del mezzo. Inserisci data e valore del contatore dell’ultimo intervento; per un mezzo nuovo usa i valori iniziali.
3. Aggiorna periodicamente il contatore ore/km.
4. Registra i lavori eseguiti: le scadenze dei piani selezionati si ricalcolano dalla nuova data e dal nuovo valore del contatore.
5. Esporta regolarmente un backup JSON.

Per le auto sono suggeriti anche filtro abitacolo, freni e distribuzione; per i trattori olio trasmissione e controllo PTO.

Nessun intervallo tecnico è preimpostato: usare le indicazioni del costruttore e dell’officina. I suggerimenti del campo intervento sono nomi, non piani universali.

## Compatibilità e aggiornamento
Gli archivi e i backup della versione 1 vengono migrati automaticamente alla versione 2: ogni vecchio mezzo resta un muletto con contatore ore, e piani, ricambi, costi e storico vengono conservati. La chiave di archivio del browser rimane `liftcare-v1`, per ritrovare i dati sullo stesso indirizzo. La migrazione avviene su una copia e viene salvata alla prima modifica.

Ogni mezzo usa un solo contatore: ore oppure km. Non sono convertiti automaticamente. L’unità può essere scelta alla creazione e modificata solo finché il mezzo non ha piani né storico; dopo, resta fissa per non reinterpretare i valori già registrati.

## Dati e limiti
I dati sono conservati in `localStorage` sul browser e sul dispositivo in uso, separatamente per indirizzo web. Non vengono inviati a GitHub. Anche le foto restano locali: lo spazio del browser è limitato e, se esaurito, il salvataggio viene rifiutato senza cancellare i dati precedenti. Esporta regolarmente il backup JSON con le foto. Sono supportate le immagini decodificabili dal browser (JPEG, PNG, WebP ecc.); i formati non supportati, per esempio HEIC su alcuni dispositivi, richiedono conversione. Non esiste sincronizzazione tra dispositivi, login, backend o invio automatico di notifiche. La cancellazione dei dati del browser cancella l’archivio: conservarne copie JSON. Le scadenze vengono aggiornate quando si apre il gestionale e quando si modifica il contatore. Le schede aperte sullo stesso browser ricevono gli aggiornamenti dell’archivio; in caso di salvataggi simultanei prevale l’ultimo.

Il progetto contiene una configurazione GitHub Actions pronta per GitHub Pages. Dopo il caricamento, in **Settings → Pages → Build and deployment → Source** seleziona **GitHub Actions**, quindi esegui il workflow `GitHub Pages` se il primo tentativo precedeva l’attivazione. I dati rimangono locali anche se l’interfaccia è pubblicata online.

## Struttura
- `src/domain.js`: calcolo scadenze, registrazione interventi e validazione backup.
- `src/app.js`: interfaccia, gestione archivio e import/export.
- `src/style.css`: layout responsive.
- `test/domain.test.js`: verifiche della logica di manutenzione.

Licenza MIT.
