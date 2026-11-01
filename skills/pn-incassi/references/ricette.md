# Incassi: ricette operative

Tutte le ricette presuppongono i descrittori letti in questo job (`qryfatture_situazione_incassi`, `qryfatture_incassi` se usata). Sostituisci i nomi campo con quelli del descrittore se diversi. Sintassi filtri: skill `pn-tabellabase-query`.

## R1. "La fattura X e pagata?"

1. Risolvi il `cidfattura`: `pn_documents_search` (macro tipo fattura, anno + numero, eventualmente cliente) o, se l'utente da il codice, usalo. Con piu risultati (sezionali diversi con lo stesso numero) chiedi quale.
2. `pn_document_receipts_status(document_code=<cidfattura>)`.
3. Rispondi con: totale, incassato, residuo, elenco movimenti (data, descrizione, importo). Se una riga e negativa e un insoluto/storno: dillo.
4. Se `received_total` > `document_total` o i movimenti hanno descrizioni che citano altri documenti: R5 e segnala l'anomalia.

## R2. Fatture da incassare di un cliente

1. Codice cliente: `arccli` (`contains` sulla ragione sociale; con piu risultati chiedi). In alternativa filtra direttamente la vista con `arccli.nome` `contains`, controllando che `rifpa_idcliente` sia unico nel risultato.
2. `pn_tabellabase_list` su `qryfatture_situazione_incassi`:

```json
[
  {"field": "qryfatture_situazione_incassi.rifpa_idcliente", "op": "=", "type": "number", "value": "1437"},
  {"field": "qryfatture_situazione_incassi.stato_incasso", "op": "in", "type": "string", "value": ["incassato_parziale", "nessun_incasso"]}
]
```

3. Per data fattura e scadenze: se il descrittore fatture del tenant espone gia `stato_incasso` / `importo_residuo` (progest: `testapiedefatture_F`), usa quello con filtro cliente + stato e ottieni data, numero, pagamento in una chiamata. Altrimenti `pn_tabellabase_list` sul descrittore fatture con `in` sui `rifpa_cidfattura` trovati.
4. Totale da incassare = somma dei `importo_residuo` > 0. Segnala a parte eventuali fatture `incassato` con residuo negativo dello stesso cliente: spesso sono incassi registrati sulla partita sbagliata che "mancano" su una fattura aperta (confronta importi e descrizioni con R4).

## R3. Situazione incassi di un periodo di fatturazione

- Per anno: filtro `rifpa_anno` + ricetta standard SKILL.md §5.
- Per mese/trimestre di **data fattura**: la vista non ha la data. Usa il descrittore fatture con le colonne di incasso, oppure estrai le fatture del periodo (`output_fields` minimi: cidfattura) e poi `aggregate` sulla vista con `in` su `rifpa_cidfattura` (oltre ~500 codici: `output=url` di entrambe e merge nel sandbox con `pn_code_exec`/`pn_dataset_merge`).
- Per sezionale: `rifpa_idcausale`.

## R4. Movimenti che compongono l'incassato di una fattura

`pn_tabellabase_list` su `qryfatture_incassi`:

```json
[
  {"field": "qryfatture_incassi.rifpa", "op": "=", "type": "string", "value": "6/421"},
  {"field": "qryfatture_incassi.csott", "op": "=", "type": "number", "value": "1508"}
]
```

`rifpa` e `csott` vengono da `rifpa_standard` e `rifpa_idcliente` della vista situazione. Righe con `importo = 0` sono righe in DARE (insoluti, storni): qui non vedi l'importo, usa R5. `sorgente_incasso = testapiedefatture` = nota di credito non contabilizzata (`chiave` = cidfattura della NC).

## R5. Saldo contabile vero di una partita (insoluti, partite condivise, rifpa errati)

`pn_coge_partitario_search`:

```json
{"search": [
  {"field": "arcmovc.csott", "op": "=", "type": "number", "value": "1508"},
  {"field": "arcmovc.rifpa", "op": "=", "type": "string", "value": "6/421"}
]}
```

Leggi `datareg`, `nmovc`, `causale`, `tipocau1`, `descr`, `impdare`, `impavere`.

- Saldo partita = `SUM(impdare) - SUM(impavere)`: > 0 credito aperto, 0 chiusa, < 0 incassato in eccesso o rifpa errato.
- Righe di fattura emessa (DARE, `tipocau1 = 0`): devono essere **una**. Se sono piu di una la partita e condivisa: l'incassato non e attribuibile alla singola fattura; dillo.
- Righe DARE con `tipocau1 = 9`: insoluti/storni/riaddebiti. Spiegano un residuo negativo della vista.
- `descr` che cita un altro documento (`Doc. n. 5/796`): incasso registrato sul rifpa sbagliato.
- Il partitario applica `tabcauc.tipo1 < 'A'` e puo dipendere dai saldi progressivi dell'utente: per l'elenco delle righe va bene; non usarlo come fonte di saldi di periodo.

## R6. Incassato in un periodo (cassa)

`pn_tabellabase_aggregate` su `qryfatture_incassi`:

```json
{
  "table_name": "qryfatture_incassi",
  "search": [
    {"field": "qryfatture_incassi.data", "op": "between", "type": "date", "value": "@start_of_month-1m,@end_of_month-1m"},
    {"field": "arcsott.tipos", "op": "=", "type": "string", "value": "C"},
    {"field": "qryfatture_incassi.importo", "op": ">", "type": "number", "value": "0"}
  ],
  "dimensions": ["qryfatture_incassi.sorgente_incasso"],
  "measures": [
    {"name": "righe", "operation": "count"},
    {"name": "incassato", "operation": "sum", "field": "importo", "round": 2}
  ]
}
```

- Il filtro sui **sottoconti clienti** (`arcsott.tipos = 'C'`) e obbligatorio: senza, sommi banche, cassa, giroconti e fornitori (su tenant B la parte non clienti e quasi il doppio di quella clienti). Se il filtro su `arcsott.tipos` viene rifiutato (`INVALID_SEARCH`), raggruppa per `qryfatture_incassi.csott` con `output=url` e incrocia nel sandbox con l'elenco clienti (`arccli`), oppure dichiara il limite.
- Il risultato e **lordo**: include le NC (`tipo1 = 1`) e le RIBA presentate (anche non maturate) e non sottrae gli insoluti. Include anche gli incassi senza `rifpa` (la vista non filtra sul riferimento), che pero non risultano su nessuna fattura in `qryfatture_situazione_incassi`. Dichiara questi limiti nella risposta.
- Per un netto di cassa con insoluti sottratti: estrai il partitario dei clienti nel periodo (`pn_coge_partitario_search` con `output=url`, causali finanziarie) e calcola `SUM(impavere) - SUM(impdare)` nel sandbox.
- Per escludere le NC: dimensione `sorgente_incasso` separa solo le NC non contabilizzate; le NC contabilizzate sono righe `arcmovc` con causale di tipo 1, distinguibili solo dal partitario (`tipocau1`).

## R7. Fatture con incassato anomalo (controllo qualita)

`pn_tabellabase_list` su `qryfatture_situazione_incassi` con `importo_residuo < -0.01` (`number`), `output_fields` minimi, ordinate per `importo_residuo` crescente. Per i primi casi applica R5 e classifica: insoluto non sottratto / partita condivisa / rifpa errato / NC contabilizzata due volte. Proponi all'utente la verifica in contabilita, non correggere.

## R8. Registrare un incasso singolo

1. R1 (stato e residuo), controllo duplicati sulla stessa data/importo.
2. `pn_document_payment_methods(direction="receipt")`.
3. Riepilogo e conferma: fattura, cliente, data, importo, modalita, causale, conto.
4. `pn_document_receipt_register`:

```json
{"mode": "single", "document_code": "<cidfattura>", "payment_date": "2026-10-07", "amount": …,
 "payment_method_code": "bonifico", "description": "bonifico del 07/10/2026"}
```

5. Rileggi con `pn_document_receipts_status` e riporta il nuovo residuo.

## R9. Registrare un bonifico che paga piu fatture

1. Per ogni fattura: R1 -> residuo. Ordina le fatture come l'utente vuole saldarle (di solito dalla piu vecchia).
2. Se `amount` != somma residui: chiedi quali fatture restano parziali (l'ultima riga del bulk assorbe tutta la differenza).
3. Riepilogo e conferma.
4. `pn_document_receipt_register`:

```json
{"mode": "bulk", "payment_date": "2026-10-07", "amount": …, "payment_method_code": "bonifico",
 "description": "bonifico cumulativo",
 "rows": [
   {"cidfattura": "<cidfattura_piu_vecchia>", "importo_scadenza": …, "importo_incassato_scadenza": 0},
   {"cidfattura": "<cidfattura_successiva>", "importo_scadenza": …, "importo_incassato_scadenza": 0}
 ]}
```

`importo_scadenza` = residuo letto al passo 1 (con `importo_incassato_scadenza = 0`). Codici e importi sono esempi: `payment_method_code` va sempre preso da `pn_document_payment_methods`.

5. Riporta `importi_per_fattura` e rileggi lo stato di ogni fattura.

## Errori tipici

| Sintomo | Causa probabile | Rimedio |
|---|---|---|
| Incassato = 2 x totale, residuo = -totale | insoluto (DARE) non sottratto dalla vista, poi nuovo incasso | `pn_document_receipts_status` o R5 |
| Incassato molto superiore al totale | partita condivisa da piu fatture o incasso cumulativo | R5, conta le righe di fattura |
| Fattura `nessun_incasso` che il cliente dice di aver pagato | incasso registrato senza `rifpa` o su altro `rifpa` | partitario del cliente nel periodo, cerca l'importo |
| `stato_incasso = incassato` ma la banca non ha accreditato | RIBA presentata (sbf), non ancora maturata o insoluta | spiegalo; stato effetti con skill `effetti-ciclo-vita` |
| 0 righe in `qryfatture_incassi` per una fattura incassata | filtrato solo per `rifpa` con csott sbagliato, o `rifpa` con anno a 4 cifre | usa `rifpa_standard` + `rifpa_idcliente` |
| Totale incassi del mese enorme | non filtrati i sottoconti clienti | R6 con `arcsott.tipos = 'C'` |
| `Esercizio contabile NON definito per la data` | data incasso fuori esercizi | chiedi la data corretta o segnala all'amministrazione |
| `Modalità di Incasso NON configurata correttamente` | causale o conto della modalita mancanti in `tabmodalitapagamento` | scegli un'altra modalita o segnala la configurazione |
| `Documento non coerente con incasso cliente` | documento senza cliente (fornitore, interno) | non e una fattura attiva |
