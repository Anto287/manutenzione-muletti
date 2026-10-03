# LiftCare — Manutenzione muletti

Gestionale web in italiano, utilizzabile da desktop e smartphone. Non richiede servizi a pagamento o dipendenze npm.

## Funzioni
- Anagrafica muletti: codice flotta, marca/modello, matricola, alimentazione e contatore ore.
- Aggiornamento progressivo delle ore di lavoro.
- Piani personalizzati: tagliandi, olio, filtri aria/olio/carburante/idraulici, ingrassaggio, batterie, catene e forche; codice ricambio per piano.
- Scadenze per ore e/o mesi: conta la prima soglia raggiunta. Preavviso entro 30 giorni o entro il minore tra 50 ore e il 10% dell’intervallo.
- Registrazione di più lavori nello stesso intervento, con data, ore, tecnico, costo totale e note.
- Storico permanente degli interventi, anche se il piano viene eliminato.
- Backup/ripristino JSON validato e storico esportabile in CSV per Excel.

## Avvio
Richiede Node.js 22 o superiore.

```sh
npm start
```
Apri http://localhost:3000. `npm test` verifica la logica delle scadenze e dei backup. `npm run build` genera `dist/` per qualunque hosting statico.

## Primo utilizzo
1. Apri **Muletti** e aggiungi un mezzo con le ore attuali.
2. Apri **Piani manutenzione** e imposta gli intervalli prescritti dal manuale del mezzo. Inserisci data e ore dell’ultimo intervento; per un mezzo nuovo usa i valori iniziali.
3. Aggiorna periodicamente il contatore ore.
4. Registra i lavori eseguiti: le scadenze dei piani selezionati si ricalcolano dalla nuova data e dalle nuove ore.
5. Esporta regolarmente un backup JSON.

Nessun intervallo tecnico è preimpostato: usare le indicazioni del costruttore e dell’officina. I suggerimenti del campo intervento sono nomi, non piani universali.

## Dati e limiti
I dati sono conservati in `localStorage` sul browser e sul dispositivo in uso, separatamente per indirizzo web. Non vengono inviati a GitHub. Non esiste sincronizzazione tra dispositivi, login, backend o invio automatico di notifiche. La cancellazione dei dati del browser cancella l’archivio: conservarne copie JSON. Le scadenze vengono aggiornate quando si apre il gestionale e quando si modifica il contatore. Le schede aperte sullo stesso browser ricevono gli aggiornamenti dell’archivio; in caso di salvataggi simultanei prevale l’ultimo.

Il progetto contiene una configurazione GitHub Actions pronta per GitHub Pages. Dopo il caricamento, in **Settings → Pages → Build and deployment → Source** seleziona **GitHub Actions**, quindi esegui il workflow `GitHub Pages` se il primo tentativo precedeva l’attivazione. I dati rimangono locali anche se l’interfaccia è pubblicata online.

## Struttura
- `src/domain.js`: calcolo scadenze, registrazione interventi e validazione backup.
- `src/app.js`: interfaccia, gestione archivio e import/export.
- `src/style.css`: layout responsive.
- `test/domain.test.js`: verifiche della logica di manutenzione.

Licenza MIT.
