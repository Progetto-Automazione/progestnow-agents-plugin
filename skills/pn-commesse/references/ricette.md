# Commesse: ricette operative

Tutte le ricette presuppongono il protocollo di apertura (descrittori `testacommesse` e `righecommesse` letti in questo job). Sostituisci i nomi campo con quelli del descrittore se diversi. Sintassi filtri: skill `pn-tabellabase-query`.

## R1. Scheda di una commessa

1. `pn_tabellabase_single("testacommesse", <cidcommessa>)` (oppure `list` con `search` su `testacommesse.cidcommessa` o `contains` su `cdesccommessa` se l'utente da solo la descrizione; con piu risultati chiedi quale).
2. Totali con la ricetta standard di SKILL.md §5 senza `dimensions`.
3. Riporta: codice, descrizione, cliente, stato (secondo il descrittore), date, e la matrice

| | Preventivo | Consuntivo | Scostamento |
|---|---|---|---|
| Costi | costo_prev | costo_cons | costo_cons - costo_prev |
| Ricavi | ricavo_prev | ricavo_cons | ricavo_cons - ricavo_prev |
| Margine | ricavo_prev - costo_prev | ricavo_cons - costo_cons | |

## R2. Analisi per centro di costo

Ricetta standard con `dimensions: ["righecommesse.cidcentrodicosto"]`. Per le descrizioni: `pn_tabellabase_list` su `centridicosto` con `in` sui codici ottenuti (una chiamata). Evidenzia i centri con consuntivo > preventivo e i centri con consuntivo ma **senza** preventivo (costi non budgettati).

## R3. Andamento nel tempo

Ricetta standard + `date_buckets: [{"name":"mese","field":"righecommesse.ddatamovimento","bucket":"month"}]`. Per il cumulato calcola la somma progressiva sui bucket ordinati.

## R4. Confronto tra commesse (portafoglio)

1. Seleziona le commesse da `testacommesse` (aperte: `chiusa = N` o stato del tenant; per cliente: `nidcliente`; per periodo: `ddataapertura`), con `output_fields` minimi.
2. Ricetta standard con `dimensions: ["righecommesse.cidcommessa"]` e filtro `in` sui codici (o filtri sulla testata tramite i campi `tc.*` se la query del descrittore fa join `tc`).
3. Top N per margine o sforamento: `order_by` su una misura + `options.limit_groups`; la differenza ricavi-costi va calcolata dopo (non e una misura nativa): con molti gruppi esporta con `output=url` e calcola nel sandbox.

## R5. Provenienza delle righe di una commessa

Aggregate su `righecommesse` filtrato per commessa, misure condizionali:

- `da_documento`: `count` con filtro `cidfattura is_not_empty`;
- `da_prima_nota`: `count` con filtro `nidmovimentocontabile > 0`;
- `manuali`: `count` con filtri `cidfattura is_empty` e `group_or` [`nidmovimentocontabile is_empty`, `nidmovimentocontabile = 0`].

Stesse misure con `sum` di `nvaloreconsuntivo` per dire *quanto* valore viene da ciascuna fonte.

## R6. Documenti collegati a una commessa

- **Collegati** (testata con `commessa_id`): `pn_tabellabase_descriptor` del descrittore documenti richiesto (`testapiedefatture_F`, `_T`, `_O`, `_D`, `_R`, ...), individua l'alias della `FROM` (standard `tpf`), poi `pn_tabellabase_list` con `{"field":"tpf.commessa_id","op":"=","type":"string","value":"<cidcommessa>"}`. Se torna 0 righe con documenti che sai esistere, controlla nome/alias del campo nella query del descrittore.
- **Che hanno prodotto righe**: aggregate su `righecommesse` con `dimensions: ["righecommesse.cidfattura","righecommesse.nnumeroriferimento"]` e `cidfattura is_not_empty`; dettaglio con `pn_document_read`.
- Differenze tra i due elenchi: documenti collegati con causale che non aggiorna la commessa (`aggiornacommessa=0`), oppure righe orfane di un documento a cui e stata tolta la commessa: segnalale.

## R7. Righe generate da un documento

`pn_tabellabase_list` su `righecommesse` con `righecommesse.cidfattura = <cidfattura>`, `output_fields` minimi. Se il documento non ha righe: verifica `commessa_id` del documento e `aggiornacommessa` della sua causale (`causalimagazzino`).

## R8. Ripartizione di un movimento di prima nota

`pn_tabellabase_list` su `righecommesse` con `righecommesse.nidmovimentocontabile = <nmovc>`: per ogni riga commessa, centro di costo, `csott`, costo/ricavo, valore. Il totale ripartito dovrebbe quadrare con il saldo dei conti economici del movimento: verificalo con `pn_coge_partitario_search` (o la TabellaBase di prima nota) se l'utente chiede "e tutto ripartito?".

## R9. Doppio conteggio documento + prima nota

Aggregate su `righecommesse` filtrato per commessa, `cpreventivoconsuntivo = C`, `ccostoricavo = RICAVO`, `dimensions: ["righecommesse.nnumeroriferimento"]`, misure `count` e `count_distinct` su `cidfattura` / `nidmovimentocontabile`, `having count > 1`. Gruppi con una riga da documento e una da prima nota per lo stesso numero = probabile doppio conteggio: mostrali, non correggerli.

## R10. Inserire un preventivo (budget)

1. Raccogli dall'utente: commessa, per ogni voce centro di costo, COSTO o RICAVO, descrizione, quantita, valore, data.
2. Verifica che i centri di costo esistano (`centridicosto`, filtro `in`).
3. Controlla se esiste gia un preventivo (aggregate `P` per centro di costo): se si, chiedi se aggiungere, sostituire (cancellare le righe `P` manuali esistenti) o annullare.
4. Mostra la tabella delle righe da inserire (`cpreventivoconsuntivo=P`, valori in `nquantitapreventivato`/`nvalorepreventivato`, colonne consuntivo a 0) e attendi conferma.
5. `pn_tabellabase_new` su `righecommesse` (o bulk insert per molte righe), poi rileggi i totali con la ricetta standard e riportali.

## Errori tipici

| Sintomo | Causa probabile | Rimedio |
|---|---|---|
| 0 righe per una commessa esistente | filtro `cidcommessa` non qualificato o codice con spazi/maiuscole diverse | `righecommesse.cidcommessa`; verifica il codice esatto su `testacommesse` |
| Totali enormi o doppi | sommati `nvalorepreventivato` e `nvaloreconsuntivo` insieme, o `righecommesse` + vista UNION | separa P/C (§5), una sola fonte |
| Ricavo consuntivo doppio | stessa fattura da documento e da prima nota | R9, segnala |
| Documento collegato senza righe | causale con `aggiornacommessa=0` o prezzi a 0 | spiegalo, non creare righe a mano |
| Riga "sparita" dopo modifica documento | rigenerazione righe al salvataggio | normale: le righe da documento seguono il documento |
| L'utente parla di fasi/lavorazioni | e una commessa di produzione MRP | `commesse_produzione`, non questa skill |
