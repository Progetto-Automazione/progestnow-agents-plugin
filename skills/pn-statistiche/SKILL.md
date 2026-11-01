---
name: pn-statistiche
description: Procedura obbligatoria per le STATISTICHE di vendita/acquisto della pagina Statistiche di ProgestNOW (fatturato, ordinato, offerto, acquistato) per 1-5 raggruppamenti (anno, mese, cliente, agente, articolo, categoria, zona, fornitore...), top clienti/articoli, confronto con l'anno precedente, margine e costo. Attivala PRIMA di pn_statistiche_query/pn_statistiche_catalog o quando l'utente chiede "come nella pagina Statistiche". Evita acquistato che somma ordini fornitore e carichi, totali sommati a mente, margini senza copertura del costo.
metadata:
  scope: core
  related_skills: pn-fatturato-documenti, pn-ordini-clienti, pn-ordini-fornitori
  auto_activate_on_tools: [pn_statistiche_*]
  auto_activate_mode: before_tool
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - Questi tool qui non esistono: `pn_dataset_calculate`, `pn_excel_generate`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Statistiche (pagina Statistiche)

Tool: `pn_statistiche_catalog` (configurazione) e `pn_statistiche_query` (numeri). Entrambi read-only, gli stessi numeri della pagina `/shared/table/tmp_statistica/list`. Mai SQL, mai `pn_tabellabase_list` su `tmp_statistica` (contiene solo l'ultima generazione UI dell'utente).

## 1. Modello concettuale

- Una riga statistica e una **riga di documento** la cui causale e configurata per un tipo statistica (`causalimagazzino.tipo_statistica`): **F** fatturato, **O** ordinato clienti, **R** offerto, **A** acquistato.
- Misure: `qta`, `valore` (netto IVA in euro, `importototale × cambio`), `costo`; derivate `margine` = valore − costo e `margine_pct`.
- Note di credito e movimenti M con segno `-` sono **gia negativi**: non sottrarli di nuovo. Le spese di piede sono escluse. Le righe con quantita 0 sono escluse.
- Chiama `pn_statistiche_catalog` **una volta per job**, prima della prima query: dice quali causali compongono ogni tipo, quale costo e attivo, se vale la regola dei doppioni DDT/fattura e quali gruppi/filtri esistono sul tenant.

## 2. Tradurre la domanda

| L'utente dice | Payload |
|---|---|
| venduto, fatturato, vendite | `tipo_statistica: "F"` |
| ordini clienti, ordinato | `"O"` |
| offerte, offerto | `"R"` (puo essere vuoto: §3) |
| acquisti, acquistato | `"A"` + separazione T/M (§3) |
| per mese del 2026 | `groups: ["mese"]` + `filters.date_from/date_to` del 2026 |
| per agente e cliente | `groups: ["agente", "cliente"]` (il primo e il livello 1) |
| top 10 | `top_n: 10` (`include_others` di default true) |
| rispetto all'anno scorso | `compare: {"mode": "previous_year"}` + periodo |
| margine | `measures: ["valore", "costo", "margine", "margine_pct"]` |

Regole:
- **Date sempre ISO** `YYYY-MM-DD` su `date_from`/`date_to` (data documento). Preferiscile all'anno.
- `filters.anno` e l'anno di **numerazione** del documento, non `YEAR(data)`: il gruppo `anno` invece usa la data. Con entrambi arriva `ANNO_IS_DOCUMENT_YEAR`.
- Il gruppo `mese` **non contiene l'anno**: usalo con il gruppo `anno` o con un periodo di un solo anno (`MESE_WITHOUT_ANNO`).
- Filtri multivalore: **sempre array di stringhe**, anche con un solo valore (`"idcliente": ["1888"]`, `"tipocausale": ["T"]`). Solo `date_from`, `date_to`, `idmagazzino_like` sono stringhe.
- `compare` non ammette il gruppo `anno`: confronta per mese, agente, cliente...

## 3. Regola su A (obbligatoria)

"Acquistato" mescola **ordini a fornitore (T)** e **carichi di magazzino (M)**: su progest ORFOR + CAR. **Mai** riportare il totale A senza separarli:
- filtra `filters.tipocausale: ["T"]` oppure `["M"]`, oppure aggiungi il gruppo `tipocausale` (o `causale`);
- se l'utente non specifica, mostra entrambi e dichiara che **non vanno sommati** (un ordine caricato compare due volte);
- se arriva `A_MIXED_T_M`, spiegalo.

R (offerto) puo essere vuoto per configurazione: con `TIPO_STATISTICA_EMPTY` di' che nessuna causale e configurata per l'offerto e **non inventare valori**; per le offerte CRM esiste la skill `pn-offerte-crm`.

## 4. Statistiche o `pn-fatturato-documenti`?

- "fatturato" generico, da riconciliare con le fatture, imponibile di testata → `pn-fatturato-documenti`.
- "come nella pagina Statistiche", breakdown per articolo/categoria/reparto, margine, ordinato/acquistato per gruppi, confronto multi-livello → questa skill.
- **Dichiara sempre la definizione usata** (`definition` della risposta). Differenze note e spiegabili con il fatturato di testata: spese di piede escluse; causali con `tipo_statistica` vuoto escluse (`CAUSALI_NOT_IN_STATISTICS`, su progest la ND); righe con quantita 0 escluse. Esempio progest 2026: righe F (NF+NFA) … contro imponibile di testata NF+NFA … (differenza = spese di piede …); la ND (…) e esclusa dalle statistiche.

## 5. Totali

- Riporta `totals` del tool, **mai somme a mente**. `others` (perimetro − top N) e gia calcolato.
- `totals` e calcolato sull'intero perimetro: puo differire di qualche centesimo dalla somma dei gruppi arrotondati (al massimo 0,005 × gruppi). E normale: riporta `totals`.
- Per somme su molti gruppi usa `pn_dataset_calculate` sul `result_set_id`.
- `has_more: true` vuol dire che ci sono altre pagine: per l'elenco completo usa il `result_set_id` (Excel o calcolo), non paginare a mano.

## 6. Codici e descrizioni

- In tabella sempre la coppia `groupN_code` + `groupN_label`.
- `label` null = codice senza anagrafica (`LABEL_MISSING`): riporta il codice, non inventare il nome.
- Codice vuoto o null = "senza agente/zona/...": riportalo come riga esplicita.
- I titoli dei gruppi sono quelli della pagina (`titoli`), anche con i refusi della UI (`CatMreceologica`).

## 7. Qualita del dato (blocco obbligatorio a fine risposta)

Riassumi in poche righe:
- copertura del costo: `data_quality.copertura_costo_pct`, `righe_senza_costo` (`COST_MISSING`);
- costo = ultimo costo attuale dell'articolo, non storico (`COST_IS_CURRENT_LAST_COST`): il margine e indicativo;
- **margine non affidabile se la copertura del costo e sotto il 90%** (soglia della skill: dichiarala);
- cambio mancante (`CAMBIO_MISSING`), causali escluse (`CAUSALI_NOT_IN_STATISTICS`), tipo statistica vuoto, codici senza descrizione, quota "senza agente".

## 8. Export ed elaborazioni

- Excel: `pn_excel_generate` con `source.type=result_set` e il `result_set_id`, senza ricopiare le righe.
- Ricalcoli, percentuali, filtri successivi: `pn_dataset_calculate` sullo stesso `result_set_id`.
- Se c'e `auto_export`, segui le sue istruzioni (dataset completo per riferimento).
- `RESULT_SET_UNAVAILABLE`: oltre 5000 gruppi; restringi con filtri o `top_n`.

## 9. Errori

| Codice | Azione |
|---|---|
| `UNSUPPORTED_GROUP` / `UNSUPPORTED_FILTER` `column_not_in_view` | la vista dei costi del tenant non ha quella colonna: scegli un altro gruppo/filtro e dichiaralo |
| `... not_available_on_tenant` | gruppo/filtro solo tenant D |
| `COMPARE_REQUIRES_PERIOD` | aggiungi `date_from`+`date_to` (o `anno`) |
| `TOO_MANY_GROUPS` | aggiungi filtri (periodo, causale), meno livelli o `top_n` |
| `PERMISSION_DENIED` | l'utente non vede la pagina Statistiche: riferiscilo, non aggirarlo |
| `QUERY_FAILED` | errore del database, non un risultato vuoto: riprova una volta piu semplice, poi riferisci |

Ricette complete con payload e valori di riferimento: `references/ricette.md`. Gruppi, filtri e limiti: `references/gruppi-e-filtri.md`. Trappole: `references/trappole.md`.

## 10. Checklist

- [ ] Ho chiamato `pn_statistiche_catalog` una volta nel job?
- [ ] Tipo statistica corretto (F/O/R/A) e dichiarato con la `definition`?
- [ ] Per A ho separato T e M (filtro o gruppo `tipocausale`)?
- [ ] Date ISO; `mese` con anno o periodo di un solo anno?
- [ ] Filtri multivalore come array di stringhe?
- [ ] Totale preso da `totals` (e `others` dal tool), nessuna somma a mente?
- [ ] Tabella con codice e descrizione di ogni livello?
- [ ] Blocco "Qualita del dato" con copertura del costo e warning?
- [ ] Export con `result_set_id`, non ricopiando le righe?
