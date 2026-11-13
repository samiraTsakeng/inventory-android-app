# Wise Inventory — fonctionnement de l'application

Application Android de **comptage d'inventaire à l'aveugle**, reliée à Odoo 18
(module `wise_inventory`). Ce document décrit ce que fait l'application, comment
les données circulent, et comment fonctionnent le mode hors ligne et l'envoi.

---

## 1. Le principe : l'inventaire à l'aveugle

1. Un **ajustement d'inventaire** (`stock.inventory`) est créé dans Odoo sur un
   emplacement. Il est découpé en **zones de rangement**.
2. Chaque zone est comptée **deux fois, par deux équipes différentes**, sans
   voir le stock théorique. Chaque comptage est une **feuille de comptage**
   (`counting.sheet`) attribuée à un responsable d'équipe.
3. Les deux comptages d'une zone sont comparés (**consolidation**) :
   - les lignes identiques sont acceptées ;
   - les écarts deviennent des **lignes contradictoires**, vérifiées
     physiquement par le responsable.
4. Le résultat consolidé est **appliqué** à l'ajustement, qui corrige le stock.

L'application couvre tout ce cycle. Le **comptage** peut se faire entièrement
hors ligne ; la consolidation et l'application se font en ligne.

---

## 2. Architecture

```
┌──────────────────┐      JSON-RPC (session Odoo)      ┌──────────────────────────────┐
│ Téléphone        │ ────────────────────────────────► │ Odoo 18                      │
│ (Flutter)        │                                   │ + module wise_inventory      │
│ - scan           │ ◄──────────────────────────────── │   - API mobile               │
│ - stockage local │                                   │     /wise_inventory/api/...  │
└──────────────────┘                                   │   - liste partagée           │
                                                       └──────────────────────────────┘
```

| Composant | Rôle | Emplacement |
|---|---|---|
| **Application mobile** | Écrans, scan, stockage sur le téléphone, mode hors ligne | `lib/` |
| **Module Odoo** | Règles métier, API mobile (`controllers/mobile_api.py`), liste partagée entre deux téléphones (`counting.sheet.live.line`) | `C:\Odoo 18.0.20250623\server\wiserp_v18\wise_inventory` |

Le téléphone parle **directement à Odoo**, à l'adresse saisie à la connexion,
sans serveur intermédiaire. Il ouvre sa **propre session Odoo**
(`/web/session/authenticate`) et appelle les routes JSON du module avec le
cookie `session_id` : chaque appel s'exécute **avec les droits de
l'utilisateur connecté**. Toutes les règles sont appliquées par Odoo : qui peut
commencer ou terminer une feuille, un seul comptage en cours par zone, un numéro
une seule fois par feuille, quantité 1 pour un article suivi par numéro de
série, etc.

Le client est `lib/services/api_client.dart` (`ApiClient.call`) ; les routes
sont listées dans `lib/services/api_config.dart`. Une session expirée
(redémarrage d'Odoo...) est rouverte automatiquement avec les identifiants
enregistrés, puis l'appel est rejoué.

---

## 3. Parcours de l'utilisateur

### 3.1 Connexion
- **Première connexion** : adresse Odoo, email et mot de passe. Une adresse
  sans `http://` ni `https://` est complétée par `http://`. Il n'y a pas de
  champ pour la base : l'application essaie les bases du serveur jusqu'à
  celle qui accepte les identifiants.
- **Ensuite**, le serveur est retenu, même après une déconnexion : la page
  demande seulement l'email et le mot de passe (lien « Serveur : … · Changer »
  pour en changer).
- **Reconnexion** : le dernier compte est retenu aussi, la page demande
  seulement le mot de passe (« Bonjour … »), avec un lien « Changer de compte ».
- À chaque lancement avec une session enregistrée, l'application **s'ouvre
  tout de suite** et se reconnecte en arrière-plan. Sans réseau, elle reste en
  mode hors ligne (les scans et les lots restent sur le téléphone). Si Odoo
  refuse les identifiants, elle revient à la page de connexion.

### 3.2 Choix de l'inventaire
- Liste des ajustements **en brouillon ou en cours** qui concernent
  l'utilisateur connecté :
  - ceux dont il est **responsable d'ajustement** (`manager_id`) ;
  - ceux où il a **une feuille de comptage** (responsable de comptage,
    attribué via « Resp. Equipes » de l'ajustement général).

  Les autres ajustements n'apparaissent pas, même pour un administrateur.
- Écran de choix :
  - **Feuille de comptage** : le travail des équipes ;
  - **Gestion des consolidations** : le travail du responsable.

  Pas de bouton pour le hors ligne : une fois connecté, l'application
  travaille avec ou sans réseau (voir §4).

### 3.3 Comptage (responsables d'équipe)

La liste montre les feuilles de l'utilisateur pour cet inventaire :

| État | Boutons |
|---|---|
| **Nouveau** | Commencer |
| **En cours** | Scanner, Terminer |
| **Validé** | « ✓ Terminé » |
| Avec du travail en attente | Envoyer, et « N lot(s) à envoyer » |

« … · à synchroniser » signale une feuille commencée ou terminée **hors ligne**,
pas encore confirmée par Odoo.

**Écran de scan**
- Scan à la caméra ou saisie manuelle d'un numéro de série / lot.
- L'article est retrouvé à partir du numéro :
  - suivi par **numéro de série** : quantité 1 ;
  - suivi par **lot** : l'application demande la quantité.
- Contrôles anti-doublon : déjà dans la liste (proposition d'ajouter une
  quantité), déjà dans un lot sauvegardé, déjà envoyé à l'ERP. Un **numéro de
  série** déjà sur la feuille dans Odoo est refusé. Un **lot** déjà sur la
  feuille (saisi sur le web ou envoyé plus tôt) est accepté avec un
  avertissement : **la quantité du mobile est prioritaire** et remplacera
  celle d'Odoo à l'envoi.
- **Deux téléphones peuvent scanner la même feuille** : la liste est partagée
  par Odoo (modèle `counting.sheet.live.line`) et rafraîchie toutes les 4 s.
  Deux scans simultanés sont traités l'un après l'autre : jamais de doublon
  ni de quantité perdue.
- La liste est enregistrée sur le téléphone à chaque scan (elle survit à un
  crash ou une batterie vide).
- Icône en haut : verte si les numéros de l'inventaire sont sur le téléphone.

**Enregistrer en lot** : la liste en cours devient un **lot** sauvegardé sur
le téléphone, et la liste partagée est vidée pour le lot suivant.

**Terminer** une feuille :
- en ligne : refusé tant que la feuille a des lots non envoyés (sinon Odoo
  validerait une feuille incomplète) ;
- hors ligne : refusé tant que des articles scannés ne sont pas enregistrés en
  lot ; la fin est faite dans Odoo après l'envoi de tous les lots de la feuille.

### 3.4 Consolidation et application (responsable de l'ajustement)
Toujours en ligne.
1. **Consolider les zones** : une zone est prête quand ses deux feuilles sont
   validées. La consolidation crée une feuille de consolidation dans Odoo.
2. **Voir les consolidations** : pour chaque ligne contradictoire, saisir la
   **quantité vérifiée**, puis valider la consolidation.
3. **Appliquer la consolidation** : met à jour les quantités de l'ajustement.

---

## 4. Mode hors ligne

### 4.1 Préparation automatique
Une fois connecté, l'application télécharge **automatiquement**, avec les
droits Odoo de l'utilisateur, tout ce qu'il faut pour travailler sans réseau,
pour **chaque inventaire** qui le concerne (`OfflinePrepService`) :
- la liste des inventaires ;
- les feuilles de l'utilisateur pour chaque inventaire ;
- tous les **numéros de série / lots en stock** dans l'emplacement inventorié,
  avec leur article (seulement si l'utilisateur a une feuille à compter) ;
- pour chaque feuille, les **numéros déjà envoyés** à Odoo ;
- pour la consolidation : l'état de l'inventaire, les feuilles de
  consolidation, les zones et le détail de chaque feuille (consultables sans
  réseau ; les actions qui modifient le stock restent en ligne).

Elle se lance :
- après la connexion ;
- à chaque démarrage de l'application quand Odoo répond ;
- dès qu'un inventaire apparaît dans la liste sans être encore sur le
  téléphone (créé ou attribué après la connexion), ou qu'on l'ouvre ;
- au retour du réseau, si la dernière préparation a plus de 15 minutes ;
- au premier lancement en ligne d'une version dont la copie contient plus
  (les références des articles depuis la v2).

En plus, **à l'ouverture d'une feuille en ligne**, la copie de son inventaire
est mise à jour en arrière-plan (une requête) : le scan continue sur la copie
en place et la nouvelle la remplace à son arrivée. Une copie datant de la
connexion du matin ne vieillit donc pas toute la journée.

Les numéros recherchés un par un sur le serveur (hors de la copie) sont gardés
au plus 2000, les plus anciens oubliés d'abord, et effacés à chaque
préparation complète réussie.

Un message confirme la fin (« Mode hors ligne prêt : N feuille(s), M
numéros »). Le bandeau « Hors ligne » n'apparaît qu'une fois connecté, jamais
sur la page de connexion.

Il suffit donc de s'être connecté une fois avec du réseau : ensuite, le
comptage complet (commencer, scanner, enregistrer en lots, terminer) se fait
sans connexion, et est envoyé à Odoo au retour du réseau (§5).

### 4.2 Ce qui fonctionne sans réseau
| Action | Comportement hors ligne |
|---|---|
| Naviguer (inventaires, feuilles) | Dernières listes reçues |
| Commencer une feuille | Enregistré sur le téléphone, fait dans Odoo à l'envoi |
| Scanner un numéro préparé | Instantané, avec les contrôles anti-doublon |
| Scanner un numéro inconnu du téléphone | Ajouté « À vérifier (hors ligne) », vérifié à l'envoi |
| Enregistrer en lot | Normal |
| Terminer une feuille | Enregistré, fait dans Odoo après l'envoi des lots |
| Consolider, appliquer | Non (demande les deux comptages dans Odoo) |

### 4.3 Détection de la connexion
- L'application passe **hors ligne** dès qu'un appel à Odoo échoue
  (immédiat sans réseau ; jusqu'à 8 à 20 s si le Wi-Fi est connecté mais le
  serveur injoignable). Un **bandeau orange** apparaît en haut de tous les
  écrans : « Hors ligne · N lot(s) en attente d'envoi ».
- **Hors ligne, les écrans n'attendent plus le serveur** : ils affichent tout
  de suite la copie du téléphone. Le serveur est réessayé au plus toutes les
  20 s, à l'occasion d'une action de l'utilisateur. Les envois (« Envoyer »,
  vérification des numéros scannés hors ligne) essaient toujours le serveur.
- L'application **n'interroge pas le serveur en tâche de fond** pour savoir si
  le réseau est revenu. L'utilisateur touche **« Réessayer »** sur le bandeau.
- Au retour du réseau, un message rappelle ce qui attend, **sans rien envoyer**.

---

## 5. Envoi des données vers Odoo

### 5.1 Toujours manuel
Rien ne part sans action de l'utilisateur :
- **Envoyer** sur une feuille : envoie cette feuille seule ;
- **Tout envoyer** (icône nuage dans la barre de la liste des feuilles) :
  envoie toutes les feuilles, une par une ;
- les boutons de la **liste des lots** (un lot, ou tous les lots de la feuille).

### 5.2 Feuille par feuille, dans l'ordre
Pour chaque feuille, dans l'ordre où les actions ont été faites sur le téléphone :
1. **Commencer** dans Odoo (si la feuille a été commencée hors ligne) ;
2. ses **lots**, du plus ancien au plus récent ;
3. **Terminer** dans Odoo (si elle a été terminée hors ligne), seulement quand
   tous ses lots sont arrivés.

Cet ordre est nécessaire car Odoo n'accepte qu'un comptage en cours par zone :
la feuille 1 d'une zone doit être terminée avant que la feuille 2 de la même
zone soit commencée.

Un résumé s'affiche, par exemple :
```
Synchronisation
F1 : commencée, 3 lot(s) envoyé(s), terminée
F2 : refusé : Veuillez terminer le comptage précédent sur cette zone
```

### 5.3 Ce que fait Odoo à la réception d'un lot
Route `/wise_inventory/api/counting/submit` du module, **une transaction**
(deux envois de la même feuille sont traités l'un après l'autre) :
- démarre la feuille si elle est encore « Nouveau » ;
- ne crée **jamais de doublon** pour un numéro déjà présent sur la feuille
  (protégé aussi par la contrainte `unique(sheet_id, number)`) : **la quantité
  du mobile est prioritaire** et remplace celle de la ligne existante, qu'elle
  vienne du web ou d'un envoi précédent. À quantité égale (renvoi après une
  réponse perdue), rien ne change. Les quantités remplacées sont renvoyées
  (`updated_items`) et annoncées dans le message d'envoi ;
- identifie l'article à partir du numéro (y compris les numéros « à vérifier ») ;
- crée les lignes ; une ligne refusée est signalée avec la raison d'Odoo, les
  autres sont gardées ;
- valide la feuille si le lot contient 50 articles ou plus et qu'aucune ligne
  n'a été refusée.

### 5.4 Après l'envoi
- **Lot accepté** : supprimé du téléphone.
- **Lot refusé** (en tout ou en partie) : il reste sur le téléphone avec le
  message d'Odoo ; on peut le corriger (supprimer un numéro inconnu, par
  exemple) et le renvoyer. Les lignes déjà acceptées ne seront pas recréées.
- Les **numéros envoyés** restent connus du téléphone pour afficher « déjà
  envoyé à l'ERP » si quelqu'un les rescanne.

### 5.5 Messages d'erreur courants
| Message | Signification |
|---|---|
| Veuillez terminer le comptage précédent sur cette zone | Une autre feuille de la même zone est en cours dans Odoo |
| Vous n'êtes pas autorisé à effectuer ce Comptage | La feuille appartient à un autre responsable |
| Aucune ligne comptée | Terminer une feuille sans aucune ligne |
| Le numéro 'X' ne correspond à aucun article | Numéro inexistant dans Odoo (souvent une erreur de scan) |
| L'article … est suivi par N° de série … ne peut être différente de 1 | Quantité ≠ 1 sur un numéro de série |
| Le module wise_inventory n'est pas à jour sur le serveur Odoo | Le module installé n'a pas l'API mobile : mettre à jour `wise_inventory` |
| Session expirée : veuillez vous reconnecter | Reconnexion automatique impossible |
| Le serveur ne répond pas (délai dépassé) | Réseau trop lent ou Odoo arrêté |

---

## 6. Données gardées sur le téléphone

Toutes les données sont séparées **par compte** (adresse Odoo + email).

Les copies hors ligne (numéros de l'inventaire, numéros déjà envoyés, listes,
numéros recherchés) sont dans des **fichiers séparés**, lus une fois puis
gardés en mémoire ; seuls les petits réglages restent dans
`SharedPreferences`. Avant, tout y était (y compris le catalogue produits
complet copié à chaque connexion), et chaque scan réécrivait ce gros fichier :
c'était la cause principale de la lenteur. La mise à jour déplace les copies
existantes au premier lancement et supprime le catalogue, devenu inutile.

Les numéros lus par la caméra sont **nettoyés** (espaces, retours à la ligne,
séparateur GS1 des étiquettes DataMatrix) comme une saisie manuelle, dans
l'application et dans Odoo : sans cela, un numéro scanné hors ligne n'était
reconnu ni par la copie du téléphone ni à l'envoi.

Une étiquette porte **plusieurs codes** : le numéro de série, et souvent la
référence interne, le code-barres ou le numéro du fabricant (MPN, champ
`w_mpn_code` de `wise_sale`) de l'article. Avec les numéros en stock, Odoo
envoie au téléphone ces références (`refs`).

**La recherche se fait sur le téléphone, en ligne comme hors ligne**, sans
requête au scan :
- les 2 ou 3 codes lus sur l'étiquette sont comparés à la copie du téléphone ;
- **un** numéro de l'inventaire trouvé : il est ajouté ;
- **plusieurs** trouvés : une fenêtre les propose, tous cochés, et
  l'utilisateur décoche celui qui ne convient pas ;
- **aucun** trouvé : les références de l'article sont écartées et ce qui
  reste est gardé « à vérifier » (avec la même fenêtre s'il reste plusieurs
  codes) ; viser seulement une référence affiche « C'est la référence de
  l'article : visez le code du numéro de série » ;
- les numéros « à vérifier » sont identifiés à l'envoi, tous ensemble en une
  seule recherche (`lookup_products`).

Le serveur n'est interrogé au scan que si la copie du téléphone n'existe pas
encore (inventaire jamais préparé).

| Donnée | Effacée quand |
|---|---|
| Liste en cours de scan (par feuille) | Enregistrement en lot, envoi direct, déconnexion |
| Lots en attente d'envoi | Envoi accepté par Odoo, suppression manuelle |
| Démarrages / fins faits hors ligne | Rejoués dans Odoo (ou refusés) |
| Numéros de l'inventaire (préparation) | Déconnexion (re-téléchargés automatiquement à la connexion) |
| Numéros déjà envoyés par feuille | Déconnexion |
| Dernières listes d'inventaires et de feuilles | Déconnexion |
| Identifiants de connexion | Déconnexion, ou identifiants refusés par Odoo |
| Serveur et dernier compte (sans mot de passe) | « Changer de compte » / nouveau serveur |

---

## 7. API mobile du module — principales routes

Routes JSON-RPC (`type='json'`, `auth='user'`) de
`wise_inventory/controllers/mobile_api.py`, préfixe `/wise_inventory/api`.
Une réponse peut porter `_status` (400 refus, 404 introuvable) ; une erreur
Odoo remonte en erreur JSON-RPC avec son message.

| Route | Usage |
|---|---|
| `/adjustments` | Ajustements en brouillon / en cours dont l'utilisateur est responsable ou où il a une feuille |
| `/feuilles` | Feuilles de l'utilisateur pour un ajustement |
| `/counting/offline_pack` | Préparation hors ligne (feuilles, numéros, déjà envoyés) |
| `/counting/sheet_lots` | Même chose pour une feuille (écran de scan) |
| `/counting/lookup_product` | Article d'un numéro + « déjà envoyé » (1 appel par scan inconnu) |
| `/counting/lookup_products` | Identification des numéros scannés hors ligne |
| `/counting/submit` | Envoi d'un lot |
| `/counting/start_sheet`, `/counting/validate_sheet` | Commencer / terminer une feuille |
| `/counting/live_items`, `/live_push`, `/live_remove`, `/live_clear` | Liste partagée entre deux téléphones. Les scans partent ensemble, 0,8 s après le dernier, en un seul appel `live_push` (`live_scan`, un scan par appel, reste pour les anciennes versions) |
| `/counting/check_erp_scan(s)` | Numéros déjà envoyés sur une feuille |
| `/products/cache`, `/products/by_barcode` | Articles gardés sur le téléphone |
| `/consolidation/...` | Zones à consolider, consolidations, lignes contradictoires, application |

L'ancienne route `/sheet/submit` (utilisée par l'ancien serveur Node) est
conservée pour les téléphones pas encore mis à jour.

---

## 8. Déploiement

1. **Module Odoo** : vérifier l'absence de doublons (feuille, numéro), puis
   mettre à jour `wise_inventory` (`-u wise_inventory`, version 18.0.1.4.0 :
   API mobile et liste partagée).
   ```sql
   SELECT sheet_id, number, count(*) FROM counting_sheet_line
   WHERE sheet_id IS NOT NULL AND number IS NOT NULL
   GROUP BY sheet_id, number HAVING count(*) > 1;
   ```
2. **Application** : `flutter analyze` puis `flutter build apk`. Aucune adresse
   à configurer dans le code : l'utilisateur saisit l'adresse d'Odoo à la
   connexion.

Le téléphone doit pouvoir joindre Odoo (même réseau Wi-Fi, ou Odoo exposé).
L'application nécessite le module mis à jour ; avec un ancien module, elle
affiche « Le module wise_inventory n'est pas à jour sur le serveur Odoo ».

---

## 9. Limites connues
- Mot de passe enregistré en clair sur le téléphone (pour rouvrir la session
  Odoo) ; préférer Odoo en HTTPS hors du réseau local.
- L'application ne fonctionne pas en version web (navigateur) : le navigateur
  interdit de transmettre le cookie de session Odoo.
- Un très grand emplacement (dizaines de milliers de numéros) allonge la
  préparation hors ligne (téléchargement), sans ralentir les scans.
