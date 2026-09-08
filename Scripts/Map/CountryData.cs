using Godot;
using System;
using System.Collections.Generic;

public partial class CountryData : Resource {
	// // Called when the node enters the scene tree for the first time.
	// public override void _Ready()
	// {
	// }
	//
	// // Called every frame. 'delta' is the elapsed time since the previous frame.
	// public override void _Process(double delta)
	// {
	// }
	float economyLawPenalty = 0.0f;
	Dictionary<string, int> armyCompositionCache = new Dictionary<string, int>{
		{ "infantry", 0 },
		{ "tank", 0 },
		{ "artillery", 0 },
	};

	const float BASE_AMRY_COST = 20;
	const float MANPOWER_RECOVERY_PER_YEAR = 0.1f;
	const float MANPOWER_RECOVERY_PER_DAY = MANPOWER_RECOVERY_PER_YEAR/365;
	float militarySizeRatio = 0.005f;

	// region --- Properties ---
	public string countryName;
	string displayName;
	string capital;
	Color countryColor;
	bool isPlayer = false;
	bool isPuppet = false;
	bool isExiled = false;
	CountryAI AIController = null;

	public Dictionary<string, int> relations = new();

	float factoryPortDailyCost = 0.2f; // Is this even used now

	// Economy
	float money					= 0;
	float gdp						= 0;
	float income				= 0;
	float factoryAmount = 0;
	float factoryIncome = 100;

	float hourlyMoneyIncome = 0.0f;
	public Dictionary<string, int> stockpile					= new Dictionary<string, int>();
	Dictionary<string, int> tradeSettings			= new Dictionary<string, int>();
	Dictionary<string, int> factoryAllocation = new Dictionary<string, int>();
	Dictionary<string, int> stockpileChange		= new Dictionary<string, int>();
	float divCostMod = 1.0f;

	public delegate void IdeologyChanged();

	// Politics
	Dictionary<string, IdeologyDriftTarget> driftTargets = new();
	float politicalPower		 = 5000.0f;
	float base_daily_pp_gain = 0.04f;
	float daily_pp_gain			 = 0.04f;
	float base_stability		 = 0.5f;
	float stability					 = 0.5f;

	// Military State
	int armyLevel = 1;

	public float GetMaxMorale() {
		return 60.0f + (stability * 40.0f) + armyLevel * 5f * (money < 0 ? 0.5f : 1.0f);
	}




}
