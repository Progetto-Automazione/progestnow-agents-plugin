---
name: attachments-support
description: Ricerca, lettura, diagnosi, invio ed eliminazione di allegati in ProgestNOW, e operazioni di upload, ZIP e copia con i tool dedicati della famiglia allegati. Attiva quando la domanda riguarda allegati/attachment/upload di file su record o documenti, allegati mancanti o non scaricabili, ZIP o email di allegati, copia allegati tra documenti, categorie/tag allegati, oggetti orfani o record DEL_.
metadata:
  knowledge_refs:
    - CAP-20260810-013
    - SCN-ATT-001..010
    - RULE-ATT-001..010
    - CFG-ATT-001..004
    - DATA-ATT-001..007
    - DIAG-ATT-001..003
    - QRY-ATT-001..004
    - FIND-ATT-001
---

> **Nel plugin (Claude, Codex).** Questa procedura nasce per il motore ProgestAI: dove differisce, vale questa nota.
> - `output=url` non va usato per scaricare dati: il tuo ambiente di esecuzione non raggiunge gli URL ProgestNOW. Restringi i filtri, aggrega lato server con `pn_tabellabase_aggregate`, oppure pagina con limiti piccoli; i calcoli locali li fai sui dati gia restituiti dai tool, nel tuo ambiente di esecuzione, al posto del "sandbox".
> - Questi tool qui non esistono: `pn_code_exec`, `pn_email_send`, `pn_ai_fetch_file`, `pn_kb_search`, `pn_attachments_zip`, `pn_app_attachments_tables`. Se un passaggio li richiede, usa un equivalente disponibile (il tuo ambiente di esecuzione per calcoli e file, la chat per testi da inviare) oppure dichiara all'utente il limite; non inventare chiamate.

# Supporto allegati e upload

## Obiettivo procedurale

Rispondere in modo affidabile a domande e lavori sugli allegati: trovarli,
leggerli, diagnosticarli, inviarli via email, eliminarli in sicurezza,
caricarli, impacchettarli in ZIP e copiarli tra documenti, usando i tool
dedicati quando disponibili e guidando alla UI per le operazioni che non
hanno ancora una primitiva (modifica metadata), senza mai simulare
operazioni prive di tool.

## Prerequisiti

- Tool disponibili nel job: TabellaBase read
  (`pn_tabellabase_catalog`, `pn_tabellabase_descriptor`,
  `pn_tabellabase_list`, `pn_tabellabase_single`); per l'eliminazione
  `pn_tabellabase_delete`; per l'invio `pn_email_send`; tool interno
  `pn_ai_fetch_file` (sempre presente). Operazioni di dominio con i tool
  dedicati `pn_attachment_upload` (upload+registrazione),
  `pn_attachments_zip` (ZIP di più allegati), `pn_attachments_copy` (copia
  tra documenti). Se un tool dedicato manca dal toolset, NON aggirare:
  dichiara il TOOLING_GAP e guida alla UI (step 8).
- Knowledge: CAP-20260810-013 via Knowledge MCP
  (`get_capability_context`/`get_canonical_query`) o risorsa KB
  "Allegati e upload - orientamento" via `pn_kb_search`.

## Sequenza operativa

1. **Classifica la domanda**:
   - ricerca/elenco allegati → step 2;
   - lettura contenuto di un allegato → step 3;
   - anomalia/troubleshooting → step 4;
   - invio email → step 5;
   - eliminazione → step 6;
   - upload/ZIP/copia → step 7 (con tool dedicati);
   - modifica metadata → step 8 (guida UI, nessun tool).
2. **Ricerca**:
   a. Risolvi il record padre se necessario (documento:
      `pn_documents_search` → `cidfattura`; prima nota (arcmovc): testata
      `cidesercizio`+`nmovc`; cliente/fornitore: TabellaBase anagrafica);
   b. chiave di collegamento: il `tableid` NON è sempre la PK del record
      padre. Convenzioni verificate: documenti →
      `testapiedefatture`+`cidfattura`; prima nota (tablename `arcmovc`) →
      `tableid='{cidesercizio}-{nmovc}'` (testata, mai l'id di riga
      dare/avere). Per altre superfici ricava lo schema da 2-3 record reali
      di `attachments` e incrocia i valori con il `main_field` del
      descrittore, non solo con la PK;
   c. `pn_tabellabase_list` su `attachments` con `search`:
      `attachments.tablename` e `attachments.tableid`; eventuali filtri
      `type`, `category`; per la data usa la colonna `date` (NON
      `creation_date`);
   d. ordina per `date` discendente; volumi grandi: `output=url`;
   e. controllo positivo: se devi concludere "nessun allegato" su un
      insieme di record, verifica PRIMA la chiave su una registrazione
      nota per avere allegati; con 0 corrispondenze metti in dubbio la
      chiave, non il dato, e dichiara la chiave usata.
3. **Lettura contenuto**:
   a. verifica `type`/estensione: `pn_ai_fetch_file` solo per
      pdf/png/jpeg/gif/webp;
   b. video/altri formati: dichiara che il contenuto non è leggibile
      nativamente; proponi il download dell'URL all'utente;
   c. PDF/Excel complessi o voluminosi: PNOWDOCREADER (delega o rinvio);
   d. `url='false'` → allegato rotto: non tentare il fetch, diagnostica.
4. **Diagnosi**: applica `references/diagnostic-tables.md`
   (DIAG-ATT-001/002/003). Verifica le ipotesi con letture mirate prima di
   concludere; cita il runbook e la regola canonica nella risposta.
5. **Invio email**:
   a. recupera gli URL degli allegati (step 2) oppure genera lo ZIP con
      `pn_attachments_zip` (step 7c) e usa il suo `file_url`;
   b. `pn_email_send` con `proceed_to_send=no` (preview) → mostra
      destinatari/oggetto/allegati all'utente → solo dopo conferma
      `proceed_to_send=yes` con `user_confirmed=true` e
      `confirmation_text=INVIA EMAIL`.
6. **Eliminazione**:
   a. identifica l'allegato (step 2) e conferma con l'utente record e
      conseguenze;
   b. dichiara PRIMA che l'oggetto S3 non verrà rimosso (resta orfano);
   c. `pn_tabellabase_delete` su `attachments` (pending action in mode
      execute); verifica post-delete con rilettura.
7. **Operazioni di dominio con tool dedicati** (upload, ZIP, copia):
   a. **Upload** (`pn_attachment_upload`): `tablename`/`tableid` del record
      (per i documenti `testapiedefatture`, mai la variante con suffisso
      causale); file come `file_base64`+`filename` (max 10 MB) oppure
      `source_url` (solo URL HTTPS dello storage S3 del tenant); `title` e
      `category` opzionali (categoria validata su `attachments_categories`).
      NON idempotente: ogni chiamata crea un nuovo oggetto e record; se lo
      stesso URL è già allegato al record viene segnalato
      `warnings.duplicate_url` senza bloccare. Verifica post-operazione:
      rileggi il record con `pn_tabellabase_single` su `attachments`.
   b. **Copia tra documenti** (`pn_attachments_copy`): `from_cidfattura` e
      `to_cidfattura` (diversi); idempotente per URL (seconda chiamata →
      `copied=0`, `skipped_duplicate=N`); non modifica il documento e non
      forza `has_attachments`.
   c. **ZIP** (`pn_attachments_zip`): selezione per `attachment_ids`
      (1-100) oppure `tablename`+`tableid` (max 100); `on_missing=error`
      (default, atomico) o `skip` (esclusi dichiarati in `skipped[]`);
      l'URL dello ZIP è firmato e temporaneo (`expires_at`): NON salvarlo,
      usarlo subito (es. per `pn_email_send`). Limite noto del flusso
      legacy (FIND-ATT-001): un oggetto S3 irraggiungibile può produrre una
      voce vuota nello ZIP — se sospetti oggetti rotti, verifica prima gli
      URL con letture (step 2/3) e usa `on_missing=error`.
   d. Tutti i write restano dietro pending action in mode execute: nessuna
      auto-approvazione.
8. **Operazioni senza tool** (modifica metadata allegato: titolo,
   descrizione, categoria, tag): NON eseguire e NON simulare. Spiega la
   procedura UI corretta (superficie `/shared/table/attachments/list`) e
   offriti per le verifiche letture pre/post.

## Decision point

- `tablename` documento: usa sempre `testapiedefatture`, mai la variante
  con suffisso causale (RULE-ATT-004).
- Chiave di collegamento con 0 corrispondenze: NON concludere "nessun
  allegato" senza controllo positivo (step 2e). Il `tableid` delle
  registrazioni di prima nota è `{cidesercizio}-{nmovc}` (testata): usare
  l'id di riga dare/avere produce un falso negativo sistematico.
- Record con `tableid` `DEL_*`: storico — chiedi all'utente se vuole
  davvero operare su allegati di un record padre cancellato.
- Categoria assente in lista: verifica `attachments_categories` (QRY-ATT-004)
  prima di parlare di dato mancante.
- ACL privata (`attachments_public_private=private`, su tenant che la
  configurano): gli URL non sono liberamente scaricabili; ZIP/email via UI
  possono produrre file vuoti (DIAG-ATT-003); per il ZIP via tool la
  risoluzione è server-side (mai URL dal modello, FIND-ATT-001).
- `url='false'` su un allegato: upload fallito — non proporre copia/ZIP di
  quell'allegato senza diagnostica (DIAG-ATT-002).

## Fallback

- Superficie non in catalogo (`pn_tabellabase_catalog` senza
  `attachments`): usa comunque `table_name=attachments` in
  `pn_tabellabase_descriptor/list` e segnala la lacuna di catalogo;
  se il permesso è negato dalla route, dichiaralo (non aggirare).
- Tool dedicato (upload/ZIP/copia) assente dal toolset: dichiara il
  TOOLING_GAP e guida alla UI (step 8); NON simulare l'operazione con
  `pn_code_exec` o prompt fragili.
- Knowledge MCP non raggiungibile: basati solo su dati verificati a
  database e dichiaralo.

## Criteri di completamento

- Risposta con evidenze (record letti, ID allegato, URL solo se necessario
  e con cautela riservatezza).
- Nessuna operazione write eseguita senza pending action/confirm.
- Riferimenti canonici citati (SCN/RULE/DIAG pertinenti).

## Quando fermarsi / delegare

- Estrazione strutturata pesante → PNOWDOCREADER.
- Analisi che richiede aggregazioni su più tabelle → PNOWORC con piano.
- Upload/ZIP/copia con tool dedicati assenti nel toolset → fermarsi alla
  guida UI (step 8), mai simulare.
