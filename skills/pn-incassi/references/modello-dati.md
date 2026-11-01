# Incassi: modello dati di riferimento (standard)

Scheda dello **standard** ProgestNOW, verificata il 2026-10-07 sulle definizioni delle viste e sui dati dei tenant `progest` e `tenant B` (definizioni identiche nei due tenant). Il descrittore del tenant vince sempre: se un campo non esiste o ne esistono altri, usa quelli del descrittore e segnalalo.

## Catena delle viste

```
testapiedefatture ──(trigger)──> trg_qrydocumenti_rifpa ──> qrydocumenti_rifpa
testapiedefatture (NC) ─(trigger)> trg_qrydocumenti_rifpa_ndccollegate ──> qrydocumenti_rifpa_ndccollegate

arcmovc ⋈ tabcauc (tipo1 IN 9,1)  ∪  qrydocumenti_rifpa_ndccollegate   ==>  qryfatture_incassi
qrydocumenti_rifpa ⋈ testapiedefatture ⟕ qryfatture_incassi (rifpa + csott), tipocausale='F', GROUP BY fattura
                                                                        ==>  qryfatture_situazione_incassi
```

### `qrydocumenti_rifpa` (tabella `trg_qrydocumenti_rifpa`, aggiornata da trigger)

Una riga per documento con `causalimagazzino.tipocausale` in `F` (fattura), `C` (nota di credito), `A` (acquisto). Ricalcolata dai trigger su `testapiedefatture` quando cambiano causale, anno, numero, cliente, fornitore o numero documento originale.

| Campo | Valore |
|---|---|
| `rifpa_cidfattura` | `cidfattura` |
| `rifpa_anno`, `rifpa_idcausale` | anno e causale |
| `rifpa_standard` | `RIGHT(anno,1) + '/' + numerofattura` (es. `6/421`) |
| `rifpa_complete` | `rifpa_standard + idcausale` (es. `6/421NF`) |
| `rifpa_idcliente` / `rifpa_idfornitore` | cliente / fornitore |
| `rifpa_doc_orig` | `RIGHT(anno,1) + '/' + n_doc_orig` (usato per i documenti passivi) |

### `qrydocumenti_rifpa_ndccollegate`

Note di credito (`tipocausale = C`) **non contabilizzate** (`bloccato` NULL o `0`) che hanno `n_doc_orig` = `cidfattura` di una fattura esistente. `rifpa_standard`/`rifpa_complete` sono quelli **della fattura collegata**; `totaledocumento`, `data_ndc`, `numero`, `anno` sono della NC.

`bloccato = 1` sul documento = documento trasferito in prima nota (impostato dalla contabilizzazione in `PrimanotaController`).

### `qryfatture_incassi`

```sql
SELECT 'arcmovc', nmovc, DATE_FORMAT(datareg,'%Y-%m-%d'), descr, impavere, rifpa, csott
  FROM arcmovc JOIN tabcauc ON caumovc = tabcauc.codice
 WHERE tabcauc.tipo1 = 9 OR tabcauc.tipo1 = 1
UNION
SELECT 'testapiedefatture', rifpa_cidfattura, data_ndc, CONCAT('NDC n.',numero,' del ',anno), totaledocumento, rifpa_standard, rifpa_idcliente
  FROM qrydocumenti_rifpa_ndccollegate
```

Note:

- `UNION` (non `UNION ALL`): due righe identiche in tutte le colonne vengono fuse (raro, ma possibile con righe uguali nella stessa registrazione).
- `tipo1 = 9` = causali finanziarie (incassi, pagamenti, RIBA, insoluti, giroconti, stipendi...). `tipo1 = 1` = note di credito di vendita. Le causali di fattura emessa hanno `tipo1 = 0` e non entrano.
- Le righe in DARE (insoluti, contropartite banca) entrano con `importo = 0`.
- Contiene righe su ogni sottoconto. Le righe clienti sono una minoranza del totale della vista.tipos = 'C'` (`F` fornitori, `S` conti generici).

### `qryfatture_situazione_incassi`

```sql
SELECT r.*, tpf.totaledocumento,
       IFNULL(SUM(i.importo),0)                        AS importo_incassato,
       tpf.totaledocumento - IFNULL(SUM(i.importo),0)  AS importo_residuo,
       CASE WHEN residuo <= 0 THEN 'incassato'
            WHEN incassato > 0 AND residuo > 0 THEN 'incassato_parziale'
            ELSE 'nessun_incasso' END                  AS stato_incasso
  FROM qrydocumenti_rifpa r
  JOIN testapiedefatture tpf ON tpf.cidfattura = r.rifpa_cidfattura
  LEFT JOIN qryfatture_incassi i ON i.rifpa = r.rifpa_standard AND i.csott = r.rifpa_idcliente
  LEFT JOIN causalimagazzino cm ON cm.idcausale = tpf.idcausale
 WHERE cm.tipocausale = 'F'
 GROUP BY r.rifpa_cidfattura
```

- Solo fatture (`F`): le NC non hanno riga propria, entrano come incasso della fattura collegata.
- Il descrittore TabellaBase aggiunge `LEFT JOIN arccli ON rifpa_idcliente = arccli.codice` (colonne `arccli_codice`, `arccli_nome`; campo `rifpa_idcliente` come reference ad `arccli`). Il descrittore di `qryfatture_incassi` aggiunge `LEFT JOIN arcsott ON csott = arcsott.codice`.
- Nessuna gestione valuta: `totaledocumento` e nella valuta del documento, `impavere` in valuta di conto.

## Calcolo del tool `pn_document_receipts_status` (ContabilitaService::getDocumentoIncassiStatus)

- `rifpa = RIGHT(anno,1)/numerofattura`, righe `arcmovc` con `tabcauc.tipo1 IN (9,1)`, `rifpa` e `csott = idcliente`;
- `importo` riga = `impavere - impdare` (**insoluti e storni sottratti**);
- + NC collegate non contabilizzate se `feature_documento_incassi_ndcnonreg` = `1` (default);
- `remaining_total` = somma `importoscadenza_1..12` - incassato, azzerato se < 0,01.

Differenze con la vista: DARE sottratto; base scadenze invece di totale documento; residuo mai negativo.

## Registrazione (ContabilitaService::registraIncasso / registraIncassoMultiplo)

- Configurazione da `tabmodalitapagamento`: `caumovc` (causale contabile incassi, deve esistere in `tabcauc`), `csott` (sottoconto contropartita in DARE, deve esistere in `arcsott`). `caumovc_pagamenti` serve ai pagamenti fornitori.
- Esercizio da `findEsercizio(data)`: errore `Esercizio contabile NON definito per la data` se manca.
- Single: 2 righe (cliente AVERE con `rifpa`, contropartita DARE con stesso `rifpa`). Nessun controllo di importo vs residuo, nessun controllo sul tipo documento.
- Bulk: riga 1 contropartita DARE (totale, senza `rifpa`), poi una riga cliente AVERE per fattura con il suo `rifpa`.
- Salvataggio con `savePn` (stesso motore della prima nota UI). Risposta: `success` (+ `importi_per_fattura` nel bulk), nessun `nmovc`.

Modalita osservate: progest `CCRED` (carta di credito, causale 21, conto 2440), `CONTANTI` (21, conto 1); tenant B `assegno`, `bonifico`, `carta_di_pagamento`, `contanti`, `RiBa` (causale 21) e `nota_di_credito` (causale 21NC). Sono dati tenant: leggili sempre con `pn_document_payment_methods`.

## Causali contabili che contano (esempi progest, `tabcauc`)

| Causale | Descrizione | tipo1 | Effetto sulla partita cliente |
|---|---|---|---|
| `01` | FATT. EMESSA | 0 | DARE: apre la partita (non entra nelle viste) |
| `02`, `02S` | NOTA CREDITO | 1 | AVERE: riduce la partita (entra come incasso) |
| `21` | INCASSATA FT | 9 | AVERE: incasso |
| `22` | ACCREDITO FT | 9 | AVERE: incasso (bonifico) |
| `26` | RIC. BANCARIA | 9 | AVERE: RIBA presentata, partita chiusa contabilmente |
| `12` | R.B. INSOLUTA | 9 | DARE: riapre la partita (**ignorata dalla vista**) |
| `14` | ASSEGNO INSOLUTO | 9 | DARE: riapre la partita (**ignorata dalla vista**) |

I codici cambiano per tenant (tenant B: fattura `CF1`, incasso `INCASSOCLI`): ragiona su `tipo1` e sul segno, non sul codice.

## Casi tipici (schematizzati)

- **RIBA insoluta poi riaccreditata**: fattura DARE, RIBA AVERE, riaccredito AVERE, insoluto DARE. Saldo contabile 0, ma la vista conta incassato il doppio del totale e residuo negativo pari al totale.
- **RIBA su piu scadenze con NC e insoluto parziale**: la vista non sottrae l'insoluto, il residuo risulta negativo per l'importo insoluto.
- **`rifpa` errato in prima nota**: piu fatture registrate sulla stessa partita e un accredito cumulativo; la vista attribuisce tutto l'accredito alla fattura.
- **Fatture importate da gestionale esterno**: decine di registrazioni di fattura sulla stessa partita e un incasso cumulativo; su tenant con molte importazioni la vista non e utilizzabile per un totale incassato senza escludere le anomalie.
