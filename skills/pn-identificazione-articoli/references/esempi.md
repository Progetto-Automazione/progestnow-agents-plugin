# Esempi

Otto esempi completi su dati reali (verificati il 2026-10-10). Gli esiti sono
rieseguiti dal test `tests/ai_agents/skill_identificazione_articoli_static_test.php`
sulla fixture di `tests/ai_agents/articoli_risolvi_codici_runtime_test.php`
(casi B-SK1..B-SK4, B-A7, V2-J46, V2-FB, RV21-05/06, RV21-01/02). Vanno rieseguiti dopo la prima
ricostruzione della lookup su ciascun tenant.

## 1. Bolla fornitore con Ns./Vs. codice ed EAN (briconettuno)

Riga del terzo (bolla del fornitore 20160):

| Ns. codice | Vs. codice | EAN | Descrizione | Qta |
| --- | --- | --- | --- | --- |
| 10007 | SE36 07 | 8002255802301 | Cofana PVC rossa | 4 |

Mappatura: `ns_codice` = `10007`, `vs_codice` = `SE36 07`, `ean` =
`8002255802301`; controparte `F 20160`.

```json
{"controparte": {"tipo": "F", "id": 20160},
 "righe": [{"rif": "r1",
   "codici": [{"valore": "10007", "etichetta": "ns_codice"},
              {"valore": "SE36 07", "etichetta": "vs_codice"},
              {"valore": "8002255802301", "etichetta": "ean"}],
   "descrizione": "Cofana PVC rossa", "qta": 4, "um": "PZ"}]}
```

Esito reale: `univoco` -> **10007** "COFANA PVC ROSSA PESANTE KAPLASTIC", forza
alta. I tre codici concordano sullo stesso articolo:
- `idmagazzino` (esatto, `globale`);
- `cpf1` e `codalt_for` (esatto, `controparte`): in DB il codice e' `SE36-07`,
  la normalizzazione toglie spazio e trattino;
- `barcode` `8002255802301` (esatto) e `barcode` `0000000010007` (`normalizzato`:
  trovato da `10007` senza zeri iniziali, forza media, non cambia l'esito).
`nqtaconf` e' `null`: confezione non indicata, nessun controllo.

## 2. Ordine cliente con codici del cliente (tenant I)

Riga dell'ordine del cliente 11005, con il codice che usa il cliente:

| Vs. codice | Descrizione | Qta |
| --- | --- | --- |
| 0311SWBIEN | Swing inglese 11 cm | 10 |

```json
{"controparte": {"tipo": "C", "id": 11005},
 "righe": [{"rif": "r1",
   "codici": [{"valore": "0311SWBIEN", "etichetta": "vs_codice"}],
   "descrizione": "Swing inglese 11 cm", "qta": 10, "um": "NR"}]}
```

Esito reale: `univoco` -> **0311SWBIIN0000C6**, fonte `listino` (listino
**11754** = listino del cliente 11005), ambito `controparte`, forza alta.

Controprova: lo **stesso** codice con il cliente **11001** (listino `ITA26`) da'
un solo candidato con ambito `altra_controparte`, forza bassa: esito
`probabile`. La fonte riporta `controparte_fonte: {"tipo": "C", "id": 11005, ...}`
(`n_controparti: 1`): il codice e' del listino di un altro cliente. Non
abbinarlo in silenzio: indicalo come probabile solo se descrizione e UM sono
coerenti, altrimenti proponi il fallback e chiedi.

## 3. Riga di listino fornitore con codice con trattini (briconettuno, file)

Listino Excel del fornitore 21556 (allegato del job, foglio `Listino`), con il
codice scritto `A-0052`. Il file non si ricopia mai nel contesto: si passa per
riferimento con `sorgente`.

```json
{"controparte": {"tipo": "F", "id": 21556},
 "sorgente": {"ref": "job_attachment:123", "foglio": "Listino",
              "colonne": {"rif": "A", "codici": [{"col": "B", "etichetta": "vs_codice"}], "descrizione": "C"},
              "riga_intestazione": 1}}
```

Esito reale della riga: `A-0052` normalizza a `A0052` -> `univoco` **34741**
(`cpf1` + `codalt_for`, ambito `controparte`, forza alta). Attenzione: 34741 e'
**obsoleto** (`obsoleto: 1`): segnalalo, non abbinarlo in silenzio. Il secondo
candidato **69769** e' `altra_controparte`, forza bassa.

Risposta (con `sorgente` arriva sempre il dataset):

```json
{"success": true, "output": "url", "dataset_export_id": "dsexp_...", "url": "https://...",
 "sintesi": {"righe": 5000, "univoche": 4820, "ambigue": 130, "non_trovate": 50, "righe_scartate": 0, "candidati_esclusi_stale": 0},
 "righe": ["... prime 50 righe non univoche ..."]}
```

In contesto hai solo `sintesi` e le prime 50 righe **non univoche**. Il
dettaglio completo (una riga per coppia riga/candidato) e' nel dataset
`dataset_export_id`: leggilo nel sandbox; se l'URL e' scaduto rinnovalo con
`pn_ai_dataset_url_renew`. Nessuna riga persa = `sintesi.righe` +
`sintesi.righe_scartate` uguale alle righe dati del file.

## 4. Codici discordanti (briconettuno)

Riga di una bolla del fornitore 20160 in cui il Vs. codice e l'EAN indicano
articoli diversi:

| Vs. codice | EAN | Descrizione | Qta |
| --- | --- | --- | --- |
| SE36 07 | 8000000000118 | Cofana | 4 |

Esito reale: `ambiguo`, `motivo: codici_discordanti`. `SE36 07` trova **10007**
(forza alta, `controparte`), `8000000000118` trova **29783** "CEMENTO NERO"
(`barcode`, forza alta) e nessun articolo e' trovato da entrambi i codici. Non
scegliere: mostra i due candidati e chiedi quale codice ha precedenza.

## 5. Codici del cliente senza controparte, poi richiamata (tenant B, job 46)

Materiale con 4 righe di codici `HQG...`, senza intestatario riconosciuto. Prima
chiamata senza controparte:

```json
{"righe": [{"rif": "r1", "codici": [{"valore": "HQG0266496", "etichetta": "sconosciuto"}]},
           {"rif": "r2", "codici": [{"valore": "HQG0223423", "etichetta": "sconosciuto"}]}]}
```

Esito reale: ogni riga `probabile` (un solo candidato, forza media): r1 ->
**GMSCO0228380** "OLIO PENETRANTE WD40 ML.500 SMARTSTRAW", fonte `codalt_cli`,
ambito `controparte_ignota`, con
`controparte_fonte: {"tipo": "C", "id": 122000483, "nome": "COSTA CROCIERE S.P.A."}`.
Nessun `pn_tabellabase_list` di verifica: se il documento e' di COSTA CROCIERE
(o il cliente e' comunque quello), richiama il tool **una volta** con
`"controparte": {"tipo": "C", "id": 122000483}`: tutte le righe diventano
`univoco` (forza alta, ambito `controparte`).

## 6. Riga non trovata con il codice di fallback

Riga di un ordine PDF: `XYZ-999-NEW` / `8009999999990`, "Raccordo speciale 3/4",
qta 2 PZ, prezzo 4,50. Esito reale: `non_trovato`; la risposta contiene
`"fallback": {"idmagazzino": "PN_TORECOGNISE", "descrizione": "TO RECOGNISE", "um": ""}`.
Proponi il fallback nella tabella (Esito finale: fallback) e, se l'utente lo
accetta o non vuole riconciliare, la Skill chiamante scrive:

```json
{"session_code": "S1", "product_code": "PN_TORECOGNISE",
 "description": "Raccordo speciale 3/4\nCod. orig.: XYZ-999-NEW / 8009999999990",
 "quantity": 2, "unit_of_measure": "PZ", "unit_net_price": 4.5,
 "discount1": 0, "discount2": 0, "discount3": 0, "discount4": 0,
 "original_description": "Raccordo speciale 3/4",
 "original_codes": ["XYZ-999-NEW", "8009999999990"]}
```

con `pn_document_new_row_add`. Nel riepilogo la riga sta sotto "da riconoscere
a mano". Con `"fallback": null` la riga resta fuori dal documento e va
segnalata.

## 7. Codice IMPA con prefisso (tenant B)

Riga di un ordine di bordo: `IMPA 110121`, "Bilanciere body building". Il
prefisso `IMPA` viene tolto (resta `110121`); su tenant B `110121` e' sia il nostro
codice dell'articolo 110121 sia il suo codice IMPA (fonte extra `impa`), e il
codice di listino `110-121` dell'articolo 530379 sui listini `F03041` e `F11356`.

Senza controparte:

```json
{"righe": [{"rif": "r1", "codici": [{"valore": "IMPA 110121", "etichetta": "sconosciuto"}]}]}
```

Esito reale: `univoco` -> **110121** "BILANCIERE BODY BUILDING 1.55 MT", forza
alta, fonti `idmagazzino` e `impa` con `"variante": "senza_prefisso"`.
L'articolo 530379 resta candidato secondario, forza bassa, `declassata: true`
(listino di controparte ignota).

Con il fornitore del listino `F03041` (`"controparte": {"tipo": "F", "id": 235001665}`)
il listino diventa una fonte della controparte del documento, forza alta:
esito `ambiguo` con `motivo: conflitto_nostro_codice`, candidati 110121
(nostro codice + IMPA) e 530379 (`listino`, ambito `controparte`,
`controparte_fonte` F <codice> "<fornitore>"), entrambi alta.
Non scegliere: mostra entrambi con le fonti e chiedi.

## 8. Codice del fornitore senza prefisso (tenant B)

Riga di una fattura RS Components: `577-419`. In anagrafica il codice fornitore
e' scritto `RS CODE 577-419` (`cpf1` del fornitore 235004994): la lookup contiene
anche la versione senza prefisso.

```json
{"controparte": {"tipo": "F", "id": 235004994},
 "righe": [{"rif": "r1", "codici": [{"valore": "577-419", "etichetta": "vs_codice"}]}]}
```

Esito reale: `univoco` -> **GMS0055143**, fonte `cpf1`, `codice_trovato`
`RS CODE 577-419`, ambito `controparte`, forza alta. Senza controparte lo stesso
codice esce `probabile` (forza media, `controparte_fonte` <fornitore>):
richiama il tool con il fornitore.

## Codice non utilizzabile

Codice `000000`: normalizzato resta `000000`, ma **senza zeri iniziali e'
vuoto** -> riportato in `codici_scartati` con `motivo: scartato_corto`, **mai**
come match. Se una riga ha solo codici cosi', esce `non_trovato` con `motivo:
scartato_corto` (nessun errore): scrivi "codice non utilizzabile".
