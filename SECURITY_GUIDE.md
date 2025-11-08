# 🔒 TRINITY Sicherheits-Anleitung für API Keys

## ⚠️ WICHTIG: API Keys NIEMALS öffentlich machen!

API Keys sind wie Passwörter. Wenn sie auf GitHub veröffentlicht werden:
- ❌ Jeder kann Ihre API nutzen
- ❌ Sie zahlen für fremde Nutzung
- ❌ Ihre Daten können kompromittiert werden
- ❌ Keys müssen sofort deaktiviert werden

---

## ✅ Sichere Speicherung (3 Methoden)

### **Methode 1: .env Datei (EMPFOHLEN für Entwicklung)**

#### Schritt 1: .env Datei erstellen
```bash
# Im TRINITY Projekt-Verzeichnis:
cp .env.example .env
```

#### Schritt 2: API Keys eintragen
```bash
# Öffne .env in einem Editor und füge deine Keys ein:
nano .env   # oder: code .env, vim .env, etc.
```

Inhalt der `.env` Datei:
```env
CLAUDE_API_KEY=sk-ant-api03-jO_egFz...  # Ihr echter Key
PERPLEXITY_API_KEY=pplx-...              # Ihr echter Key (wenn vorhanden)
OPENAI_API_KEY=sk-...                    # Optional
```

#### Schritt 3: In Xcode laden
Die TRINITY App lädt automatisch aus `.env`:

```swift
// Wird beim App-Start automatisch aufgerufen:
Configuration.shared.loadFromFile()  // Lädt .env

// Oder aus Environment Variables:
Configuration.shared.loadFromEnvironment()
```

#### ✅ Sicherheit:
- `.env` ist in `.gitignore` → **wird NICHT committed**
- Nur lokal auf Ihrem Mac
- Einfach zu aktualisieren

---

### **Methode 2: Xcode Environment Variables**

#### In Xcode:
1. Öffnen Sie Ihr Scheme: **Product** → **Scheme** → **Edit Scheme**
2. Wählen Sie **Run** → **Arguments**
3. Unter **Environment Variables** hinzufügen:

| Name | Value |
|------|-------|
| `CLAUDE_API_KEY` | `sk-ant-api03-jO_egFz...` |
| `PERPLEXITY_API_KEY` | `pplx-...` |

4. ✅ Klicken Sie auf **Close**

#### Laden in der App:
```swift
// Beim App-Start:
Configuration.shared.loadFromEnvironment()
```

#### ✅ Sicherheit:
- Nur in Ihrer lokalen Xcode-Konfiguration
- Wird nicht zu Git committed
- Pro Scheme separat

---

### **Methode 3: iOS App Settings (PRODUKTION)**

Für die finale App sollten Keys im iOS Keychain gespeichert werden:

```swift
import Security

class KeychainManager {
    static func saveAPIKey(_ key: String, service: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecValueData as String: key.data(using: .utf8)!
        ]

        SecItemDelete(query as CFDictionary)  // Lösche alte
        let status = SecItemAdd(query as CFDictionary, nil)

        guard status == errSecSuccess else {
            throw NSError(domain: "Keychain", code: Int(status))
        }
    }

    static func loadAPIKey(service: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecReturnData as String: true
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        guard status == errSecSuccess,
              let data = result as? Data,
              let key = String(data: data, encoding: .utf8) else {
            return nil
        }

        return key
    }
}

// Verwendung:
try KeychainManager.saveAPIKey("sk-ant-...", service: "trinity.claude")
let key = KeychainManager.loadAPIKey(service: "trinity.claude")
```

#### ✅ Sicherheit:
- Verschlüsselt im iOS Keychain
- Nicht extrahierbar ohne Gerät
- Beste Methode für Produktion

---

## 🚨 Was tun wenn Key versehentlich committed wurde?

### **SOFORT:**

#### 1. Key auf Anthropic deaktivieren
```
1. Gehen Sie zu: https://console.anthropic.com/settings/keys
2. Löschen Sie den kompromittierten Key
3. Erstellen Sie einen NEUEN Key
```

#### 2. Git History bereinigen
```bash
# WARNUNG: Ändert Git-Historie!

# Datei aus allen Commits entfernen:
git filter-branch --force --index-filter \
  "git rm --cached --ignore-unmatch .env" \
  --prune-empty --tag-name-filter cat -- --all

# Force push (wenn bereits gepusht):
git push origin --force --all
```

#### 3. GitHub kontaktieren
Wenn der Key bereits auf GitHub war:
- GitHub Support kontaktieren
- Key aus Cache/Snapshots entfernen lassen

---

## 📋 Checkliste: Ist mein Projekt sicher?

Überprüfen Sie folgendes **BEVOR** Sie pushen:

```bash
# 1. Ist .env in .gitignore?
grep ".env" .gitignore
# ✅ Sollte ".env" enthalten

# 2. Ist .env wirklich ignoriert?
git status --ignored
# ✅ .env sollte unter "Ignored files" sein

# 3. Keine Keys in Code-Dateien?
grep -r "sk-ant-api03" --exclude-dir=.git .
# ✅ Sollte NICHTS finden (außer in .env)

# 4. Keine Keys in committed files?
git log -p -S "sk-ant-api03"
# ✅ Sollte NICHTS finden

# 5. .env.example hat nur Platzhalter?
cat .env.example
# ✅ Sollte "your_key_here" enthalten, KEINE echten Keys
```

---

## 📁 Datei-Struktur (nach Setup)

```
TRINITY/
├── .env                    ← NICHT committed (echter Key)
├── .env.example            ← COMMITTED (Platzhalter)
├── .gitignore              ← Schützt .env
├── TrinityApp/
│   └── Sources/
│       └── Utils/
│           └── Configuration.swift  ← Lädt Keys sicher
└── SECURITY_GUIDE.md       ← Diese Anleitung
```

---

## 🎯 Empfohlenes Vorgehen für TRINITY

### Für Entwicklung (jetzt):
1. ✅ `.env` Datei verwenden (bereits erstellt!)
2. ✅ Keys niemals in Swift-Dateien hardcoden
3. ✅ Vor jedem commit: `git status` prüfen

### Für Produktion (später):
1. ✅ iOS Keychain verwenden
2. ✅ Settings-Screen zum Key-Eingabe
3. ✅ Keys per UserDefaults mit Keychain-Backup

---

## 🔍 Häufige Fehler vermeiden

### ❌ NIEMALS:
```swift
// FALSCH: Key direkt im Code!
let apiKey = "sk-ant-api03-jO_egFz..."
```

### ✅ IMMER:
```swift
// RICHTIG: Key aus sicherer Quelle laden
let apiKey = Configuration.shared.claudeKey
```

### ❌ NIEMALS:
```bash
# FALSCH: .env committen
git add .env
git commit -m "Add API keys"  # ❌ GEFÄHRLICH!
```

### ✅ IMMER:
```bash
# RICHTIG: Nur .env.example committen
git add .env.example
git commit -m "Add API key template"  # ✅ Sicher
```

---

## 📞 Support

Bei Sicherheitsfragen:
- **Anthropic Support:** https://support.anthropic.com
- **GitHub Security:** https://docs.github.com/en/code-security

---

## ✅ Aktueller Status

Ihr TRINITY Projekt ist jetzt **sicher konfiguriert**:

- ✅ `.gitignore` schützt alle Key-Dateien
- ✅ `.env` enthält Ihren echten Claude Key (lokal)
- ✅ `.env.example` als Template (committed, sicher)
- ✅ `Configuration.swift` lädt Keys sicher
- ✅ Keine Keys in Git-Historie

**Sie können sicher entwickeln!** 🎉

---

## 🚀 Nächste Schritte

1. Wenn Sie Ihr MacBook haben:
   ```bash
   git clone <ihr-repo>
   cd TRINITY
   cp .env.example .env
   nano .env  # Ihre Keys eintragen
   open TrinityApp.xcodeproj
   ```

2. In Xcode: Build & Run (⌘R)

3. Die App lädt automatisch Ihre Keys aus `.env`!

**Viel Erfolg mit TRINITY!** 🎯
