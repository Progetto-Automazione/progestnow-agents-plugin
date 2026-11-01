# Gruppi, filtri, misure e limiti di `pn_statistiche_query`

La disponibilita reale sul tenant (colonne della vista attiva, gruppi tenant D) e in `pn_statistiche_catalog` (`groups[].available`, `filters[].available`).

## Gruppi (`groups`, 1-5 livelli)

| Chiave | Titolo pagina | Codice (`groupN_code`) | Descrizione (`groupN_label`) | Note |
|---|---|---|---|---|
| `anno` | Anno | `YEAR(datafattura)` | = codice | anno della data documento (non il filtro `anno`) |
| `mese` | Mese | `01`..`12` | nome del mese | **non contiene l'anno** |
| `causale` | Causale | `idcausale` | descrizione causale | |
| `tipocausale` | Tipologia causale | `F`,`C`,`O`,`R`,`T`,`M`,`D` | Fattura, Nota di credito, Ordine cliente, Offerta, Ordine fornitore, Movimento/carico, DDT | solo AI; serve per separare T e M nell'acquistato |
| `codricavo` | ricavo | conto ricavo | `arcsott.descr` | |
| `codricavorighefatture` | ricavo | conto ricavo | `arcsott.descr` | identico a `codricavo` |
| `cliente` | Cliente | `idcliente` | `arccli.nome` | |
| `tipocli` | Tipocli | tipologia cliente | `tabtipoc.descr` | |
| `macrotipoc` | Macro cat.cli | `codice_macro` | `tabtipoc_macro.descr` | |
| `sorgente_code` | Sorgente cli | sorgente | `arccli_sorgenti.titolo` | |
| `agente` | Agente | `codage` | `agenti.nome` | codice vuoto = senza agente |
| `nazione` | Nazione | `nazione` | `nazioni.cdescnazione` | |
| `zona` | Zona | `codzona` | `tabzone.descr` | |
| `prov` | Provincia | `prov` | = codice | |
| `diversadestinazione` | Diversa Destinazione | id destinazione | destinazione - citta | assente nelle viste dei costi 1/2 |
| `articolo` | Articolo | `idmagazzino` | descrizione articolo | in pagina compare come "codice - descrizione" in una colonna |
| `tipoart` | Tipoart | `idtipologia` | `tipologie.descrizionetipologia` | |
| `catmerc` | CatMreceologica | `idcategoriamerceologica` | descrizione categoria | refuso del titolo come in pagina |
| `reparto` | Reparto | `idreparto` | `reparti.descrizionereparto` | |
| `collezione` | Collezione | `collezione_codice` | `articoli_collezioni.descrizione` | assente nelle viste dei costi 1/2 |
| `idfornitore` | Fornitore | fornitore del documento | `arcfor.nome` | assente nelle viste dei costi 1/2 |
| `idfornitore1` | Fornitore art. | fornitore abituale dell'articolo | `arcfor.nome` | |
| `cogal_*`, `codice_varianteelement1/2` | Linea, Mastro, Forma, Confezione, Nazione, Composizione, Tipo Commercializzato, Sottoclasse, Responsabile Commerciale, Taglia, Colore | colonne `zz_cogal_*` | anagrafiche tenant D | solo tenant tenant D |

## Filtri (`filters`)

Via MCP i filtri multivalore sono **array di stringhe** (1-100 valori, 1-100 caratteri), anche con un solo valore: un array diventa `IN`.

| Chiave | Tipo | Significato |
|---|---|---|
| `date_from`, `date_to` | stringa `YYYY-MM-DD` | data documento (inclusa); `date_from <= date_to` |
| `anno` | array di `YYYY` | anno di **numerazione** del documento |
| `tipocausale` | array enum `F,C,O,R,T,M,D` | tipologia della causale (solo AI) |
| `idcausale` | array | codice causale |
| `idcliente`, `tipocli`, `macrotipoc`, `sorgente_code` | array | cliente e sue classificazioni |
| `codage` | array | agente |
| `nazione`, `codzona`, `prov` | array | territorio |
| `idmagazzino` | array | codice articolo esatto |
| `idmagazzino_like` | stringa | codice articolo con jolly `%` e `_` |
| `idtipologia`, `idreparto`, `idcategoriamerceologica`, `marca_codice` | array | classificazioni articolo |
| `idfornitore`, `collezione_codice` | array | assenti nelle viste dei costi 1/2 |
| `zz_cogal_*`, `codice_varianteelement1/2` | array | solo tenant D |

Non esistono filtri liberi, `where`, `sql`, `customsearch` o `user_id`: il tipo statistica, la regola dei doppioni DDT/fattura e la vista dei costi sono applicati automaticamente.

## Misure (`measures`)

| Misura | Significato |
|---|---|
| `qta` | somma quantita |
| `valore` | somma valore netto IVA in euro |
| `costo` | somma costo (secondo il tipo di costo del catalogo) |
| `margine` | valore − costo |
| `margine_pct` | margine / valore × 100 (`null` se valore 0) |
| `valore_senza_costo` | valore delle righe senza costo |
| `righe_senza_costo`, `righe` | conteggi righe |
| `documenti` | documenti distinti (non additivo: in `others` vale `null`) |

Default: `qta`, `valore`, `costo`. Con `compare` per `qta`, `valore`, `costo`, `margine` arrivano `<m>_cmp`, `delta_<m>`, `delta_<m>_pct` (percentuale su |confronto|, `null` se il confronto e 0).

## Ordinamento, top N, pagine, limiti

- `order_by.field`: una misura richiesta, `<m>_cmp`, `delta_<m>`, `delta_<m>_pct` o `group1`..`group5` (ordina per codice). Spareggi per codici crescenti.
- Senza `order_by` e senza `top_n`: codici crescenti. Con `top_n` senza `order_by`: `valore` decrescente.
- `top_n` 1-1000 sull'insieme completo, prima della paginazione; `others` = perimetro − top N.
- `page_size` max 100; `has_more` indica altre pagine; `result_set_id` copre tutti i gruppi (fino a 5000).
- Limite gruppi `pn_statistiche_max_groups` (default 20000): oltre risponde `TOO_MANY_GROUPS`.
