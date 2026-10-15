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
┌──────────────────┐   HTTP / JSON    ┌──────────────────┐   JSON-RPC    ┌─────────────────────┐
│ Téléphone        │ ───────────────► │ Serveur Node.js  │ ────────────► │ Odoo 18             │
│ (Flutter)        │                  │ backend/, :3001  │               │ + module            │
│ - scan           │ ◄─────────────── │ - relais Odoo    │ ◄──────────── │   wise_inventory    │
│ - stockage local │                  │ - liste partagée │               │                     │
└──────────────────┘                  └──────────────────┘               └─────────────────────┘
```

| Composant | Rôle | Emplacement |
|---|---|---|
| **Application mobile** | Écrans, scan, stockage sur le téléphone, mode hors ligne | `lib/` |
| **Serveur Node** | Connexion à Odoo, relais des appels, liste partagée entre deux téléphones | `backend/src/` |
| **Module Odoo** | Règles métier : feuilles, lignes, consolidation, application au stock, route d'envoi mobile | `C:\Odoo 18.0.20250623\server\wiserp_v18\wise_inventory` |

Le téléphone ne parle **jamais directement à Odoo** (sauf pour lister les bases
à la connexion). Toutes les règles sont appliquées par Odoo : qui peut commencer
ou terminer une feuille, un seul comptage en cours par zone, un numéro une seule
fois par feuille, quantité 1 pour un article suivi par numéro de série, etc.

L'adresse du serveur Node est définie dans `lib/services/api_config.dart`
(`baseUrl`).

---

## 3. Parcours de l'utilisateur

### 3.1 Connexion
- Saisie de l'adresse Odoo, de l'email et du mot de passe.
- À chaque lancement, l'application se reconnecte avec la session enregistrée.
- **Sans réseau au lancement**, la session est conservée et l'application
  s'ouvre en mode hors ligne (les scans et les lots restent sur le téléphone).
  La session n'est effacée que si Odoo refuse les identifiants.

### 3.2 Choix de l'inventaire
- Liste des ajustements **en brouillon ou en cours** qui concernent
  l'utilisateur connecté :
  - ceux dont il est **responsable d'ajustement** (`manager_id`) ;
  - ceux où il a **une feuille de comptage** (responsable de comptage,
    attribué via « Resp. Equipes » de l'ajustement général).

  Les autres ajustements n'apparaissent pas, même pour un administrateur.
- Écran de choix :
  - **Feuille de comptage** : le travail des équipes ;
  - **Préparer le hors ligne** : télécharge ce qu'il faut pour compter sans
    réseau (voir §4) ;
  - **Gestion des consolidations** : le travail du responsable.

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
  quantité), déjà dans un lot sauvegardé, déjà envoyé à l'ERP.
- **Deux téléphones peuvent scanner la même feuille** : la liste est partagée
  par le serveur Node et rafraîchie toutes les 4 s.
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

### 4.1 Préparer (avec réseau)
Le bouton **Préparer le hors ligne** (écran de choix) télécharge en un appel :
- les feuilles de l'utilisateur pour l'inventaire ;
- tous les **numéros de série / lots en stock** dans l'emplacement inventorié,
  avec leur article ;
- pour chaque feuille, les **numéros déjà envoyés** à Odoo.

La carte indique ensuite « Prêt : N numéros · mis à jour le … ». Rien n'est
téléchargé automatiquement : il faut refaire « Préparer » pour rafraîchir.

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
- L'application passe **hors ligne** dès qu'un appel au serveur Node échoue
  (immédiat sans réseau ; jusqu'à 8 à 20 s si le Wi-Fi est connecté mais le
  serveur injoignable). Un **bandeau orange** apparaît en haut de tous les
  écrans : « Hors ligne · N lot(s) en attente d'envoi ».
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
Route `POST /wise_inventory/api/sheet/submit` du module, **une transaction** :
- démarre la feuille si elle est encore « Nouveau » ;
- **ignore les numéros déjà présents** sur la feuille : renvoyer un lot ne crée
  jamais de doublon (protégé aussi par la contrainte `unique(sheet_id, number)`) ;
- identifie l'article à partir du numéro (y compris les numéros « à vérifier ») ;
- crée les lignes ; une ligne refusée est signalée avec la raison d'Odoo, les
  autres sont gardées ;
- valide la feuille si le lot contient 50 articles ou plus et qu'aucune ligne
  n'a été refusée.

Si le module installé n'a pas encore cette route, le serveur Node utilise
l'ancien chemin (appels `call_kw` successifs) avec les mêmes garanties.

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
| Odoo injoignable, rien n'a été envoyé | Le serveur Node ne joint pas Odoo |
| Session expirée : veuillez vous reconnecter | Reconnexion automatique impossible |
| Le serveur ne répond pas (délai dépassé) | Réseau trop lent ou serveur arrêté |

---

## 6. Données gardées sur le téléphone

Toutes les données sont séparées **par compte** (adresse Odoo + email).

| Donnée | Effacée quand |
|---|---|
| Liste en cours de scan (par feuille) | Enregistrement en lot, envoi direct, déconnexion |
| Lots en attente d'envoi | Envoi accepté par Odoo, suppression manuelle |
| Démarrages / fins faits hors ligne | Rejoués dans Odoo (ou refusés) |
| Numéros de l'inventaire (préparation) | Déconnexion (re-téléchargés par « Préparer ») |
| Numéros déjà envoyés par feuille | Déconnexion |
| Dernières listes d'inventaires et de feuilles | Déconnexion |
| Identifiants de connexion | Déconnexion, ou identifiants refusés par Odoo |

---

## 7. Serveur Node — principales routes

| Route | Usage |
|---|---|
| `POST /auth/login` | Connexion (401 = identifiants refusés, 502 = Odoo injoignable) |
| `GET /adjustments` | Ajustements en brouillon / en cours dont l'utilisateur est responsable ou où il a une feuille |
| `GET /feuilles/:adjustmentId` | Feuilles de l'utilisateur |
| `GET /counting/offline-pack/:adjustmentId` | Préparation hors ligne (feuilles, numéros, déjà envoyés) |
| `POST /counting/lookup-product` | Article d'un numéro + « déjà envoyé » (1 appel par scan inconnu) |
| `POST /counting/lookup-products` | Identification des numéros scannés hors ligne |
| `POST /counting/submit-scans` | Envoi d'un lot (via la route du module) |
| `POST /counting/start-sheet`, `/validate-sheet` | Commencer / terminer une feuille |
| `GET /counting/live-items/:sheetId`, `POST /counting/live-scan` | Liste partagée entre deux téléphones |
| `/consolidation/...` | Zones à consolider, consolidations, application |

---

## 8. Déploiement

1. **Module Odoo** : vérifier l'absence de doublons (feuille, numéro), puis
   mettre à jour `wise_inventory` (`-u wise_inventory`).
   ```sql
   SELECT sheet_id, number, count(*) FROM counting_sheet_line
   WHERE sheet_id IS NOT NULL AND number IS NOT NULL
   GROUP BY sheet_id, number HAVING count(*) > 1;
   ```
2. **Serveur Node** : `cd backend && npm install && npm start` (port 3001).
3. **Application** : vérifier `baseUrl` dans `lib/services/api_config.dart`,
   puis `flutter analyze` et `flutter build apk`.

La nouvelle application nécessite le nouveau serveur Node. Le serveur Node
fonctionne avec l'ancien comme avec le nouveau module.

---

## 9. Limites connues
- Le serveur Node utilise **une seule session Odoo** pour tous les téléphones
  (le dernier connecté) : à corriger pour un usage multi-utilisateurs réel.
- Mot de passe enregistré en clair sur le téléphone ; serveur Node en HTTP sans
  jeton d'accès.
- Si Odoo est arrêté mais le serveur Node joignable, l'application reste « en
  ligne » et affiche des erreurs « Odoo injoignable » au lieu du bandeau.
- Un très grand emplacement (dizaines de milliers de numéros) rend la
  préparation hors ligne lourde (stockage `SharedPreferences`).
