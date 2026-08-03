# ChoomLink installieren (Testerinnen und Tester)

Diese Anleitung ist für Leute gedacht, die noch nie ein Cyberpunk-Mod installiert haben.
Sie dauert etwa zehn Minuten. Wenn irgendwo etwas nicht so aussieht wie beschrieben:
**nicht raten, nachfragen** — eine halb installierte Mod-Kette produziert Abstürze, deren
Ursache man nachher schwer findet.

---

## 0. Was ChoomLink ist (und was nicht)

ChoomLink macht aus Cyberpunk 2077 eine gemeinsame Welt: Ihr seht euch gegenseitig
laufen, Waffen ziehen und schießen. Es ist ein **Testaufbau in Entwicklung**, kein
fertiges Spiel. Rechne mit Rucklern, Puppen, die kurz falsch stehen, und damit, dass
manches noch gar nicht synchronisiert wird.

Dein normaler Einzelspieler-Spielstand bleibt unangetastet: ChoomLink lädt ihn nur,
verändert die Speicherdatei aber nicht.

---

## 1. Voraussetzungen prüfen

### Spielversion 2.31

ChoomLink ist bewusst auf **genau Version 2.31** festgelegt (dasselbe Vorgehen wie bei
FiveM für GTA V). Ein Spiel-Update bricht die Verbindung, deshalb prüfen wir das zuerst.

So findest du deine Version: Hauptmenü starten, unten rechts steht die Versionsnummer.

Wenn dort etwas anderes als 2.31 steht, melde dich — dann bringen die nächsten Schritte
nichts.

> **Steam-Updates abschalten:** Rechtsklick auf Cyberpunk 2077 in der Bibliothek →
> Eigenschaften → Updates → „Nur beim Start des Spiels aktualisieren". Damit aktualisiert
> Steam nicht mehr im Hintergrund. Und da wir das Spiel ohnehin nicht über Steam starten
> (siehe Schritt 5), bleibt die Version stehen.

### Deinen Spielordner finden

Bei Steam liegt das Spiel normalerweise hier:

```
C:\Program Files (x86)\Steam\steamapps\common\Cyberpunk 2077
```

Falls nicht: Rechtsklick auf das Spiel in Steam → Verwalten → Lokale Dateien anzeigen.

In diesem Ordner liegen unter anderem `bin`, `r6`, `archive` und `REDprelauncher.exe`.
**Alles, was jetzt kommt, wird in genau diesen Ordner entpackt.** Nicht in einen
Unterordner, nicht in „Downloads".

---

## 2. Die drei Mod-Grundlagen installieren

ChoomLink baut auf drei verbreiteten Modding-Frameworks auf. Ohne sie startet es nicht.
Alle drei funktionieren gleich: Zip herunterladen, Inhalt in den Spielordner entpacken,
beim Nachfragen „Dateien zusammenführen/ersetzen" bestätigen.

| # | Was | Woher | Getestete Version |
|---|-----|-------|-------------------|
| 1 | **RED4ext** — lädt native Plugins | <https://github.com/WopsS/RED4ext/releases> | 1.30.0 |
| 2 | **redscript** — kompiliert die Skript-Seite | <https://github.com/jac3km4/redscript/releases> | 0.5.31 |
| 3 | **Codeware** — Skript-Bibliothek, die ChoomLink benutzt | <https://github.com/psiberx/cp2077-codeware/releases> | 1.20.3 |

Neuere Versionen funktionieren meistens auch. Wenn etwas klemmt, nimm exakt die oben
genannten — diese sind auf 2.31 verifiziert.

**Zwischenprüfung:** Starte das Spiel einmal ganz normal über Steam und geh bis ins
Hauptmenü. Wenn das klappt, sind die Grundlagen in Ordnung. Danach das Spiel wieder
beenden.

Wenn das Spiel jetzt schon abstürzt, liegt es an den drei Frameworks, nicht an
ChoomLink — dann melde dich, bevor du weitermachst.

---

## 3. ChoomLink entpacken

Die Datei `ChoomLink-<version>.zip` in denselben Spielordner entpacken.

Danach liegen dort zusätzlich:

```
Cyberpunk 2077\
├─ ChoomLink starten.bat          ← damit startest du künftig
├─ choomlink-server.txt           ← hier steht, mit welchem Server du dich verbindest
├─ LIESMICH.txt
├─ red4ext\plugins\Cyberverse\    ← 5 DLL-Dateien
├─ r6\scripts\Cyberverse\         ← 3 .reds-Dateien
└─ archive\pc\mod\choomlink_puppet.archive
```

Wenn diese Ordner woanders gelandet sind (etwa in
`Cyberpunk 2077\ChoomLink-1.0\red4ext\...`), hast du eine Ebene zu tief entpackt.
Verschiebe den Inhalt eine Ebene nach oben.

---

## 4. Serveradresse eintragen

`choomlink-server.txt` mit dem Editor öffnen. Sie sieht so aus:

```
address=100.64.12.34
port=1337
```

Trage die Adresse ein, die du bekommen hast.

### Wenn der Server über Tailscale läuft

Tailscale legt ein privates Netz zwischen unseren Rechnern an — der Server braucht dann
keine offenen Ports und keine feste öffentliche IP.

1. <https://tailscale.com/download> installieren.
2. Mit dem Konto anmelden, zu dem du eingeladen wurdest.
3. Die Adresse in `choomlink-server.txt` ist dann die Tailscale-IP des Servers
   (beginnt mit `100.`).

Tailscale muss laufen, solange du spielst.

---

## 5. Starten

**`ChoomLink starten.bat` doppelklicken.**

Nicht über Steam starten. Cyberpunk hat noch keine Serverauswahl im Spiel — die
Verbindung wird ausschließlich über Startargumente hergestellt, und Steam gibt diese
Argumente nicht weiter. Über Steam gestartet landest du still und leise im normalen
Einzelspieler.

Das Spiel lädt automatisch deinen letzten Spielstand und verbindet sich dabei.

Beim ersten Start dauert es länger als gewohnt: redscript kompiliert die Skripte einmal
neu.

---

## 6. Prüfen, ob es wirklich läuft

Wenn ihr euch nicht seht, ist die wichtigste Frage: liegt es an der Installation oder an
der Verbindung? Diese beiden Logdateien beantworten das.

**`red4ext\logs\red4ext.log`** — hier muss eine Zeile mit `Cyberverse` stehen
(„has been loaded"). Fehlt sie, wurde das native Plugin nicht gefunden: Der Ordner
`red4ext\plugins\Cyberverse` liegt an der falschen Stelle.

**`r6\logs\redscript_rCURRENT.log`** — hier muss die Kompilierung ohne Fehler
durchlaufen. Steht dort `UNRESOLVED_...` oder ein anderer Fehler, fehlt meist Codeware
oder eine `.reds`-Datei ist beim Entpacken liegen geblieben.

Beide Dateien sind reiner Text und können einfach mitgeschickt werden.

---

## 7. Häufige Probleme

**Ich bin allein in der Welt.**
Fast immer eine von drei Ursachen: über Steam gestartet, falsche Adresse in
`choomlink-server.txt`, oder der Server läuft gerade nicht.

**Das Spiel stürzt beim Laden des Spielstands ab.**
Meist eine unvollständige Skript-Installation. Prüfe
`r6\logs\redscript_rCURRENT.log`.

**Die Startdatei sagt, sie findet `bin\x64\Cyberpunk2077.exe` nicht.**
Das Zip wurde nicht in den Spielordner entpackt (siehe Schritt 3).

**Nach einem Spiel-Update geht nichts mehr.**
Steam hat auf eine neuere Version aktualisiert. ChoomLink braucht 2.31. Nichts neu
installieren, sondern melden.

**Ich will ChoomLink wieder loswerden.**
Diese Pfade löschen, dann ist das Spiel wieder unverändert:
`red4ext\plugins\Cyberverse`, `r6\scripts\Cyberverse`,
`archive\pc\mod\choomlink_puppet.archive`, `ChoomLink starten.bat`,
`choomlink-server.txt`. Die drei Frameworks aus Schritt 2 können bleiben, sie stören
den Einzelspieler nicht.

---

## Für Serverbetreiber

Server starten (siehe `server/`), er lauscht auf UDP-Port **1337**. Die Testerinnen und
Tester brauchen nur Adresse und Port. Über Tailscale ist keine Portfreigabe im Router
nötig.

Alle verbundenen Clients müssen dieselbe Spielversion und dieselbe ChoomLink-Version
benutzen wie der Server.
