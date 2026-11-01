# ProgestNOW Agents

Plugin per Claude e Codex che collega il gestionale ProgestNOW alla chat.

## Cosa fa

Espone il connettore MCP ProgestNOW (documenti commerciali, scadenzario,
statistiche, TabellaBase, agenda, allegati e attività) insieme alle skill
che spiegano al modello quando e come usare ciascuna area. Le procedure
specifiche del tenant a cui ci si autentica arrivano dal server.

## Come si usa

Installa il plugin, collega il connettore ProgestNOW con le credenziali del
tuo tenant e chiedi in linguaggio naturale: "fatture scadute del cliente X",
"ordini fornitore aperti questo mese", "fatturato per cliente nel 2026".

## Dati

Il plugin invia le richieste al server MCP del tuo tenant ProgestNOW tramite
OAuth. Non memorizza nulla e non contiene credenziali.

## Collegamento

Se al collegamento del connettore viene chiesto un ID client OAuth, inserisci
`claude-plugin` e lascia vuoto il segreto.

## Generare lo zip del plugin

```bash
./build-zip.sh
```

Crea `dist/progestnow-agents-<versione>.zip` (versione da `plugin.json`),
escludendo `misc/`, `dist/`, `.git/` e lo script stesso.
