# Commesse: modello dati di riferimento (standard)

Questa scheda descrive lo **standard** ProgestNOW. Il descrittore del tenant vince sempre: se un campo qui elencato non esiste o ne esistono altri, usa quelli del descrittore e segnalalo.

## testacommesse (testata)

| Campo | Tipo | Significato |
|---|---|---|
| `cidcommessa` | varchar(20), PK | codice commessa (spesso generato da `commesse_code_struct`, default `{{YEAR}}-{{K}}`) |
| `cdesccommessa` | varchar(255) | descrizione |
| `nidcliente` | int | cliente -> `arccli.codice` |
| `ctipocommessa` | varchar(50) | tipologia (testo libero o codifica del tenant) |
| `ddataapertura` / `ddatachiusura` | datetime | apertura / chiusura |
| `ddataconsegna` | datetime | consegna prevista |
| `criferimento` | varchar(50) | riferimento / CIG |
| `idvaluta` | varchar(5) | valuta -> `tabvalute.codice` |
| `chiusa` | varchar(1) | `N` aperta, `S` chiusa |
| `iddocumento_origine` | varchar(30) | documento da cui e nata (es. ordine cliente) |
| `mnote` | longtext | note |
| `clistmat`, `clistman`, `manodopera_tipologia_2`, `tipologia_manodopera_2` | | listini materiali/manodopera e tipologie (uso dipendente dal tenant) |

Personalizzazioni frequenti da cercare nel descrittore: stato con codifica propria, commessa master/sottocommesse (livello, padre), responsabile, budget in testata, campi verticali (`trade_*`, `zz_*`), tabelle figlie aggiuntive (SAL `testacommesse_sal`, rapportini `testacommesse_rapportini`, `project_task.commessa_id`).

## righecommesse (righe)

| Campo | Tipo | Significato |
|---|---|---|
| `idcomm` | int, PK | id riga |
| `cidcommessa` | varchar(20) | commessa -> `testacommesse.cidcommessa` |
| `cpreventivoconsuntivo` | varchar(1) | `P` Preventivo, `C` Consuntivo |
| `ccostoricavo` | varchar(10) | `COSTO`, `RICAVO` (vuoto = riga anomala) |
| `ddatamovimento` | datetime | data dell'evento (data documento o data registrazione/riferimento contabile) |
| `cidcentrodicosto` | varchar(10) | centro di costo/ricavo -> `centridicosto.cidcentrodicosto` |
| `cidmanodopera` | varchar(10) | risorsa manodopera -> `manodopera.cidmanodopera` |
| `cidarticolo` | varchar(20) | articolo -> `articoli.idmagazzino`; `*` = riga senza articolo (totale documento, descrittiva) |
| `cdescrizione` | varchar(255) | descrizione |
| `nquantitapreventivato` / `nvalorepreventivato` | double | quantita/valore **solo** per righe `P` |
| `nquantitaconsuntivo` / `nvaloreconsuntivo` | double | quantita/valore **solo** per righe `C` |
| `nnumeroriferimento` | int | numero del documento/fattura di riferimento |
| `cidfattura` | varchar(50) | documento di origine (`testapiedefatture.cidfattura`); vuoto se non da documento |
| `nidmovimentocontabile` | int | movimento di prima nota di origine (`arcmovc.nmovc`); vuoto/0 se non da prima nota |
| `nidmovimentomagazzino` | int | movimento di magazzino (raramente valorizzato) |
| `lflagordine` | varchar(1) | `1` riga nata da ordine fornitore (impegnato), `0` no |
| `nnumeroordine`, `nquantitaordinata` | | numero e quantita dell'ordine fornitore |
| `nidfornitore` | int | fornitore -> `arcfor.codice` |
| `cidrepartocomm` | varchar(10) | reparto |
| `csott` | int | sottoconto (righe da prima nota analitica) |
| `stato_riga` | varchar(5) | stato riga (`commesse_righe_stati` dove presente; uso tenant) |

Enum verificati sul descrittore standard (`referencemanual`): `cpreventivoconsuntivo` C=Consuntivo, P=Preventivo; `ccostoricavo` COSTO=Costo, RICAVO=Ricavo; `lflagordine` 0=No, 1=Si.

Distribuzione osservata su un tenant con uso intensivo (ordini di grandezza, non regole): la gran parte delle righe e `C`/`COSTO`, di cui ~60% da prima nota e ~25% da documento; il ricavo consuntivo nasce quasi tutto da prima nota; preventivi solo manuali/import. Esistono poche righe con `ccostoricavo` vuoto.

## centridicosto

`cidcentrodicosto` (PK), `cdesccentrodicosto`, `cunitamisura`, `ctipologia` (raggruppamento -> `tipicentrodicosto.cidtipocentro` dove presente), `obsoleto`.

Il centro di costo puo arrivare da: causale di magazzino (`causalimagazzino.cidcentrodicosto`), fornitore (`arcfor.commesse_centrodicosto`), riga documento (`righefatture.commessa_centrodicosto`), articolo (`articoli.commesse_centrodicosto`), categoria del sottoconto (`arcsott.categoria` = `C<cc>` per costi, `R<cc>` per ricavi) per la prima nota. Quale vince dipende da configurazione e tenant: leggi il valore sulla riga, non ricostruirlo.

## Documenti -> righe (causale di magazzino)

`causalimagazzino.aggiornacommessa`:

| Valore | Righe generate |
|---|---|
| `0` / vuoto | nessuna (il documento puo comunque avere `commessa_id`) |
| `C` | Consuntivo COSTO |
| `R` | Consuntivo RICAVO |
| `CP` | Preventivo COSTO |
| `RP` | Preventivo RICAVO |

Regole di generazione (standard):

- al salvataggio del documento le righe con quel `cidfattura` vengono **cancellate e ricreate**; se il documento perde la commessa le righe spariscono;
- **COSTO**: una riga per ogni riga documento con prezzo totale != 0 (articolo, descrizione, quantita, valore = prezzo netto totale x cambio); segno negativo se la causale scarica con `-`; da ordine fornitore `lflagordine=1` e `nnumeroordine`;
- **RICAVO**: di norma una sola riga per documento (`cidarticolo=*`, descrizione "Documento <causale> n.<numero> - <cliente>", valore = imponibile x cambio); con configurazioni di dettaglio per centro di costo una riga per centro di costo;
- configurazioni che cambiano il comportamento: `feature_documenti_commesse_centrodicostoarticolo`, `feature_documenti_commesse_RP_dettaglio` (valori tenant da verificare, non hardcodare).

## Prima nota -> righe

- Modulo `coge_industriale` (config): con valore `3` la registrazione contabile su sottoconti economici (categoria `C...`/`R...`) apre la **ripartizione su commesse e centri di costo**; le righe create sono `C` con `nidmovimentocontabile = nmovc`, `csott`, valore ripartito, data = data registrazione (o data riferimento se configurato). A ogni salvataggio del movimento le righe vengono ricreate; se il movimento non tocca piu conti economici vengono cancellate.
- Con valore `1` il trasferimento fattura in prima nota puo creare una riga `C`/`RICAVO` di imponibile sulla commessa della fattura (`nidmovimentocontabile` del movimento creato).
- Alcuni tenant hanno routine proprie (descrizione di riga strutturata `|commessa|centro|ordine|qta|fornitore|`, righe automatiche da import): sono delta tenant, non standard.

## Viste di supporto che puoi incontrare

- `qrycommesse_righe`: UNION di righe commessa (`record_source=righecommesse`), righe documento (`righefatture`), costi documento (`testapiedefatture_costi`), rapportini; campi `prev_cons` (PREVENTIVO/CONSUNTIVO), `costo_ricavo`, `valore`, `valore_smart` (costi con segno negativo). Usala come alternativa, **non** in somma con `righecommesse`.
- `qrycommesse_documenti` / `qrycommesse_righe_documenti`: documenti con `commessa_id` e righe con classificazione prev/cons e costo/ricavo derivata dalla causale.
- `riepilogo_commessa`: aggregato con scostamenti (dove presente).

Esistenza e definizione sono per tenant: verificale nel catalogo/descrittore.
