# Ordini a fornitore: modello dati

**Fonti.**
- DB `tenant A` (tenant di riferimento), più `progest`, `tenant B`, `tenant C`, `tenant D` per le differenze tra tenant. Letture del 2026-10-10.
- Descrittori core `testapiedefatture_T`, `qrystatistichedocumenti`, `qrystampafattura` e override di tenant A (`config_personalizzati`).
- Viste `qryordevasi*`, `qrystatistichedocumenti`, `qrydocumenti_documentievasi`, `qrywms_tmp_carichi_ordfor`.
- KB `CAP-20260811-011`, `CAP-20260810-009`.

## 1. Tipologie e flag: cosa è un ordine fornitore

Il discriminante è sempre la coppia `causalimagazzino.tipocausale` + `causalimagazzino.flagidcliente_idfornitore` (C = intestato a cliente, F = intestato a fornitore). Il codice causale cambia da tenant a tenant.

| tipocausale | flag | Significato | Causali su tenant A (documenti dal 2025) |
|---|---|---|---|
| **T** | **F** | **ordine a fornitore** | `ORFOR` (3.429) |
| R | F | richiesta d'offerta a fornitore, **non** è un ordine | `RICHO` (128) |
| R | C | offerta a cliente | `OFF` |
| M | F, `movimentaquantitacaricata = '+'` | carichi: da fornitore `CAR` (3.687), ma anche `CARP` carico da produzione (326), `RIP` rettifica positiva (216), `CARI` carico inventario | |
| M | C | `RCLI` reso da cliente (601), `RIN` rettifica negativa, `SCAP` scarico da produzione | |
| M | F | `RFOR` reso a fornitore (1) | |
| A | F | fatture d'acquisto e autofatture (`AUINB` 1.161 ecc.) | |
| I | C | ordine interno `ORINT` (0) | |

Conseguenze:

- **Ordine fornitore = T + F.** Filtra per tipologia. Se un tenant avesse una causale T con flag C, escludila dichiarandolo.
- **Il carico che evade non si riconosce dalla causale.** Il flag F + `'+'` include anche produzione, rettifiche e inventario. Si riconosce dal collegamento di riga: righe M con `riferimentorigaordine` = `idriga` di una riga d'ordine T.
  - Su tenant A le righe che puntano a righe d'ordine T dal 2025 sono `CAR` 19.087 e `CARP` 2.
  - Su tenant B (102.450) e tenant C (38.399) puntano solo da `CAR`.
- **`causalimagazzino.levadeordfor` non indica chi evade**: su tenant A vale 0 anche su `CAR`, che evade tutti gli ordini.
- **`causalimagazzino.no_evasione = 1`**: causale non soggetta a evasione, da escludere dall'aperto (su tenant A 0 ovunque).

## 2. Testata (`testapiedefatture`, TabellaBase `testapiedefatture_T`)

Query del descriptor core:

```
SELECT tpf.*, ..., cm.*, tabpag.descr AS descrpag,
       qryordevasi.evaso AS evaso, qryordevasi.descrizione_stato AS descrizione_stato,
       round(qryordevasi.totqtaevasa/qryordevasi.totqta*100,2) AS perc_evasione,
       tipologieordine.cdesctipologiaordine AS tipologia_ordine, fos_user.username AS operatore_username,
       qrymindataconsegnaordini.dataconsegna AS dataconsegna_en, DATE_FORMAT(...) AS dataconsegna
FROM testapiedefatture tpf INNER JOIN causalimagazzino cm ON tpf.idcausale=cm.idcausale
LEFT JOIN arcfor AS arccli ON tpf.idfornitore=arccli.codice
LEFT JOIN qryordevasi ON qryordevasi.cidfattura=tpf.cidfattura
LEFT JOIN tipologieordine ... LEFT JOIN fos_user ON tpf.cidoperatore=fos_user.id
LEFT JOIN qrymindataconsegnaordini ...
-- additional_where: AND cm.tipocausale='T'
```

Cosa comporta la query:

- **`arccli` è un alias di `arcfor`**: `arccli.nome` e `arccli.tipocli` sono del fornitore.
- `datafattura` e `dataconsegna` in lista sono stringhe formattate. Filtra su `tpf.datafattura` e usa `dataconsegna_en` / `qrymindataconsegnaordini`.
- **Override di tenant A**: `qryordevasi` e `qrymindataconsegnaordini` sono sostituite da `trg_testapiedefatture_dati AS qryordevasi` e `AS qrymindataconsegnaordini`, con colonne `dataconsegna_min` e `dataconsegna_max`. Su tenant A questa tabella copre tutti i 3.429 ordini dal 2025, ma su molti tenant è incompleta: non usarla come fonte fuori da tenant A.
- `additional_where` filtra solo `tipocausale='T'`, non il flag.

Campi sui dati di tenant A (ordini dal 2025):

| Campo | Significato | Note su tenant A |
|---|---|---|
| `datafattura` | data dell'ordine | — |
| `idfornitore` | fornitore → `arcfor.codice` | 1 ordine senza fornitore |
| `riferimento` | testo libero (rif. offerta del fornitore, numero PO…) | compilato su 3.382, ma solo 11 corrispondono a un `cidfattura` esistente: 8 `ORCLI`, 2 `OFF`, 1 `RICHO`. La UI dei documenti collegati (RULE-LNK-013) lo usa per caricare l'ordine cliente d'origine. Va trattato come collegamento solo se il documento esiste ed è di tipologia O |
| `n_doc_orig` | documento d'origine | stringa `'NULL'` su 3.226; non punta a nessun documento su 3.233 (comprese stringhe libere tipo `ORDEN DE COMPRA N°57/STO/AC` o codici `LISTP…` di altri tenant); punta a `ORCLI` su 71, `RICHO` su 45, un altro `ORFOR` su 75, `OFF` su 3, `CAR` su 2 |
| `nidtipologiaordine` | stato operativo → `tipologieordine` (filtrare `tipocausale` contenente `T`) | 0 su tenant A (non usato) |
| `cidoperatore` | chi ha emesso l'ordine (buyer) → `fos_user` | il dato utile sugli acquisti |
| `codage` | agente | valorizzato su 7 ordini: nessun significato sugli acquisti |
| `idvaluta`, `cambio` | valuta | dal 2025: EUR 3.418 (1 con cambio ≠ 1), USD 5, FFC 6. Prima del 2025 compaiono codici non normalizzati: `''` (152–527 ordini l'anno nel 2019–2021, presumibilmente la valuta di default), `EURO` (1.436 nel 2019), `US$`, accanto a `EUR`/`USD`. Anagrafica `tabvalute` (`codice`, `cambio`, `cambio_euro`, `valuta_default`): su tenant A EUR è default, USD `cambio` 0,86 |
| `totaleimponibile` | valore dell'intero ordine | non è il residuo |

### Stati (`tipologieordine`) su altri tenant

| Tenant | Stati con T | Note |
|---|---|---|
| tenant A | nessuno in uso | — |
| tenant C | 6 IN PREPARAZIONE - NON INVIATO A FOR, 7 INVIATO - ATTESA CONFERMA, 8 CONFERMATO | stati anche per O (clienti) e M (11 CARICO DA VALIDARE, 12 CARICO VALIDATO) |
| tenant B | 3 ANNULLATO (`T,O`), 9 DA INVIARE, 10 INVIATO, 11 INVIATO, IN ATTESA PAGAMENTO (`T,P`), 17 PAGATO (`T,P`) | ordini dal 2025 con `evaso = N`: 2.524 in INVIATO, 272 DA INVIARE, 72 IN ATTESA PAGAMENTO, 31 PAGATO, 31 senza stato, 0 ANNULLATO |

`tipologieordine.tipocausale` è un elenco separato da virgole: filtralo con `contains` `T`. Campi: `nidtipologiaordine`, `cdesctipologiaordine`, `cbloccato`, `tipocausale`, `causali`, `ordering`.

## 3. Righe (`righefatture`)

- `quantita`, `quantitaevasa`, `levasioneasaldo` (vale "chiusa" solo `S`; su tenant A compaiono anche `''`, `0` nello storico e `N`, mai NULL; su altri tenant può essere NULL), `dataconsegna`, `idriga`, `idmagazzino`, `prezzounitario`, `percentualesconto_1..3`, `importototale` (totale riga netto sconti, IVA esclusa).
- **Residuo di riga** = 0 se `levasioneasaldo = 'S'` o `quantitaevasa >= quantita`; altrimenti `quantita − quantitaevasa`. È la stessa formula degli ordini clienti e di `qrystatistichedocumenti.riga_quantitadaevadere`.
- **Valore residuo** = residuo × `importototale` / `quantita`. È netto degli sconti di riga e non comprende spese o sconti di testata.
- **Righe `*`**: 434 dal 2025. 54 hanno quantità e 20 importo, 11 restano aperte e mantengono 5 ordini a `evaso = N`.
- **Data di consegna** compilata molto più che sugli ordini clienti: 12.851 righe su 19.408 dal 2025. Il ritardo è quindi un'analisi significativa.

## 4. Evasione

### Meccanismo

- Il carico (M) ha righe con `riferimentorigaordine = idriga` della riga d'ordine.
- Al salvataggio, il motore aggiorna `quantitaevasa` e `levasioneasaldo` della riga d'ordine (RULE-DOC-019).
- Per i ricevimenti WMS lo fa `aggiornaQuantitaEvasa` dopo la conferma della temporanea (RULE-WRC-005).

### Verifica su tenant A (righe ordine 2026, escluse le `*`: 8.456)

- righe con almeno un `CAR` collegato: 7.874, di cui 7.869 con `quantitaevasa` uguale alla somma delle quantità dei carichi;
- evasione oltre l'ordinato: 50;
- chiuse a saldo senza alcun carico: 132;
- chiuse a saldo con evaso < ordinato: 148;
- `quantitaevasa > 0` senza nessun documento che le referenzi: 6.

### Regole

- La fonte autorevole è **`quantitaevasa` + `levasioneasaldo` sulla riga d'ordine**.
- Non sommare i documenti con `riferimentorigaordine`: su altri tenant il riferimento può essere propagato anche a fatture d'acquisto (A, RULE-LNK-003) o a richieste di acquisto (I, RULE-LNK-013). Su tenant A, tenant B e tenant C oggi puntano alle righe T solo carichi M.
- Per sapere **chi** ha evaso: `pn_document_linked_documents`.
  - Legge `qrydocumenti_documentievasi`, cioè righe D/F/M con `riferimentorigaordine` verso la riga d'origine, quindi restituisce i carichi di un ordine.
  - **Non** restituisce l'ordine cliente da `riferimento`, né le richieste d'offerta da `n_doc_orig`.

### `qryordevasi` (stato per ordine)

Colonne comuni: `cidfattura`, `evaso`, `descrizione_stato`, `totqta`, `totqtaevasa`, `totqtaresidua`.

`qryordevasi_00` somma le righe di O, T e I, **comprese le `*`**:

```
totqtaevasa       = SUM(IF(quantitaevasa >= quantita OR levasioneasaldo='S', quantita, quantitaevasa))   -- saldo = tutto evaso
totqtaevasa_reale = SUM(quantitaevasa)                                                                 -- ricevuto reale (anche eccedenze)
totqta            = SUM(quantita)
```

Su `qryordevasi_0`:
- `evaso` = N se `totqtaevasa <= 0`, S se `totqtaevasa = totqta`, N se parziale;
- `descrizione_stato` = `round(totqtaevasa_reale) / round(totqta)`.

Differenze tra tenant:

| Tenant | `qryordevasi` | `totqtaevasa_reale` esposto | Note |
|---|---|---|---|
| tenant A | vista su `qryordevasi_0` + `qryliste_ordini` | no (solo in `qryordevasi_00`) | `evaso = 'P'` se l'ordine è in una lista; dal 2025: S 3.273, N 156 |
| progest, tenant B | vista su `trg_qryordevasi` (materializzata) | sì | — |
| altri | variabili | — | leggi i valori distinti prima di interpretarli |

Gli ordini aperti contati dalle righe (151 su tenant A) e gli `evaso = N` (156) non coincidono: 5 ordini sono N solo per righe `*`.

### Ricevimenti parziali WMS (CAP-20260811-011)

- `wms_tmp_carichi_ordfor` è una temporanea per utente; la vista `qrywms_tmp_carichi_ordfor` la presenta, con colonne:
  - `carico_cidfattura`, `carico_idriga`, `carico_quantita`, `carico_idfornitore`, `carico_fornitore_nome`;
  - `ordf_cidfattura`, `ordf_idriga`, `ordf_quantita_residua`, `ordf_dataconsegna`;
  - `user_id`.
- Contiene le attribuzioni carico → riga d'ordine ancora da confermare. **Finché non si conferma, l'ordine non è evaso.**
- Esiste solo su alcuni tenant: tenant D, con TabellaBase `qrywms_tmp_carichi_ordfor`, 13 righe e 2 ordini al 2026-10-10, più alcuni database `fix`. Su tenant A non esiste.
- Va letta, non toccata mai: la svuotano la rigenerazione (RULE-WRC-004) e la conferma.
- DIAG-WRC-002: evasione mancante o errata dopo la conferma.
- **FIND-WRC-002** (finding interno engineering, citato in DIAG-WRC-002): alla conferma, la quantità residua senza riferimento eredita l'ultimo `ordf_idriga` del gruppo, quindi la riga d'ordine risulta evasa oltre l'ordinato.

## 5. Puntualità: dati di tenant A (righe ordine 2026 con almeno un carico M)

- 7.874 righe, di cui 2.223 senza data di consegna.
- Delle 5.651 con data: 1.113 con ultimo carico entro la data (20%), 1.139 con primo carico entro la data.
- Ritardo medio (ultimo carico − data consegna): 11,3 giorni; tra le sole righe in ritardo, 14,9 giorni.
- 299 righe consegnate in più carichi.
- Per fornitore (righe → puntuali, ritardo medio):
  - FIP 778 → 322, 4,6 gg;
  - HIDROTEN 712 → 202, 4,1 gg;
  - PLIMAT 685 → 51, 19,9 gg;
  - GARVER 342 → 8, 11,4 gg;
  - FUCOLI-SOMEPAL 288 → 49, 9,1 gg.

La `dataconsegna` è la data richiesta sull'ordine, non una data confermata dal fornitore. Va dichiarato.

## 6. Ordinato aperto: dati di tenant A (ordini dal 2025, righe non `*`)

- 495 righe aperte in 151 ordini, 62 fornitori, quantità residua ….
- Righe in ritardo: 319, con ritardo medio 52,6 giorni (massimo 596) e valore … EUR. Righe senza data: 61.
- Valore in arrivo: … (tutte le righe aperte sono in EUR).
- Ordini aperti da oltre 180 giorni: 23. Di questi, 8 senza nessun ricevimento (ordini fermi), per una quantità di 2.304.

## 7. Riferimenti KB

- `RULE-DOC-019`: aggiornamento di `quantitaevasa`/`levasioneasaldo` al salvataggio del documento evasore.
- `RULE-WRC-005`: conferma della temporanea WMS ed evasione degli ordini fornitore. Ultimo `ordf_idriga` ereditato: FIND-WRC-002.
- `RULE-WRC-004`: pulizia e rigenerazione della temporanea.
- `DIAG-WRC-002`: evasione degli ordini fornitore mancante o errata.
- `CAP-20260811-011`: ricevimenti parziali WMS da ordini fornitore. Vedi anche `DATA-WRC-001` (temporanea), `DATA-WRC-002` (vista), `QRY-WRC-002` (residui).
- `RULE-LNK-003`: ordini evasi tramite `riferimentorigaordine` da F/D/A.
- `RULE-LNK-013`: collegamenti di un ordine fornitore (evasori, ordine cliente da `riferimento`, richieste di acquisto I, impegni da `n_doc_orig`).
- `CAP-20260810-009`: consultare i documenti collegati.
