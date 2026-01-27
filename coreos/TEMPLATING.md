# Butane Template Workflow - Sichere Secrets + Single Source

Diese Anleitung beschreibt den **empfohlenen Workflow** mit Template-basierten Butane Configs.

## Vorteile

✅ **Ein Template** statt 3+ separater Dateien
✅ **Secrets nicht in Git** - saubere Trennung
✅ **Reproduzierbar** - einfaches Regenerieren
✅ **Weniger Fehler** - zentrale Konfiguration

---

## Quick Start

### 1. Secrets erstellen

```bash
cd coreos/

# Kopiere das Template
cp secrets.env.example secrets.env

# Editiere secrets.env
nano secrets.env
```

**In `secrets.env` eintragen:**

```bash
# SSH Public Key
SSH_PUBLIC_KEY='ssh-rsa AAAAB3... user@host'

# Password Hash generieren:
mkpasswd -m sha-512
# Dann Hash eintragen:
PASSWORD_HASH='$6$rounds=4096$...'

# JOIN_TOKEN kommt später (nach Bootstrap)
JOIN_TOKEN=''
```

### 2. Bootstrap-Config generieren

```bash
# Generiert nur host03 (Bootstrap-Node)
./generate-configs.sh

# Resultat: generated/fcos-host03-bootstrap.bu
```

### 3. Ignition erstellen & USB brennen

```bash
# Butane → Ignition konvertieren
butane --strict --pretty generated/fcos-host03-bootstrap.bu > host03.ign

# USB erstellen
sudo coreos-installer install /dev/sdX \
  --image-file fedora-coreos-*.iso \
  --ignition-file host03.ign
```

### 4. Host03 booten & Join-Token holen

```bash
# Nach Installation & Boot:
ssh core@10.0.100.103

# Token holen
sudo cat /var/lib/rancher/rke2/server/node-token
# Beispiel: K10abc123def456ghi789jkl012mno345pqr678stu901vwx234yz::server:a1b2c3d4e5f6
```

### 5. Join-Token eintragen & Join-Configs generieren

```bash
# Zurück auf Workstation
cd coreos/

# Token in secrets.env eintragen
nano secrets.env
# JOIN_TOKEN='K10abc123...'

# Jetzt ALLE Configs generieren (host01, host02, host03)
./generate-configs.sh
```

**Resultat:**
```
generated/
├── fcos-host01-join.bu
├── fcos-host02-join.bu
└── fcos-host03-bootstrap.bu
```

### 6. Join-Nodes installieren

```bash
# host01
butane --strict --pretty generated/fcos-host01-join.bu > host01.ign
sudo coreos-installer install /dev/sdX --image-file fcos.iso --ignition-file host01.ign

# host02
butane --strict --pretty generated/fcos-host02-join.bu > host02.ign
sudo coreos-installer install /dev/sdX --image-file fcos.iso --ignition-file host02.ign
```

---

## Template anpassen

Das Template liegt in `fcos-template.bu` und ist versioniert in Git.

**Änderungen am Cluster (z.B. neue VLANs, andere Netzwerk-Config):**

1. `fcos-template.bu` editieren
2. `./generate-configs.sh` ausführen
3. Neue Ignition-Files erstellen
4. Nodes neu installieren

**Variablen im Template:**

```yaml
{{HOSTNAME}}           # host01, host02, host03
{{NODE_IP}}            # 10.0.100.101, .102, .103
{{SSH_PUBLIC_KEY}}     # Aus secrets.env
{{PASSWORD_HASH}}      # Aus secrets.env
{{JOIN_TOKEN}}         # Aus secrets.env (nur für Join-Nodes)
{{RKE2_CONFIG}}        # Generiert vom Script (Bootstrap vs Join)
{{POST_INSTALL_SCRIPT}} # Generiert vom Script
```

---

## Sicherheit

### Was wird NICHT in Git committed:

✅ `secrets.env` - enthält SSH-Keys, Passwords, Tokens
✅ `generated/*.bu` - enthalten eingebettete Secrets
✅ `*.ign` - Ignition-Files (kompilierte Configs)

### Was WIRD in Git committed:

✅ `fcos-template.bu` - Template ohne Secrets
✅ `generate-configs.sh` - Generator-Script
✅ `secrets.env.example` - Template mit Platzhaltern
✅ `.gitignore` - Schutz gegen versehentliches Commit

### Zusätzliche Absicherung

Prüfen, dass keine Secrets committed werden:

```bash
# Vor jedem commit:
git status

# Sollte NICHT auftauchen:
# - secrets.env
# - generated/
# - *.ign

# Pre-commit hook erstellen (optional):
cat > .git/hooks/pre-commit << 'EOF'
#!/bin/bash
if git diff --cached --name-only | grep -E 'secrets.env|\.ign$|^generated/'; then
  echo "❌ Error: Trying to commit secrets!"
  exit 1
fi
EOF
chmod +x .git/hooks/pre-commit
```

---

## Alternative: SOPS (für Teams)

Für Team-Environments mit geteilten Secrets:

### SOPS + Age Encryption

```bash
# Age key generieren
age-keygen -o age.key

# Public key für Team teilen
cat age.key | grep "public key:"

# secrets.env verschlüsseln
sops --age <PUBLIC_KEY> --encrypt secrets.env > secrets.env.enc

# In Git committen:
git add secrets.env.enc

# Andere Team-Member entschlüsseln:
export SOPS_AGE_KEY_FILE=~/age.key
sops --decrypt secrets.env.enc > secrets.env
```

**Vorteil:** Secrets können sicher in Git liegen (verschlüsselt)

---

## Workflow-Vergleich

| Aspekt | Alt (3 separate Dateien) | Neu (Template + Generator) |
|--------|--------------------------|----------------------------|
| Dateien | 3x .bu mit Duplikaten | 1x Template |
| Secrets | In jeder Datei | Separate secrets.env |
| Updates | 3x editieren | 1x Template ändern |
| Git | Secrets manuell entfernen | Automatisch ausgeschlossen |
| Fehler | Inkonsistenzen möglich | Single source of truth |
| Regenerieren | Manuell | `./generate-configs.sh` |

---

## Troubleshooting

### "secrets.env not found"

```bash
cp secrets.env.example secrets.env
nano secrets.env
```

### "JOIN_TOKEN not set"

Normal beim ersten Durchlauf! Erst Bootstrap installieren, dann Token holen und regenerieren.

### Butane Conversion Error

```bash
# Syntax prüfen
butane --strict generated/fcos-host03-bootstrap.bu

# Häufige Fehler:
# - YAML Indentation falsch
# - Variablen nicht ersetzt ({{...}} noch sichtbar)
```

### Generated configs sind leer

```bash
# Script-Output prüfen
./generate-configs.sh

# Permissions prüfen
chmod +x generate-configs.sh
```

---

## Backup & Recovery

### Secrets sichern

```bash
# Lokales Backup (außerhalb Git)
cp secrets.env ~/secure-backup/k8s-homelab-secrets.env

# Oder verschlüsselt:
gpg --encrypt --recipient your@email.com secrets.env
# → secrets.env.gpg (kann in Git)
```

### Join Token neu generieren

Wenn Token abgelaufen oder verloren:

```bash
# Auf Bootstrap-Node (host03):
sudo kubeadm token create --print-join-command
# oder
sudo cat /var/lib/rancher/rke2/server/node-token
```

---

## Migration von alten Configs

Wenn Sie bereits `fcos-host0X-*.bu` Dateien haben:

```bash
# 1. Secrets extrahieren
grep "ssh_authorized_keys" fcos-host03-bootstrap.bu
grep "password_hash" fcos-host03-bootstrap.bu
grep "token:" fcos-host01-join.bu

# 2. In secrets.env eintragen
nano secrets.env

# 3. Alte Dateien archivieren
mkdir -p archive
mv fcos-host0*.bu archive/

# 4. Neue Configs generieren
./generate-configs.sh

# 5. Vergleichen (optional)
diff archive/fcos-host03-bootstrap.bu generated/fcos-host03-bootstrap.bu
```

---

## Zusammenfassung

**Workflow:**
1. `secrets.env` erstellen (einmalig)
2. Bootstrap: `./generate-configs.sh` → nur host03
3. Host03 installieren & Token holen
4. Token in `secrets.env` eintragen
5. Join-Nodes: `./generate-configs.sh` → alle Nodes
6. Host01 & Host02 installieren

**Sicherheit:**
- Secrets nie in Git
- `.gitignore` schützt automatisch
- Optional: SOPS für Team-Umgebungen

**Wartung:**
- Template ändern → regenerieren → neu installieren
- Single source of truth
- Keine manuellen Duplikate

---

**Empfehlung:** Nutzen Sie diesen Workflow für alle zukünftigen Installationen!
