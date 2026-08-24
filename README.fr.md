<div align="center">

# SwiftBar Connection Health

**Un voyant dans la barre des menus macOS qui répond d'un coup d'œil à une seule question : ma connexion internet est-elle saine, ou dois-je basculer sur un autre Wi-Fi / le partage 4G ?**

Construit autour d'une contrainte que la plupart des outils de barre de menus ignorent : le voyant occupe une **largeur strictement constante**, il ne décale donc jamais les icônes situés à sa gauche.

![macOS](https://img.shields.io/badge/macOS-Ventura%2B-000000?logo=apple&logoColor=white)
![SwiftBar](https://img.shields.io/badge/SwiftBar-plugin-FF6A00)
![bash](https://img.shields.io/badge/bash-3.2%2B-4EAA25?logo=gnubash&logoColor=white)
![i18n](https://img.shields.io/badge/i18n-EN%20%2F%20FR-blue)
![tests](https://img.shields.io/badge/tests-auto--test%20int%C3%A9gr%C3%A9-brightgreen)
![licence](https://img.shields.io/badge/licence-MIT-lightgrey)

[English](README.md) · **Français**

</div>

---

## À quoi ça ressemble

```text
┌─ barre des menus ───────────────────────────────────────────────┐
│                       🟡 120ms              🔋  📶  🕐  Toi...  │
└─────────────────────────────────────────────────────────────────┘
                          └── pastille colorée + latence, largeur fixe
```

La couleur donne le verdict instantané, le chiffre la nuance :

| Affichage | Signification | Seuil |
|---|---|---|
| 🟢 `42 ms` | sain | < 80 ms |
| 🟡 `120ms` | correct | 80 – 149 ms |
| 🟠 `200ms` | moyen | 150 – 279 ms |
| 🔴 `400ms` | mauvais, mais connecté | ≥ 280 ms |
| 🔴 `1834` | très mauvais — au-delà de 999 ms l'unité saute, la valeur reste exacte | ≥ 1000 ms |
| ⚫ `-OFF-` | aucun réseau → change de connexion | sonde en échec / timeout |
| 🚫 `LOGIN` | portail captif → ouvre un navigateur et authentifie-toi | réponse ≠ `204` |

Le texte fait **toujours 5 caractères**, dans une police monospace. `-OFF-` et `LOGIN` ne sont volontairement pas traduits : ils sont neutres linguistiquement et doivent rester à exactement 5 caractères. Le libellé complet vit dans le menu déroulant.

---

## Sommaire

- [Fonctionnalités](#fonctionnalités)
- [Prérequis](#prérequis)
- [Installation](#installation)
- [Le menu déroulant](#le-menu-déroulant)
- [Langue](#langue)
- [Helper « nom du Wi-Fi »](#helper--nom-du-wi-fi)
- [Réglages](#réglages)
- [Comment ça marche](#comment-ça-marche)
- [Tests](#tests)
- [Dépannage](#dépannage)
- [Structure du dépôt](#structure-du-dépôt)
- [Notes SwiftBar](#notes-swiftbar)
- [Contribuer](#contribuer)
- [Licence](#licence)

---

## Fonctionnalités

- **Largeur constante garantie** — 5 caractères, police monospace, contrat vérifié par l'auto-test intégré. Les icônes voisines ne bougent plus.
- **Distingue les trois façons d'être coupé** — aucun réseau (⚫), portail captif (🚫), et « réseau + DNS OK mais le web ne répond pas ».
- **Latence honnête** — le RTT du handshake TCP, pas le temps de requête total qui gonflerait le chiffre ×3-4.
- **Diagnostic à la demande** — les sondes supplémentaires (IP brute sans DNS, résolution de nom) ne s'exécutent *que* si la sonde principale échoue.
- **Bilingue** — tous les libellés en français ou en anglais, `UI_LANG` suit la langue du système par défaut.
- **Nom du Wi-Fi malgré le verrou macOS** — via un helper signé de 40 lignes, autorisé une fois pour toutes.
- **Lignes cliquables et utiles** — la passerelle ouvre l'interface admin de la box, la cause de panne ouvre les réglages Wi-Fi.
- **Empreinte minuscule** — quelques octets toutes les 5 s ; l'IP externe est mise en cache 3 minutes.
- **Auto-tests hors ligne** — logique de seuils, contrat de largeur et les deux tables de traduction sont vérifiés sans réseau.
- **Zéro dépendance** — bash 3.2, `curl`, `awk`, `route`, `networksetup`. Tout est livré avec macOS.

---

## Prérequis

| Élément | Détail |
|---|---|
| macOS | Testé sur macOS 26. L'URL de réglages Wi-Fi utilisée existe depuis Ventura (non vérifié en dessous). |
| [SwiftBar](https://github.com/swiftbar/SwiftBar) | `brew install --cask swiftbar` |
| Xcode CLT | Uniquement pour compiler le helper SSID optionnel (`swiftc`). Le plugin seul n'a besoin de rien. |

---

## Installation

```sh
# 1. SwiftBar
brew install --cask swiftbar

# 2. ce dépôt
git clone https://github.com/iconoclasteee/swiftbar-connection-health.git ~/dev/swiftbar-connection-health
chmod +x ~/dev/swiftbar-connection-health/plugins/connection.5s.sh

# 3. lancer SwiftBar et lui désigner le dossier de plugins
open -a SwiftBar
```

Au premier lancement, SwiftBar demande un **dossier de plugins** → choisir `~/dev/swiftbar-connection-health/plugins/`.

> Ce dossier est volontairement séparé de la racine du dépôt : SwiftBar exécute **tout** fichier exécutable du dossier qu'on lui donne, README compris.

**Facultatif** — afficher le nom du réseau Wi-Fi : voir [Helper « nom du Wi-Fi »](#helper--nom-du-wi-fi).

---

## Le menu déroulant

| Ligne | Contenu | Cliquable |
|---|---|---|
| **Réseau** | nom du Wi-Fi + type de lien (Wi-Fi / iPhone USB / Bluetooth PAN…) | → réglages Wi-Fi de macOS |
| **IP locale** | adresse privée ; `169.254.x` est signalé « pas de bail DHCP » | — |
| **Passerelle** | adresse de la box, côté LAN | → son interface d'administration |
| **IP externe** | adresse publique, cache 3 min — **elle change quand tu bascules de réseau**, ce qui confirme que la bascule a bien eu lieu | — |
| **Qualité** | le libellé complet : sain / correct / moyen / mauvais / hors-ligne / pas d'internet | — |
| **Latence** | valeur exacte en ms (RTT TCP) | — |
| **Réseau brut / DNS** | ✅ / ❌ — les deux signaux du diagnostic | — |
| **→ cause** | uniquement en panne : « aucun réseau » / « DNS en rade » / « le web ne répond pas » | → réglages Wi-Fi |
| **Vérifié à** | horodatage du dernier passage | — |

---

## Langue

`UI_LANG`, en haut du plugin, prend trois valeurs :

```bash
UI_LANG="auto"   # "fr" | "en" | "auto"
```

`auto` lit la langue préférée de macOS (`AppleLanguages`) et choisit le français sur un système français, l'anglais sinon. Mettre `fr` ou `en` pour figer le choix.

Ajouter une langue = ajouter un bras de `case` par clé dans `t()`. L'auto-test parcourt toutes les clés dans toutes les langues : un bras manquant fait échouer le test au lieu d'afficher silencieusement une ligne vide.

---

## Helper « nom du Wi-Fi »

**Le problème.** Depuis macOS Sonoma, lire le SSID exige la permission *Localisation* — le nom d'un réseau suffit à géolocaliser la machine. SwiftBar ne l'a pas : un plugin qui appelle CoreWLAN directement reçoit `<redacted>`.

**La solution.** Un mini-`.app` signé de 40 lignes, sans icône Dock, qui détient la permission et imprime le nom. L'autorisation est attachée à **l'identité du binaire**, pas au réseau : on l'accorde **une seule fois**, elle survit aux changements de Wi-Fi, aux redémarrages et aux mises à jour de macOS. Le plugin met le résultat en cache 30 s pour ne pas relancer le helper à chaque rafraîchissement.

```sh
# 1. compiler + installer
~/dev/swiftbar-connection-health/helper/build.sh

# 2. accorder la Localisation UNE fois — un dialogue apparaît dans Terminal.app → « Autoriser »
"$HOME/Library/Application Support/connexion-menubar/WifiSSID.app/Contents/MacOS/WifiSSID" --grant
```

Le binaire a deux modes : `--grant` (interactif, déclenche le dialogue) et sans argument (lecture du SSID, ce qu'appelle le plugin).

- **Recompiler** le helper change sa signature → refaire `--grant` une fois.
- **Révoquer** : Réglages → Confidentialité et sécurité → Localisation → décocher WifiSSID.
- **Sans le helper**, le plugin dégrade proprement : il affiche le type de lien et signale que le nom est masqué.

> Le chemin d'installation et l'identifiant de bundle contiennent encore `connexion-menubar`. Ce n'est pas un oubli : l'autorisation Localisation est attachée à cette identité, et la renommer révoquerait la permission pour tous ceux qui l'ont déjà accordée.

---

## Réglages

Tout se trouve dans le bloc `SETTINGS` en haut de `plugins/connection.5s.sh`.

| Réglage | Défaut | Effet |
|---|---|---|
| `UI_LANG` | `auto` | langue de l'interface : `fr`, `en`, ou suivre le système |
| `T_GREEN` / `T_YELLOW` / `T_ORANGE` | `80` / `150` / `280` ms | seuils des couleurs |
| `TIMEOUT` | `2` s | délai avant de déclarer le lien mort |
| `URL` | `gstatic.com/generate_204` | endpoint de la sonde |
| `EXT_IP_TTL` | `180` s | durée du cache de l'IP externe |
| `SSID_TTL` | `30` s | durée du cache du nom de Wi-Fi |
| `BAR_FONT` | `Menlo-Regular` | police de la barre ; `""` = police système |
| `BAR_SIZE` | `""` | taille ; `""` = valeur par défaut de SwiftBar |
| `INFO_LIGHT` / `INFO_DARK` | `#555555` / `#aaaaaa` | gris des lignes d'info, mode clair / sombre |
| intervalle | `5s` dans le **nom du fichier** | renommer en `connection.3s.sh` pour ~5 s de réactivité au lieu de ~7 s |

> **Pourquoi Menlo et pas SF Mono** — SF Mono est inutilisable ici : macOS n'expose que `.SF NS Mono`, un nom interne que `NSFont` refuse (vérifié via `NSFontManager`). Menlo est livré avec tout macOS. Avec `BAR_FONT=""`, les valeurs chiffrées restent alignées grâce au chiffre-espace (voir plus bas), seuls `-OFF-` et `LOGIN` décalent légèrement.

---

## Comment ça marche

### La sonde

Toutes les 5 s, **une seule** requête HTTP très légère vers un endpoint « 204 » (`gstatic.com/generate_204`, quelques octets), dont on extrait trois signaux :

1. **Temps de connexion TCP** (`time_connect − time_namelookup`) = la latence affichée. C'est le RTT du handshake, pas le temps total de la requête.
2. **Code HTTP** — `204` prouve que c'est bien le serveur visé qui a répondu. Tout autre code signifie qu'un intermédiaire s'est interposé : c'est le **portail captif** (Wi-Fi d'hôtel, d'aéroport, de train) → 🚫 `LOGIN`.
3. **Code de sortie de curl** — non nul = aucune réponse HTTP du tout → ⚫ `-OFF-`.

> **Pourquoi `http://` et pas `https://`** — en HTTPS, un portail captif casserait le TLS, curl échouerait, et on afficherait « hors-ligne » à tort : on perdrait l'information la plus actionnable (« va cliquer sur *J'accepte* »). Le prix payé est un endpoint en clair, sans conséquence ici puisqu'on n'envoie aucune donnée et qu'on ne lit qu'un code de retour.

**Uniquement en cas d'échec**, deux sondes indépendantes du DNS départagent la cause : une connexion TCP vers une IP brute (`1.1.1.1`, sans résolution) et une résolution de nom (`host`). D'où les trois verdicts : *aucun réseau*, *réseau OK mais DNS en rade*, *réseau + DNS OK mais le web ne répond pas*. Sur le chemin sain, elles ne tournent **jamais** — une requête vers un **nom** ayant réussi prouve déjà que réseau et DNS fonctionnent.

### La largeur constante

Deux mécanismes se cumulent, ce qui rend le résultat robuste même si l'un est désactivé :

1. **Une police monospace** (`BAR_FONT`) — 5 caractères = 5 largeurs identiques, lettres comprises.
2. **Le chiffre-espace U+2007**, un caractère espace exactement aussi large qu'un chiffre. Il remplace l'espace ordinaire entre la valeur et son unité, ce qui maintient l'alignement des valeurs chiffrées même sous la police système proportionnelle — car une espace ordinaire, elle, est *plus étroite* qu'un chiffre.

Le formatage vit dans une fonction pure `fmt_bar(clé_état, latence)` dont le contrat — *toujours 5 caractères* — est vérifié par l'auto-test. Deux détails y comptent :

- `09 ms` plutôt que ` 9 ms` : un zéro de tête est un vrai chiffre, il ne peut pas être rogné comme une espace en début de ligne.
- Au-delà de 999 ms, c'est **l'unité** qui saute, pas la valeur (`1834`) : quatre chiffres plus un remplissage occupent à peu près la même place que trois chiffres plus « ms ».

`state()` renvoie une clé indépendante de la langue (`healthy`, `captive`, …) et la traduction n'intervient qu'à l'impression. Cela garde une seule source de vérité pour l'état, et permet aux tests de porter sur des clés plutôt que sur des chaînes d'affichage.

### Détection de l'IP locale

`ipconfig getifaddr` ne connaît que les adresses distribuées par le service IPConfiguration. En partage de connexion iPhone, l'interface porte une adresse `192.0.0.x` qu'il ne signale *pas*, ce qui faisait afficher « pas de bail DHCP » alors que le lien fonctionnait parfaitement. Le plugin retombe désormais sur l'analyse de `ifconfig` avant d'affirmer cela.

---

## Tests

Les deux fonctions pures et les deux tables de traduction sont testables **sans réseau** :

```sh
cd ~/dev/swiftbar-connection-health/plugins
./connection.5s.sh --test     # seuils + contrat de largeur 5 caractères + toutes les clés i18n
./connection.5s.sh            # sortie SwiftBar réelle (nécessite le réseau)
```

```text
ok    state(0 204 13) = 🟢|healthy
ok    fmt_bar(offline 0) = [-OFF-] (5 chars)
ok    fmt_bar(healthy 42) = [42 ms] (5 chars)
ok    fmt_bar(poor 1834) = [1834 ] (5 chars)
ok    t(fr, q_healthy) = sain
ok    t(en, q_healthy) = healthy
--- ALL TESTS PASS
```

Le reste dépend du réseau réel et se vérifie à la main :

- [ ] Connecté normalement → 🟢, latence proche d'un speedtest
- [ ] Wi-Fi coupé → ⚫ `-OFF-` en ~7 s
- [ ] Wi-Fi d'hôtel / aéroport avant login → 🚫 `LOGIN`
- [ ] Bascule sur partage 4G/5G → voyant et ligne Réseau se mettent à jour, l'IP externe change

---

## Dépannage

| Symptôme | Cause probable | Correction |
|---|---|---|
| Le plugin n'apparaît pas | fichier non exécutable, ou plugin **ajouté** sans redémarrage de SwiftBar | `chmod +x`, puis `killall SwiftBar; open -a SwiftBar` |
| Les lignes du menu sont grisées | SwiftBar plus ancien, ou `bash=` retiré de la ligne | voir [Notes SwiftBar](#notes-swiftbar) |
| Le nom du Wi-Fi manque | helper non compilé, ou Localisation non accordée | `helper/build.sh`, puis `--grant` |
| ⚫ alors que le web fonctionne | `TIMEOUT` trop court sur un lien lent | monter `TIMEOUT` à 3 – 4 s |
| Le voyant paraît trop gros | Menlo a une hauteur d'x généreuse | régler `BAR_SIZE=12`, ou `BAR_FONT=""` |
| Latence bien plus élevée qu'un speedtest | normal : le RTT TCP inclut le saut Wi-Fi et la box | comparer plutôt à un `ping` de la passerelle |
| Mauvaise langue d'interface | la langue du système n'est ni le français ni l'anglais | figer `UI_LANG="fr"` ou `UI_LANG="en"` |

---

## Structure du dépôt

```text
swiftbar-connection-health/
├── plugins/
│   └── connection.5s.sh     # le plugin — réglages, i18n, fonctions pures, sonde, sortie
├── helper/
│   ├── agent.swift          # lecture du SSID via CoreLocation
│   ├── Info.plist           # LSUIElement : pas d'icône Dock
│   └── build.sh             # compile, signe, installe le .app
├── README.md                # version anglaise
├── README.fr.md             # ce fichier
└── LICENSE
```

---

## Notes SwiftBar

Trois comportements qui coûtent du temps quand on les découvre en cours de route :

- **Ajouter un nouveau plugin** (nouveau fichier) exige de **redémarrer SwiftBar** — un simple refresh ne le découvre pas. Modifier un plugin existant : le refresh suffit.
- **Lignes d'info lisibles** — macOS grise les éléments de menu *non cliquables*. Les rendre « actives » via une action neutre (`bash=/usr/bin/true`) lève le gris forcé **et** fait respecter `color=`. Effet de bord accepté : les lignes se surlignent au survol, le clic ne fait rien.
- **Couleur clair / sombre** — la syntaxe `color=clair,sombre` n'est **pas** supportée. Le plugin détecte le mode à l'exécution (`defaults read -g AppleInterfaceStyle`) et émet une seule couleur valide.

---

## Contribuer

Issues et pull requests bienvenues. Deux points à garder en tête :

- `./plugins/connection.5s.sh --test` doit passer. Si tu touches `fmt_bar`, ajoute le cas aux assertions de largeur ; si tu touches `t()`, le parcours des clés te couvre déjà.
- Le plugin cible **bash 3.2**, la version que macOS livre comme `/bin/bash`. Pas de tableaux associatifs, pas de `${var^^}`, pas de `$'\u…'`.

---

## Licence

[MIT](LICENSE) © Olivier Rhein
