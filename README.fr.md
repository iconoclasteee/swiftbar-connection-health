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
- [Journal CSV — constituer une preuve pour ton FAI](#journal-csv--constituer-une-preuve-pour-ton-fai)
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
- **Journal CSV + rapport** — enregistre chaque sonde pendant des jours, puis en tire un résumé qui attribue une dégradation à une couche précise : ton lien, l'uplink opérateur, ou toute la chaîne.
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

## Journal CSV — constituer une preuve pour ton FAI

« On ne détecte rien de notre côté » est la réponse standard à une panne intermittente. Le journal existe pour clore cette conversation : il enregistre **chaque sonde**, horodatée et associée au nom du réseau, aussi longtemps que tu le laisses tourner.

### Lancer, mettre en pause, arrêter, ouvrir

Tout est dans le menu déroulant du voyant — aucune commande shell, rien à retenir. Le menu affiche en permanence l'état du journal :

```
📓 Journal actif · 20K · 176 relevés — ouvrir
⏹ Arrêter le journal…
📂 Montrer dans le Finder
```

| Ligne | Ce que le clic fait |
|---|---|
| **📓 Journal actif · taille · relevés** | **ouvre le fichier** dans l'app associée aux `.csv`. « Où est mon journal » et « est-ce qu'il enregistre » sont la même question : elles partagent donc la même ligne. Quand le suivi est arrêté, elle affiche `📓 Journal arrêté · 20K conservés — ouvrir` |
| **⏺ Démarrer le journal** | lance ou reprend l'enregistrement (s'affiche quand c'est arrêté) |
| **⏹ Arrêter le journal…** | arrête, puis **demande s'il faut vider le journal** — voir ci-dessous |
| **📂 Montrer dans le Finder** | révèle le fichier dans le Finder sans l'ouvrir |

Le libellé dit toujours l'état courant **et** l'action du clic : « Arrêter » ne s'affiche que si ça tourne.

### Arrêter ≠ vider

Les points de suspension de « Arrêter le journal… » annoncent une question. À l'arrêt, une fenêtre s'ouvre :

> **Suivi arrêté.**
> Vider le journal (176 relevés, 20K) ou le conserver pour continuer plus tard ?
> `[ Conserver ]` `[ Vider ]`

**« Conserver » est le bouton par défaut** : une pause pendant une visio ne doit pas détruire trois jours de preuves. Une frappe de trop sur Entrée, ou un Échap, conservent les données. Il faut cliquer explicitement sur « Vider » pour effacer.

Reprendre écrit dans le **même fichier** : une pause laisse un trou visible dans les horodatages plutôt que de perdre l'historique — et `--report` compte ce trou séparément des vraies coupures.

### En ligne de commande

L'état tient dans un unique fichier témoin, dont la seule présence est l'interrupteur :

```sh
touch ~/Library/Logs/.connection-health-logging   # démarrer
rm    ~/Library/Logs/.connection-health-logging   # arrêter, sans poser de question
open  ~/Library/Logs/connection-health.csv        # ouvrir
open -R ~/Library/Logs/connection-health.csv      # montrer dans le Finder
```

Il n'y a aucun processus dédié à surveiller ni à tuer : c'est le plugin lui-même qui écrit une ligne à chacun de ses passages.

### Ce qui est enregistré

`~/Library/Logs/connection-health.csv`, séparateur point-virgule : s'ouvre directement dans Excel FR sans assistant d'import.

Le contexte d'abord (quand, où, quel état), puis **un bloc de mesure par couche** : chaque temps de réponse est immédiatement suivi de l'adresse réellement mesurée, pour qu'une ligne se lise seule sans rien croiser.

| # | Colonne | Signification |
|---|---|---|
| 1 | `timestamp` | `2026-08-24 10:14:23.02` — **au centième de seconde**, sinon deux relevés de la même seconde sont indiscernables |
| 2 | `network` | nom du Wi-Fi, ou type de lien à défaut — c'est ce qui te permet de **filtrer les heures passées en partage de connexion** |
| 3 | `link` | Wi-Fi / iPhone USB / Bluetooth PAN… |
| 4 | `state` | sain / correct / moyen / mauvais / hors-ligne / portail captif |
| 5 | `local_ip` | ton IP privée |
| 6 | `rtt_gw_ms` | ping ICMP de ta box, sur le LAN |
| 7 | `gw_ip` | ↳ l'adresse pinguée : `192.168.1.254` |
| 8 | `rtt_uplink_ms` | ping ICMP d'une IP publique brute, **sans DNS** |
| 9 | `uplink_ip` | ↳ l'adresse pinguée : `1.1.1.1` (réglable par `UPLINK_IP`) |
| 10 | `rtt_web_ms` | handshake TCP vers le nom d'hôte de `URL` |
| 11 | `web_ip` | ↳ l'adresse **réellement atteinte**, telle que curl la rapporte : `2a00:1450:4007:81c::2003` |
| 12-13 | `raw_ok`, `dns_ok` | les deux signaux du diagnostic, renseignés quand la sonde échoue |
| 14 | `epoch` | le même instant en secondes Unix, centièmes compris — pour trier et calculer sans reparser une date |

### Ce que mesure chacun des trois

| Colonne | Ce qui est traversé | Ce qu'un pic accuse |
|---|---|---|
| `rtt_gw_ms` | ton Wi-Fi (ou ton câble) puis ta box, **rien d'autre** | **ton côté** : interférence Wi-Fi, distance, box saturée |
| `rtt_uplink_ms` | tout ce qui précède **+ la fibre, le point de mutualisation, le réseau opérateur** | **l'opérateur** : c'est la colonne qui accuse Bouygues |
| `rtt_web_ms` | tout ce qui précède **+ le DNS, le peering, le CDN de destination** | la chaîne complète : si seule celle-ci monte, regarde d'abord le DNS ou le serveur visé |

Chaque colonne contient la précédente. **Lues de gauche à droite, elles isolent la couche fautive :** un pic qui apparaît en colonne 8 mais pas en colonne 6, c'est en amont de ta box. Une ligne à `rtt_gw_ms=2`, `rtt_uplink_ms=340`, `rtt_web_ms=420` est exactement cette preuve — et c'est ce qui transforme « redémarrez votre box » en escalade réelle.

`web_ip` n'est pas décoratif : le CDN change de nœud, et l'adresse dit aussi si la sonde est passée en **IPv4 ou IPv6**. Une dégradation qui ne touche que l'IPv6 est un vrai mode de panne, invisible autrement.

> **Changement de schéma.** L'ordre des colonnes vit dans une seule constante, `LOG_HEADER`, qui sert aussi de contrôle : un journal dont l'entête ne correspond pas est **mis de côté** sous `connection-health-AAAAMMJJ-HHMMSS.csv` et un fichier neuf démarre. Deux ordres de colonnes ne peuvent donc jamais se retrouver mélangés dans le même fichier — ce qui rendrait tout rapport faux sans prévenir.

> **Changement de schéma.** L'ordre des colonnes vit dans une seule constante, `LOG_HEADER`, qui sert aussi de contrôle : un journal dont l'entête ne correspond pas est **mis de côté** sous `connection-health-AAAAMMJJ-HHMMSS.csv` et un fichier neuf démarre. Deux ordres de colonnes ne peuvent donc jamais se retrouver mélangés dans le même fichier — ce qui rendrait tout rapport faux sans prévenir.

### Le rapport

```sh
~/dev/swiftbar-connection-health/plugins/connection.5s.sh --report
```

Ne lit que le journal, jamais le réseau — utilisable pendant que l'enregistrement continue.

```text
Période : 2026-08-23 17:46:40.00  ->  2026-08-23 19:08:50.54
Relevés : 186  (~15 min 30 s)
Trous (Mac en veille / SwiftBar arrêté) : 1  (1 h 06 min)

Par réseau
  réseau                    relevés   coupé    lent    max box  max uplink    max web
  Bbox-Vernon                   156      12      24       2 ms      340 ms     420 ms
  Oli iPhone                     30       0       0       3 ms       45 ms      52 ms

Épisodes dégradés les plus longs
  début                            durée   nature       réseau
  2026-08-23 17:51:41.79      3 min 01 s   mixte        Bbox-Vernon
```

Les trois colonnes de maxima suivent le trajet physique du paquet : **box → uplink → web**. Lues de gauche à droite, elles disent où la latence apparaît. Ici `2 ms` chez toi et `340 ms` dès la sortie de la box : le défaut n'est pas dans ton salon.

Les trous sont comptés **à part** des coupures, volontairement : un Mac en veille n'est pas une panne réseau, et le compter comme telle détruirait la crédibilité de tout le document.

### Combien de temps le laisser tourner

Cinq à sept jours sans interruption. En dessous de 48–72 h, impossible de distinguer un motif journalier (pic du soir, maintenance de nuit) d'un mauvais après-midi ; une semaine complète sépare la semaine du week-end. Ne l'arrête pas la nuit — une panne qui ne survient qu'entre 2 h et 5 h du matin, c'est de la maintenance opérateur, et c'est une trouvaille précieuse que tu ne verrais jamais autrement.

Le journal n'avance que si le Mac est éveillé et SwiftBar lancé. Pour couvrir les nuits sans surveillance, garde le Mac éveillé sur secteur :

```sh
caffeinate -s      # à laisser tourner dans un terminal ; Ctrl-C l'arrête
```

### Coût

| Ressource | Impact |
|---|---|
| CPU | un cycle de shell toutes les 5 s, une fraction de seconde chacun. N'entre jamais en concurrence avec l'encodeur d'une visio. |
| Réseau | deux paquets ICMP plus une requête HTTP `204` par cycle, ~200 octets / 5 s. Une visio consomme 1,5 à 3 Mbps — cinq ordres de grandeur au-dessus. |
| Disque | **140 octets par ligne** (mesuré, pas estimé) → **2,3 Mo par jour, 16 Mo pour une semaine** en 24/7. Voir le détail ci-dessous. |
| Batterie | les pings supplémentaires ne partent **que** si le lien est actif ; sur un lien mort le plugin les saute au lieu de brûler 2 s par cycle en timeouts. |

Tu peux supprimer le fichier quand tu veux — il est recréé avec son entête à la ligne suivante.

#### Taille du journal, mesurée

Une ligne réelle fait **140 octets** (relevé sur 204 lignes : min 139, max 141). À un relevé toutes les 5 s, soit 17 280 par jour :

| Durée en 24/7 | Taille |
|---|---|
| 1 jour | **2,3 Mo** |
| **1 semaine** | **16 Mo** |
| 1 mois | 69 Mo |
| 1 an | 845 Mo |

Deux nuances : les lignes de coupure sont plus courtes (les colonnes de mesure sont vides), et une sonde web qui passe en IPv4 fait gagner une douzaine d'octets par ligne face à une adresse IPv6. 16 Mo est donc un plafond réaliste, pas un plancher.

Pour la semaine de mesure visée, aucune rotation n'est nécessaire. Au-delà, le fichier se compresse remarquablement bien — les lignes sont très répétitives : `gzip` ramène la semaine à **1,3 Mo**, soit un facteur 12.

```sh
gzip -k ~/Library/Logs/connection-health.csv     # garde l'original à côté
```

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
| `LOG_CSV` | `~/Library/Logs/connection-health.csv` | chemin du journal ; `""` retire la fonction et ses entrées de menu |
| `LOG_FLAG` | `~/Library/Logs/.connection-health-logging` | fichier témoin : présent = enregistrement actif |
| `UPLINK_IP` | `1.1.1.1` | pingué uniquement pendant l'enregistrement — RTT uplink sans DNS |
| `BAR_FONT` | `Menlo-Regular` | police de la barre ; `""` = police système |
| `BAR_SIZE` | `""` | taille ; `""` = valeur par défaut de SwiftBar |
| `INFO_LIGHT` / `INFO_DARK` | `#555555` / `#aaaaaa` | gris des lignes d'info, mode clair / sombre |
| intervalle | `5s` dans le **nom du fichier** | **ne pas descendre sous 5 s** — sur un lien mort la chaîne de sondes coûte ~3,2 s (mesuré), et un intervalle plus court empilerait des exécutions pendant la panne même que tu documentes |

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
./connection.5s.sh --report   # résumé du journal CSV (ne lit que le fichier)
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
| Un voyant manque dans la barre | un gestionnaire de barre de menus (Bartender, Ice, Hidden Bar…) l'a rangé dans la zone masquée | déplier la zone masquée, ou ⌘-glisser l'élément hors de celle-ci |
| Le journal a un gros trou | le Mac a dormi, ou SwiftBar était arrêté | normal — `--report` le compte comme un trou, jamais comme une coupure. `caffeinate -s` pour les nuits sans surveillance |
| `--report` dit que le journal est introuvable | l'enregistrement n'a jamais été démarré | menu → **⏺ Démarrer le journal** |
| ⚠️ *Boutons désactivés : un espace dans …* | le dossier de plugins ou le chemin du journal contient un espace, or SwiftBar découpe ses paramètres `bash=` sur les espaces | déplacer le plugin dans un dossier sans espace, ou pointer `LOG_CSV` vers un chemin sans espace |

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
