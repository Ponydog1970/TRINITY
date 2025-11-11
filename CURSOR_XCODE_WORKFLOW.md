# 🚀 Cursor + Xcode: Praktischer Workflow Guide

**Hands-on Anleitung für maximale Produktivität**

---

## 📥 Teil 1: Installation & Setup (10 Minuten)

### Schritt 1: Cursor installieren

**Option A: Download (Empfohlen)**
```bash
# Gehen Sie zu: https://cursor.sh
# Download für macOS
# DMG installieren → Applications verschieben
```

**Option B: Homebrew**
```bash
brew install --cask cursor
```

**Verifizieren:**
```bash
# Cursor sollte jetzt in Applications sein
open -a Cursor
```

### Schritt 2: Claude Sonnet 4.5 aktivieren

**In Cursor:**
1. Öffnen Sie Cursor
2. Drücken Sie `⌘,` (Settings)
3. Gehen Sie zu: **"Models"** (links)
4. Wählen Sie: **"Claude Sonnet 4.5"**

**API Key eingeben:**
```
Settings → Models → API Keys
→ "Add Anthropic API Key"
→ Gehen Sie zu: https://console.anthropic.com/settings/keys
→ "Create Key" → Key kopieren
→ In Cursor einfügen
```

**Alternative: Cursor Pro (empfohlen)**
```
Settings → Billing → Subscribe to Pro
→ $20/Monat
→ Unlimited AI (kein eigener API Key nötig!)
→ Claude Sonnet 4.5 inklusive
```

### Schritt 3: Projekt öffnen

```bash
# Im Terminal:
cd /home/user/TRINITY
cursor .

# Oder nur SimpleChatbot:
cursor SimpleChatbot/
```

**In Cursor GUI:**
```
File → Open Folder → /home/user/TRINITY/SimpleChatbot
```

---

## 🎯 Teil 2: Der optimale Workflow

### Setup: Beide Apps nebeneinander

**Bildschirm-Layout (empfohlen):**

```
┌─────────────────────────────────────────────┐
│                                             │
│         CURSOR (links, 60% Bildschirm)      │
│         ┌─────────────────────────────┐     │
│         │  File Explorer              │     │
│         │  Code Editor                │     │
│         │  Terminal unten             │     │
│         └─────────────────────────────┘     │
│                                             │
├─────────────────────────────────────────────┤
│                                             │
│         XCODE (rechts, 40% Bildschirm)      │
│         ┌─────────────────────────────┐     │
│         │  Project Navigator          │     │
│         │  Preview/Simulator          │     │
│         │  Console                    │     │
│         └─────────────────────────────┘     │
│                                             │
└─────────────────────────────────────────────┘
```

**Oder: Separate Spaces (⌃→)**
```
Space 1: Cursor (Fullscreen)
Space 2: Xcode (Fullscreen)
→ Mit ⌃→ / ⌃← wechseln
```

---

## 💻 Teil 3: Praktische Beispiele

### Beispiel 1: Neue Datei erstellen (mit AI)

**Szenario:** Sie brauchen einen `ThemeManager` für SimpleChatbot

#### In CURSOR:

**Schritt 1: Composer öffnen**
```
⌘I (oder ⌘⇧I)
```

**Schritt 2: Prompt eingeben**
```
Create a ThemeManager.swift file in SimpleChatbot/Services/:

- ObservableObject class
- Support for light, dark, and custom themes
- Color definitions for chat bubbles
- @Published properties
- UserDefaults persistence
- Use SwiftUI Color
```

**Schritt 3: AI generiert Code**
```swift
// ThemeManager.swift wird automatisch erstellt!
import SwiftUI

@MainActor
class ThemeManager: ObservableObject {
    enum Theme: String, Codable {
        case light, dark, system
    }

    @Published var currentTheme: Theme {
        didSet {
            UserDefaults.standard.set(currentTheme.rawValue, forKey: "selectedTheme")
        }
    }

    // ... kompletter Code generiert!
}
```

**Schritt 4: Datei speichern**
```
⌘S
```

#### In XCODE:

**Schritt 5: Xcode lädt automatisch**
- Xcode zeigt "File has changed" notification
- Klick auf "Reload" oder automatisch

**Schritt 6: In Xcode-Projekt hinzufügen**
```
1. Rechtsklick auf "Services" Ordner
2. "Add Files to SimpleChatbot..."
3. Wähle ThemeManager.swift
4. ✅ "Add to targets: SimpleChatbot"
5. Klick "Add"
```

**Schritt 7: Build testen**
```
⌘R
```

**Fertig!** ✅

---

### Beispiel 2: Bestehenden Code refactoren

**Szenario:** LocalAIService zu PerplexityService umbauen

#### In CURSOR:

**Schritt 1: Datei öffnen**
```
⌘P (Quick Open)
→ Tippe "LocalAI"
→ Enter
```

**Schritt 2: Code markieren**
```
⌘A (alles markieren)
oder
Manuell markieren
```

**Schritt 3: AI Edit**
```
⌘K
```

**Schritt 4: Prompt**
```
Refactor this to use Perplexity API:
- Rename class to PerplexityService
- Add API call to https://api.perplexity.ai/chat/completions
- Use URLSession for networking
- Add proper error handling
- Keep the @MainActor and ObservableObject
- Use async/await
```

**Schritt 5: AI refactored Code**
```
✅ Review changes
✅ Accept (oder Reject falls nicht gut)
```

**Schritt 6: Speichern**
```
⌘S
```

#### In XCODE:

**Schritt 7: Build**
```
⌘R
```

**Wenn Fehler:**
```
→ Zurück zu Cursor
→ ⌘L (Chat)
→ Error-Message einfügen
→ AI hilft beim Fix
```

---

### Beispiel 3: Debugging Workflow

**Szenario:** App crasht beim Senden einer Nachricht

#### In XCODE:

**Schritt 1: Crash entdecken**
```
⌘R → App startet
Nachricht senden → Crash! 💥
```

**Schritt 2: Breakpoint setzen**
```
1. Öffne ChatView.swift in Xcode
2. Klick auf Zeile vor dem Crash (Zeile 45)
3. Blauer Breakpoint erscheint
```

**Schritt 3: Re-run mit Debugger**
```
⌘R
App stoppt bei Breakpoint
```

**Schritt 4: Variablen inspizieren**
```
Debug Area (unten):
→ Siehe "messageText" = ""
→ Siehe "messages" = 5 items
→ Finde Problem: nil in message.user
```

**Schritt 5: Stack Trace kopieren**
```
Rechtsklick auf Stack → Copy
```

#### In CURSOR:

**Schritt 6: AI um Hilfe bitten**
```
⌘L (Chat öffnen)

Prompt:
"I'm getting a crash when sending messages. Here's the stack trace:
[paste stack trace]

Here's the relevant code:
@file ChatView.swift

What's causing this and how do I fix it?"
```

**Schritt 7: AI analysiert**
```
AI: "The issue is in line 45. The message.user is nil
because you're not initializing it properly.

Here's the fix:
[AI schlägt Lösung vor]
"
```

**Schritt 8: Fix anwenden**
```
⌘K auf markiertem Code
→ "Apply the suggested fix"
→ ⌘S speichern
```

#### Zurück zu XCODE:

**Schritt 9: Verify**
```
⌘R
→ Nachricht senden
→ Kein Crash! ✅
```

---

### Beispiel 4: UI Design Iteration

**Szenario:** Chat-Bubbles schöner machen

#### In CURSOR:

**Schritt 1: ChatView.swift öffnen**
```
⌘P → "ChatView"
```

**Schritt 2: MessageBubble finden**
```
⌘F → "MessageBubble"
```

**Schritt 3: Mit AI verbessern**
```
Markiere MessageBubble struct
⌘L (Chat)

Prompt:
"Improve this MessageBubble design:
- Add subtle shadow
- Rounded corners should be asymmetric (more rounded on one side)
- Add slight gradient background
- Smooth animations when appearing
- Better spacing
Show me modern, clean design like iMessage"
```

**Schritt 4: AI schlägt vor**
```swift
struct MessageBubble: View {
    let message: Message

    var body: some View {
        HStack {
            if message.isUser { Spacer(minLength: 60) }

            VStack(alignment: message.isUser ? .trailing : .leading, spacing: 4) {
                Text(message.text)
                    .padding(12)
                    .background(
                        LinearGradient(
                            colors: message.isUser ?
                                [Color.blue, Color.blue.opacity(0.8)] :
                                [Color(.systemGray5), Color(.systemGray6)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .foregroundColor(message.isUser ? .white : .primary)
                    .cornerRadius(18, corners: message.isUser ? [.topLeft, .topRight, .bottomLeft] : [.topLeft, .topRight, .bottomRight])
                    .shadow(color: .black.opacity(0.1), radius: 3, x: 0, y: 2)

                Text(message.timestamp, style: .time)
                    .font(.caption2)
                    .foregroundColor(.secondary)
            }
            .transition(.scale.combined(with: .opacity))

            if !message.isUser { Spacer(minLength: 60) }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message.id)
    }
}

// Custom corner radius extension
extension View {
    func cornerRadius(_ radius: CGFloat, corners: UIRectCorner) -> some View {
        clipShape(RoundedCorner(radius: radius, corners: corners))
    }
}

struct RoundedCorner: Shape {
    var radius: CGFloat = .infinity
    var corners: UIRectCorner = .allCorners

    func path(in rect: CGRect) -> Path {
        let path = UIBezierPath(
            roundedRect: rect,
            byRoundingCorners: corners,
            cornerRadii: CGSize(width: radius, height: radius)
        )
        return Path(path.cgPath)
    }
}
```

**Schritt 5: Anwenden**
```
⌘K auf MessageBubble
→ "Apply this improved design"
→ ⌘S
```

#### In XCODE:

**Schritt 6: Live Preview**
```
1. Öffne ChatView.swift in Xcode
2. Canvas rechts öffnen (⌥⌘↵)
3. "Resume" klicken
→ Live Preview zeigt neue Bubbles!
```

**Schritt 7: Tweaks**
```
Gefällt nicht? Zurück zu Cursor:
⌘K → "Make corners more rounded"
⌘S → Preview updated in Xcode
```

**Schritt 8: Finale Test**
```
⌘R → Run in Simulator
Test verschiedene Nachrichten
✅ Perfekt!
```

---

## ⌨️ Teil 4: Die wichtigsten Shortcuts

### Cursor Shortcuts

| Shortcut | Funktion | Wann nutzen |
|----------|----------|-------------|
| `⌘K` | AI Edit | Code markieren → AI ändern lassen |
| `⌘L` | AI Chat | Fragen stellen, Erklärungen |
| `⌘I` | Composer | Multi-file editing |
| `⌘P` | Quick Open | Schnell Datei öffnen |
| `⌘⇧F` | Search in project | Code suchen |
| `⌘⇧P` | Command Palette | Alle Commands |
| `⌥⌘L` | Accept AI suggestion | Tab-Autocomplete akzeptieren |
| `⌘/` | Toggle comment | Zeile kommentieren |
| `⌥↑/↓` | Move line up/down | Code verschieben |
| `⌘D` | Select next occurrence | Multi-cursor editing |
| `⌘⇧K` | Delete line | Zeile löschen |

### Xcode Shortcuts

| Shortcut | Funktion |
|----------|----------|
| `⌘R` | Build & Run |
| `⌘B` | Build only |
| `⌘.` | Stop running |
| `⌘U` | Run tests |
| `⌥⌘↵` | Show Canvas/Preview |
| `⌘0` | Toggle Navigator |
| `⌘⌥0` | Toggle Inspector |
| `⌘⇧Y` | Toggle Console |
| `⌘⇧O` | Quick Open |
| `⌘/` | Comment selection |

---

## 🔄 Teil 5: Typische Workflows im Detail

### Workflow: Neue Feature komplett implementieren

**Ziel:** Settings-Screen mit Theme-Auswahl

#### Phase 1: Planning (In Cursor Chat)

```
⌘L

Prompt:
"I want to add a Settings screen to SimpleChatbot with:
- Theme selection (Light/Dark/System)
- API settings
- About section

Using MVVM pattern. What files do I need?"

AI antwortet:
"You'll need:
1. SettingsView.swift (View)
2. SettingsViewModel.swift (ViewModel)
3. ThemeManager.swift (Service)
4. Settings.swift (Model)
"
```

#### Phase 2: Implementation (In Cursor Composer)

```
⌘I

Prompt:
"Create a complete Settings feature with these files:

1. SimpleChatbot/Models/Settings.swift
   - Codable struct for settings
   - Theme, API key storage

2. SimpleChatbot/ViewModels/SettingsViewModel.swift
   - ObservableObject
   - @Published settings
   - Save/load from UserDefaults

3. SimpleChatbot/Views/SettingsView.swift
   - SwiftUI Form
   - Theme Picker
   - Text fields for API settings
   - Modern design

4. SimpleChatbot/Services/ThemeManager.swift
   - ObservableObject
   - Theme switching logic
   - Color definitions

Use iOS 17+ APIs, follow MVVM strictly."
```

**AI erstellt alle 4 Dateien gleichzeitig!** 🎉

```
✅ Review jede Datei
✅ Anpassungen mit ⌘K
✅ Speichern mit ⌘S
```

#### Phase 3: Integration (In Cursor)

```
1. Öffne SimpleChatbotApp.swift
2. ⌘K auf der App struct

Prompt:
"Add ThemeManager as @StateObject and inject it
Also add navigation to SettingsView from ChatView"
```

#### Phase 4: Test (In Xcode)

```
1. Füge neue Files zum Xcode Projekt hinzu
2. ⌘R → Build & Run
3. Test Settings Screen
4. Debug falls nötig (siehe Beispiel 3)
```

#### Phase 5: Polish (Beide)

```
Cursor: UI Tweaks, Code cleanup
Xcode: Performance testen, Memory-Leaks checken
```

---

### Workflow: Code Review vor Commit

#### In CURSOR:

**Schritt 1: Alle geänderten Files anschauen**
```
⌘⇧G G (Git panel)
→ Siehe alle modified files
```

**Schritt 2: AI Review**
```
⌘L

Prompt:
"Review all my changes in this commit for:
- Bugs
- Memory leaks
- Performance issues
- Swift best practices
- Missing error handling
- Documentation

Be thorough and critical."
```

**Schritt 3: AI Feedback umsetzen**
```
Für jedes Issue:
→ File öffnen
→ ⌘K auf problematischem Code
→ "Fix the [issue AI mentioned]"
```

**Schritt 4: Commit**
```
Im Git Panel:
→ Stage all
→ Commit message schreiben
→ Commit
```

---

### Workflow: Learning / Code verstehen

**Szenario:** Verstehen wie PerplexityService funktioniert

#### In CURSOR:

```
⌘P → "Perplexity"
⌘L

Prompts (nacheinander):
"Explain how this PerplexityService works step by step"
→ AI erklärt

"What's the purpose of the ChatRequest struct?"
→ AI erklärt

"How does the error handling work here?"
→ AI erklärt

"Can you show me how to add retry logic?"
→ AI zeigt Code

"Add the retry logic with exponential backoff"
→ ⌘K → AI implementiert
```

**Learning by doing mit AI! 🎓**

---

## 🎨 Teil 6: Cursor UI optimal einstellen

### Empfohlene Settings

```json
// .cursor/settings.json
{
  // Editor
  "editor.fontSize": 14,
  "editor.fontFamily": "'SF Mono', Monaco, 'Courier New'",
  "editor.lineHeight": 22,
  "editor.tabSize": 4,
  "editor.formatOnSave": true,
  "editor.minimap.enabled": true,

  // AI
  "cursor.ai.model": "claude-sonnet-4-5",
  "cursor.ai.contextSize": "large",
  "cursor.ai.alwaysShowSuggestions": true,

  // Swift
  "swift.path": "/usr/bin/swift",
  "sourcekit-lsp.serverPath": "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/sourcekit-lsp",

  // Files
  "files.autoSave": "afterDelay",
  "files.autoSaveDelay": 1000,
  "files.exclude": {
    "**/.build": true,
    "**/DerivedData": true,
    "**/.swiftpm": true,
    "**/xcuserdata": true
  },

  // Terminal
  "terminal.integrated.fontSize": 13,
  "terminal.integrated.shell.osx": "/bin/zsh"
}
```

### UI Layout Tipps

**Linke Sidebar:**
```
- Explorer (⌘⇧E): File tree
- Search (⌘⇧F): Find in files
- Git (⌃⇧G): Source control
```

**Bottom Panel:**
```
- Terminal (⌃`): Command line
- Problems: Compiler errors
- Output: Build output
```

**Right Sidebar:**
```
- AI Chat (⌘L): Permanent chat
- Keep open für quick questions!
```

---

## ⚡ Teil 7: Pro-Tipps

### Tip 1: @ Mentions nutzen

```
Im Chat (⌘L):

@file ChatView.swift "Add loading state"
→ AI hat Kontext der Datei

@folder /Services "Explain the architecture"
→ AI analysiert ganzen Ordner

@code [markierter Code] "Optimize this"
→ AI fokussiert auf Selection

@web "Latest Swift 6 features"
→ AI sucht im Web (mit Pro)
```

### Tip 2: Multi-Cursor Editing

```
1. ⌘D mehrmals drücken → selektiert nächste Vorkommen
2. Gleichzeitig an mehreren Stellen tippen
3. Perfekt für Renaming, Bulk-Edits

Beispiel:
"userMessage" mehrfach → ⌘D x3 → Zu "message" ändern
→ Alle 3 gleichzeitig geändert!
```

### Tip 3: Snippets mit AI generieren

```
⌘L

"Create a SwiftUI snippet for a loading button that:
- Shows ProgressView when loading
- Disabled when loading
- Accepts title and action
- Can be reused"

→ AI gibt Code
→ Speichern als "LoadingButton.swift"
→ Überall wiederverwenden!
```

### Tip 4: Git in Cursor

```
⌘⇧G G (Git panel)

Funktionen:
- ✅ Staged/Unstaged sehen
- ✅ Diff visuell
- ✅ Commit direkt
- ✅ Push/Pull
- ✅ Branch wechseln
- ✅ Merge conflicts lösen (mit AI!)

AI kann helfen:
"Explain this merge conflict and suggest resolution"
```

### Tip 5: Custom Prompts speichern

```
Settings → Prompts → Add Custom Prompt

Beispiel:
Name: "Swift Review"
Prompt: "Review this Swift code for:
- Memory leaks
- Force unwraps
- Threading issues
- SwiftUI best practices
Be specific with line numbers."

→ Wiederverwendbar mit Shortcut!
```

---

## 🎯 Teil 8: Häufige Probleme & Lösungen

### Problem: Cursor sieht Swift-Typen nicht

**Lösung:**
```bash
# SourceKit-LSP neu starten
⌘⇧P → "Developer: Reload Window"

# Oder Index rebuilden
⌘⇧P → "Developer: Rebuild Extension Host"
```

### Problem: Xcode lädt Änderungen nicht

**Lösung:**
```
1. In Xcode: File → Workspace → Close Workspace
2. Reopen
3. Oder: ⌘⌥⇧K (Clean Build Folder)
```

### Problem: AI Suggestions sind langsam

**Lösung:**
```
Settings → AI → Lower context size
Oder: Upgrade zu Cursor Pro (schnellere API)
```

### Problem: Build Error nach AI-Code

**Lösung:**
```
⌘L in Cursor
"I got this build error: [paste error]
From this code: @file [filename]
How do I fix it?"

AI gibt meist sofort richtigen Fix!
```

### Problem: Zu viele AI-Tokens verbraucht

**Lösung:**
```
- Nutzen Sie kleinere Context (@file statt @folder)
- Cursor Pro: Unlimited tokens
- Oder: Eigenen API Key (pay-as-you-go)
```

---

## 📊 Teil 9: Produktivitäts-Metriken

### Vorher (nur Xcode):

```
Feature implementieren: 4 Stunden
- Planning: 30 Min
- Coding: 2 Stunden
- Debugging: 1 Stunde
- Documentation: 30 Min
```

### Nachher (Cursor + Xcode):

```
Feature implementieren: 2 Stunden
- Planning mit AI: 10 Min
- Coding mit AI: 1 Stunde
- Debugging: 30 Min
- Documentation mit AI: 20 Min

→ 50% schneller! 🚀
```

---

## ✅ Checkliste: Sind Sie bereit?

**Setup:**
- [ ] Cursor installiert
- [ ] Claude Sonnet 4.5 aktiviert (oder Pro Abo)
- [ ] SimpleChatbot in Cursor geöffnet
- [ ] Xcode parallel geöffnet
- [ ] Beide nebeneinander positioniert

**Grundlagen:**
- [ ] ⌘K ausprobiert (AI Edit)
- [ ] ⌘L ausprobiert (AI Chat)
- [ ] ⌘I ausprobiert (Composer)
- [ ] Code in Cursor geändert → Xcode Build getestet

**Workflow:**
- [ ] Neue Datei mit AI erstellt
- [ ] Bestehenden Code refactored
- [ ] Bug mit AI-Hilfe gefixt
- [ ] Git Commit gemacht

---

## 🎓 Übungsaufgaben

### Übung 1: Simple Task (5 Min)
```
In Cursor:
1. Öffne ChatView.swift
2. ⌘L → "Add a character counter below the input field"
3. Apply the suggestion
4. ⌘S

In Xcode:
5. ⌘R → Test it!
```

### Übung 2: Medium Task (15 Min)
```
Erstellen Sie ein "Export Chat" Feature:
1. In Cursor: ⌘I
2. "Create an ExportManager that can export chat history
   as plain text and Markdown. Add a share button to ChatView."
3. Review & Apply
4. In Xcode: Test the export function
```

### Übung 3: Complex Task (30 Min)
```
Implementieren Sie Voice Input:
1. Research mit AI: "How to add voice input in SwiftUI?"
2. Mit Composer: Create Voice Input Feature
3. Integration in ChatView
4. Testing in Xcode
5. Bug fixes with AI help
```

---

## 🎉 Zusammenfassung

**Der perfekte Workflow:**

```
1. Denken/Planen → In Cursor Chat (⌘L)
2. Schreiben → In Cursor mit AI (⌘K, ⌘I)
3. Testen → In Xcode (⌘R)
4. Debuggen → In Xcode (Breakpoints)
5. Fixen → Zurück zu Cursor mit AI-Hilfe
6. Repeat! 🔄
```

**Key Takeaways:**

✅ Cursor = Ihr AI-Pair-Programmer
✅ Xcode = Ihre Build/Debug/Test-Umgebung
✅ Zusammen = 50%+ schnellere Development
✅ Die 3 Shortcuts merken: ⌘K, ⌘L, ⌘I

---

**Bereit loszulegen?** 🚀

Öffnen Sie jetzt:
1. Cursor → SimpleChatbot öffnen
2. Xcode → SimpleChatbot/Package.swift öffnen
3. Probieren Sie die Beispiele aus!

**Bei Fragen:** Fragen Sie einfach! Ich helfe Ihnen durch jeden Schritt. 💪
