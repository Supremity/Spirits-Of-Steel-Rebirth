# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

Spirits of Steel Rebirth is a grand-strategy / RTS game built in **Godot 4.7** (GL Compatibility renderer). Almost all code is GDScript. The project is also a .NET project (`Spirits of Steel Rebirth.csproj`, `net8.0`), so it needs the **mono/.NET build of Godot**. The only C# is `Scenes/RecipeData.cs` and the console addon's C# bindings (`addons/console/cs_bindings/`).

## Commands

There is no build system, linter, or test suite beyond Godot itself.

- Open the editor: `godot-mono --editor --path .`
- Run the game: `godot-mono --path .` (the main scene is set in `project.godot`)
- Build the C# assembly: `dotnet build` (the Godot editor also does this)
- Run a standalone script headless: `godot-mono --headless --path . --script res://scratch/test_interpreter.gd` (the script must `extends SceneTree`). Autoloads aren't available in this mode, so most manager code can't be tested this way.
- Export targets are in `export_presets.cfg`.

`.uid` files sit next to every script and shader. Commit them together with their source files, because scenes and `project.godot` reference many resources by `uid://` instead of by path.

## Architecture

### Autoload singletons (`Managers/`)
Global state lives in autoloads registered in `project.godot`. Code throughout the project calls them directly by name (`MapManager`, `CountryManager`, `GameState`, `WarManager`, `TroopManager`, `DecisionManager`, `EconomyManager`, `EventManager`, `InterpreterManager`, `FactionManager`, `IdeologyManager`, `PlansManager`, etc.). Some names don't match their files:
- `SceneSwitcher` → `Managers/SceneManager.gd`. It switches between the MENU, WORLD and EDITOR scenes behind a loading screen and keeps the world scene cached.
- `GameState` is a grab-bag of session flags: the current start, the selected country, UI modes, pending save loads, and a reference to `current_world`.

`MapManager.gd` (~1700 lines) is the core. It holds the province ID map image, the province → country lookups (`country_to_provinces`, owned, occupied, rightful), the `Province` objects, the province graph (`SoiStar`, used for pathfinding), and the state-color texture that the map shader reads.

### Game loop
`Scripts/game_clock.gd` (`$/root/Main/Clock`) emits `hour_passed` and `day_passed`. `World.DoSetup` (`Scripts/Map/World.gd`) connects these to `CountryManager._on_hour_passed` and `_on_day_passed`, and to `EventManager._on_day_passed`. CountryManager then calls `process_hour()` / `process_day()` on each `CountryData`, runs `EconomyManager.process_economy_day()`, and checks for super events. UI scripts connect to the clock on their own.

### Scenarios ("starts") and saves
Each folder in `starts/<Name>/` is a playable scenario:
- `map_data.json`: polities, provinces, biomes, resources, buildings, ideologies, wars, factions, significant figures, and the clock
- `regions.png`: the province ID map
- `decisions/`: `default.json` plus optional `<CountryName>.json` overrides. If a start has no `default.json`, the root `decisions/default.json` is used.
- `superevents.json`, `building_functions.json`, and an optional `flags/` folder

`World.DoSetup` / `load_map_data` loads `res://starts/<GameState.current_start>/map_data.json`. If `GameState.pending_load_save` is set, it loads `res://saves/<name>.json` instead; a save has the same shape plus `scenario_path`. The `tmp/` subfolders in starts are scratch copies.

### Data-driven scripting
Decisions and super events are written as JSON expression trees of the form `{"func": "<name>", "args": [...]}`. `InterpreterManager` evaluates them. To add a new scriptable function:
1. Add its argument types to `InterpreterManager.functions`.
2. Add its parameter names to `param_names` (the in-game decision editor shows these).
3. Handle it in `get_function`.

Building recipes in `building_functions.json` work differently. Their values are Godot `Expression` strings (e.g. `has_tag('fuel')`, `input_amount(0)`), which `Scripts/Map/TagMatcher.gd` evaluates.

`Docs/ImportantFigureSkillsReference.md` lists the skill modifiers that significant figures can have (additive vs. multiplicative).

### Code layout
- `Scripts/Map/`: data classes (`CountryData`, `Province`, `BuildingData`, `ResourceData`, ...), mostly with `FromDict`/`ToDict` serialization
- `Scripts/Diplomacy/`, `Scripts/Divisions/`, `Scripts/Events/`: domain data classes and popups
- `Scripts/UI/`: UI controllers; `GameUI.gd` is the main in-game HUD
- `Scripts/UI/MapEditor/`: the in-game map/scenario editor
- `shaders/map_shader.gdshader`: renders the map from the region ID texture and the state-color lookup texture

## Conventions

- New code uses CamelCase for function names (recent commits are migrating to it), but much of the existing code is still snake_case. Match the file you're editing.
- Author notes are written as `# NOTE(soi):` / `# TODO(pol):`.
