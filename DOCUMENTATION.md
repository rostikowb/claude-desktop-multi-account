# Claude accounts — документація

Локальна програма для запуску кількох акаунтів Claude Desktop на одному ПК:
окреме вікно, окремий профіль, окремий вхід і окремий значок у панелі задач.
Це форк [Leonxlnx/claude-desktop-multi-account](https://github.com/Leonxlnx/claude-desktop-multi-account)
з локальними змінами (ізоляція, окремий процес usage-вікна, українська
локалізація, ручна корекція тижневого ресету).

> Неофіційний інструмент. Не пов'язаний з Anthropic. Використовуйте лише
> власні акаунти; не передавайте доступ і не діліть акаунти між людьми.

## 1. Де що лежить

| Що | Шлях |
|---|---|
| Програма (репозиторій + `ClaudeAccounts.exe`) | `D:\Soft\claude-multi-account` |
| Дані акаунтів (профілі) | `D:\Soft\claude-multi-account\accounts\<name>` |
| Змінна, що задає цей каталог | `CCM_HOME` (user environment) |
| Ярлик у Пуску | `Claude accounts` → `Claude <name>` / `Claude accounts` |
| Ярлик на робочому столі | `%USERPROFILE%\OneDrive\Desktop\Claude accounts.lnk` |
| Команда `ccm` у терміналі | `%LOCALAPPDATA%\Microsoft\WindowsApps\ccm.cmd` і `ccm.ps1` |
| Форк на GitHub | https://github.com/rostikowb/claude-desktop-multi-account |
| Ця документація | `D:\Soft\claude-multi-account\DOCUMENTATION.md` |
| Аналіз ізоляції та план | `D:\Soft\claude-multi-account\ISOLATION.md` |
| Опис оригіналу | `D:\Soft\claude-multi-account\README.md` |

`ClaudeAccounts.exe` збирається локально з `ClaudeAccounts.cs` штатним
компілятором Windows (`csc.exe`), без завантаження готових бінарників.

## 2. Архітектура

- **`ClaudeAccounts.exe`** — C#/.NET Framework 4.x:
  - `tray` — легкий процес WinForms (~25 МБ), тримає іконку, меню та
    призначає кожному вікну Claude окремий AppUserModelID для панелі задач;
  - `usage` — окремий процес WPF (~75 МБ), вікно з картками акаунтів.
    Закриття вікна завершує цей процес і повертає пам'ять.
- **Вікно акаунта** — звичайний Claude Desktop, запущений з
  `--user-data-dir="<профіль>"`. Це окремий Chromium-профіль: cookies,
  IndexedDB, localStorage, токени, кеші, `ant-did` та історія usage.
- **`ccm`** — PowerShell-обгортка: створює/видаляє профілі, ярлики та іконки,
  перевіряє ізоляцію, збирає `.exe`, ставить лаунчери в PATH.
- **Claude Code** кожного акаунта отримує власний `CLAUDE_CONFIG_DIR`
  (`<профіль>\claude-config`) і власний `TEMP`/`TMP` (`<профіль>\temp`).

## 3. Швидкий старт

1. Створити акаунт:
   - у вікні **Claude accounts** натиснути **«+ Додати акаунт»**, або
   - правий клік по іконці в треї → **«Додати акаунт…»**, або
   - у терміналі: `ccm add work`.
2. Відкрити його: **Пуск → Claude accounts → Claude work** або `ccm work`.
3. Увійти через **Continue with email** (не Google) і ввести код із листа.
4. За бажанням закріпити вікно на панелі задач.
5. Відкрити usage-вікно: лівий клік по трею або `ccm usage`.

## 4. Команди `ccm`

| Команда | Що робить |
|---|---|
| `ccm add <name>` | створити профіль, ярлик, іконку й відкрити вікно |
| `ccm <name>` | відкрити вікно акаунта |
| `ccm usage` | відкрити usage-вікно |
| `ccm list` | показати 5h/Weekly у терміналі |
| `ccm doctor` | перевірити, що install id / machine id / device name різні |
| `ccm isolate <name>` | достворити ізоляційні каталоги для наявного акаунта |
| `ccm claude <name> [args]` | запустити Claude Code CLI з конфігом акаунта |
| `ccm telemetry <name> off\|on` | увімкнути/вимкнути блокування essential telemetry |
| `ccm remove <name>` | видалити профіль, ярлик, дані й облікові записи Code |
| `ccm rename <old> <new>` | перейменувати акаунт (вікно має бути закрите) |
| `ccm shortcuts` | перестворити ярлики та іконки |
| `ccm build` | перезібрати `ClaudeAccounts.exe` |
| `ccm install` | зібрати, створити ярлики й покласти `ccm` у PATH |

Додатково `ClaudeAccounts.exe add <name>` робить те саме, що `ccm add`,
але без відкриття терміналу.

## 5. Вікно usage

- Картки акаунтів: статус `Відкрито/Закрито`, 5-годинний і тижневий ліміти,
  час останнього збереження.
- Клік по картці відкриває відповідне вікно.
- Правий клік по картці:
  - **Відкрити**;
  - **Задати тижневе скидання…** — вставити точний час із
    **Claude → Settings → Usage**;
  - **Видалити акаунт…** — видаляє профіль після підтвердження.
- **«+ Додати акаунт»** — створює новий профіль.

### Звідки беруться дати скидання

- Точний час (`exact`) береться з `cachedUsageUtilization`, який Claude Code
  зберігає у `<профіль>\claude-config\.claude.json` (для основного застосунку —
  `%USERPROFILE%\.claude.json`), якщо він належить цьому акаунту.
- Інакше час **оцінюється** за `plan-usage-history.json`: шукається момент,
  коли відсоток обнулився/впав, і до нього додається 5 годин або 7 днів.
  Якщо історія починається вже з ненульового значення, показується
  **верхня межа** («не пізніше ніж»), бо точний старт вікна невідомий.
- Ручна корекція (`ccm-reset.json`) має приоритет і показується як `вручну`.
  Після настання дати ігнорується.
- Для тижневого рядка показується відлік у днях/годинах і кількість
  повних 5-годинних вікон, що ще влізуть до скидання.

## 6. Ізоляція акаунтів

Кожне вікно отримує:

- власний `--user-data-dir` (усі cookies, токени, IndexedDB, кеші, `ant-did`);
- власний `CLAUDE_CONFIG_DIR` — `machineID`, `userID`, історія та облікові
  дані Claude Code не перетинаються з іншими акаунтами;
- власні `TEMP`/`TMP`;
- `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`;
- за бажанням `--desktop-managed-config={"disableEssentialTelemetry":true}`
  (файл `<профіль>\no-telemetry`, команда `ccm telemetry <name> off`);
- унікальний `remoteToolsDeviceName` замість hostname.

`ccm remove` видаляє профіль, ярлик у Пуску, закріплений ярлик, запис
`Claude Code-credentials-<hash>` у Windows Credential Manager і локальні
дані. Історія Claude Code в `%USERPROFILE%\.claude` (спільна для основного
застосунку) не видаляється.

Що залишається спільним і не змінюється клієнтом: публічний IP, залізо,
hostname ОС, заголовки `anthropic-client-*`, платіжні дані та email.
Детальні заміри — у `ISOLATION.md`.

## 7. Файли профілю

| Файл/каталог | Призначення |
|---|---|
| `config.json` | токени й налаштування вікна Claude Desktop |
| `ant-did` | install id (base64 UUID), унікальний для профілю |
| `ant-device-registry.json` | реєстр пристрою для акаунта |
| `plan-usage-history.json` | семпли 5h/Weekly |
| `claude-config\` | конфіг Claude Code: `.claude.json`, `projects`, `sessions` |
| `temp\` | TEMP/TMP цього вікна |
| `ccm-reset.json` | ручна корекція тижневого ресету (необов'язково) |
| `ccm-icon.ico` | іконка з міткою акаунта |
| `claude_desktop_config.json` | налаштування Cowork/remote tools |

## 8. Розробка та деплой

- Локальний репозиторій: `D:\Soft\claude-multi-account`.
- `origin` — форк `rostikowb/claude-desktop-multi-account`;
  `upstream` — `Leonxlnx/claude-desktop-multi-account`.
- Перезбирання після змін `ClaudeAccounts.cs`: `ccm build`.
- Після змін `ccm.ps1` перезібрання не потрібне.
- Публікація: `git add -A && git commit -m "..." && git push`.
- Синхронізація з оригіналом: `git pull upstream main`.

## 9. Діагностика

1. `ccm doctor` — головна перевірка: install id / machine id / device name
   мають бути різними; `code config` і `temp` — `True` для акаунтів.
2. `ccm list` — ті самі цифри, що у вікні.
3. Якщо `ccm` не знаходиться: відкрити новий термінал або запустити
   `D:\Soft\claude-multi-account\ccm.cmd <команда>`.
4. Якщо usage-вікно не відкривається: `ccm usage`; перевірити процеси
   `ClaudeAccounts` у диспетчері задач.
5. Якщо трей зник: `ClaudeAccounts.exe tray` (або перезапустити usage-вікно).
6. Якщо `ccm remove` не може видалити профіль: повністю закрити вікно
   (X лише ховає в трей; вихід — через трей-іконку вікна), зачекати кілька
   секунд (антивірус/індексатор можуть тримати файли) і повторити.
7. Якщо дата тижневого ресету не збігається з Claude: це оцінка; задати
   точний час через правий клік → **Задати тижневе скидання…**.

## 10. Відомі обмеження

- `claude://`-посилання завжди відкривають основний Claude; Google-вхід у
  додаткових вікнах не працює — використовуйте email + код.
- Точний тижневий ресет зберігається лише на сервері; локально його немає,
  тому без ручної корекції показується оцінка/верхня межа.
- Інструмент не робить запитів до Anthropic: тільки читає локальні файли.
- Оновлення Claude Desktop можуть змінити внутрішні шляхи; після великого
  оновлення перевіряйте `ccm doctor`.
- Один акаунт = один повний Chromium-процес (~0.5–1 ГБ RAM). Тримайте
  відкритими лише потрібні вікна.

## 11. Безпека

- Не використовуйте інструмент для спільного доступу до акаунтів або
  обходу лімітів; перевіряйте Consumer Terms Anthropic.
- Локальні дані акаунтів не шифруються додатково; захист — обліковий запис
  Windows і BitLocker.
- Після видалення акаунта серверні чати/підписка на боці Anthropic не
  видаляються — їх треба скасовувати/видаляти окремо.

## 12. Історія локальних змін

| Коміт | Що змінено |
|---|---|
| `9bdc273` | ізоляція: `CLAUDE_CONFIG_DIR`, `TEMP`, device name, `ccm doctor/isolate/claude/telemetry` |
| `70fd256` | трей і usage-вікно — окремі процеси, трей без WPF |
| `3a577d7` | створення акаунтів із usage-вікна та меню трею |
| `e5f5a77` | темні кнопки, видалення акаунта з UI, очищення Credential Manager |
| `730a36a` | дати ресетів як діапазон/межа, відлік і кількість 5-годинних вікон |
| `b770951` | українська локалізація UI, ручна корекція тижневого ресету |

## 13. Видалення

1. Закрити всі вікна Claude і вийти з трею.
2. `ccm remove <name>` для кожного акаунта.
3. Видалити ярлики з Пуска/панелі задач.
4. Видалити `D:\Soft\claude-multi-account` і, за бажання, змінну `CCM_HOME`.
5. Видалити `%LOCALAPPDATA%\Microsoft\WindowsApps\ccm.cmd` і `ccm.ps1`.
