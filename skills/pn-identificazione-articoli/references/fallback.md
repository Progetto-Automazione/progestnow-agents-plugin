# Riga con il codice di fallback

Il campo `fallback` della risposta di `pn_articoli_risolvi_codici` contiene
l'articolo generico del tenant (parametro `pn_ai_articoli_codice_fallback`,
es. `PN_TORECOGNISE`):

```json
"fallback": {"idmagazzino": "PN_TORECOGNISE", "descrizione": "TO RECOGNISE", "um": ""}
```

- `null` = non configurato: le righe senza abbinamento restano fuori dal
  documento e vanno segnalate all'utente.
- `null` con `sintesi.warnings[].code = "FALLBACK_ARTICLE_INVALID"` = parametro
  impostato ma articolo inesistente o obsoleto: come non configurato, e segnala
  all'utente che il fallback del tenant va corretto.
- Il fallback **non e' mai un candidato**: il tool lo espone e basta.

## Quando usarlo

- Riga `non_trovato`.
- Riga `ambiguo` o `probabile` che l'utente non conferma.
- Riga che l'utente chiede di non riconciliare, o abbinamento rifiutato.

## Come scrivere la riga

Con `pn_document_new_row_add` (documento nuovo) o `pn_document_edit_row_add`
(documento in modifica), una chiamata per riga:

```json
{"session_code": "S1", "product_code": "PN_TORECOGNISE",
 "description": "VITE TE M8X20 ZINCATA CL 8.8\nCod. orig.: ABC-123 / 8001234567890",
 "quantity": 100, "unit_of_measure": "PZ", "unit_net_price": 0.12,
 "discount1": 0, "discount2": 0, "discount3": 0, "discount4": 0,
 "original_description": "VITE TE M8X20 ZINCATA CL 8.8",
 "original_codes": ["ABC-123", "8001234567890"]}
```

- `description`: descrizione originale completa, poi a capo e "Cod. orig.: "
  con tutti i codici letti sulla riga separati da " / ". La descrizione passata
  non viene sostituita da quella dell'articolo generico.
- `quantity`, `unit_of_measure`, `unit_net_price`: quelli del documento.
- `discount1..4`: quelli del documento, `0` se assenti (senza sconti espliciti
  il gestionale applicherebbe gli sconti automatici del cliente).
- `original_description`: la descrizione originale senza la riga "Cod. orig.".
- `original_codes`: tutti i codici letti (max 10).

Risposta: `fallback_row.import_fields` = `saved` (il tenant conserva descrizione
e codice originali per il riconoscimento manuale successivo) oppure
`not_supported` (il tenant non ha questa funzione: il dato resta nella
descrizione della riga). Un warning `original_fields_ignored` indica che la
riga non usava il codice di fallback configurato.

## Nella risposta all'utente

Le righe con fallback stanno in un elenco a parte "da riconoscere a mano", con
descrizione originale, codici, quantita', UM e prezzo. Mai mescolarle con le
righe confermate.
