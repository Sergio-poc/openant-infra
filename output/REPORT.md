# OpenAnt Scan Report — `vuln/buffer-overflow`

**Date** : 2026-06-17  
**Run ID** : `run-20260617T102458-632c7134`  
**Target** : `../vuln/examples/buffer-overflow/vuln.c`  
**Language** : C  
**Model** : Claude Opus 4 (via Bedrock EU)

---

## Résumé

| Métrique | Valeur |
|----------|--------|
| Fichiers scannés | 1 |
| Fonctions analysées | 2 |
| Vulnérabilités détectées | **1** |
| Safe | 1 |
| Coût total | ~$0.08 |

---

## Pipeline

| Étape | Durée | Coût | Résultat |
|-------|-------|------|----------|
| Parse | 0.5s | $0.00 | 2 unités extraites |
| Enhance | 17.8s | $0.04 | 2/2 classifiées "exploitable" |
| Analyze | 14.1s | $0.04 | 1 vulnerable, 1 safe |
| Verify | 0.0s | $0.00 | Pas de findings à vérifier (bug entrypoint) |

---

## Vulnérabilité trouvée

### 🔴 CWE-121 : Stack-based Buffer Overflow

| Champ | Détail |
|-------|--------|
| **Fonction** | `check_password(const char *input)` |
| **Fichier** | `vuln.c:4-15` |
| **Confiance** | 97% |
| **Verdict** | VULNERABLE |

#### Description

La fonction copie l'entrée contrôlée par l'attaquant (`input`) dans un buffer stack de 16 octets via `strcpy` sans aucune vérification de taille. Toute entrée de plus de 15 octets déborde le buffer.

La variable locale adjacente `authenticated` peut être écrasée avec une valeur non-nulle, déclenchant le branch `if (authenticated)` qui affiche "Access granted!" — un **bypass d'authentification**.

Un payload suffisamment long peut aussi écraser l'adresse de retour sauvegardée, permettant un **détournement de flux de contrôle / exécution de code arbitraire**.

#### Vecteur d'attaque

```
Fournir une chaîne de >=16 octets, par ex. 16 caractères 'A' suivis d'un octet non-nul,
pour que strcpy déborde buffer[16] et écrase l'entier 'authenticated' adjacent
(et/ou l'adresse de retour).
```

#### Code vulnérable

```c
void check_password(const char *input) {
    int authenticated = 0;
    char buffer[16];

    strcpy(buffer, input);  // ← overflow ici

    if (authenticated) {
        printf("Access granted!\n");
    } else {
        printf("Access denied.\n");
    }
}
```

#### Exploitation (PoC)

```bash
./vuln $(python3 -c "print('A'*16 + '\x01')")
# Output: Access granted!
```

---

## Fonction safe

### ✅ `main(int argc, char *argv[])`

**Verdict** : SAFE (confiance 85%)

La fonction main valide uniquement `argc >= 2`, affiche l'usage avec un format string littéral, et passe `argv[1]` à `check_password()`. Elle n'effectue aucune copie de buffer ni opération non-bornée sur l'entrée. Le forwarding d'un pointeur est un comportement normal.

---

## Notes

- Le stage **verify** n'a pas produit de résultats car l'entrypoint passait `dataset.json` au lieu de `results.json` comme input. Le bug a été identifié mais la vérification Stage 2 n'a pas été exécutée sur ce run.
- Les modèles Bedrock ont été mis à jour de Sonnet 4 → Sonnet 4.5 et Opus 4 → Opus 4.8 suite à la dépréciation "Legacy" par AWS.
