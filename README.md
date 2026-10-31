<p align="center">
  <img src="docs/images/hero-banner.svg" alt="MeuCleaner Banner" width="100%" />
</p>

<p align="center">
  <img src="docs/images/app-icon.png" alt="MeuCleaner App Icon" width="128" height="128" />
</p>

<h1 align="center">✨ MeuCleaner</h1>

<p align="center">
  <strong>Limpador nativo para macOS em Swift + SwiftUI — rápido, transparente e seguro por padrão.</strong><br/>
  Acha o lixo do sistema, mapeia o disco em anéis interativos (Space Lens), desinstala apps sem deixar restos na Library, monitora CPU/RAM na barra de menus e envia tudo para a Lixeira antes de apagar.
</p>

<p align="center">
  <a href="https://github.com/vagneralencar/MeuCleaner-Mac/releases/latest">
    <img src="https://img.shields.io/badge/Release-v1.2.0%20Pro-AF52DE?style=for-the-badge&logo=github" alt="Release v1.2.0" />
  </a>
  <img src="https://img.shields.io/badge/macOS-14.0%2B-0A84FF?style=for-the-badge&logo=apple&logoColor=white" alt="macOS 14+" />
  <img src="https://img.shields.io/badge/Swift-6.0-F05138?style=for-the-badge&logo=swift&logoColor=white" alt="Swift" />
  <img src="https://img.shields.io/badge/UI-SwiftUI%20Liquid%20Glass-5AC8FA?style=for-the-badge" alt="SwiftUI" />
  <img src="https://img.shields.io/badge/Telemetria-Zero-30D158?style=for-the-badge" alt="Zero Telemetry" />
</p>

---

## 📸 Screenshots

### Canal 00 · Varredura Inteligente (Smart Scan)
Resumo completo do Mac em segundos: medidor de espaço livre, diagnóstico de **Lixo do Sistema**, **Restos de Apps** e **Lixeira** em uma única tela.

<p align="center">
  <img src="docs/images/channel-00-home.png" alt="Canal 00 - Varredura Inteligente" width="860" />
</p>

---

### Canal 01 · Lixo do Sistema (System Junk)
Limpa caches de aplicativos, logs de diagnóstico, `DerivedData` e `DeviceSupport` do Xcode, caches de ferramentas de desenvolvimento (`npm`, `pnpm`, `Bun`, `Cargo`, `Gradle`), `~/.cache` e downloads incompletos.
> **Segurança inteligente**: Caches de aplicativos abertos no momento (`App aberto`) e pastas em `~/.cache` (`Revisar`) vêm desmarcados por padrão.

<p align="center">
  <img src="docs/images/channel-01-junk.png" alt="Canal 01 - Lixo do Sistema" width="860" />
</p>

---

### Canal 02 · Space Lens (Mapa do Disco em Anéis)
Visualização em anéis concêntricos (*Sunburst*): cada anel representa um nível de pasta, e quanto maior o arco, mais espaço ele ocupa no disco. Clique em qualquer arco ou item da lista para mergulhar nas subpastas.

<p align="center">
  <img src="docs/images/channel-02-spacelens.png" alt="Canal 02 - Space Lens" width="860" />
</p>

---

### Canal 04 · Desinstalador Completo +Agente na Barra de Menus
Arrastar um aplicativo para a Lixeira deixa preferências, caches, containers e estados salvos espalhados na `~/Library`. O **Desinstalador** mostra exatamente cada pasta associada (`Dados`, `Caches`, `Preferências`, `Cookies`, `Compartilhado`) e remove tudo junto. Já o **Agente na Barra de Menus** monitora CPU, RAM, Disco, Bateria e Rede em tempo real.

| Canal 04 · Desinstalador Completo | Agente na Barra de Menus (`MenuBarExtra`) |
| :---: | :---: |
| <img src="docs/images/channel-04-uninstaller.png" alt="Canal 04 - Desinstalador" width="540" /> | <img src="docs/images/menubar-agent.png" alt="Agente na Barra de Menus" width="280" /> |

---

## 🎛️ Os 8 Canais (`⌘0` a `⌘7`)

| Canal | Atalho | Módulo | O que faz |
| :---: | :---: | :--- | :--- |
| **00** | `⌘0` | **Varredura Inteligente** | Lê o Mac em segundos e resume lixo do sistema, restos de apps e espaço livre. |
| **01** | `⌘1` | **Lixo do Sistema** | Caches de usuário, logs, Xcode (`DerivedData`, simuladores), `npm`, `pnpm`, `bun`, `Cargo`, `Gradle`, `~/.cache` e downloads pela metade. |
| **02** | `⌘2` | **Space Lens** | Mapa visual interativo em anéis por nível de pasta + navegação com breadcrumbs. |
| **03** | `⌘3` | **Grandes e Antigos** | Localiza arquivos pesados esquecidos filtrados por tipo (`Vídeos`, `Imagens de disco`, `Compactados`, `Áudio`, `Imagens`, `Documentos`) e idade (`90 dias`, `6 meses`, `1 ano`). |
| **04** | `⌘4` | **Desinstalador** | Remove aplicativos junto com todos os arquivos que espalharam na `~/Library`. Detecta apps abertos e oferece botão para encerrá-los antes. |
| **05** | `⌘5` | **Restos de Apps** | Encontra pastas órfãs na `~/Library` de apps que já foram apagados no passado. Nada vem marcado por padrão. |
| **06** | `⌘6` | **Lixeira** | Lista os itens na Lixeira do macOS (`~/.Trash`) e exige **segurar o botão até encher** para esvaziar permanentemente. |
| **07** | `⌘7` | **Atualizador de Apps** | Busca e instala atualizações em 1 clique via **Homebrew Cask**, feeds **Sparkle (`SUFeedURL`)** e **Mac App Store Lookup API**. |
| **08** | `⌘8` | **Dev & IA Cleaner (PRO)** | Encontra `node_modules`, `.next`, `.venv`, `target` e `.build` de projetos inativos, modelos locais de IA (**Ollama**, **Hugging Face**, **LM Studio**) e limpa simuladores antigos do Xcode. |
| **09** | `⌘9` | **Inicialização & Daemons (PRO)** | Gerencia `LaunchAgents` e `LaunchDaemons` ocultos em background com ativação/pausa via `launchctl`. |
| **10** | `⌘D` | **Arquivos Duplicados (PRO)** | Caçador ultrarrápido em 3 estágios (`Tamanho` → `Hash Parcial 64 KB` → `SHA-256`) com botão *Manter Apenas o Mais Recente*. |

---

## 🚀 Diferenciais Exclusivos (Pro Suite)

- **👻 Vigia da Lixeira (Trash Watcher)**: Detecta automaticamente quando você joga um `.app` na Lixeira pelo Finder e exibe um alerta imediato caso aquele aplicativo tenha deixado restos órfãos na `~/Library`.
- **🎯 Drop Zone de Desinstalação**: Arraste qualquer `.app` do Finder diretamente para a janela do Desinstalador para mapear todos os arquivos vinculados na `~/Library`.
- **📊 Histórico Acumulado e Janela de Ajustes (`⌘,`)**: Registra quantos GBs você já liberou neste Mac ao longo do tempo e permite configurar o destino padrão da limpeza.

---

## 🛡️ Filosofia de Segurança (`SafetyGuard`)

1. **Escanear só lê**: Nenhuma varredura move ou altera arquivos no disco.
2. **Lixeira por padrão**: Toda limpeza utiliza `FileManager.default.trashItem` para enviar arquivos à Lixeira do macOS primeiro, permitindo restaurar qualquer item pelo Finder.
3. **Segurar para apagar de vez (`HoldToConfirmButton`)**: A exclusão permanente só acontece se você mantiver o botão pressionado até a barra completar — um clique acidental nunca apaga nada.
4. **Guarda de Caminhos Intocáveis**: A camada `SafetyGuard` recusa qualquer operação em:
   - Pastas do sistema (`/System`, `/usr`, `/bin`, `/sbin`, `/Library`, `/Users/Shared`)
   - Pastas pessoais críticas (`~/Documents`, `~/Desktop`, `~/Pictures/Photos Library.photoslibrary`)
   - Dados sensíveis (`~/Library/Keychains`, `~/Library/Mail`, `~/Library/Messages`)
   - Nuvem (`~/Library/Mobile Documents` / iCloud Drive e `~/Library/CloudStorage` / Google Drive, Dropbox, OneDrive)
   - Daemons essenciais da Apple (`HomeKit`, `CloudKit`, `bird`, `akd`, `nsurlsessiond`, `containermanagerd`)
   - O próprio bundle do `MeuCleaner`.

---

## 🏗️ Arquitetura do Projeto

```text
MeuCleaner/
├── Package.swift
├── scripts/
│   └── build-app.sh                        # Empacota o binário Release em build/MeuCleaner.app
├── Sources/MeuCleaner/
│   ├── MeuCleanerApp.swift                 # Entrypoint @main, WindowGroup, atalhos ⌘0–⌘7 e MenuBarExtra
│   ├── Models/
│   │   ├── Channel.swift                   # Definição dos 8 canais (00 a 07), ícones SF Symbols e cores
│   │   └── ScanModels.swift                # Modelos de Lixo, Space Lens, Desinstalador, Restos e Updates
│   ├── Services/
│   │   ├── SafetyGuard.swift               # Validação estrita de caminhos protegidos e integração com Trash
│   │   ├── DiskScannerService.swift        # Motor assíncrono de varredura para os 8 canais + parser Sparkle XML
│   │   └── SystemMonitorService.swift      # Telemetria local Mach/IOKit (CPU, RAM, Disco, Bateria, Rede)
│   └── Views/
│       ├── MainView.swift                  # NavigationSplitView com barra lateral translúcida
│       ├── Components/
│       │   ├── GlassCard.swift             # Cartões nativos com Material/Vibrancy do macOS
│       │   ├── HoldToConfirmButton.swift   # Botão de segurança "Segure para confirmar"
│       │   └── SpaceLensRingChart.swift    # Gráfico Sunburst interativo em anéis concêntricos
│       ├── Channels/                       # Telas dedicadas dos canais 00 a 07
│       └── MenuBar/
│           └── MenuBarPopoverView.swift    # Popover do agente na barra de menus
└── Tests/MeuCleanerTests/
    └── MeuCleanerTests.swift               # Testes unitários da Guarda de Segurança e regras de seleção
```

---

## 🚀 Como Compilar e Executar

### Pré-requisitos
- **macOS 14.0 (Sonoma)** ou superior
- **Swift 5.10 / 6.0+** (Xcode 16+ ou Command Line Tools)

### 1. Rodar os testes unitários
```bash
swift test
```

### 2. Executar em modo desenvolvimento
```bash
swift run MeuCleaner
```

### 3. Gerar o aplicativo nativo `MeuCleaner.app` (Release)
```bash
chmod +x scripts/build-app.sh
./scripts/build-app.sh
open build/MeuCleaner.app
```

---

## 📄 Licença

Distribuído sob a licença MIT.
