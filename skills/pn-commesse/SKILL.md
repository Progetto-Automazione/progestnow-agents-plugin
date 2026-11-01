---
name: pn-commesse
description: Procedura obbligatoria per COMMESSE/PRATICHE ProgestNOW (testacommesse, righecommesse). Attivala PRIMA di leggere o aggregare commesse o rispondere su commessa, pratica, cantiere, preventivo/consuntivo, costi/ricavi, margine, scostamenti, centri di costo, documenti o prima nota collegati, budget. Impone di leggere il descrittore di testacommesse (spesso personalizzato). Evita preventivo sommato al consuntivo, ricavi doppi documento+prima nota, righe automatiche modificate a mano.
metadata:
  scope: core
  capability_ref: CAP-20260811-006
  requires_skill: pn-tabellabase-query
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".

# Commesse (pratiche): contenitore di documenti e di righe costo/ricavo

La **commessa** (in alcuni tenant "pratica", "cantiere", "job") e un **contenitore**: raccoglie i documenti che le vengono collegati e un insieme di **righe** (`righecommesse`) che misurano, nel tempo, quanto si e **previsto** e quanto si e **realmente** speso e incassato. Non e un documento e non ha un totale proprio: ogni numero di una commessa e un'aggregazione delle sue righe.

Regola zero: **prima di qualunque lettura chiedi il descrittore di `testacommesse`** (§1). La testata e spesso personalizzata per tenant (campi, stati, tipologie, sottocommesse, viste di riepilogo): senza descrittore stai ragionando su una commessa che non e quella del cliente.

Per la sintassi di `search`, `aggregate`, `output=url` segui la skill `pn-tabellabase-query` (attivala se non e gia attiva): questa skill dice **cosa** leggere e **come interpretarlo**, quella dice **come** scrivere i filtri.

## 1. Protocollo obbligatorio di apertura (sempre, una volta per job)

1. **`pn_tabellabase_descriptor("testacommesse")`**. Leggi `ai_instructions`, `single_fields` (campi fisici: cerca campi oltre allo standard, es. stato, responsabile, commessa padre/master, sottocommessa, tipologia, valori di budget, campi `zz_*` o con prefisso tenant), `columns`/`output_fields_allowed`, `dttable.query` se ti serve la `FROM` reale. Annota:
   - la **chiave** (standard `cidcommessa`, stringa) e il campo descrittivo (`cdesccommessa`);
   - come il tenant esprime lo **stato** (standard: `chiusa` = `S`/`N` e `ddatachiusura`; molti tenant aggiungono uno stato proprio);
   - se esiste una **gerarchia** (master/sottocommesse): in quel caso chiedi o verifica se i totali vanno calcolati sulla sola commessa o anche sulle figlie;
   - le tabelle **figlie** dichiarate nelle relazioni (sempre `righecommesse`; a volte `project_task`, SAL, rapportini, allegati).
2. **`pn_tabellabase_descriptor("righecommesse")`** e leggi `ai_instructions`. Verifica i nomi fisici (§3) e se il tenant ha colonne aggiuntive sulle righe (stato riga, reparto, responsabile, sottoconto `csott`, orari).
3. Se servono descrizioni dei centri di costo: `centridicosto` (chiave `cidcentrodicosto`, descrizione `cdesccentrodicosto`).
4. **`pn_tabellabase_catalog`** (indice) per scoprire se il tenant ha superfici dedicate alle commesse (es. `righecommesse_P`, `righecommesse_C`, `riepilogo_commessa`, viste `qrycommesse_*`). Se esiste una vista di riepilogo **leggi le sue `ai_instructions` prima di usarla**: alcune uniscono righe commessa **e** righe documento e non vanno sommate con `righecommesse` (§5).
5. Se il descrittore rivela campi o logiche che questa skill non descrive, **dichiaralo all'utente** e usa i nomi del descrittore; non forzare il modello standard.

Se `pn_tabellabase_descriptor` non e nel toolset o fallisce: fermati e dichiaralo. Non procedere "a memoria" con i campi standard.

## 2. Il modello in una pagina

```
testacommesse (1) ── cidcommessa ──< righecommesse (0..n)
      ^                                   │  cpreventivoconsuntivo  P | C
      │ commessa_id                       │  ccostoricavo           COSTO | RICAVO
testapiedefatture (documenti) ──cidfattura┘  cidcentrodicosto  -> centridicosto
arcmovc (prima nota) ──── nmovc ── nidmovimentocontabile
```

Ogni riga ha **due assi** indipendenti:

| | COSTO | RICAVO |
|---|---|---|
| **P = Preventivo** | budget di spesa | ricavo atteso / valore offerto |
| **C = Consuntivo** | costo sostenuto | ricavo realizzato (fatturato) |

e un **centro di costo/ricavo** (`cidcentrodicosto`) che dice *su cosa* (materiali, manodopera, appalti, trasporti...). Margine, scostamento e avanzamento sono incroci di questa matrice per centro di costo.

**I valori stanno in colonne diverse secondo P/C** (trappola numero uno):

| Riga | Quantita | Valore |
|---|---|---|
| `P` | `nquantitapreventivato` | `nvalorepreventivato` |
| `C` | `nquantitaconsuntivo` | `nvaloreconsuntivo` |

Le colonne dell'altro tipo sono 0. Non sommare mai `nvalorepreventivato + nvaloreconsuntivo` senza separare per `cpreventivoconsuntivo`.

Dettaglio campi, enum e origini in `references/modello-dati.md`.

## 3. Nomi fisici e decodifiche (standard, verifica sempre sul descrittore)

- `testacommesse`: chiave `cidcommessa`; `cdesccommessa`, `nidcliente` (-> `arccli.codice`), `ctipocommessa`, `ddataapertura`, `ddatachiusura`, `ddataconsegna`, `criferimento`, `idvaluta`, `chiusa` (`S`/`N`), `iddocumento_origine`, `mnote`.
- `righecommesse`: chiave `idcomm`; `cidcommessa`, `cpreventivoconsuntivo` (`P` Preventivo, `C` Consuntivo), `ccostoricavo` (`COSTO`, `RICAVO`; puo essere vuoto su righe sporche), `ddatamovimento`, `cidcentrodicosto`, `cidarticolo` (`*` = riga descrittiva/totale senza articolo), `cidmanodopera`, `cdescrizione`, `nidfornitore` (-> `arcfor.codice`), `nnumeroriferimento` (numero documento/fattura), **`cidfattura`** (documento di origine), **`nidmovimentocontabile`** (movimento di prima nota di origine), `lflagordine` (`1` = riga nata da ordine fornitore) + `nnumeroordine`, `csott` (sottoconto, solo da prima nota analitica).
- Documenti: il collegamento e **`testapiedefatture.commessa_id`** (non `cidcommessa`). Il descrittore documenti lo espone di solito come colonna non visibile e non ricercabile.
- Nel descrittore standard di `righecommesse` la query fa join con `testacommesse` con alias `tc`: filtra con **`righecommesse.cidcommessa`** (qualificato), non con `cidcommessa` nudo.

## 4. Da dove nascono le righe (provenienza)

Prima di interpretare o toccare una riga, classifica la provenienza:

| Provenienza | Come la riconosci | Chi la scrive | Si modifica a mano? |
|---|---|---|---|
| **Documento** collegato | `cidfattura` valorizzato | salvataggio del documento con causale di magazzino che aggiorna la commessa (`causalimagazzino.aggiornacommessa`: `C` costo cons., `R` ricavo cons., `CP` costo prev., `RP` ricavo prev., `0` niente) | **No**: a ogni salvataggio del documento le sue righe vengono cancellate e ricreate |
| **Prima nota** (gestione extra-contabile / analitica) | `nidmovimentocontabile` valorizzato (`= arcmovc.nmovc`) | registrazione contabile con ripartizione su commessa/centro di costo (modulo `coge_industriale`) | **No**: rigenerate a ogni salvataggio del movimento |
| **Manuale / import** | `cidfattura` vuoto e `nidmovimentocontabile` vuoto/0 | utente (UI, import Excel) | Si, con conferma |

Conseguenze:

- Le righe da documento seguono la **causale**, non il tipo di documento: un ordine fornitore puo generare consuntivo di costo, un'offerta puo generare preventivo di ricavo. Leggi `aggiornacommessa` della causale se devi spiegare perche un documento ha (o non ha) prodotto righe.
- Un documento con `commessa_id` valorizzato ma causale con `aggiornacommessa = 0` e **collegato** alla commessa ma **non produce righe**: compare tra i documenti della commessa, non nei suoi totali.
- I ricavi da documento sono di norma **una riga per documento** (`cidarticolo = *`, descrizione "Documento ... n. ...", valore = imponibile x cambio); i costi una riga per riga documento con prezzo != 0. Il centro di costo viene da causale, fornitore, riga o articolo secondo la configurazione: non dedurlo, leggilo dalla riga.
- Righe con segno negativo: resi, note di credito, storni di ordine. Sono valori corretti, non errori.

## 5. Calcolare i numeri di una commessa (ricetta standard)

Mai leggere righe per sommarle: usa `pn_tabellabase_aggregate` su `righecommesse` con **misure condizionali**, una chiamata per tutte le combinazioni:

```json
{
  "table_name": "righecommesse",
  "search": [{"field": "righecommesse.cidcommessa", "op": "=", "type": "string", "value": "2026-0012"}],
  "dimensions": ["righecommesse.cidcentrodicosto"],
  "measures": [
    {"name": "costo_prev", "operation": "sum", "field": "nvalorepreventivato", "round": 2,
     "filter": [{"field": "righecommesse.cpreventivoconsuntivo", "op": "=", "type": "string", "value": "P"},
                {"field": "righecommesse.ccostoricavo", "op": "=", "type": "string", "value": "COSTO"}]},
    {"name": "costo_cons", "operation": "sum", "field": "nvaloreconsuntivo", "round": 2,
     "filter": [{"field": "righecommesse.cpreventivoconsuntivo", "op": "=", "type": "string", "value": "C"},
                {"field": "righecommesse.ccostoricavo", "op": "=", "type": "string", "value": "COSTO"}]},
    {"name": "ricavo_prev", "operation": "sum", "field": "nvalorepreventivato", "round": 2,
     "filter": [{"field": "righecommesse.cpreventivoconsuntivo", "op": "=", "type": "string", "value": "P"},
                {"field": "righecommesse.ccostoricavo", "op": "=", "type": "string", "value": "RICAVO"}]},
    {"name": "ricavo_cons", "operation": "sum", "field": "nvaloreconsuntivo", "round": 2,
     "filter": [{"field": "righecommesse.cpreventivoconsuntivo", "op": "=", "type": "string", "value": "C"},
                {"field": "righecommesse.ccostoricavo", "op": "=", "type": "string", "value": "RICAVO"}]},
    {"name": "righe", "operation": "count"}
  ]
}
```

Senza `dimensions` hai il totale commessa; con `cidcentrodicosto` il dettaglio per centro; con `date_buckets` su `ddatamovimento` l'andamento nel tempo; con `cidcommessa` come dimensione (e filtro su cliente/periodo/stato) il confronto tra commesse. Poi calcola tu, dichiarando le formule:

- **margine preventivo** = `ricavo_prev - costo_prev`; **margine consuntivo** = `ricavo_cons - costo_cons`;
- **scostamento costi** = `costo_cons - costo_prev` (positivo = sforamento), per centro di costo;
- **avanzamento costi** = `costo_cons / costo_prev` (solo se `costo_prev > 0`).

Prima di dare i numeri controlla:

- **Righe senza tipo**: aggiungi una misura `count` con filtro `ccostoricavo is_empty`; se > 0 segnalale (non entrano in nessun totale).
- **Doppio conteggio dei ricavi**: se la stessa fattura ha prodotto sia una riga da documento (`cidfattura`) sia una riga da prima nota (`nidmovimentocontabile`) con lo stesso `nnumeroriferimento`, il ricavo e contato due volte. Verifica con un'aggregazione per `nnumeroriferimento` con `having count > 1` sulle righe `C`/`RICAVO` e, se trovi coppie, mostrale all'utente invece di "correggere" il totale.
- **Viste di riepilogo del tenant** (`riepilogo_commessa`, `qrycommesse_righe`, ...): usale se il tenant le prevede, ma non sommarle con `righecommesse`. Alcune (es. `qrycommesse_righe`) uniscono righe commessa, righe documento e rapportini con un campo `record_source` e un `valore_smart` gia con segno (costi negativi): leggi la definizione dal descrittore prima.
- Se il tenant ha sottocommesse, dichiara se il totale include o no le figlie.

Altre ricette (documenti collegati, righe di un documento, ripartizione da prima nota, commesse aperte, confronto tra commesse) in `references/ricette.md`.

## 6. Documenti e prima nota collegati

- **Documenti della commessa**: `pn_documents_search` non filtra per commessa. Usa `pn_tabellabase_list` sul descrittore documenti del tipo richiesto (es. `testapiedefatture_F`, `_T`, `_O`, `_D`, `_R`) con filtro sul campo fisico della commessa (standard `tpf.commessa_id` o `testapiedefatture.commessa_id`: verifica l'alias della `FROM` nel descrittore), oppure deriva i `cidfattura` distinti dalle righe commessa (aggregate per `cidfattura`) e poi `pn_document_read`. Le due strade danno risultati diversi per costruzione (§4): la prima elenca i documenti *collegati*, la seconda quelli che *hanno prodotto righe*.
- **Movimenti di prima nota della commessa**: aggregate/list su `righecommesse` con `nidmovimentocontabile is_not_empty` (e `<> 0`); per il dettaglio contabile `pn_coge_partitario_search` o la TabellaBase di prima nota sul `nmovc`.

## 7. Scritture

- **Testata** (nuova commessa, chiusura, modifica): solo con i tool TabellaBase di scrittura se presenti nel toolset (`pn_tabellabase_new` / `pn_tabellabase_update` su `testacommesse`), rispettando i campi obbligatori e la generazione del codice del tenant (il codice puo essere generato dal sistema: non inventarlo, lascialo vuoto se il descrittore lo prevede). Chiudere una commessa = il campo/stato indicato dal descrittore (standard `chiusa=S` + `ddatachiusura`): chiedi conferma.
- **Righe manuali** (tipicamente il **preventivo**: budget per centro di costo): `pn_tabellabase_new` su `righecommesse` con `cidcommessa`, `cpreventivoconsuntivo`, `ccostoricavo`, `cidcentrodicosto`, `ddatamovimento`, `cdescrizione` e **le colonne valore coerenti con P/C** (§2). Mostra all'utente la tabella delle righe che inserirai e attendi conferma; per molte righe usa il bulk insert se disponibile.
- **Mai** creare, modificare o cancellare righe con `cidfattura` o `nidmovimentocontabile` valorizzati: si correggono modificando il documento o il movimento di origine (verranno rigenerate). Mai inserire a mano un consuntivo che "dovrebbe" venire da un documento: duplicheresti il valore al prossimo salvataggio del documento.
- **Collegare un documento a una commessa**: i tool di sessione documento (`pn_document_new_set_header` / `pn_document_edit_set_header`) non espongono la commessa. Se l'utente lo chiede, dichiara il `TOOLING_GAP` e indica la UI del documento; non aggirarlo scrivendo `righecommesse` a mano.
- Le write si fanno solo se il tool e nel toolset del job: la skill non concede permessi.

## 8. Confini (non confondere)

- **`commesse_produzione`** (MRP, ordini di produzione con lavorazioni) e un'altra entita: se l'utente parla di produzione, lavorazioni, fasi, gantt di reparto, non usare questa skill.
- Verticali (Trade, spedizionieri, ...) estendono `testacommesse` con superfici e tool propri (`pn_trade_commessa_*`, bacheche, SAL): se il descrittore o il catalogo li mostrano, segui quelli per le operazioni di processo; questa skill resta valida per la lettura delle righe costo/ricavo.
- Semantica completa e diagnostica: Knowledge MCP `CAP-20260811-006` (nodi `RULE-CMS-*`, `DATA-CMS-*`, `DIAG-CMS-*`, `QRY-CMS-*`) se disponibile.

## 9. Checklist prima di rispondere

- [ ] Ho letto il descrittore di `testacommesse` (e `ai_instructions`) in questo job e ho tenuto conto dei campi personalizzati?
- [ ] Ho filtrato le righe con `righecommesse.cidcommessa` (qualificato) e verificato che non tornino 0 righe per nome campo sbagliato?
- [ ] Ho separato P/C e COSTO/RICAVO usando la colonna valore giusta per ciascun tipo?
- [ ] Ho segnalato righe senza `ccostoricavo` e possibili doppi conteggi documento + prima nota?
- [ ] Ho dichiarato le formule di margine/scostamento e se il totale include le sottocommesse?
- [ ] Per i documenti collegati ho usato `commessa_id` e distinto "collegati" da "che hanno prodotto righe"?
- [ ] Nessuna scrittura su righe con `cidfattura`/`nidmovimentocontabile`; ogni scrittura confermata dall'utente?
