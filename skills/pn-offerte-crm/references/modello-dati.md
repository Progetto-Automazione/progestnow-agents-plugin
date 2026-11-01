# Offerte e pipeline: modello dati

Fonti: DB `progest` (2026-10-10), descrittore `testapiedefatture_R` (core e override `config_personalizzati` di progest, stessa query), vista `qryleads`, `_qryleads.json`, KB `CAP-20260811-005`, `AiService::document_*_set_header` / `document_linked_documents`.

## 1. L'offerta

- Documento con `causalimagazzino.tipocausale = 'R'` **e** `causalimagazzino.flagidcliente_idfornitore = 'C'`.
- La tipologia R contiene anche le **richieste di offerta a fornitore** (`flagidcliente_idfornitore = 'F'`, documenti intestati a `idfornitore`). Su `tenant A` (2026-10-10):

| causale | descrizione | flag | documenti |
|---|---|---|---|
| `OFF` | OFFERTA/PRO FORMA INVOICE | C | 17.662 |
| `RICHO` | RICHIESTA OFFERTA A FORNITORE | F | 328 in totale, 128 dal 2025; 323 con `idfornitore` |

  Su `progest` esiste solo `OFF` (C).
- La TabellaBase `testapiedefatture_R` ha `additional_where = AND cm.tipocausale='R'` sia nel core sia negli override di progest e tenant A, quindi **non** esclude le richieste a fornitore. Aggiungi sempre il filtro `tpf.idcausale` `in` [causali R con flag C]:
  - gli elenchi si leggono da `causalimagazzino` con `pn_tabellabase_list` (output `idcausale`, `tipocausale`, `flagidcliente_idfornitore`); `pn_document_types` non restituisce il flag;
  - **non** filtrare su `cm.flagidcliente_idfornitore`. Dove il catalogo campi MCP è attivo (`pn_mcp_tabellabase_field_catalog_enabled = 1`: progest e tenant J, non tenant A al 2026-10-10), i filtri `search` accettano solo i campi del catalogo:
    - nel catalogo di progest per `testapiedefatture_R` il flag non c'è e la chiamata viene rifiutata con `FIELD_UNKNOWN`;
    - in `testapiedefatture_F` c'è, ma come campo `output_only`, non filtrabile;
    - `tpf.idcausale` invece è filtrabile;
  - dimensioni e misure qualificate (`cm.flagidcliente_idfornitore`, `cm.idcausale`) passano anche se non sono nel catalogo: si possono usare per raggruppare, non per filtrare.

  Lo stesso vale per gli ordini (`testapiedefatture_O`, `additional_where = AND cm.tipocausale='O'`), dove ci sono anche gli ordini a fornitore: filtro `tpf.idcausale` `in` [causali O con flag C] (progest: `ORCLI`).
- Per vedere quali causali R ha il tenant e quanti documenti hanno: `aggregate` su `testapiedefatture_R` con `dimensions: ["cm.idcausale", "cm.flagidcliente_idfornitore"]` e misura `count`.
- Testata: `testapiedefatture` (chiave `cidfattura`, es. `OFF2026213`). Righe: `righefatture`, mai evase (vedi §4).
- Query del descrittore (core = progest):

```
SELECT tpf.*, tpf.idcliente AS codice_cliente, arccli.tipocli,
       DATE_FORMAT(tpf.datafattura,'%d-%m-%Y') AS datafattura, tpf.datafattura AS datafattura_eng, cm.*,
       tabpag.descr AS descrpag,
       leads_statuses.description AS leads_status,
       leads_funnel_statuses.title AS leads_funnel_status,
       leads_conversion_score.title AS leads_conversion_score,
       cm.descrizione AS descr_cau, tipologieordine.cdesctipologiaordine AS tipologia_ordine,
       fos_user.username AS operatore_username
FROM testapiedefatture tpf
INNER JOIN causalimagazzino cm ON tpf.idcausale=cm.idcausale
LEFT JOIN tabpag ... LEFT JOIN arccli ON tpf.idcliente=arccli.codice
LEFT JOIN leads_statuses ON tpf.leads_status_code = leads_statuses.id
LEFT JOIN leads_funnel_statuses ON tpf.leads_funnel_status_code = leads_funnel_statuses.code
LEFT JOIN leads_conversion_score ON tpf.leads_conversion_score_code = leads_conversion_score.code
LEFT JOIN fos_user ON tpf.cidoperatore = fos_user.id
LEFT JOIN tipologieordine ...
```

Conseguenze per i tool:

- filtri, dimensioni e `date_buckets` su `tpf.<campo>`. `aggregate` riscrive anche i campi fisici non qualificati in `tpf.` quando risolve la tabella principale, ma conviene scriverli espliciti;
- `datafattura` in `output_fields` è una stringa `gg-mm-aaaa`. `datafattura_eng` non è tra gli `output_fields_allowed` (non è una colonna della lista). Nel sandbox converti con `dayfirst=True`;
- le decodifiche di stato, fase e probabilità sono già in join: si possono usare come dimensioni `leads_statuses.description`, `leads_funnel_statuses.title`, `leads_conversion_score.title`.

## 2. Campi CRM della testata

| Campo | Tipo (progest) | Significato | Decodifica |
|---|---|---|---|
| `leads_status_code` | varchar | stato dell'opportunità | `leads_statuses.id` → `description` (progest: 1 Aperto, 2 Chiuso Positivo, 3 Chiuso Negativo, 4 On hold; un'offerta dal 2025 ha `''`) |
| `leads_funnel_status_code` | varchar | fase del funnel | `leads_funnel_statuses.code` → `title`, `ordering`, `kanban_exclude`, `leads_statuses_id` |
| `leads_funnel_statuses_ordering` | int | ordine della card nella colonna kanban | — |
| `leads_conversion_score_code` | varchar | probabilità | `leads_conversion_score.code` → `title`, `percentage`, `is_default` (progest: ALT/MED/BAS, percentage 0) |
| `expected_conversion_date` | date | data prevista di chiusura | — |
| `codage` | varchar | agente commerciale | `agenti.idagente` → `agenti.nome` (`''` = senza agente) |
| `cidoperatore` | varchar | operatore che ha registrato (non l'agente) | `fos_user.id` → `username` |
| `idcliente` | | cliente | `arccli.codice` |
| `lead_company_id` | int | azienda CRM | `leads_companies.id` |
| `lead_company_people_id` | | contatto CRM | `leads_companies_people.id` |
| `lead_opportunity_id` | | opportunità CRM | `leads_opportunities` |
| `validity_days` | varchar | validità (testo libero) | non affidabile (28 offerte compilate) |
| `totaleimponibile` | | valore dell'offerta netto IVA | — |
| `datafattura` | datetime | data dell'offerta | — |
| `mnoteinterne` | | note interne | — |
| `n_doc_orig` | varchar | documento d'origine (copia/revisione) | può valere la stringa `'NULL'` |

### Tabelle di decodifica su progest

`leads_statuses`: `1 Aperto` (ordering 1), `2 Chiuso Positivo`, `3 Chiuso Negativo`, `4 On hold`; tutti con `show_in_kanban = 1`.

`leads_funnel_statuses`:

| code | title | ordering | leads_statuses_id | kanban_exclude |
|---|---|---|---|---|
| PRM | Primo meeting | 1 | 1 | 1 |
| 1 | Richiesta offerta | 2 | 0 | 0 |
| 2 | Fatta offerta | 3 | 0 | 0 |
| CTR | Discussione offerta | 4 | 0 | 1 |
| 3 | Accettata offerta | 5 | 0 | 0 |
| 4 | Installato | 6 | 0 | 0 |
| 5 | Fatturato | 7 | 2 | 1 |
| 1B | Fatta offerta indicativa | 0 | 0 | 1 |
| 1C | Fatta demo - preparare offerta finale | 0 | 1 | 1 |

`leads_conversion_score`: `ALT` ALTA, `MED` MEDIA, `BAS` BASSA, tutte con `percentage = 0` e `is_default = 0`.

Sono dati di progest: su un altro tenant rileggili sempre.

## 3. Vista `qryleads` e TabellaBase `_qryleads` (kanban opportunità)

`qryleads` è una `UNION ALL` tra:

1. **lead** (`leads l` + `leads_companies_people` + `leads_companies` + `arccli`), con `lead_internal_type = 'lead'`;
2. **offerte**: `testapiedefatture tpf` + `causalimagazzino` con `tipocausale = 'R'`, con `lead_internal_type = 'offerta'`. La vista **non** filtra `flagidcliente_idfornitore`: dove esistono causali R fornitore (tenant A: `RICHO`), anche le richieste di offerta a fornitore finiscono nel kanban come "offerte". Usa `_qryleads` solo per le righe `lead`; le offerte prendile sempre da `testapiedefatture_R` con il filtro `tpf.idcausale` `in` [causali R con flag C].

Mapping per le offerte:

| colonna qryleads | offerta |
|---|---|
| `lead_id` | `cidfattura` |
| `lead_internal_type` | `'offerta'` |
| `user_id` | `cidoperatore` |
| `idagente` | `codage` |
| `date` | `datafattura` |
| `client_id` | `idcliente` |
| `lead_title`, `lead_company_name` | `nome` |
| `leads_funnel_status_code` | `leads_funnel_status_code` |
| `leads_funnel_status_ordering` | `leads_funnel_statuses_ordering` |
| `leads_status_id` | `leads_status_code` |
| `lead_budget` | `totaleimponibile` |
| `lead_notes` | `mnoteinterne` |
| `expected_conversion_date`, `leads_conversion_score_code`, `lead_company_people_id`, `email` | stessi campi |

Per i lead: `leads.leads_funnel_statuses` (fase), `leads.leads_statuses_id` (stato), `leads.budget`, `leads.idagente`, `leads.date`.

La TabellaBase `_qryleads` (`FROM qryleads ql`, join su stati, fasi, punteggi, `agenti`, `fos_user`, `leads_rows`, `lead_tag`, con `GROUP BY ql.lead_id`) espone `agente_nome`, `lead_status_description`, `lead_status_funnel_title`, `lead_conversion_score_title`. Il kanban mostra solo `leads_statuses.show_in_kanban = 1` e solo le fasi con `kanban_exclude <> 1`: le offerte con fase orfana (`OFF`) o con fase esclusa **non compaiono in nessuna colonna** del kanban.

Su progest `leads` ha 119 righe, l'ultima del 2018-04-01: la pipeline reale sono solo le offerte. Su altri tenant i lead possono essere vivi. In quel caso conviene usare `_qryleads` per la pipeline complessiva, tenendo separati `lead` e `offerta`: un lead non ha ordine collegato.

## 4. Offerta → ordine

- L'ordine cliente (tipologia `O`) creato da un'offerta ha `testapiedefatture.n_doc_orig = <cidfattura offerta>`.
- Le righe d'offerta non vengono evase: su progest `quantitaevasa` e `riferimentorigaordine` sono a 0 su tutte le 941 righe d'offerta dal 2025. Quindi:
  - `qrydocumenti_documentievasi` non contiene nessun legame con tipologia R (0 righe su progest);
  - `pn_document_linked_documents` (basato su quella vista e su `qryfatture_ddtevasi`) **non restituisce l'ordine** di un'offerta. Verificato su 5 coppie offerta-ordine recenti: 0 legami.
- `n_doc_orig` serve anche ad altro. Sui documenti R e O di progest dal 2025:
  - in 123 offerte su 223 e in 81 ordini su 206 vale la **stringa** `'NULL'`;
  - in 88 offerte punta a un'altra offerta (copia o revisione); in 11 punta a un altro tipo di documento;
  - nel complesso 602 offerte e 729 ordini (`ORCLI`) puntano a un'offerta.
  
  Per la conversione tieni solo gli ordini cliente (tipologia O, filtro `tpf.idcausale` `in` [causali O con flag C]) e fai il join sul `cidfattura` delle offerte del perimetro.
- Su progest, dal 2025: 89 offerte con ordine, nessuna con più di un ordine. Tempo medio di chiusura 23,6 giorni, da −28 a 252: un valore negativo significa offerta registrata dopo l'ordine, va segnalato.
- Chiusura automatica dello stato:
  - quando un ordine nasce come **copia** dell'offerta (`InvoicesService`, salvataggio con `id_copy`), lo stato dell'offerta diventa il valore del parametro `crm_offerta2ordine_stato` (`config_webprogest`; progest: `2`). Se il parametro è vuoto lo stato non cambia;
  - una nuova offerta prende lo stato da `crm_default_offer_status` (progest: `1`);
  - anche il modulo trade (`TradeBundle`) aggiorna lo stato in conversione.
  
  Gli ordini creati senza copia, o gli stati cambiati a mano dopo, producono le incoerenze stato/ordine. I codici di stato hanno significati diversi da tenant a tenant: ad esempio alcuni controller trattano `4` o `5` come stati specifici. Vanno sempre decodificati con `leads_statuses` del tenant.

## 5. RULE-CRM-013 (sincronizzazione stato e fase)

- Spostamento card kanban (`/tabelle/_qryleads/move`, `QryleadsController::moveCardAction`):
  - `lead_internal_type = 'offerta'` → `UPDATE testapiedefatture SET leads_funnel_status_code, leads_funnel_statuses_ordering`. **Lo stato non cambia.**
  - lead → `UPDATE leads SET leads_funnel_statuses, leads_funnel_statuses_ordering`.
- Update di un lead (`LeadsController::postUpdateAction`): se la fase ha `leads_statuses_id` valorizzato (≠ vuoto, null, `"0"`) aggiorna anche `leads.leads_statuses_id`. **Solo per i lead.**
- Conseguenza: per un'offerta, stato e fase vanno impostati entrambi e in modo esplicito. Una fase "Fatturato" (`leads_statuses_id = 2`) non rende un'offerta *Chiuso Positivo*.

## 6. Scrittura dei campi CRM di un'offerta

- `pn_document_edit_set_header` / `pn_document_new_set_header` accettano `offer_status_code` → `leads_status_code`, `offer_funnel_status_code` → `leads_funnel_status_code`, `offer_conversion_score_code` → `leads_conversion_score_code`. Sono ammessi solo su documenti R e i codici vengono validati. Il tool controlla solo la tipologia R, non il flag cliente/fornitore: una richiesta a fornitore (`RICHO`) verrebbe accettata. Prima di scrivere verifica che la causale abbia `flagidcliente_idfornitore = 'C'`. Le opzioni ammesse si leggono con `pn_document_offer_crm_options`.
- `expected_conversion_date`, `leads_funnel_statuses_ordering` e `codage` non sono esposti come parametri CRM della sessione: `TOOLING_GAP`, va fatto da UI.

## 7. Numeri di riferimento (progest, offerte con `datafattura` ≥ 2025-01-01, estratti il 2026-10-10)

| Stato | n | imponibile | con ordine | data prevista passata | fase orfana |
|---|---|---|---|---|---|
| 1 Aperto | 122 | … | 1 | 112 | 118 |
| 2 Chiuso Positivo | 95 | … | 88 | 92 | 92 |
| 3 Chiuso Negativo | 4 | … | 0 | 4 | 4 |
| 4 On hold | 1 | … | 0 | 1 | 1 |
| (vuoto) | 1 | … | 0 | 1 | 0 |

Altri dati:

- Fasi dal 2025: `OFF` (orfana) 215; `2` 3; `1` 2; `CTR` 2; `''` 1.
- Aperte con revisione successiva: 31, per 709.380 €.
- Pipeline aperta divisa per data prevista:
  - attive (≥ oggi): 10 offerte, 29.910 €;
  - ferme: 112 offerte, ….
- Data prevista anteriore alla data dell'offerta, ereditata dalla copia: 83 offerte su 223, di cui 41 aperte per 845.671 €.
- 2 offerte hanno `expected_conversion_date = '0000-00-00'`.
- Conversione 2026, offerte → ordini per mese di offerta:
  - gen 14 → 7; feb 14 → 5; mar 14 → 10; apr 10 → 2; mag 10 → 8;
  - giu 12 → 6; lug 15 → 7; ago 3 → 1; set 13 → 3; ott 7 → 1.
- Agenti, su tutte le offerte: `''` 968, `FE` 733 ("Invio fatt. a mezzo email"), `FP` 29 ("Invio fatt. a mezzo posta"), `3` 11, `sca` 10 (Gruppo SCA), `5` 2, `CO` 1 ("Crediti Obsoleti"). Dal 2025 solo 5 offerte su 223 hanno `codage`.

## 8. Riferimenti KB (Knowledge MCP)

- `CAP-20260811-005`: Gestire lead, aziende, opportunità e campagne (CRM).
- `DATA-CRM-003`: vista `qryleads` (lead + offerte).
- `DATA-CRM-004`: `leads_statuses`, `leads_funnel_statuses`, `leads_conversion_score`.
- `QRY-CRM-002`: verifica opportunità e funnel.
- `RULE-CRM-013`: sincronizzazione stato e fase delle opportunità.
- `SCN-CRM-004`: consultare le opportunità commerciali.
- `SCN-CRM-005`: spostare le card nel funnel kanban.
- `SCN-CRM-007`: gestire stati, fasi e punteggi di conversione.
- `DIAG-CRM-004`: stato non aggiornato o card non spostata.
