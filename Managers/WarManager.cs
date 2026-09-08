using Godot;
using System.Collections.Generic;

public partial class WarManager : Node {
	public static WarManager Instance { get; private set; }

	// --- Constants ---
	public const float BATTLE_TICK = 1.0f;
	public const float MORALE_DECAY_RATE = 0.02f; // Adjusted for better flow
	public const float MORALE_BOOST_DEFENDER = 10.0f;

	public override void _Ready() { Instance = this; }

	Dictionary<string, string[]> wars;
	Battle[] activeBattles;
	// Blablabla buncha shit here
	
	public string[] GetEnemiesOf(string a_countryName) {
		string[] enemies = [];
		CountryData countryData CountryManager.Instance.countries[a_countryName];

		if (!(countryData && wars.ContainsKey(countryData))) {

		}
	}
}
