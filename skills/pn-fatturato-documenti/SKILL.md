---
name: pn-fatturato-documenti
description: Procedura obbligatoria per FATTURATO, vendite, ricavi e venduto calcolati dai documenti ProgestNOW. Attivala PRIMA di aggregare documenti di vendita o di rispondere su fatturato per periodo, mese, anno, cliente, agente o articolo, miglior mese, confronto tra periodi, top clienti. Default = imponibile delle fatture (tipologia F) meno note di credito (tipologia C) per data fattura, con TUTTE le causali della tipologia. Evita fatturato su una sola causale, IVA inclusa, autofatture o proforma.
metadata:
  scope: core
  requires_skill: pn-tabellabase-query
  related_skills: pn-incassi
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`, `pn_dataset_calculate`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Fatturato dai documenti

**Dipendenza.** Per la sintassi di `search`, `pn_tabellabase_aggregate`, `order_by`, misure condizionali e `output=url` segui la skill `pn-tabellabase-query` (attivala se non e attiva). Questa skill dice **quali documenti**, **quale importo**, **quale tabella** e **come controllare il risultato**. Mai `freesql`, mai SQL diretto: solo i tool TabellaBase e documenti.

## 1. Definizione di default (imponila, non chiederla)

```
Fatturato = Σ totaleimponibile dei documenti di tipologia F
          − Σ totaleimponibile dei documenti di tipologia C
            filtrati per datafattura
```

- **Netto IVA**, note di credito **sottratte**. E la stessa definizione della dashboard Statistica CRM.
- **Escluse** proforma (P), documenti di acquisto e autofatture (A), offerte, ordini, DDT e documenti interni (R, O, D, T, M, I).
- **Incluse** le fatture di acconto (TD02, es. NFA su progest, NFANT/NFCEA su tenant E): la fattura di saldo storna l'acconto, il totale torna. Se nel periodo ci sono acconti, riportane l'importo a parte.
- **Fatturato lordo** (`totaledocumento`, IVA inclusa) solo se l'utente lo chiede, dichiarandolo.
- Il default si **dichiara** nella risposta, non si chiede all'utente.

## 2. Le due regole che hanno causato l'errore del job 57 (tenant J)

**Regola 1: la tipologia sta in `causalimagazzino.tipocausale`, mai nel codice causale.** `testapiedefatture.idcausale` e un codice libero del tenant, e ogni tenant ha piu causali per tipologia. Ad esempio le F sono NF, NFS, NFPA, NFPAS, NFA, NFB, ND su tenant J e NF, NFA, NFACC, NFE, NFI, ND, AF su progest.

Mai filtrare il fatturato per codice causale, salvo richiesta esplicita dell'utente ("solo le NF"). Lo stesso codice cambia significato tra tenant: NFA e "fattura acconto" su progest e "fattura accompagnatoria" su tenant J e tenant E.

**Regola 2: le note di credito sono salvate con importi positivi** (verificato: nessun importo negativo nel 2026 su progest e tenant J). Vanno **sottratte** esplicitamente; sommarle insieme alle fatture gonfia il fatturato.

Caso reale, tenant J, febbraio 2026:
- F: NFS 860 documenti (…), NFPAS 2 (…), NF 1 (85,00; totale documento 103,70);
- C: NCS 32 (…).

Fatturato netto corretto: **…** (… − …). Il job 57 ha risposto 103,70 €, cioe il totale documento (IVA inclusa) della sola NF; a gennaio bene ha 698 fatture NFS e nessuna NF, quindi ha concluso "nessuna fattura".

## Regola sui totali (obbligatoria)

- **Mai sommare a mente più di 3 numeri.** Il totale di un periodo lo calcola il server, in uno di questi due modi:
  - un aggregate su `testapiedefatture` con filtro `tpf.idcausale` `in` [tutte le causali F e C] e `dimensions: ["cm.tipocausale"]` soltanto: 2 gruppi, F e C;
  - oppure due aggregate senza dimensioni su `testapiedefatture_F` e `testapiedefatture_C`, ma solo se il loro descriptor non ha `group_by` (su progest e tenant J `_F` ce l'ha e l'aggregate la rifiuta).
- **Se servono anche mese, causale o agente, fai DUE chiamate**: una per il totale (poche righe) e una per il dettaglio. Il totale riportato è quello della prima chiamata, non una somma del dettaglio.
- Se devi sommare molti gruppi, usa `pn_dataset_calculate` o il sandbox, mai il ragionamento.
- **Prima di rispondere**, la somma delle righe di dettaglio deve coincidere con il totale (tolleranza 1 €). Se non coincide, NON rispondere: ricalcola.
- **Il numero di documenti da riportare è il `count` dei soli gruppi F e C, mai `total_matching_records`** della query: se la TabellaBase non è filtrata per tipologia, quel valore conta tutti i documenti del periodo (ordini, proforma, DDT). Su `qrystatistichedocumenti` conta le righe: usa `count_distinct testa_cidfattura`.
- **Non aggregare su `testapiedefatture` (tutti i documenti) senza il filtro `tpf.idcausale` `in` [causali F e C]**, così ordini, proforma e DDT non entrano mai nel calcolo.
  - `cm.tipocausale` non è filtrabile, perché non è nel catalogo campi: le causali vanno prese da `pn_document_types`.
  - Le TabelleBase per tipologia (`_F`, `_C`) vanno bene solo se aggregabili.
- **Strada secondaria**: se un filtro o la dimensione `cm.tipocausale` (o un altro campo `cm.*`) risponde `FIELD_UNKNOWN` / `FIELD_NOT_FILTERABLE`:
  1. raggruppa per `tpf.idcausale`, con lo stesso filtro sulle causali;
  2. assegna ogni codice a F o C con l'elenco di `pn_document_types`, che restituisce `code` e `macro_type`;
  3. somma con `pn_dataset_calculate` o nel sandbox.

  Filtri sempre con `in` + `string`, mai `collection` / `collection_or`.

## 3. Procedura

1. **Chiarisci** periodo, dimensione (totale, mese, cliente, agente, articolo) e se serve lordo o netto. Default netto: dichiaralo, non chiederlo. Chiedi solo il periodo se manca davvero.
2. **Obbligatorio**: `pn_document_types(document_macro_type="F")` e `(document_macro_type="C")`. Prendi **tutti** i `code`: sono l'elenco del filtro `tpf.idcausale` `in` di ogni ricetta su `testapiedefatture`.
3. **Aggrega** con la ricetta giusta (§4). Tabella principale: `testapiedefatture` (`FROM testapiedefatture tpf INNER JOIN causalimagazzino cm`), filtrata sulle causali F e C, con `cm.tipocausale` come **dimensione**. Prima il totale (solo `cm.tipocausale`), poi l'eventuale dettaglio.
4. **Calcola** netto = F − C per ogni gruppo (mese, agente, cliente). Una C assente vale 0.
5. **Controllo di plausibilita** (§5) prima di rispondere.
6. **Rispondi** nel formato di §6.

Campi di `testapiedefatture` (alias `tpf`, sempre qualificati): `tpf.datafattura` (data, filtro e bucket), `tpf.anno`, `tpf.totaleimponibile` (netto IVA), `tpf.totaledocumento` (IVA inclusa), `tpf.totalemerce`, `tpf.totalespese`, `tpf.totaleimposta`, `tpf.totaleapagare`, `tpf.idcliente`, `tpf.codage` (agente), `tpf.idcausale`, `tpf.idvaluta`, `tpf.cambio`; dalla causale `cm.tipocausale`. Non usare `datafattura` non qualificato (e la data formattata, non filtrabile) ne `tpf.tipocausale` (non esiste).

## 4. Ricette (payload completi in `references/ricette.md`)

| Domanda | Ricetta |
|---|---|
| Fatturato di un periodo, con elenco causali | R1: `testapiedefatture` filtrata sulle causali F e C; totale con `cm.tipocausale`, dettaglio con `cm.tipocausale` + `tpf.idcausale` |
| Fatturato mensile, miglior mese, confronto tra periodi | R2: R1 + `date_buckets` mensile (o misure condizionali per anno) |
| Per agente | R3: dimensioni `tpf.codage` + `cm.tipocausale` |
| Per cliente, top clienti | R4: causali F e C da `pn_document_types`, misure condizionali, `order_by` |
| Per articolo, famiglia, categoria | R5: `qrystatistichedocumenti` a livello riga |
| `testapiedefatture` non aggregabile | R6: fallback |

R1, la base di tutto (chiamata 1, totale; esempio tenant J, causali da `pn_document_types`):

```json
{
  "table_name": "testapiedefatture",
  "search": [
    {"field": "tpf.datafattura", "op": ">=", "type": "date", "value": "01/02/2026"},
    {"field": "tpf.datafattura", "op": "<=", "type": "date", "value": "28/02/2026", "nulls": "exclude"},
    {"field": "tpf.idcausale", "op": "in", "type": "string", "value": ["ND", "NF", "NFA", "NFB", "NFPA", "NFPAS", "NFS", "NC", "NCPA", "NCPAS", "NCS"]}
  ],
  "dimensions": ["cm.tipocausale"],
  "measures": [
    {"name": "documenti", "operation": "count"},
    {"name": "imponibile", "operation": "sum", "field": "tpf.totaleimponibile", "round": 2},
    {"name": "totale_documento", "operation": "sum", "field": "tpf.totaledocumento", "round": 2}
  ]
}
```

Tornano due gruppi (`cm_tipocausale` = F e C): netto = `imponibile` F − `imponibile` C. Atteso su tenant J: F …, C …, netto ….

Chiamata 2 (dettaglio per causale, per il controllo "una sola causale"): stesso `search`, `dimensions: ["cm.tipocausale", "tpf.idcausale"]`. La somma dei gruppi F deve tornare con F della chiamata 1.

**`testapiedefatture_F` / `_C` solo come fallback (R6)**: su progest e tenant J `_F` ha `GROUP BY tpf.cidfattura` e l'aggregate risponde `UNSUPPORTED_QUERY_SHAPE`.

Per articolo (R5) `qrystatistichedocumenti` e **a livello riga**: si sommano solo i campi `riga_*`. I campi `piede_*` sono ripetuti su ogni riga e sommarli moltiplica i totali (tenant J, febbraio, NFS: … invece di …). Le spese di piede non sono incluse: dichiaralo.

## 5. Controllo di plausibilita (obbligatorio prima di rispondere)

Non riportare come dato certo, ma **segnala e verifica**, se:

- in una serie un mese e a zero o vicino a zero mentre gli altri no;
- la variazione rispetto al mese precedente supera ±70%;
- e stata trovata una sola causale F dove il tenant ne ha di piu (`pn_document_types`), oppure tutto il fatturato e su una causale "storico" o "PA";
- il netto e negativo, o le C superano il 20% delle F;
- `total_matching_records` e 0 su un periodo in cui il tenant lavora.

Verifica = rilancia R1 sul solo mese anomalo con `tpf.idcausale` come dimensione e il solo filtro sulle causali F e C. Il job 57 avrebbe colto subito "gennaio 0, febbraio 103 €, marzo 510.000 €". Se l'anomalia resta, riportala esplicitamente come tale.

## 6. Formato della risposta

Dichiara sempre:

1. **Definizione**: "fatturato netto = imponibile fatture (F) − note di credito (C), IVA esclusa, per data fattura" (o lordo, se richiesto).
2. **Periodo** esatto.
3. **Causali incluse**, per tipologia (es. "F: NFS, NFPAS, NF; C: NCS").
4. **Tabella** con F, C e netto (per mese, cliente o agente se richiesto), con numero documenti.
5. Eventuali **anomalie** del §5 e acconti del periodo.
6. **Valuta**: piu valute nel periodo vanno riportate separate; dichiara se hai usato `tpf.cambio`.
7. Il link `urls.list`, se presente.

## 7. Se l'utente confronta con una schermata del gestionale

Il prodotto calcola il fatturato in tre modi diversi: tab "Dati gestionali" del cliente (prima nota), dashboard Statistica CRM (come questa skill) e viste statistiche (campi `_stat`). Dettaglio in `references/definizioni.md`. Se i numeri differiscono, spiega la differenza citando la definizione usata da quella schermata. Usa i campi `_stat` solo se l'utente chiede "come nelle statistiche del gestionale", segnalando le anomalie di configurazione. Se chiede i numeri "come nella pagina Statistiche" (anche per articolo, categoria, margine, ordinato o acquistato) usa la skill `pn-statistiche` (`pn_statistiche_query`).

## 8. Non e questa skill

- Incassato, da incassare, residuo, insoluti: skill `pn-incassi`. Il fatturato non e l'incassato.
- Fatturato contabile, registri e liquidazioni IVA (`arcmovi`): agente `PNOWCONTABILITA`. Qui va solo citato come definizione alternativa.
- Margini e costi: skill `pn-statistiche`.
- Fatture passive, acquisti, autofatture (tipologia A): non sono fatturato.

## 9. Checklist

- [ ] Ho usato la tipologia (`cm.tipocausale`) e non un codice causale?
- [ ] Ho filtrato `tpf.idcausale` `in` tutte le causali F e C, e il totale viene da un aggregate con solo `cm.tipocausale` (non da una somma a mente)?
- [ ] La somma del dettaglio coincide con il totale entro 1 €?
- [ ] Il numero di documenti viene dal `count` dei gruppi F e C, non da `total_matching_records`?
- [ ] Ho sottratto le note di credito (C)?
- [ ] Ho sommato `totaleimponibile` (netto IVA), salvo richiesta di lordo dichiarata?
- [ ] Ho filtrato su `tpf.datafattura` qualificato?
- [ ] Ho fatto il controllo di plausibilita su mesi a zero, salti oltre ±70% e causale singola?
- [ ] La risposta dichiara definizione, periodo, causali incluse e tabella F, C, netto?
- [ ] Per articolo ho sommato solo campi `riga_*`, mai `piede_*`?
