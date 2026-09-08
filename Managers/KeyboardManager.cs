using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

public partial class KeyboardManager : Node {
	enum MapView {
		COUNTRIES,
		POPULATION,
		INFRASTRUCTURE,
		GDP,
		ETHNICITY,
		FACTION,
		RESOURCES,
		BIOMES
	}
	CanvasLayer settings;
	MapView currentView = MapView.COUNTRIES;
	// [Signal] public delegate void ToggleMenu();
	private bool _debounce = false;

	public override void _Ready() {
    settings = (CanvasLayer) GetNode("/root/Main/SettingsLayer");
	}

	public override void _Process() {
		if (Console.Instance.isVisible()) {
			return;
		}
		if (Input.IsActionJustPressed("deselect_troops")) {
			settings.Visible != settings.Visible;
			switch (SceneSwitcher.Instance.currentType) {
			    SceneSwitcher.Instance.Type.WORLD:
						if (!TroopManager.Instance.troopSelection.selectedTroops.Length == 0) {
						    TroopManager.Instance.troopSelection.DeselectAll();
						} else if (GameState.Instance.gameUI.isOpen) {
							
						    
						}
			    default:
			}
		}
	}

}
