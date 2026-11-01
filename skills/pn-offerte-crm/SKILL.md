---
name: pn-offerte-crm
description: >-
  Procedura obbligatoria per OFFERTE e PIPELINE COMMERCIALE (offerte a clienti: tipologia R con
  causale cliente, kanban opportunità). Attivala PRIMA di rispondere su offerte aperte, pipeline,
  preventivi, trattative, opportunità, funnel, tasso di conversione, offerte vinte o perse, offerte
  per agente, offerte scadute, previsione di chiusura, o prima di cambiare stato o fase di un'offerta.
  Evita pipeline gonfiata da offerte ferme o revisionate, tassi di vincita falsi, fasi orfane, agenti
  mancanti. Un'offerta non è fatturato.
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`, `pn_dataset_calculate`, `pn_document_offer_crm_options`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Offerte e pipeline commerciale

Un'**offerta** è un documento con `causalimagazzino.tipocausale = 'R'` **e** `causalimagazzino.flagidcliente_idfornitore = 'C'`. Testata in `testapiedefatture`, TabellaBase `testapiedefatture_R`.

La tipologia R comprende anche le **richieste di offerta a fornitore** (flag `F`; su tenant A la causale `RICHO`, 128 documenti dal 2025). La TabellaBase filtra solo `tipocausale='R'`, quindi:

1. leggi le causali R del tenant con il loro flag (ricetta R0: `pn_tabellabase_list` su `causalimagazzino`);
2. metti **in ogni `search`** il filtro `{"field": "tpf.idcausale", "op": "in", "type": "string", "value": [<causali R con flag C>]}`.

Non filtrare su `cm.flagidcliente_idfornitore`: non è nel catalogo campi e, dove il catalogo è attivo (progest, bene), la chiamata viene rifiutata con `FIELD_UNKNOWN`. Come dimensione di solito funziona.

**Strada secondaria.** Se un filtro o una dimensione su un campo della causale (`cm.*`) risponde `FIELD_UNKNOWN` / `FIELD_NOT_FILTERABLE`:
1. leggi le causali su `causalimagazzino` (R0; se anche quel filtro fallisce, leggila tutta: sono poche righe);
2. rilancia filtrando `tpf.idcausale` con `"op": "in", "type": "string"` e l'elenco dei codici;
3. al posto della dimensione usa `tpf.idcausale`, e riconduci ogni codice alla sua tipologia e al suo flag con l'elenco.

Mai `collection` / `collection_or`: confrontano con `LIKE` in stile CSV, e `collection` mette i valori in AND.

- Sintassi di `search`, `aggregate`, `output=url`: skill `pn-tabellabase-query` (attivala se non è attiva).
- **Un'offerta non è fatturato.** Per fatturato, venduto o ricavi usa la skill `pn-fatturato-documenti`. Non sommare mai offerte e fatture.
- Dettaglio di campi, vista `qryleads`, RULE-CRM-013, numeri e riferimenti KB: `references/modello-dati.md`. Payload pronti all'uso: `references/ricette.md`.

## 1. Campi CRM della testata (nomi da usare nei filtri)

La query di `testapiedefatture_R` è `FROM testapiedefatture tpf` con join su `leads_statuses`, `leads_funnel_statuses` e `leads_conversion_score`. Nei filtri e nelle dimensioni usa `tpf.<campo>`. In `output_fields` usa gli alias.

| Filtro / dimensione | Significato | Alias in output |
|---|---|---|
| `tpf.idcausale` | causale (filtro sulle causali R cliente) | `idcausale` |
| `tpf.leads_status_code` (string) | stato → `leads_statuses.id` | `leads_status` |
| `tpf.leads_funnel_status_code` | fase → `leads_funnel_statuses.code` | `leads_funnel_status` |
| `tpf.leads_conversion_score_code` | probabilità → `leads_conversion_score.code` | `leads_conversion_score` |
| `tpf.expected_conversion_date` (date) | data prevista di chiusura | `expected_conversion_date` |
| `tpf.codage` | **agente** → `agenti.idagente` | `codage` |
| `tpf.cidoperatore` | chi ha registrato (**non** è l'agente) | `operatore_username` |
| `tpf.totaleimponibile` | valore netto IVA | `totaleimponibile` |
| `tpf.datafattura` (date) | data offerta (l'alias `datafattura` è una stringa: mai filtrarlo) | `datafattura` |
| `tpf.n_doc_orig` | documento da cui l'offerta è stata copiata | `n_doc_orig` |

Decodifiche disponibili come dimensioni: `leads_statuses.description` e `leads_funnel_statuses.title`. L'agente si decodifica con la TabellaBase `agenti`.

## 2. Definizioni obbligatorie (dichiarale in ogni risposta)

- **Valore pipeline** = Σ `totaleimponibile` delle offerte *Aperto* (più *On hold* solo se richiesto), sempre diviso in **attive** (data prevista ≥ oggi), **ferme** (data passata) e **senza data**. Mai un totale unico.
- **Tasso di conversione** = offerte con ordine collegato / **tutte** le offerte del periodo, per numero e per valore. In alternativa si può usare lo stato *Chiuso Positivo*, dichiarando quale delle due basi si usa.
- **Tempo di chiusura** = `datafattura` dell'ordine con `n_doc_orig` = offerta − `datafattura` dell'offerta.
- **Offerta scaduta** = `expected_conversion_date` < oggi (dichiaralo). Mai `validity_days`.
- Stato e fase si riportano **sempre decodificati**, mai con i codici nudi.

## 3. Regola sui totali e sui conteggi (obbligatoria)

- **Mai sommare a mente più di 3 numeri.** I totali li calcola il server: un aggregate su `testapiedefatture_R`, filtrato sulle causali R cliente, con poche dimensioni (es. solo `tpf.leads_status_code` + `leads_statuses.description`) e le misure condizionali attive / ferme / senza data (R1).
- **Se serve anche il dettaglio per agente, mese o fase, fai DUE chiamate**: una per il totale e una per il dettaglio. Il totale riportato è quello della prima chiamata, non una somma del dettaglio.
- Molti gruppi da sommare: usa `pn_dataset_calculate` o il sandbox, mai il ragionamento.
- **Prima di rispondere**, la somma del dettaglio deve coincidere con il totale (tolleranza 1 €). Se non coincide, NON rispondere: ricalcola.
- **Il numero di offerte da riportare è il `count` dei gruppi della chiamata filtrata sulle causali R cliente, mai `total_matching_records`** di una query non filtrata così: conterebbe anche le richieste a fornitore. Per lo stesso motivo non aggregare su `testapiedefatture` né su `_qryleads`, che includono anche lead e richieste a fornitore.

## 4. Trappole verificate (progest, offerte dal 2025: 223)

1. **Fase orfana**: `leads_funnel_status_code = 'OFF'` (215 su 223) non esiste in `leads_funnel_statuses`. Trattala come "fase non impostata" e segnalala; lo stesso vale per ogni codice che non si decodifica.
2. **Probabilità senza valore**: `percentage` = 0 per tutti i codici. Niente pipeline pesata: raggruppa per `title` e dichiaralo. Pesa solo se `percentage > 0`.
3. **"Aperto" non vuol dire viva**: 112 aperte su 122 hanno la data prevista passata. Inoltre:
   - una copia eredita la data prevista dell'originale: 41 aperte hanno una data *anteriore alla data dell'offerta*. Va segnalato;
   - `0000-00-00` va trattata come "senza data".
4. **Le perse non vengono chiuse**: 4 Chiuso Negativo contro 95 Chiuso Positivo. "Vinte / (vinte + perse)" darebbe 96%, un dato falso.
5. **Revisioni**: la vecchia offerta resta *Aperto*; 31 aperte (709.380 €) hanno già una revisione. Segnalale e toglile dal valore attivo (R6).
6. **Stato e ordini non coincidono**: 7 vinte senza ordine, 1 aperta con ordine. Incrocia sempre stato e ordine.
7. **Agente**: `codage` è presente solo su 5 offerte su 223. `FE`, `FP` e `CO` sono codici `agenti` usati per altro, non persone. Riga **"senza agente"** sempre esplicita; mai `cidoperatore` come agente.
8. **Collegamento all'ordine**: le righe d'offerta non vengono evase. La conversione si legge da **ordine.`n_doc_orig` = offerta.`cidfattura`**, solo sugli ordini **cliente**: `testapiedefatture_O` con `tpf.idcausale` `in` [causali O con flag C].
   - `n_doc_orig` può valere la stringa `'NULL'` o puntare a offerte (revisioni).
   - `pn_document_linked_documents` **non vede** questo collegamento: per una singola offerta usa R5.

## 5. Procedura

1. **Configurazione** (R0):
   - causali R e O con flag, da `causalimagazzino`;
   - decodifiche `leads_statuses`, `leads_funnel_statuses`, `leads_conversion_score`, oppure `pn_document_offer_crm_options`.

   Ricava gli id di *Aperto*, *Chiuso Positivo* ecc. (mai quelli di progest su altri tenant) e annota fasi orfane e percentuali a zero.
2. **Descriptor** `pn_tabellabase_descriptor("testapiedefatture_R")` + `ai_instructions`: query `FROM testapiedefatture tpf`, `aggregate_capability.supported` true. Se il tenant l'ha personalizzata, adatta i nomi.
3. **Totali per stato** (R1), poi l'eventuale **dettaglio** per agente, fase o mese (R1 dettaglio, R2), sempre con il filtro sulle causali R cliente.
4. **Conversione**: export (`output=url`) delle offerte del periodo e degli ordini cliente con `tpf.n_doc_orig` valorizzato, poi incrocio nel sandbox (R3).
5. **Offerte ferme**: stato *Aperto* e `tpf.expected_conversion_date` nel passato, ordinate per valore (R4).
6. **Lead vivi**: se `leads` ha lead recenti, prendi i lead da `_qryleads` (`lead_internal_type = 'lead'`) e le offerte sempre da `testapiedefatture_R`. Su progest `leads` è ferma al 2018.
7. **Controlli di plausibilità** e blocco "Qualità del dato CRM" (§7).

Domande del tipo "l'offerta contiene il codice X?": se X e' un codice di terzi (codice fornitore/cliente, EAN) e hai il tool `pn_articoli_risolvi_codici`, attiva `pn-identificazione-articoli` passando la controparte del documento; poi cerca l'`idmagazzino` risultante nelle righe del documento. Con esito `probabile` indicalo come probabile; con `ambiguo` o `non_trovato` dichiaralo, non dedurre.

## 6. Scritture (solo su richiesta esplicita, con conferma)

- Stato, fase e probabilità di **una** offerta cliente (causale con flag C):
  1. `pn_document_edit_start(document_code=<cidfattura>)`;
  2. `pn_document_edit_set_header` con `offer_status_code`, `offer_funnel_status_code`, `offer_conversion_score_code` (codici da `pn_document_offer_crm_options`);
  3. `pn_document_edit_save(confirm_save=yes)`.

  Riepilogo e conferma prima del salvataggio, rilettura dopo.
- **RULE-CRM-013**: per le offerte, spostare la card cambia solo la fase. Imposta **sempre** stato e fase insieme.
- `expected_conversion_date` non è scrivibile con i tool di sessione documento: `TOOLING_GAP`, rimanda alla UI. Mai `pn_tabellabase_update` su `testapiedefatture`.
- **Mai aggiornamenti massivi**: proponi l'elenco, decide l'utente offerta per offerta.
- Creare offerte o convertirle in ordine: delega a chi ha `pn-evasione-ordini` e i tool di scrittura documenti.

## 7. Blocco obbligatorio a fine risposta: "Qualità del dato CRM"

Numero e quota sul perimetro analizzato:

- fasi orfane o non impostate;
- percentuali di probabilità a zero;
- perse rispetto a vinte;
- aperte ferme (di cui con data anteriore all'offerta) e senza data, con il valore;
- aperte già revisionate, con il valore;
- aperte con ordine e vinte senza ordine;
- offerte senza agente e codici agente che non sono persone;
- definizioni usate.

## 8. Checklist

- [ ] Filtro `tpf.idcausale` `in` [causali R con flag C] in ogni `search` (e [causali O con flag C] sugli ordini), mai `cm.flagidcliente_idfornitore` come filtro? Se un campo `cm.*` ha dato errore, uso la strada secondaria?
- [ ] Filtri su `tpf.*` e `tpf.datafattura`, non sull'alias `datafattura`?
- [ ] Totale da un aggregate (prima chiamata), dettaglio a parte, quadratura entro 1 €?
- [ ] Numero di offerte dal `count` dei gruppi, non da `total_matching_records`?
- [ ] Stati letti dal tenant e riportati decodificati?
- [ ] Pipeline divisa in attive, ferme e senza data, revisioni segnalate?
- [ ] Tasso su tutte le offerte del periodo, con la base dichiarata?
- [ ] Riga "senza agente" presente, `cidoperatore` mai usato come agente?
- [ ] Nessuna somma con il fatturato, blocco "Qualità del dato CRM" presente?
