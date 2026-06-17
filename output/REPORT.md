# OpenAnt Scan Report — `vuln/buffer-overflow`

**Date** : 2026-06-17  
**Run ID** : `run-20260617T135051-a94a9b46`  
**Target** : `../vuln/examples/buffer-overflow/vuln.c`  
**Language** : C  
**Models** : Claude Sonnet 4.5 (enhance) / Claude Opus 4.5 (analyze + verify) via Bedrock EU

---

## Résumé

| Métrique | Valeur |
|----------|--------|
| Fichiers scannés | 1 |
| Fonctions analysées | 2 |
| Stage 1 — Vulnérabilités détectées | **1** (check_password) |
| Stage 2 — Confirmées exploitables | **0** |
| Stage 2 — Verdict final | SAFE (non exploitable à distance) |
| Coût total | ~$0.13 |

---

## Pipeline

| Étape | Durée | Coût | Résultat |
|-------|-------|------|----------|
| Parse | 0.5s | $0.00 | 2 unités extraites |
| Enhance | 17.8s | $0.04 | 2/2 classifiées "exploitable" |
| Analyze (Stage 1) | 14.1s | $0.04 | 1 vulnerable, 1 safe |
| Verify (Stage 2) | 26.2s | $0.05 | 0 confirmée (1 disagreed) |

---

## Stage 1 — Détection

### 🔴 CWE-121 : Stack-based Buffer Overflow

| Champ | Détail |
|-------|--------|
| **Fonction** | `check_password(const char *input)` |
| **Fichier** | `vuln.c:4-15` |
| **Confiance** | 97% |
| **Verdict Stage 1** | VULNERABLE |

#### Description (Stage 1)

`strcpy(buffer, input)` copie une entrée contrôlée par l'attaquant dans un buffer stack de 16 octets sans bounds checking. Overflow → écrasement de `authenticated` → auth bypass. Payload plus long → contrôle de l'adresse de retour → RCE.

#### Vecteur d'attaque proposé

```
Fournir une chaîne de >=16 octets via argv[1] pour que strcpy déborde buffer[16]
et écrase l'entier 'authenticated' adjacent.
```

---

## Stage 2 — Vérification par simulation d'attaque

### Verdict : ❌ DISAGREED → SAFE

**Le Stage 2 infirme la vulnérabilité pour le modèle d'attaquant par défaut.**

#### Raisonnement du vérificateur

> L'analyse technique du Stage 1 est correcte (strcpy dans un buffer 16 octets sans bounds check). Cependant, l'évaluation de vulnérabilité ne prend pas en compte le modèle d'attaquant.
>
> C'est une application CLI standalone qui accepte l'entrée uniquement via les arguments de ligne de commande (argv[1]). Il n'y a pas d'interface réseau, pas de service web, pas de mécanisme d'entrée à distance.
>
> Pour le modèle d'attaquant défini ("un attaquant sur internet avec un navigateur"), il n'y a AUCUN MOYEN d'atteindre ce code vulnérable. L'attaquant aurait besoin de :
> 1. Un accès local à la machine
> 2. La capacité d'exécuter le binaire
> 3. La capacité de passer des arguments en ligne de commande
>
> Ce n'est pas une vulnérabilité exploitable à distance.

#### Exploit Path Analysis

| Champ | Détail |
|-------|--------|
| Entry point | `argv[1]` — LOCAL ACCESS ONLY |
| Sink reached | ❌ Non |
| Path broken at | Entry point requires local access — no network/remote input path |

#### Data Flow

1. User runs program locally with `argv[1]`
2. `main()` passes `argv[1]` to `check_password()`
3. `check_password()` calls `strcpy(buffer, input)` with no bounds check
4. Buffer overflow occurs if input > 15 bytes

#### Conclusion du vérificateur

> Le code contient une véritable vulnérabilité de buffer overflow (CWE-120). **Si ce code était intégré dans un service réseau ou une application web** où des utilisateurs distants pourraient fournir le paramètre 'input', il serait critiquement vulnérable. En tant qu'outil CLI standalone, il ne pose aucun risque pour les attaquants distants.

---

## PoC (exploitation locale)

Le PoC suivant fonctionne en local pour démontrer le bug technique :

```bash
# Compiler sans protections
gcc -fno-stack-protector -g -D_FORTIFY_SOURCE=0 -O0 -o vuln vuln.c

# 16 bytes remplissent le buffer, le 17e écrase authenticated
./vuln $(python3 -c "print('A'*16 + 'B')")
# → "Access granted!"
```

Voir `exploits/poc.sh` pour le script automatisé.

---

## Conclusion

OpenAnt a correctement identifié le pattern dangereux (Stage 1) puis contextualisé son exploitabilité réelle (Stage 2). Le buffer overflow est un vrai bug mais pas une vulnérabilité exploitable dans le contexte d'un CLI local — démontrant la valeur de la vérification en deux étapes pour réduire les faux positifs.
