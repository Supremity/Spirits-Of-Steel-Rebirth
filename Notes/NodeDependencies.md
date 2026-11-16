# Node & Function Dependencies

Generated from a scan of every `.gd` file (excluding `addons/`) for `<Autoload>.<member>` calls, `$`/`get_node` paths, and `.connect()` calls. Arrow labels are the functions/members that the source calls on the target.

## 1. Scene tree

```mermaid
flowchart TD
    subgraph Main["Main (Scenes/main.tscn, main.gd)"]
        Test["Test (RecipeData.cs)"]
        MapContainer --> CultureSprite & RegionSprite
        Camera2D --> CameraController["CameraController (camera_controller.gd)"]
        Clock["Clock (game_clock.gd)"]
        CurrentScene
        Tooltip["Tooltip / PanelContainer (Tooltip.gd)"]
        Audio["Audio (Audio.gd)"] --> Music & SFX
        SettingsLayer --> SettingsMain["Settings (Settings.gd)"]
    end

    CurrentScene -. "SceneSwitcher.switch_to" .-> MainMenu["MainMenu (main_menu.tscn)"]
    CurrentScene -. "SceneSwitcher.switch_to" .-> World
    CurrentScene -. "SceneSwitcher.switch_to" .-> MapEditor["MapEditor (MapEditor.tscn)"]

    subgraph World["World (Scenes/world.tscn, World.gd)"]
        CustomRenderer["CustomRenderer (custom_renderer.gd)"] --> TroopMultiMesh
        TroopSelection["TroopSelection (troop_selection.gd)"]
        ui_game["ui_game (GameUI.gd)"]
        DecisionTreeUI
        CountryManageUI["CountryManageUI (ManageCountryUI.gd)"]
        PeaceProcessUI
        LostTerritoryUI
        GovernmentUI
        SettingsWorld["Settings (Settings.gd)"]
    end
```

## 2. Signals & node-path lookups

```mermaid
flowchart LR
    Clock["Main/Clock"]
    Clock -- "hour_passed → _on_hour_passed" --> CountryManager
    Clock -- "day_passed → _on_day_passed" --> CountryManager
    Clock -- "day_passed → _on_day_passed" --> EventManager
    Clock -- "day_passed" --> CustomRenderer
    Clock -- "day_passed → refresh_ui" --> ActionRow

    MapManager -- "province_ownership_changed" --> CustomRenderer
    MapManager -- "province_ownership_changed" --> CountryAI
    CountryManager -- "player_country_changed" --> CustomRenderer
    CountryManager -- "player_country_changed" --> GameUI
    MapManager -- "country_clicked / close_sidemenu" --> GameUI

    World -- "$/root/Main/Clock" --> Clock
    World -- "KeyboardManager.settings = $/root/Main/SettingsLayer" --> KeyboardManager
    KeyboardManager -- "$/root/Main/SettingsLayer" --> SettingsLayer["Main/SettingsLayer"]
    World -- "TroopManager.troop_selection = $TroopSelection" --> TroopManager
    World -- "GameState.current_world = self" --> GameState
```

## 3. Autoload ↔ autoload

```mermaid
flowchart LR
    ConsoleManager -- "add_command, print_info, print_line" --> Console
    ConsoleManager -- "make_puppet, set_player_country, cleanup_empty_countries" --> CountryManager
    ConsoleManager -- "_load_decisions, debug" --> DecisionManager
    ConsoleManager -- "invite_faction" --> FactionManager
    ConsoleManager -- "AnnexCountry, ReleaseCountry, InstantiateCountryFromProvinces, ChangeProvinceTypes, AllowPids" --> MapManager
    ConsoleManager -- "switch_to" --> SceneSwitcher
    ConsoleManager -- "declare_war, call_to_arms, _handle_total_collapse" --> WarManager
    ConsoleManager -- "current_start, instabuild" --> GameState

    CountryManager -- "process_economy_day" --> EconomyManager
    CountryManager -- "check_super_events" --> EventManager
    CountryManager -- "invite_faction, clear_faction" --> FactionManager
    CountryManager -- "get_ideology_name" --> IdeologyManager
    CountryManager -- "AllowPids, UnallowPids, ShowCountriesMap, country_to_*" --> MapManager
    CountryManager -- "get_flag, get_troops_for_country" --> TroopManager

    DecisionManager -- "get_function" --> InterpreterManager
    DecisionManager -- "show_alert" --> EventManager
    DecisionManager -- "player_country" --> CountryManager

    EconomyManager -- "countries, player_country" --> CountryManager
    EconomyManager -- "show_alert" --> EventManager
    EconomyManager -- "ProvinceUpdated, buildingTypesToCountryCount" --> MapManager
    EconomyManager -- "play_sfx" --> MusicManager

    EventManager -- "get_function" --> InterpreterManager
    EventManager -- "play_sfx, play_custom_file" --> MusicManager

    FactionManager -- "AllowPids, UnallowPids" --> MapManager
    FactionManager -- "countries" --> CountryManager

    GameState -- "ShowCountriesMap" --> MapManager

    InterpreterManager -- "make_puppet, release_puppet, set_player_country" --> CountryManager
    InterpreterManager -- "schedule_event, show_alert" --> EventManager
    InterpreterManager -- "invite_faction" --> FactionManager
    InterpreterManager -- "AnnexCountry, ReleaseCountry, ChangeProvinceTypes" --> MapManager
    InterpreterManager -- "plans, current_start_folder" --> PlansManager
    InterpreterManager -- "settings" --> SettingsManager
    InterpreterManager -- "get_flag" --> TroopManager
    InterpreterManager -- "declare_war, is_at_war_names" --> WarManager

    KeyboardManager -- "is_visible" --> Console
    KeyboardManager -- "CycleMapMode, close_sidemenu" --> MapManager
    KeyboardManager -- "troop_selection" --> TroopManager
    KeyboardManager -- "_current_type" --> SceneSwitcher

    MapManager -- "add_country, make_puppet, GetCountryColor, cleanup_empty_countries" --> CountryManager
    MapManager -- "start_construction, StartInfrastructureConstruction, construction_queue" --> EconomyManager
    MapManager -- "factions" --> FactionManager
    MapManager -- "RemoveTroop, get_troops_for_country, load_troops_for_province" --> TroopManager
    MapManager -- "is_visible" --> Console

    MusicManager -- "settings" --> SettingsManager
    PlansManager -- "get_function" --> InterpreterManager
    SceneSwitcher -- "current_world, tooltip" --> GameState

    SettingsManager -- "set_music_volume, set_sfx_volume, radios" --> MusicManager
    SettingsManager -- "debug" --> DecisionManager & InterpreterManager

    TroopManager -- "find_path, heuristic, province_centers" --> MapManager
    TroopManager -- "start_battle, resolve_province_arrival, is_at_war_names" --> WarManager
    TroopManager -- "countries" --> CountryManager

    WarManager -- "OccupyProvince, DeoccupyProvince, TransferOwnership, province_graph" --> MapManager
    WarManager -- "RemoveTroop, teleport_troop_to_province, get_province_strength" --> TroopManager
    WarManager -- "clear_faction, in_faction" --> FactionManager
    WarManager -- "show_alert" --> EventManager
    WarManager -- "play_music, play_sfx" --> MusicManager
    WarManager -- "countries, cleanup_empty_countries" --> CountryManager
```

## 4. Scene scripts & data classes → autoloads

```mermaid
flowchart LR
    %% Bootstrap / loading
    main_gd["main.gd"] -- "switch_to" --> SceneSwitcher
    StartEntry -- "current_start" --> GameState
    StartEntry -- "switch_to" --> SceneSwitcher
    MainMenu -- "settings" --> KeyboardManager
    Audio -- "setup_audio" --> MusicManager

    World -- "initialize_countries, SaveCountries, set_player_country" --> CountryManager
    World -- "load_events, save_events" --> EventManager
    World -- "Initialize, SaveFactions" --> FactionManager
    World -- "HandleClick, HandleHover, _BuildGlobalRegistry, Save*" --> MapManager
    World -- "load_wars, save_wars, check_for_new_battles, reset_state" --> WarManager
    World -- "clear_all_troops" --> TroopManager
    World -- "apply_settings" --> SettingsManager

    MapData -- "LoadProvinces, LoadBiomes, LoadResources, BuildLookupTexture" --> MapManager
    MapData -- "initialize_countries, generate_missing_leaders" --> CountryManager
    MapData -- "load_decisions_from_path" --> DecisionManager
    MapData -- "LoadBuildings, initialize" --> EconomyManager
    MapData -- "load_super_events" --> EventManager
    MapData -- "Initialize" --> FactionManager
    MapData -- "Initialize" --> IdeologyManager
    MapData -- "load_plans_from_path" --> PlansManager
    MapData -- "set_custom_flag_path" --> TroopManager
    MapData -- "load_wars, load_original_territories" --> WarManager

    %% Simulation
    CountryData -- "process_country_day" --> DecisionManager
    CountryData -- "get_country_gdp, get_country_population" --> CountryManager
    CountryData -- "DeployReady, deploy_specific_divisions" --> TroopManager
    CountryData -- "get_enemies_of" --> WarManager
    CountryData -- "get_ideology_name" --> IdeologyManager
    CountryData -- "owns" --> CountryAI
    CountryAI -- "declare_war, call_to_arms, get_enemies_of" --> WarManager
    CountryAI -- "DeployReady, command_move_assigned" --> TroopManager
    CountryAI -- "_ProvinceBuildIndustry, IncreaseWorldTension, GetProvincesBorderingEnemies" --> MapManager
    CountryAI -- "construction_queue" --> EconomyManager
    CountryAI -- "factions, in_faction" --> FactionManager
    SoiStar -- "province_objects" --> MapManager
    TroopData -- "countries" --> CountryManager

    %% World-scene nodes
    CustomRenderer -- "troops, troop_selection, get_flag" --> TroopManager
    CustomRenderer -- "active_battles" --> WarManager
    CustomRenderer -- "province_centers, all_cities" --> MapManager
    TroopSelection -- "command_move_assigned, RemoveTroop, _start_next_leg" --> TroopManager
    TroopSelection -- "GetProvinceAtPos, province_graph" --> MapManager
    TroopSelection -- "play_sfx" --> MusicManager

    %% UI
    GameUI -- "create_faction, invite_faction, kick_faction" --> FactionManager
    GameUI -- "declare_war, call_to_arms, is_at_war" --> WarManager
    GameUI -- "SetMapMode, AnnexCountry, ShowIndustryCountry" --> MapManager
    GameUI -- "make_puppet, release_puppet, set_player_country" --> CountryManager
    GameUI -- "play_music, skip_track, radios" --> MusicManager
    GameUI -- "has_available_decisions" --> DecisionManager
    GameUI -- "has_available_plans" --> PlansManager
    GameUI -- "building_designs, construction_queue" --> EconomyManager
    GameUI -- "save_settings" --> SettingsManager
    DecisionTreeUI -- "start_decision, save_country_decisions, get_country_categories" --> DecisionManager
    ManageCountryUI -- "ReleaseCountry, ReleasePuppet, TransferOwnership" --> MapManager
    ManageCountryUI -- "make_puppet, set_player_country" --> CountryManager
    ManageCountryUI -- "get_element" --> InterpreterManager
    ManageCountryUI -- "plans" --> PlansManager
    PeaceProcessUI -- "TransferOwnership, InstantiateCountryFromProvinces" --> MapManager
    PeaceProcessUI -- "make_puppet" --> CountryManager
    LostTerritoryUI -- "MakeHost, release_puppet, set_player_country" --> CountryManager
    GovernmentUI -- "significantFigures" --> MapManager
    Settings -- "switch_to" --> SceneSwitcher
    Settings -- "apply_settings, save_settings" --> SettingsManager
    Tooltip -- "GetResourceIcon, current_hovered_pid" --> MapManager
    Tooltip -- "construction_queue" --> EconomyManager
    building_designer -- "building_designs, building_functions" --> EconomyManager
    building_designer -- "uses" --> TagMatcher
    ExpressionBox -- "functions, get_param_name" --> InterpreterManager
    custom_event_popup -- "get_element, refresh_buttons" --> InterpreterManager
    MapEditorUI -- "TransferOwnership, SetProvinceColor(s), Occupy/DeoccupyProvince" --> MapManager
    MapEditorUI -- "RenameCountry, make_puppet" --> CountryManager
    CreationPopupUI -- "InstantiateCountryFromProvinces" --> MapManager
    CreationPopupUI -- "add_country, MakeHost" --> CountryManager
    CreationPopupUI -- "create_faction" --> FactionManager
    CameraController -- "MAP_HEIGHT" --> MapManager
    game_clock -- "game_ui, in_peace_process" --> GameState
```

Notes:
- `GameState` is read by almost every script (`current_world`, `game_ui`, `selectingCountry`, ...). Those edges are left out of section 4 to keep the graph readable.
- `Console.is_visible` is checked by `camera_controller`, `troop_selection`, `MapEditorUI`, `KeyboardManager` and `MapManager` to block input while the console is open.
- Autoload names that differ from file names: `SceneSwitcher` = `Managers/SceneManager.gd`, `Console` = the console addon.
