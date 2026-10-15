# iPump-mini – Name, Icon und Designsprache (Vorschlag)

Stand: Entwurf zur Entscheidung durch Simon. Noch nichts davon ist in der App umgesetzt.

## Name
- Anzeigename **„iPump-mini“** (Home-Bildschirm, Widgets, AltStore). Alternativ ohne Bindestrich „iPump mini“.
- **Bundle-ID bleibt** `de.sgitaize.openminipump`. Eine neue Bundle-ID wäre für iOS eine neue App: Kopplung, Daten, Schlüsselbund und Einstellungen wären weg, und die Pumpe müsste neu gekoppelt werden.
- Repo-Name kann später umbenannt werden (GitHub leitet alte URLs weiter).
- Hinweis: Namen mit vorangestelltem „i“ werden mit Apple-Produkten assoziiert. Für den App Store wäre das heikel; für eine Open-Source-Seitenverteilung (AltStore) unkritischer. Bitte bewusst entscheiden.

## Icon-Varianten (`docs/internal/design/icon-proposals.png`)
| | Idee | Wirkung |
|---|---|---|
| 0 | aktuell: Tropfen mit CGM-Kurve auf Türkis→Blau | freundlich, eher „Glukose-App“ |
| **A** | kleines Gerät mit Display, Kurve und aktuellem Punkt | passt am besten zu „iPump“, eigenständig, nicht Medtronic-Optik |
| B | „i“, dessen Punkt ein Tropfen ist | sehr reduziert, starker Bezug zum Namen |
| C | Ring (Sensor/Anzeige) mit Kurve, dunkel | technisch, gut als Widget-/Watch-Motiv |

Empfehlung: **A** als App-Icon, Motiv C für Widgets/Komplikationen. Die Skripte zum Erzeugen: `docs/internal/design/render-proposals.swift`, finales Icon über `apps/ios/Scripts/render-icon.swift`.

## Designsprache: schlicht, aber schick, kein generischer „AI-Look“
- **Farben:** eine Akzentfarbe (Petrol `#0F766E`), sonst Systemfarben. Bedeutungsfarben fest:
  - Zielbereich grün
  - hoch orange
  - niedrig rot
  - Bolus blau
  - Autokorrektur lila
  - Auto-Basal türkis
- **Keine Verläufe, kein Glas, keine Emojis** in der App. Flächen ruhig, Karten mit dezentem Hintergrund, viel Weißraum.
- **Typografie:** Werte in SF Rounded, tabellarische Ziffern; Text in SF Pro. Eine klare Hierarchie: großer Wert, darunter Kontext, dann Details.
- **Startseite:** oben der aktuelle Wert, darunter der Graph. Statuskarte nur, wenn etwas zu tun ist (nicht gekoppelt, Verbindung weg, Alarme stumm). Die Kacheln werden zu einer kompakten Liste mit Symbolen.
- **Symbole:** nur SF Symbols, einheitliche Strichstärke.
- **Ton:** kurz, sachlich, Deutsch; Fachbegriffe wie auf der Pumpe (SmartGuard, IE, SG).
- **Dunkelmodus** gleichwertig gestalten, Graph-Farben darauf abstimmen.
