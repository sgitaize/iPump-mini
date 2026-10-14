# ADR 0002: Lizenz (offen)

- Status: **angenommen: GPL-3.0** (2026-10-14, Simon)
- Datum: 2026-10-14

## Kontext
Das Projekt soll später veröffentlicht werden. Relevant sind die Kompatibilität mit möglichen Fremdprojekten, die wir wiederverwenden (Ergebnis von Phase 1), der App-Store-Vertrieb unter iOS und der Haftungsausschluss.

## Optionen

| Lizenz | Pro | Contra |
|---|---|---|
| **GPL-3.0** | Copyleft, passt zu xDrip+, AndroidAPS und 600SeriesAndroidUploader (alle GPL-3.0). Code aus diesen Projekten wäre übernehmbar. | Verträgt sich schlecht mit dem App Store (bekannter Konflikt zwischen FSF und den Apple-Nutzungsbedingungen). Für iOS ist Selbst-Build oder TestFlight trotzdem möglich. |
| **AGPL-3.0** | Erfasst auch die Nutzung über ein Netzwerk (wegen der REST-API) | dieselben App-Store-Probleme, schreckt Integratoren ab |
| **MIT / Apache-2.0** | Maximal kompatibel und App-Store-tauglich. Apache-2.0 enthält eine Patentklausel. | Erlaubt geschlossene Forks. GPL-Code aus Fremdprojekten darf nicht übernommen werden. |
| **MPL-2.0** | Copyleft auf Dateiebene, App-Store-tauglich | weniger verbreitet in der DIY-Diabetes-Szene |

## Vorläufige Tendenz
Wir entscheiden nach Phase 1. Übernehmen wir GPL-Code, ist GPL-3.0 zwingend. Bei einer Neuentwicklung ist Apache-2.0 oder MPL-2.0 attraktiv, weil der Fokus auf iOS liegt.

## Entscheidung
GPL-3.0. Das Projekt wird Open Source und baut auf OpenMinimed (GPL-3.0) auf, siehe ADR 0003. Für iOS: Selbst-Build bzw. TestFlight statt App Store.
