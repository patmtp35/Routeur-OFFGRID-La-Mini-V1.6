# offsrmini : modifications par rapport au composant d'origine

Copie du composant `offsr` de **SeByDocKy**, adaptée à un pack de batteries 24 V.

- Source : [SeByDocKy/myESPhome](https://github.com/SeByDocKy/myESPhome), dossier `components/offsr`
- Version copiée : commit `12fb7b56ea32077d93d7dc2d2706528b0caa9113` (25/10/2026)
- Licence amont : aucune au moment de la copie. Les droits sur le code restent à son auteur. Cette copie est fournie pour faciliter l'usage de `la-mini.yaml` ; elle sera retirée si l'auteur le demande.

**La logique de régulation n'est pas modifiée** : `offsr.cpp`, les `.cpp` et `.h` des sous-composants, et tous les autres fichiers sont identiques à l'original (hors fins de ligne), sauf ceux du tableau ci-dessous.

## Ce qui change

| # | Fichier | Original | `offsrmini` | Pourquoi |
|---|---|---|---|---|
| 1 | dossier | `components/offsr` | `components/offsrmini` | Cohabiter avec un `offsr` déjà présent dans le même `components/` |
| 2 | `binary_sensor/__init__.py`, `number/__init__.py`, `select/__init__.py`, `sensor/__init__.py`, `switch/__init__.py` | `DEPENDENCIES = ["offsr"]` | `DEPENDENCIES = ["offsrmini"]` | Nom du composant = nom du dossier |
| 3 | `number/__init__.py` | bornes `starting` 45–60 V, `charged` 50–60 V, `discharged` 45–60 V | 20–64 V pour les trois | Les bornes d'origine (~48 V) excluaient le 24 V ; 20–64 V couvre les deux |
| 4 | `__init__.py` | pas d'option de profil | option `battery_voltage: 24` ou `48` (24 par défaut), qui appelle `set_default_battery_voltages(...)` | Un seul flag pour choisir les seuils de départ |
| 5 | `offsr.h` | pas de setter | `set_default_battery_voltages(starting, charged, discharged)` | Reçoit les valeurs du profil avant l'initialisation des entités number |
| 6 | profil `48` | 53,0 / 55,8 / 55,6 V (défauts d'origine de Seby) | identique | Rien ne change pour un 48 V |
| 7 | profil `24` | — | 27,0 / 28,0 / 27,6 V (démarrage / chargée / déchargée) | Valeurs de départ pour un gel 24 V |
| 8 | `offsr.h` | `output_min` 0,18 | 0,0 | Un triac doit pouvoir descendre à 0 % |
| 9 | `offsr.h` | consigne de charge 20 A | 15 A | La pince HSTS016L sature vers 19 A |
| 10 | tous les `.h`, `.cpp`, `.py` | fins de ligne CRLF | LF | Normalisation |
| 11 | `testoffsr.yaml` | présent | supprimé | Exemple de l'auteur, inutile ici |

Les seuils, `output_min` et la consigne se règlent aussi à l'exécution (curseurs, mémorisés en flash). Le flag `battery_voltage` ne change que les valeurs de départ : un seuil déjà mémorisé en flash n'est pas écrasé. L'espace de noms C++ reste `offsr` : ne mets pas `offsr` et `offsrmini` dans le même firmware.

## Vérifier

`offsrmini-vs-upstream.diff` contient le diff exact (fins de ligne ignorées, `testoffsr.yaml` exclu).

## Refaire cette copie

`prepare-offsr.sh` (à la racine du dépôt) la recrée à partir de la dernière version de Seby, avec les mêmes modifications, et accepte d'autres valeurs de départ (`V24_START`, `V24_CHARGED`, `V24_DISCH`, `OUT_MIN`, `SP_CHARGE`).
