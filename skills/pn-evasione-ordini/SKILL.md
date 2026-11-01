---
name: pn-evasione-ordini
description: Procedura obbligatoria per EVADERE ordini ProgestNOW, fornitore o cliente, creando il documento che li evade (carico da ordine fornitore, DDT o fattura da ordine cliente) con i tool pn_document_evadable_rows e pn_document_session_evade_rows dentro una sessione pn_document_new_*. Attivala quando l'utente chiede di evadere un ordine, caricare la merce arrivata, registrare il DDT del fornitore allegato, fatturare o spedire righe di un ordine cliente, o chiudere a saldo righe d'ordine. Evita gli errori piu costosi gia accaduti - righe ricopiate a mano con row_add (ordine non evaso), doppia fatturazione di righe gia evase, quantita applicate alle righe sbagliate, codice ordine messo nel numero documento d'origine, save prematuro seguito da correzioni.
metadata:
  scope: core
  spec_ref: 191-mcp-progestnow-document-session-evade-rows
  auto_activate_on_tools:
    - pn_document_evadable_rows
    - pn_document_session_evade_rows
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Evasione ordini: carico da ordine fornitore, DDT/fattura da ordine cliente

Evadere un ordine significa creare un documento (carico, DDT, fattura) le cui righe sono **collegate alle righe dell'ordine**: al salvataggio ProgestNOW aggiorna da solo la quantita evasa dell'ordine e lascia aperto il residuo. Il collegamento esiste solo se le righe nascono da `pn_document_session_evade_rows`.

Regola zero: **le righe di un ordine non si ricopiano mai con `pn_document_new_row_add`.** Una riga aggiunta a mano non evade nulla: l'ordine resta aperto e la riga puo essere fatturata o caricata una seconda volta.

## 1. Flusso standard (sempre in quest'ordine)

1. **Individua l'ordine o gli ordini** coinvolti con i tool di ricerca documenti. Se l'utente allega il DDT del fornitore, il riferimento ordine e di solito scritto sul DDT ("Vs. ordine n. ... del ..."). Un DDT puo evadere piu ordini dello stesso fornitore.
2. **`pn_document_evadable_rows`** con `source_document_codes=[...]` (fino a 20 ordini insieme). E l'**unica fonte** dello stato di evasione: non usare `line_status`/`quantity_remaining` di letture o ricerche documenti per decidere cosa e evadibile. Di default risponde con `rows_table`: una riga di testo per riga d'ordine, colonne in `rows_table_columns` (`line_number | row_id | product_code | description | unit_of_measure | ordered_qty | evaded_qty | residual_qty | ... | unit_price`). Copia `row_id`, `line_number` e `description` **da li**: non indovinarli, non contarli e non ricopiarli a mano in uno script.
3. **Confronta con quanto richiesto** (righe e quantita del DDT del fornitore, o righe indicate dall'utente). Prepara la tabella riga ordine → quantita seguendo le regole di abbinamento del §2. Se una riga richiesta ha `residual_qty` = 0 o non compare (gia evasa o chiusa a saldo): **fermati e chiedi all'utente** prima di proseguire.
4. **`pn_document_new_start`** con la causale del documento da creare (es. carico `CAR`, DDT a cliente, fattura) e l'intestatario. Se non conosci il codice causale usa `pn_document_types`. Se l'intestatario manca, `pn_document_session_evade_rows` lo prende dall'ordine.
5. **`pn_document_session_evade_rows` in UNA sola chiamata per ordine**, con `selection_mode=rows` e tutte le righe del passo 3: `row_id` + `quantity` + **`expected_description`** (la descrizione della riga d'ordine copiata da `rows_table`), eventuale `force_closure`. Con `expected_description` il tool rifiuta (`row_description_mismatch`, nessuna riga aggiunta) se il `row_id` non e quello della descrizione: e la protezione contro gli sfasamenti di una riga. Usa `selection_mode=all_residual` solo se l'utente vuole evadere tutto il residuo cosi com'e. Se l'evasione nasce da un documento della controparte (DDT fornitore), passa anche `original_document_number` e `original_document_date` (vedi §4).
6. Altri ordini dello stesso fornitore/cliente: ripeti il passo 5 sulla **stessa** sessione (un DDT = un solo carico).
7. **Righe del DDT che non stanno in nessun ordine**: solo queste con `pn_document_new_row_add`, e segnalale all'utente.
8. **Rifiniture** (lotto, scadenza, prezzo diverso da quello d'ordine): `pn_document_new_row_update` usando i `draft_row_id` restituiti in `evasion.evaded_rows_table`.
9. **Verifica** `evasion.evaded_rows_table`: per ogni riga `description` e `quantity` devono essere quelle attese. Il riepilogo all'utente si costruisce **da questa risposta**, non dalla tua tabella di partenza.
10. **Anteprima**: per l'evasione bastano `evasion.evaded_rows_table` e `totals` della risposta di evasione. `pn_document_new_get` serve solo se hai aggiunto righe libere o modifiche: su documenti con molte righe la sua risposta viene troncata, quindi non usarla per verificare le righe evase. Riepilogo all'utente con i warning, **conferma esplicita**, poi `pn_document_new_save` con `confirm_save=yes`.

Dettagli sui parametri e esempi completi in `references/esempi.md`.

## 2. Identificare le righe senza sbagliare

| Identificatore | Dove vale | Da dove arriva |
|---|---|---|
| `row_id` dell'ordine | `pn_document_session_evade_rows.rows[].row_id` | `pn_document_evadable_rows` |
| `line_number` dell'ordine | `pn_document_session_evade_rows.rows[].line_number` | `pn_document_evadable_rows` |
| `draft_row_id` | `pn_document_new_row_update` / `pn_document_new_row_remove` | `evasion.evaded_rows_table` (ultima colonna `draft_row_id`) |
| `line_number` della sessione | `pn_document_new_row_update` | **evitalo** |

**Trappola numero uno**: i numeri di riga della sessione **non coincidono** con quelli dell'ordine. Il documento nuovo ha in testa una riga descrittiva ("N. Ordine 3 - 03/10/2026"), quindi la riga 14 della sessione e la riga 13 dell'ordine. Correggere quantita per `line_number` della sessione ha gia prodotto quantita sulle righe sbagliate: usa sempre `draft_row_id`.

`product_code` nella selezione e comodo, ma se l'articolo compare in piu righe evadibili dello stesso ordine il tool rifiuta con `ambiguous_product_code` e ti elenca i candidati: scegli il `row_id`. I DDT dei fornitori riportano spesso il **codice articolo del fornitore**: confrontalo con `alternative_product_codes` e con la descrizione.

### Abbinare le righe del DDT alle righe d'ordine

Per identificare gli articoli delle righe attiva `pn-identificazione-articoli` (se hai il tool `pn_articoli_risolvi_codici`; altrimenti segui l'ordine di affidabilita qui sotto). Passa la controparte (fornitore del DDT o cliente dell'ordine) e in `candidati_preferiti` i `product_code` delle righe d'ordine aperte di `rows_table` (acquisto) oppure gli articoli gia acquistati dal cliente (vendita). Un esito `univoco` vale come "stesso codice articolo" del punto 1. Un esito `probabile` vale come "stesso codice articolo" solo se il candidato e' tra i `candidati_preferiti` (`preferito: true`, articolo di una riga d'ordine aperta) e descrizione e unita di misura sono coerenti; altrimenti e' incerto. `ambiguo`, `non_trovato` e i `probabile` incerti sono abbinamenti incerti: non salvare. Il codice di fallback (`fallback`) **non** si usa nell'evasione: le righe non abbinate restano fuori e vanno segnalate; solo su richiesta esplicita dell'utente si aggiungono come righe di fallback, con i dati originali (passo 6 di `pn-identificazione-articoli`).

Ordine di affidabilita, dal piu sicuro:

1. stesso codice articolo (`product_code`) o codice fornitore in `alternative_product_codes`;
2. **descrizione del DDT** confrontata con la descrizione della riga d'ordine;
3. nient'altro. **Non dedurre l'articolo dal solo codice del fornitore** (es. "CLN-ARIA" = spray aria): e un'ipotesi, non un abbinamento.

Righe d'ordine con `product_code` = `*` sono righe descrittive senza articolo di magazzino: l'unico aggancio possibile e la descrizione. In quel caso ti servono le **descrizioni del DDT** riga per riga: se nel task hai solo codici e quantita, rileggi l'allegato o chiedile, non procedere a intuito.

**Se anche una sola riga e abbinata per ipotesi, non salvare.** Mostra all'utente (o restituisci all'agente che ti ha delegato) la tabella di abbinamento `riga DDT (codice, descrizione, quantita) -> riga ordine (line_number, descrizione, residuo)` e attendi conferma. Un abbinamento sbagliato salvato carica a magazzino l'articolo sbagliato e altera l'evaso dell'ordine.

Controllo di quadratura prima del save: somma quantita del DDT = somma quantita evase + quantita delle righe DDT non abbinate. Se non torna, c'e un abbinamento sbagliato o una riga persa.

## 3. Quantita, residui e chiusura a saldo

- **Default** della quantita = residuo ancora disponibile (residuo dell'ordine meno quanto gia messo nella sessione).
- **Quantita oltre il residuo**: ammessa. Il tool restituisce il warning `over_delivery`: riportalo all'utente nel riepilogo, non ignorarlo.
- **Consegna parziale** (arriva meno dell'ordinato): metti la quantita arrivata e **non** chiudere a saldo; il residuo resta aperto sull'ordine.
- **`force_closure=S`**: chiude a saldo la riga d'ordine anche se la quantita e inferiore (es. "il resto non arrivera"). Usalo solo se l'utente lo chiede o lo conferma.
- Stessa riga richiesta due volte nella stessa chiamata: le quantita vengono sommate in una sola riga.
- Al save il tool rilegge i residui: se un altro documento li ha consumati nel frattempo arriva il warning `evasion_residual_changed`.

## 4. Numero e data del documento della controparte

Quando l'evasione nasce da un documento del fornitore (tipicamente il DDT allegato), riporta sul documento creato **numero e data di quel documento**: parametri `original_document_number` e `original_document_date` (formato `YYYY-MM-DD`) di `pn_document_session_evade_rows` o di `pn_document_new_set_header`. Finiscono nei campi "numero/data documento d'origine" della testata.

- Non obbligatori, ma da valorizzare sempre quando li conosci.
- **Mai** mettere li il codice o il numero dell'ordine evaso: il collegamento all'ordine e gia riga per riga. Su fatture e fatture di acquisto un codice documento ProgestNOW in quel campo viene interpretato come documento d'origine dalla logica acconti.
- Non usare `reference` (riferimento libero) al posto di questi campi.
- Se arriva `original_document_already_registered`, quel DDT risulta gia caricato su un altro documento dello stesso fornitore: **fermati e chiedi** all'utente se si tratta di un doppio caricamento.

## 5. Causale del documento

- Fornitore: carico (`M`), oppure fattura di acquisto (`A`) che movimenta il magazzino.
- Cliente: DDT (`D`) o fattura (`F`) che movimenta il magazzino.
- Se la causale non aggiorna l'evaso degli ordini (fatture che non movimentano il magazzino) il tool rifiuta con `target_causale_does_not_evade`: proponi all'utente una causale che movimenta, non aggirare con `row_add`.
- Liste di prelievo, proforma, fatture di acconto e sessioni di modifica non sono supportate dall'evasione.

## 6. Risparmiare passaggi (e crediti)

- Una chiamata `pn_document_session_evade_rows` per ordine, con tutte le quantita: non evadere tutto per poi correggere riga per riga.
- Non salvare finche l'anteprima non torna con l'utente: correggere un documento gia salvato richiede una sessione di modifica intera.
- Lascia `response_detail` al default `compact`; `pn_document_new_get` solo una volta, per l'anteprima finale.
- Non serve il sandbox (`pn_code_exec`) per questo flusso: le righe e i residui arrivano gia strutturati da `pn_document_evadable_rows`. In particolare **non ricopiare le righe dell'ordine in uno script** per fare l'abbinamento: righe ricopiate a mano da una risposta lunga sono gia uscite sfasate di una riga.
- Se una risposta contiene `_pn_runtime_note` o e stata troncata, le righe mancanti non le conosci: richiama `pn_document_evadable_rows` con `line_numbers` o `product_codes` per le righe che ti servono, non ricostruirle.
- Dopo il save il codice del documento creato e in `saved_cidfattura`: non cercarlo con altre letture.

## 7. Se deleghi l'evasione a un altro agente

Chi legge il DDT allegato e delega l'evasione deve passare, per **ogni riga del DDT**: codice articolo del fornitore, **descrizione**, quantita, unita di misura; piu numero e data del DDT, fornitore e ordini citati. Mai solo `codice=quantita`: senza descrizione l'agente delegato non puo abbinare le righe d'ordine senza articolo.

Se hai il tool `pn_articoli_risolvi_codici`, identifica gli articoli delle righe con `pn-identificazione-articoli` prima di delegare (controparte + `candidati_preferiti` come al §2) e passa all'agente delegato solo gli abbinamenti `univoco` e i `probabile` con `preferito: true` e descrizione/UM coerenti (§2), con le eccezioni del punto 5 di `pn-identificazione-articoli`: un `univoco` con articolo obsoleto o confezione incoerente (`nqtaconf` diversa da quantita o unita della riga) va segnalato e confermato come le righe incerte. Le righe `ambiguo`/`non_trovato` e gli altri `probabile` restano da confermare; il fallback non si usa senza richiesta esplicita dell'utente.

L'agente delegato che non riesce ad abbinare con certezza tutte le righe **non salva**: restituisce la tabella di abbinamento proposta e le righe incerte, e chi ha delegato la porta all'utente.

## 8. Errori e rimedi

Vedi `references/errori.md`. I piu frequenti: `row_not_found` (identificativo non dell'ordine: rileggi `pn_document_evadable_rows`), `ambiguous_product_code` (scegli `row_id` tra i candidati), `target_causale_missing` (imposta prima la causale), `counterparty_mismatch` (ordine di un altro fornitore/cliente: serve un'altra sessione), `currency_mismatch` (imposta la valuta con `pn_document_new_set_header`). Gli errori di validazione sono atomici: **nessuna riga viene aggiunta**, correggi e richiama.

## 9. Checklist prima del save

- [ ] Ho preso `row_id`/`line_number` da `pn_document_evadable_rows`, non da deduzioni?
- [ ] Ogni elemento di `rows` aveva `expected_description`, e `evasion.evaded_rows_table` riporta le descrizioni attese?
- [ ] Ogni riga DDT e abbinata per codice o per descrizione, nessuna per ipotesi sul codice fornitore? Altrimenti tabella all'utente e niente save.
- [ ] La quadratura torna (quantita DDT = evase + non abbinate)?
- [ ] Nessuna riga d'ordine e stata aggiunta con `pn_document_new_row_add`?
- [ ] Le righe con residuo 0 richieste dall'utente le ho segnalate e confermate?
- [ ] Le quantita corrispondono al DDT/richiesta, controllando `evasion.evaded_rows_table`?
- [ ] Le consegne parziali sono senza `force_closure=S`, salvo richiesta esplicita?
- [ ] Numero e data del DDT fornitore sono in `original_document_number`/`original_document_date` (non il codice ordine)?
- [ ] Ho riportato all'utente `over_delivery`, `original_document_already_registered` e le righe libere aggiunte?
- [ ] L'utente ha confermato l'anteprima prima di `pn_document_new_save` con `confirm_save=yes`?
