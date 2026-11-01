# Definizioni di fatturato e modello dati

## 1. Tipologie documento (`causalimagazzino.tipocausale`)

Ogni documento (`testapiedefatture`) ha una causale (`idcausale`); la causale ha una tipologia. La tipologia, non il codice, decide se un documento e fatturato.

| tipocausale | Significato | Nel fatturato |
|---|---|---|
| F | fatture e note di debito (incluse fatture di acconto, PA, storiche, elettroniche) | **si, in somma** |
| C | note di credito | **si, in sottrazione** |
| P | proforma | no |
| A | documenti di acquisto e autofatture (TD16-TD19 integrazioni/autofatture, FACQ, VF fattura fornitore) | no |
| R | offerte | no |
| O | ordini cliente | no |
| D | DDT | no |
| T | ordini fornitore | no |
| M | carichi e movimenti di magazzino | no |
| I | documenti interni | no |

Causali per tipologia nei tenant verificati (2026-10-10):

| Tenant | F | C | A | P |
|---|---|---|---|---|
| progest | AF, ND, NF, NFA, NFACC, NFE, NFI | NDC, NDCE | AUB17, AUEXS, AUINB, AUINS, AURCI, VF | PROFO |
| tenant J | ND, NF, NFA, NFB, NFPA, NFPAS, NFS | NC, NCPA, NCPAS, NCS | AUEXB, AUEXS, AUINB, AUINS, AURCI, FACQ | PROFO |
| tenant E | ND, NF, NF-GS, NFA, NFANT, NFCEA, NFCEE, NFEC | NDC, NDCCE | AUEXB, AUEXS, AUINB, AUINS, AURCI, FACQ | PROFO |
| inpath | ND, NDE, NF, NFE | NCE, NDC | - | - |

Note:

- Lo stesso codice cambia significato: NFA = "fattura acconto" su progest, "fattura accompagnatoria" su tenant J e tenant E. Leggi sempre la descrizione con `pn_document_types`.
- Su progest `AF` ("auto fattura/nota credito") e `NFI` ("fattura uso interno x statistiche") sono di tipologia F: per la definizione di default restano incluse. Se nel periodo hanno movimenti, segnalali con il loro importo, cosi l'utente puo decidere se escluderli.
- Le autofatture AU* (tipologia A) **non** sono fatturato: nel job 872 di progest erano state mescolate ai documenti del periodo.
- Le note di credito sono salvate con importi **positivi** (verificato su progest e tenant J, 2026: nessun `totaleimponibile` negativo): si sottraggono.
- Acconti (TD02): la fattura di saldo storna l'acconto, quindi includerli non duplica il fatturato sul lungo periodo. In un periodo breve un acconto senza il relativo saldo anticipa ricavo: riportane l'importo.

## 2. Campi di `testapiedefatture` (alias SQL `tpf`)

| Campo | Significato |
|---|---|
| `datafattura` | data documento (il filtro di periodo del fatturato) |
| `anno` | anno del documento (numerazione) |
| `totaleimponibile` | imponibile, netto IVA: **l'importo del fatturato** |
| `totaledocumento` | totale IVA inclusa (fatturato lordo, solo su richiesta) |
| `totalemerce` | totale righe merce |
| `totalespese` | spese di piede (trasporto, bancarie) |
| `totaleimposta` | IVA |
| `totaleapagare` | netto a pagare (dopo acconti/ritenute) |
| `idvaluta`, `cambio` | valuta del documento e cambio |
| `idcliente` | cliente (`arccli.codice`) |
| `codage` | agente (`agenti.idagente`) |
| `idcausale` | causale (join con `causalimagazzino`) |

## 3. Le tre definizioni del prodotto

Usale per spiegare una differenza con una schermata, non come default.

### 3.1 Tab "Dati gestionali" del cliente (RULE-GES-003, QRY-GES-001, CAP-20260811-013)

- Query primaria: `SUM(arcmovi.imponibile)` sul sottoconto del cliente, raggruppato per **anno di registrazione** contabile (`year(datareg)`), ultimi 5 anni.
- Se la primaria e vuota: `SUM(testapiedefatture.totaledocumento)` delle sole causali di tipologia F, per `anno`.
- Differenze dal default: fonte contabile (data di registrazione, non data fattura) oppure, nel ripiego, **IVA inclusa** e **note di credito non sottratte**.

### 3.2 Dashboard Statistica CRM (QRY-20260919-004, CAP-20260919-005, verticale spedizionieri)

- `SUM(IF(cm.tipocausale = 'C', -1, 1) * totaleimponibile)` su tipologie F e C, per `datafattura`, clienti non obsoleti.
- Coincide con il default di questa skill. La query applicativa applica anche il cambio valuta e i filtri di team, che la query diagnostica non riproduce.

### 3.3 Viste statistiche (`qrystatistichedocumenti`)

- Una riga per **riga di documento**. Campi `testa_*` (testata), `riga_*` (riga), `piede_*` (piede ripetuto su ogni riga).
- I campi `*_stat` applicano `causalimagazzino.segno_statistica` (sulle NC risultano negativi se il segno e `-`).
- Si sommano solo i `riga_*` (`riga_importototale_stat`, `riga_importototale`). Sommare i `piede_*` moltiplica il totale per il numero di righe del documento (tenant J, febbraio 2026, NFS: `piede_totali_imponibile_stat` … contro …).
- Le spese di piede non sono incluse nelle righe.

## 4. Configurazione statistica incoerente tra tenant

`tipo_statistica` e `segno_statistica` di `causalimagazzino` non sono affidabili come definizione di fatturato:

| Tenant | Anomalia |
|---|---|
| inpath | NC (`NDC`, `NCE`) con `tipo_statistica` vuoto e segno `+`; ND, NDE, NFE con `tipo_statistica` vuoto |
| tenant E | `NDCCE` (nota di credito CEE/extra CEE) con segno `+` |
| progest | `NDCE` (nota di credito elettronica) con `tipo_statistica` vuoto e segno `+`; `AF` e `ND` con `tipo_statistica` vuoto; `NFI` "uso interno x statistiche" |
| tenant J | coerente (F `+`, C `-`) |

Conseguenze:

- con i campi `_stat` una NC con segno `+` viene **sommata** al fatturato invece che sottratta;
- un filtro `tipo_statistica = F` esclude in silenzio causali di vendita reali.

Per questo il default usa `tipocausale` e il segno esplicito F − C. I campi `_stat` si usano solo se l'utente chiede "come nelle statistiche del gestionale", e in quel caso le anomalie del tenant vanno elencate nella risposta.

## 5. Fuori da questa skill

- Fatturato contabile e IVA da prima nota (`arcmovi`, registri, liquidazioni): agente `PNOWCONTABILITA`.
- Incassato e residuo: skill `pn-incassi`.
- Margini e costi: skill `pn-statistiche` (`pn_statistiche_query`, stessi numeri della pagina Statistiche).
