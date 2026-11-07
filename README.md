# Opus 5.5 Effort Test

**English** | [Русский](#русский)

The same prompt was given to Claude Opus 5.5 at six effort levels: **low, medium, high, xhigh, max and ultracode**.
The task: build a Forza Horizon-style game from scratch (open world, 10 cars, traffic, weather, activities) in **Godot 4.7**, with the 3D models made in **Blender** through MCP.

This repository holds all six resulting games, the prompt and the agents' reports. You can download the games and play them yourself.

| # | Effort | Game | Folder |
|---|---|---|---|
| 1 | low | Horizon Drift: Four Valleys | [`1-low-effort`](1-low-effort) |
| 2 | medium | Verdant Ridge Festival | [`2-medium-effort`](2-medium-effort) |
| 3 | high | Velora Roads | [`3-high-effort`](3-high-effort) |
| 4 | xhigh | VALORIA: Open Road Festival | [`4-xhigh-effort`](4-xhigh-effort) |
| 5 | max | Ridgeline Festival | [`5-max-effort`](5-max-effort) |
| 6 | ultracode | Sunward Roads | [`6-ultracode-effort`](6-ultracode-effort) |

Every folder has an `OPUS_5.5_FINAL_REPORT.md` with the agent's summary: what worked, what didn't, how much time and how many tokens it took.
The prompt itself is in each folder as `Prompt_<number>_<level>.md`. It is the same for all six; only the effort level changes.

**Guide: how to connect an AI agent to a game engine and to Blender via MCP** → [`guide/`](guide) ([PDF, English](guide/Blender_MCP_Guide_EN.pdf) · [PDF, Russian](guide/Blender_MCP_Guide_RU.pdf))

---

# How to run the games (beginner guide)

No programming and no manual installation needed. You need a Windows or Mac computer, an internet connection (for the first launch) and disk space: about 1 GB per game including the engine.

> The games are heavy: an open world with traffic and weather. You need a graphics card that supports Vulkan (almost any gaming GPU from recent years works, so do Apple Silicon Macs). On weak computers the games will run slowly. The author ran them on an RTX 5070-class GPU.

## Step 1. Download the project

1. Open the repository page on GitHub.
2. Click the green **Code** button, then **Download ZIP**.
3. Wait for the download to finish. The file is large (several hundred megabytes).

## Step 2. Unpack the archive

The games **cannot be run from inside the ZIP**. Unpack it first.

- **Windows:** right-click the ZIP, **Extract All…**, **Extract**.
- **macOS:** double-click the ZIP; a folder appears next to it.

Keep the path short and not buried deep inside other folders. For example, unpack it right onto the desktop.

## Step 3. Open the folder of the game you want

Inside the unpacked folder there are six folders: `1-low-effort`, `2-medium-effort` and so on. Open the game you want to try. Each game runs on its own.

## Step 4a. Running on Windows

1. Find **`PLAY-Windows.bat`** and double-click it.
2. If Windows shows a blue “Windows protected your PC” window, click **More info**, then **Run anyway**. This is the normal protection for files from the internet. The file is plain text; you can open it in Notepad and read it.
3. A black window opens and goes through the steps:
   - **[1/3]** the Godot engine is downloaded (about 85 MB). Only once for all games.
   - **[2/3]** on the first launch of a game its files are prepared. This takes 2 to 10 minutes. The window may look frozen; just wait.
   - **[3/3]** the game starts.
4. Do not close the black window while playing. When you are done, quit the game normally and the window closes by itself.

## Step 4b. Running on macOS

1. Find **`PLAY-Mac.command`** and double-click it.
2. If macOS says the file can't be opened because the developer cannot be verified:
   - **right-click** the file (or Control-click), choose **Open**, then **Open** again in the dialog;
   - or open **System Settings → Privacy & Security** and click **Open Anyway** at the bottom.
3. A Terminal window opens with the same steps as on Windows: engine download (about 165 MB, once), file preparation (2–10 minutes on the first launch) and the game start.
4. If Terminal says `Permission denied`, open Terminal and run these two commands. Replace `1-low-effort` with the folder you need:

   ```bash
   cd ~/Desktop/Opus5-5-Effort-Test-main
   chmod +x 1-low-effort/PLAY-Mac.command
   ```

   Then double-click the file again.
5. If macOS blocks all files after downloading the ZIP, remove the block with one Terminal command (use your folder):

   ```bash
   xattr -dr com.apple.quarantine ~/Desktop/Opus5-5-Effort-Test-main
   ```

## Controls (the same in all games)

| Key | Action |
|---|---|
| **W / S** or arrows | throttle / brake and reverse |
| **A / D** or arrows | steering |
| **Space** | handbrake |
| **C** | change camera |
| **R** | put the car back on the road |
| **F1** or **Tab** | garage: choose from 10 cars |
| **F2** | debug menu: teleports, weather, time of day, traffic |
| **`** (backtick, left of the 1 key) | command console (`help` lists all commands, `cars` lists the cars) |
| **M** | map |
| **P** | photo mode |
| **F12** | screenshot |

Some games have extra keys. See `DEVELOPMENT.md` inside the game's folder for the full list.

## If something goes wrong

| Problem | What to do |
|---|---|
| Godot does not download | Check your internet connection and run the file again. If your provider blocks GitHub, turn on a VPN for the download. |
| The first launch takes very long | That is normal; wait up to 10 minutes. Do not close the window. |
| The window closed right after starting | Run the file again. If that doesn't help, update your graphics driver. |
| The game is slow | Close other programs. The games are made for powerful GPUs. |
| I want to start over | Delete the hidden `.godot` folder inside the game's folder and run the file again. |
| I want to remove the engine | Windows: delete `%LOCALAPPDATA%\OpusEffortTest`. macOS: delete `~/Library/Application Support/OpusEffortTest`. |

If something doesn't work for you, open an **Issue** on GitHub and attach a screenshot of the window with the error.

## For the curious: what happens on launch

The launcher does three things: downloads the official Godot 4.7.2 engine from [Godot Engine on GitHub](https://github.com/godotengine/godot-builds/releases) into your user folder, prepares the game files once with `godot --import`, and starts the game with `godot --path .`. Nothing is installed into the system and no administrator rights are needed. All launchers are plain text and can be read.

The `blender_source/` folder inside each game holds the source `.blend` file with all its 3D models. Open it in [Blender](https://www.blender.org/) to look at the models.

---

<a id="русский"></a>

# Opus 5.5 Effort Test — Русский

[English](#opus-55-effort-test) | **Русский**

Один и тот же промпт отправили Claude Opus 5.5 на шести уровнях мышления: **low, medium, high, xhigh, max и ultracode**.
Задача: с нуля сделать игру в стиле Forza Horizon (открытый мир, 10 машин, трафик, погода, активности) на движке **Godot 4.7**, а 3D-модели создать в **Blender** через MCP.

Здесь лежат все шесть получившихся игр, промпт и отчёты агентов. Игры можно скачать и запустить самому.

| # | Уровень | Игра | Папка |
|---|---|---|---|
| 1 | low | Horizon Drift: Four Valleys | [`1-low-effort`](1-low-effort) |
| 2 | medium | Verdant Ridge Festival | [`2-medium-effort`](2-medium-effort) |
| 3 | high | Velora Roads | [`3-high-effort`](3-high-effort) |
| 4 | xhigh | VALORIA: Open Road Festival | [`4-xhigh-effort`](4-xhigh-effort) |
| 5 | max | Ridgeline Festival | [`5-max-effort`](5-max-effort) |
| 6 | ultracode | Sunward Roads | [`6-ultracode-effort`](6-ultracode-effort) |

В каждой папке есть `OPUS_5.5_FINAL_REPORT.md` с итогами работы агента: что получилось, что нет, сколько времени и токенов ушло.
Сам промпт лежит в каждой папке в файле `Prompt_<номер>_<уровень>.md`, он одинаковый для всех шести, меняется только уровень мышления.

**Гайд: как подключить ИИ-агента к игровому движку и к Blender через MCP** → [`guide/`](guide) ([PDF на русском](guide/Blender_MCP_Guide_RU.pdf) · [PDF на английском](guide/Blender_MCP_Guide_EN.pdf))

---

# Как запустить игры (инструкция для новичков)

Программировать и ставить ничего вручную не нужно. Нужен компьютер с Windows или Mac, интернет (для первого запуска) и место на диске: примерно 1 ГБ на одну игру вместе с движком.

> Игры тяжёлые: это открытый мир с трафиком и погодой. Нужна видеокарта, которая поддерживает Vulkan (подойдёт почти любая игровая видеокарта последних лет, Mac на Apple Silicon тоже подходит). На слабых компьютерах игра будет работать медленно. Автор запускал игры на видеокарте уровня RTX 5070.

## Шаг 1. Скачайте проект

1. Откройте страницу репозитория на GitHub.
2. Нажмите зелёную кнопку **Code**, затем **Download ZIP**.
3. Дождитесь окончания загрузки. Файл большой (несколько сотен мегабайт).

## Шаг 2. Распакуйте архив

Игру **нельзя запускать из архива**. Её нужно сначала распаковать.

- **Windows:** нажмите на ZIP правой кнопкой мыши, **Извлечь всё…**, **Извлечь**.
- **macOS:** дважды кликните по ZIP, рядом появится папка.

Лучше, чтобы путь к папке не был слишком длинным и не лежал глубоко внутри других папок. Например, распакуйте прямо на рабочий стол.

## Шаг 3. Откройте папку нужной игры

Внутри распакованной папки есть шесть папок: `1-low-effort`, `2-medium-effort` и так далее. Откройте ту игру, которую хотите попробовать. Каждая игра запускается отдельно.

## Шаг 4a. Запуск на Windows

1. Найдите файл **`PLAY-Windows.bat`** и дважды кликните по нему.
2. Если Windows показывает синее окно «Windows защитила ваш компьютер», нажмите **Подробнее**, затем **Выполнить в любом случае**. Это обычная защита для файлов из интернета. Внутри файла только текст, его можно открыть Блокнотом и прочитать.
3. Откроется чёрное окно. В нём будут идти шаги:
   - **[1/3]** скачивается движок Godot (около 85 МБ). Это только один раз для всех игр.
   - **[2/3]** на первом запуске игры готовятся её файлы. Это занимает от 2 до 10 минут. Окно может казаться зависшим, просто подождите.
   - **[3/3]** запускается игра.
4. Чёрное окно закрывать нельзя, пока вы играете. Когда закончите, закройте игру обычным способом, окно закроется само.

## Шаг 4b. Запуск на macOS

1. Найдите файл **`PLAY-Mac.command`** и дважды кликните по нему.
2. Если macOS пишет, что файл нельзя открыть, потому что разработчик не подтверждён:
   - кликните по файлу **правой кнопкой** (или с зажатым Control), выберите **Открыть**, затем ещё раз **Открыть** в окне;
   - либо откройте **Системные настройки → Конфиденциальность и безопасность**, внизу нажмите **Всё равно открыть**.
3. Откроется окно Терминала с теми же шагами, что и на Windows: скачивание движка (около 165 МБ, один раз), подготовка файлов (2–10 минут при первом запуске) и запуск игры.
4. Если Терминал пишет `Permission denied` («нет прав»), откройте Терминал и выполните две команды. Папку `1-low-effort` замените на нужную:

   ```bash
   cd ~/Desktop/Opus5-5-Effort-Test-main
   chmod +x 1-low-effort/PLAY-Mac.command
   ```

   После этого снова дважды кликните по файлу.
5. Если macOS блокирует все файлы после скачивания ZIP, снимите блокировку одной командой в Терминале (подставьте свою папку):

   ```bash
   xattr -dr com.apple.quarantine ~/Desktop/Opus5-5-Effort-Test-main
   ```

## Управление (одинаково во всех играх)

| Клавиша | Действие |
|---|---|
| **W / S** или стрелки | газ / тормоз и задний ход |
| **A / D** или стрелки | руль |
| **Пробел** | ручной тормоз |
| **C** | сменить камеру |
| **R** | вернуть машину на дорогу |
| **F1** или **Tab** | гараж: выбор из 10 машин |
| **F2** | меню отладки: телепорты, погода, время суток, трафик |
| **`** (тильда, левее цифры 1) | консоль команд (`help` покажет все команды, `cars` список машин) |
| **M** | карта |
| **P** | фоторежим |
| **F12** | скриншот |

В разных играх есть дополнительные клавиши. Полный список смотрите в файле `DEVELOPMENT.md` внутри папки игры.

## Если что-то пошло не так

| Проблема | Что делать |
|---|---|
| Не скачивается Godot | Проверьте интернет и запустите файл ещё раз. Если провайдер блокирует GitHub, включите VPN на время скачивания. |
| Первый запуск идёт очень долго | Это нормально, подождите до 10 минут. Закрывать окно нельзя. |
| Окно закрылось сразу после запуска | Запустите файл ещё раз. Если не помогло, обновите драйвер видеокарты. |
| Игра тормозит | Закройте другие программы. Игры сделаны для мощных видеокарт. |
| Хочу начать заново | Удалите папку `.godot` внутри папки игры (она скрытая) и запустите файл снова. |
| Хочу удалить движок | Windows: удалите папку `%LOCALAPPDATA%\OpusEffortTest`. macOS: удалите папку `~/Library/Application Support/OpusEffortTest`. |

Если у вас что-то не работает, напишите об этом в разделе **Issues** на GitHub и приложите скриншот окна с ошибкой.

## Для любопытных: что происходит при запуске

Файл запуска делает три вещи: скачивает официальный движок Godot 4.7.2 с [GitHub Godot Engine](https://github.com/godotengine/godot-builds/releases) в папку пользователя, один раз готовит файлы игры командой `godot --import` и запускает игру командой `godot --path .`. Ничего не устанавливается в систему и не требует прав администратора. Все файлы запуска — обычный текст, их можно прочитать.

В папке `blender_source/` внутри каждой игры лежит исходный `.blend`-файл со всеми 3D-моделями. Чтобы посмотреть модели, откройте его в [Blender](https://www.blender.org/).
