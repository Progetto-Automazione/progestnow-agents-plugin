---
name: pn-incassi
description: >-
  Procedura obbligatoria per INCASSI di FATTURE ATTIVE. Attivala PRIMA di rispondere su incassato, da
  incassare, residuo, fatture pagate/non pagate/parziali, insoluti, crediti aperti di un cliente,
  incassi di un periodo, o PRIMA di registrare un incasso. Fonti: qryfatture_situazione_incassi (stato
  per fattura), qryfatture_incassi (movimenti), partitario, pn_document_receipts_status,
  pn_document_receipt_register. Evita incassato gonfiato da insoluti, partite condivise e righe banca.
metadata:
  scope: core
  requires_skill: pn-tabellabase-query
  related_skills: effetti-ciclo-vita
  auto_activate_on_tools: [pn_document_receipts_status, pn_document_receipt_register]
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`, `pn_dataset_merge`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Incassi delle fatture attive

Un **incasso** non e un campo della fattura: e una riga di **prima nota** (`arcmovc`) in **AVERE sul conto del cliente** con lo stesso **riferimento partita** (`rifpa`) della fattura. Lo "stato incasso" di una fattura e quindi sempre una **ricostruzione**: si prendono le righe contabili della partita (e le note di credito collegate) e si confrontano con il totale del documento.

Per la sintassi di `search`, `aggregate`, `output=url` segui la skill `pn-tabellabase-query` (attivala se non e attiva): questa skill dice **cosa** leggere e **come interpretarlo**.

## 1. Il collegamento fattura -> partita -> movimenti (da sapere a memoria)

```
testapiedefatture.cidfattura  ==  qryfatture_situazione_incassi.rifpa_cidfattura
qryfatture_situazione_incassi.rifpa_standard + rifpa_idcliente
        ==  arcmovc.rifpa + arcmovc.csott          (righe contabili della partita)
        ==  qryfatture_incassi.rifpa + qryfatture_incassi.csott   (singoli incassi)
```

- **`rifpa_standard` = ultima cifra dell'anno + `/` + numero fattura** (es. fattura n. 421 del 2026 -> `6/421`). Non contiene ne la causale ne l'anno intero.
- La chiave di una partita e **sempre la coppia** `rifpa` + `csott` (codice cliente = sottoconto). Mai filtrare i movimenti per il solo `rifpa`: `6/421` esiste per decine di clienti e anche per i fornitori.
- `rifpa_complete` (es. `6/421NF`) aggiunge la causale ma **non** e il valore scritto in prima nota: per i join con `arcmovc` usa `rifpa_standard`.

## 2. Le due TabellaBase e cosa contengono davvero

Leggi sempre i descrittori in questo job (`pn_tabellabase_descriptor("qryfatture_situazione_incassi")` e, se ti servono i movimenti, `pn_tabellabase_descriptor("qryfatture_incassi")`) e le loro `ai_instructions` se presenti: il tenant puo averli personalizzati. Entrambe sono **viste di sola lettura**.

### `qryfatture_situazione_incassi` — una riga per fattura (solo causali `tipocausale = F`)

| Campo | Significato |
|---|---|
| `rifpa_cidfattura` (chiave) | `cidfattura` del documento |
| `rifpa_anno`, `rifpa_idcausale` | anno e causale della fattura |
| `rifpa_standard` | rifpa della partita (`6/421`) |
| `rifpa_idcliente` | codice cliente (`arccli.codice` = `arcmovc.csott`) |
| `arccli_nome` | ragione sociale del cliente (join `arccli` nel descrittore; alias di lista, per filtrare usa `arccli.nome`) |
| `totaledocumento` | totale fattura (IVA inclusa) |
| `importo_incassato` | **somma lorda** degli AVERE della partita + NC collegate (vedi §3) |
| `importo_residuo` | `totaledocumento - importo_incassato` (puo essere **negativo**) |
| `stato_incasso` | `incassato` (residuo <= 0), `incassato_parziale`, `nessun_incasso` |

Non contiene data fattura, agente, scadenze: per filtrare per periodo/agente vedi §4. Query del descrittore: `FROM qryfatture_situazione_incassi LEFT JOIN arccli`: filtra con i nomi qualificati `qryfatture_situazione_incassi.<campo>` e `arccli.<campo>`.

### `qryfatture_incassi` — un movimento per riga

| Campo | Significato |
|---|---|
| `sorgente_incasso` | `arcmovc` (riga di prima nota) oppure `testapiedefatture` (nota di credito non ancora contabilizzata) |
| `chiave` | `arcmovc.nmovc` (numero registrazione) oppure `cidfattura` della NC. **Non e univoca**: una registrazione puo avere piu righe sulla stessa partita (es. RIBA con 4 scadenze) -> non usare `pn_tabellabase_single` su questa vista |
| `data` | data registrazione (stringa `aaaa-mm-gg`; per le NC data della NC) |
| `descrizione` | descrizione della riga contabile (per le NC `NDC n. X del AAAA`) |
| `importo` | `arcmovc.impavere` (solo AVERE) oppure totale NC |
| `rifpa`, `csott` | partita e sottoconto della riga |
| `arcsott_codice`, `arcsott_descr` | decodifica del sottoconto (join `arcsott`) |

Questa vista prende **tutte** le righe di prima nota con causale contabile `tabcauc.tipo1 = 9` (movimenti finanziari) o `tipo1 = 1` (note di credito), **su qualunque sottoconto**: banche, cassa, fornitori, clienti. Le righe in DARE compaiono con `importo = 0`. Filtra sempre per partita (`rifpa` + `csott`) oppure per clienti (§5, R6).

## 3. Come nasce `importo_incassato` e perche puo mentire

Formula della vista (identica su ogni tenant verificato):

```
importo_incassato = SUM(arcmovc.impavere)  su  rifpa = rifpa_standard  AND  csott = rifpa_idcliente
                                           AND tabcauc.tipo1 IN (9, 1)
                  + SUM(totaledocumento delle NC collegate non contabilizzate)
```

Le NC "collegate" sono documenti con `tipocausale = C`, `n_doc_orig = cidfattura` della fattura e `bloccato` vuoto/0 (non ancora trasferite in prima nota). Quando la NC viene contabilizzata (`bloccato = 1`) esce dalla parte documentale e conta solo se la sua registrazione contabile porta il `rifpa` della fattura.

Trappole verificate sui dati reali (progest, tenant B):

1. **Gli insoluti non vengono sottratti.** La vista somma solo l'AVERE. Uno storno/insoluto (es. causale "R.B. INSOLUTA", "ASSEGNO INSOLUTO") e una riga in **DARE** sul cliente: la vista la ignora. Risultato: fattura con RIBA presentata, poi insoluta e poi incassata con bonifico -> `importo_incassato` = 2 x totale, `importo_residuo` negativo, `stato_incasso = incassato` anche se l'insoluto non e mai stato recuperato.
2. **La RIBA presentata conta come incassata.** La presentazione in banca (es. causale "RIC. BANCARIA", sbf) chiude la partita del cliente in contabilita: per la vista la fattura e `incassato` dal giorno della presentazione, non dalla maturazione.
3. **Partite condivise.** Se in prima nota piu fatture dello stesso cliente sono state registrate con lo stesso `rifpa` (registrazioni manuali, fatture importate da un gestionale esterno con numerazione diversa, collisione di decennio `6/xxx` 2016 vs 2026), l'incasso dell'intera partita viene attribuito a ciascuna fattura. Su tenant B circa il 10% delle partite clienti 2026 e condiviso (casi con incassato 1000 volte il totale fattura).
4. **`rifpa` sbagliato in prima nota.** Un incasso registrato con il riferimento di un'altra fattura gonfia una partita e lascia aperta l'altra. La `descrizione` della riga (es. `Doc. n. 5/796` su `rifpa 6/211`) spesso lo rivela.
5. **Incassi senza `rifpa`** (acconti generici, incassi cumulativi non abbinati) non entrano in nessuna fattura: il cliente risulta "non pagato" anche se ha pagato.

Regola operativa: **`importo_residuo < 0` non significa "credito verso il cliente" e `incassato` non significa "soldi in banca"**. Ogni volta che una fattura ha residuo negativo, o l'utente chiede una cifra puntuale su una fattura, verifica la partita (§6). Nelle risposte aggregate segnala sempre il numero e l'importo delle fatture con residuo negativo invece di sommarle in silenzio.

## 4. Quale strumento per quale domanda

| Domanda | Strumento |
|---|---|
| Stato incasso di **una** fattura ("la 421 e pagata?") | `pn_document_receipts_status(document_code=<cidfattura>)` -> autorevole (§6) |
| Elenco / conteggi / totali per stato su **molte** fatture | `qryfatture_situazione_incassi` (list con `output=url` o `aggregate`) |
| Fatture di un cliente o di un periodo con il loro stato | descrittore fatture del tenant se espone `stato_incasso`/`importo_residuo` (es. `testapiedefatture_F` su progest, join gia presente), altrimenti due passi: fatture -> `in` su `rifpa_cidfattura` (ricette R2, R3) |
| Movimenti che compongono l'incassato di una fattura | `qryfatture_incassi` filtrata per `rifpa` + `csott` (R4) |
| Saldo contabile vero di una partita, insoluti, storni | `pn_coge_partitario_search` su `arcmovc.rifpa` + `arcmovc.csott` (R5) |
| Incassato in un periodo (cassa) | `qryfatture_incassi` per `data` **solo sottoconti clienti** (R6), con le avvertenze di §3 |
| Scadenze future / scaduto per data scadenza | non e questa vista: scadenziario o `pn_coge_scadenzario` se disponibili; RIBA/RID: skill `effetti-ciclo-vita` |
| Registrare un incasso | `pn_document_receipt_register` (§7) |

Per filtrare `qryfatture_situazione_incassi`:

- per anno: `qryfatture_situazione_incassi.rifpa_anno` (`string`, es. `"2026"`);
- per cliente: `qryfatture_situazione_incassi.rifpa_idcliente` (`number`) oppure `arccli.nome` (`contains`, verifica che individui un solo cliente);
- per stato: `qryfatture_situazione_incassi.stato_incasso` (`in` su `incassato_parziale`,`nessun_incasso` = "da incassare");
- residuo anomalo: `qryfatture_situazione_incassi.importo_residuo` `<` `-0.01` (`number`);
- per causale/sezionale: `qryfatture_situazione_incassi.rifpa_idcausale`.

La ragione sociale e gia in lista (`arccli_nome`): non serve una lettura di `arccli` per cliente.

## 5. Ricetta standard: crediti aperti / situazione incassi

Una sola `pn_tabellabase_aggregate` con misure condizionali:

```json
{
  "table_name": "qryfatture_situazione_incassi",
  "search": [{"field": "qryfatture_situazione_incassi.rifpa_anno", "op": "=", "type": "string", "value": "2026"}],
  "dimensions": ["qryfatture_situazione_incassi.stato_incasso"],
  "measures": [
    {"name": "fatture", "operation": "count"},
    {"name": "totale_fatture", "operation": "sum", "field": "totaledocumento", "round": 2},
    {"name": "incassato_lordo", "operation": "sum", "field": "importo_incassato", "round": 2},
    {"name": "residuo_positivo", "operation": "sum", "field": "importo_residuo", "round": 2,
     "filter": [{"field": "qryfatture_situazione_incassi.importo_residuo", "op": ">", "type": "number", "value": "0.01"}]},
    {"name": "fatture_residuo_negativo", "operation": "count",
     "filter": [{"field": "qryfatture_situazione_incassi.importo_residuo", "op": "<", "type": "number", "value": "-0.01"}]},
    {"name": "eccedenza_residuo_negativo", "operation": "sum", "field": "importo_residuo", "round": 2,
     "filter": [{"field": "qryfatture_situazione_incassi.importo_residuo", "op": "<", "type": "number", "value": "-0.01"}]}
  ]
}
```

- **Da incassare** = `residuo_positivo` (somma dei soli residui > 0). Mai `SUM(importo_residuo)` su tutte le righe: i residui negativi delle partite gonfiate abbatterebbero il credito aperto.
- Con `dimensions: ["qryfatture_situazione_incassi.rifpa_idcliente"]` e filtro `stato_incasso in (incassato_parziale, nessun_incasso)` ottieni i crediti aperti per cliente; ordina per `residuo_positivo`.
- Riporta sempre a parte `fatture_residuo_negativo` / `eccedenza_residuo_negativo` come "anomalie da verificare in contabilita" (§3).
- Dichiara che `nessun_incasso` include le fatture non ancora scadute: per lo **scaduto** serve la data scadenza, che questa vista non ha.

Altre ricette in `references/ricette.md`; dettaglio di viste, causali e casi reali in `references/modello-dati.md`.

## 6. Verifica di una singola fattura (sempre prima di affermare "pagata", "insoluta", o di registrare)

1. `pn_document_receipts_status(document_code=<cidfattura>)`: restituisce `receipts` (righe con `primanota_id`, `data`, `descrizione`, `importo`) e `totals` (`document_total`, `received_total`, `remaining_total`).
   - A differenza della vista, il tool calcola `importo = AVERE - DARE`: **gli insoluti sono gia sottratti**.
   - `remaining_total` e calcolato sulle **scadenze** del documento (`importoscadenza_1..12`), non sul totale, ed e azzerato se negativo: se differisce dalla vista, il tool e il dato da riportare, spiegando la differenza.
   - Le NC non contabilizzate compaiono con `source = unregistered_credit_note` (se il tenant non ha disattivato `feature_documento_incassi_ndcnonreg`).
2. Se `received_total` > `document_total`, o la vista mostra residuo negativo: leggi la partita completa (R5). Cerca nelle righe in DARE con causale finanziaria (insoluti, storni) e **conta le righe di fattura** (causale di tipo vendita, DARE) sulla stessa partita: piu di una = partita condivisa (§3.3). Riferisci all'utente cosa hai trovato con `nmovc`, data, causale e importo; non "correggere" i numeri.
3. Se il tool non e nel toolset: usa R4 + R5 e dichiaralo.

## 7. Registrare un incasso: `pn_document_receipt_register`

Unico strumento ammesso per registrare incassi. Non usare `pn_tabellabase_new` su `arcmovc`, non comporre la prima nota a mano. Se il tool non e nel toolset: fermati, dichiaralo e indica la UI (incassi documento o prima nota).

Cosa scrive (verificato su `ContabilitaService::registraIncasso` / `registraIncassoMultiplo`): **una registrazione di prima nota** con la causale contabile della modalita scelta (`tabmodalitapagamento.caumovc`), data = `payment_date`, esercizio ricavato dalla data:

- riga cliente: `csott = idcliente` della fattura, **AVERE** = importo, `rifpa = <ultima cifra anno>/<numero>`;
- riga contropartita: sottoconto della modalita (`tabmodalitapagamento.csott`, es. banca o cassa) in **DARE**.

Parametri:

| Parametro | Regola |
|---|---|
| `mode` | `single` (una fattura) o `bulk` (piu fatture, una sola registrazione con N righe cliente) |
| `document_code` | solo `single`: `cidfattura` della fattura |
| `payment_date` | `aaaa-mm-gg`; deve cadere in un esercizio contabile esistente |
| `amount` | importo incassato, > 0 |
| `payment_method_code` | `code` restituito da `pn_document_payment_methods(direction="receipt")`; mai inventarlo |
| `description` | opzionale; viene preceduta dalla descrizione della modalita e messa in maiuscolo |
| `rows` | solo `bulk`: `[{"cidfattura", "importo_scadenza", "importo_incassato_scadenza"}]` |

Procedura obbligatoria:

1. Identifica la fattura (cidfattura) e verifica che sia una **fattura attiva** (`tipocausale F`, ha un cliente). Non usare il tool su note di credito, fatture fornitore o documenti non fiscali: scriverebbe un AVERE sul cliente con segno sbagliato.
2. `pn_document_receipts_status` -> residuo e incassi gia presenti. **Controllo duplicati**: se esiste gia una riga con stessa data e stesso importo, fermati e chiedi.
3. `pn_document_payment_methods(direction="receipt")` -> scegli la modalita indicata dall'utente; se ambigua chiedi. Riporta causale e conto che verranno movimentati (`receipt_accounting_cause`, `account_code`).
4. **Controlla l'importo tu**: in `single` il backend **non** confronta l'importo con il residuo. Importo > residuo = chiedi conferma esplicita (acconto/eccedenza) o correggi.
5. Mostra all'utente il riepilogo (fattura, cliente, data, importo, modalita, conto) e attendi conferma.
6. Esegui. La risposta e solo `success` (nessun numero di registrazione): **rileggi** `pn_document_receipts_status` e riporta la nuova riga e il nuovo residuo.

Modalita `bulk` (un bonifico che paga piu fatture):

- Il backend calcola per ogni fattura `max(0, importo_scadenza - importo_incassato_scadenza)` e assegna l'importo **nell'ordine delle righe**; **l'ultima fattura riceve tutto il resto**, anche oltre il suo residuo. Passa le righe nell'ordine voluto, con `importo_scadenza` = residuo reale da `pn_document_receipts_status` e `importo_incassato_scadenza = 0` (oppure scadenza e incassato coerenti), e fai in modo che `amount` = somma dei residui; se l'importo non quadra chiedi come ripartirlo.
- Tutte le fatture devono essere dello stesso cliente o comunque autorizzate dall'utente: la registrazione e unica, una riga cliente per fattura.
- La risposta contiene `importi_per_fattura`: riportala e verifica ogni fattura rileggendo lo stato.

Fuori perimetro di questo tool (dichiaralo come `TOOLING_GAP` se richiesto): registrare insoluti, stornare o cancellare un incasso, incassi in valuta, abbuoni/arrotondamenti, incassi non legati a una fattura. RIBA/RID (distinte, trasferimento, insoluti): skill `effetti-ciclo-vita` e tool `pn_effetti_*`.

## 8. Confini

- Fatture **passive** / pagamenti fornitori: `pn_document_payments_status` / `pn_document_payment_register`, non questa skill (stessa logica, conto fornitore in DARE).
- Provvigioni su incassato: hanno una propria selezione degli incassi (`pn_provvigioni_*`), non confrontarle con questa vista.
- Semantica contabile generale della prima nota: capability `CAP-20260810-003` (Knowledge MCP) se disponibile.

## 9. Checklist prima di rispondere

- [ ] Ho letto i descrittori delle viste in questo job e filtrato con i nomi qualificati?
- [ ] Ho trattato la partita come coppia `rifpa` + `csott`, mai solo `rifpa`?
- [ ] Il "da incassare" e la somma dei soli residui positivi, e ho segnalato a parte le fatture con residuo negativo?
- [ ] Per una singola fattura ho usato `pn_document_receipts_status` (che sottrae gli insoluti) e verificato la partita se i numeri non tornano?
- [ ] Ho detto che `incassato` include RIBA presentate e che `nessun_incasso` include fatture non ancora scadute?
- [ ] Sui movimenti di periodo ho filtrato solo i sottoconti clienti?
- [ ] Ogni registrazione: fattura attiva verificata, nessun duplicato, importo <= residuo o confermato, modalita da `pn_document_payment_methods`, conferma utente, rilettura finale?
