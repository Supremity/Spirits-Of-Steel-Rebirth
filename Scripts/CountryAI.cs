using Godot;
using System;
using System.Linq;
using System.Collections.Generic;
using GDictionary = Godot.Collections.Dictionary<string, Godot.Variant>;


public partial class CountryAI : Node {
	private delegate float ScoreDelegate();
	private delegate bool  ExecuteDelegate();

	struct Action(float a_score, ExecuteDelegate a_executeDelegate) {
		public float	         score  = a_score;
		public ExecuteDelegate action = a_executeDelegate;
	}

	struct Personality(Random random, float extremism) {
		public Random random                      = random;
		public float  economyTrade                = (float) random.NextDouble();
		public float  economyIndustryAmountFactor = 2.0f * (float) random.NextDouble();
		public float  economyIndustry             = (float) random.NextDouble();
		public float  economySurplus              = (float) random.NextDouble();
		public float  militaryTrainingFactor      = (float) random.NextDouble();
		public float  militaryMaxEconomicRatio    = 0.7f;
		public float  warProbabilityBase          = (1 + extremism) * ((float) random.NextDouble());
		public float  warProbabilityTensionFactor = (2.0f + extremism * 5.0f) * (float) random.NextDouble();
		public float  warScoreStrength            = 2.0f * (float) random.NextDouble();
		public float  warScoreMoneyFactor         = 0.00001f * (float) random.NextDouble();
		public float  warScoreMaxCities           = 3.0f * (float) random.NextDouble();
		public float  warScoreCities              = (float) random.NextDouble();
		public float  warCombatAttackWeight       = 5.0f * (float) random.NextDouble();
		public float  warCombatDefenseWeight      = 5.0f * (float) random.NextDouble();
		public float  warCombatCityBonus          = 100.0f * (float) random.NextDouble();
		public float  warMinStrengthRatio         = 1.1f + (float) random.NextDouble();
		public float  warMinEconomy               = 10000f * (float) random.NextDouble();
		public float  aggression                  = (extremism * 2.0f) + (AI_CHAOS * (float) random.NextDouble());
	}

	// --- TUNING ---
	const int   TICK_RATE_PEACE  = 12;  // Slower thinking in peace time
	const int   TICK_RATE_WAR    = 2;  // Think fast during war
	const float SATURATION_IDEAL = 1.0f;  // Target: At least 1 division equivalent per province
	const float SATURATION_MAX   = 4.0f;  // Avoid overstacking; redistribute if exceeding
	const float DISTANCE_PENALTY = 0.1f;  // Reduce score per unit distance to discourage far moves
	// NOTE(soi): why tf was this 1?!?!??
	const int MIN_DIVISIONS_PER_SPLIT = 10;  // Smallest split size
	const int MIN_TOTAL_POWER_FOR_WAR = 5000; // Minimum power/divisions to even think about war
	const int MAX_SPLITS_PER_TROOP    = 5;  // Limit splits to prevent micro-management overhead

	// --- AI DIPLOMACY/WAR LOGIC---
	const int   DECLARE_WAR_COOLDOWN_FRAMES    = 600;
	const int	  MAX_PARALLEL_WARS              = 2;
	const float WAR_SCORE_THRESHOLD            = 0.6f;
	const int	  MAX_WAR_DECLARATIONS_PER_TICK  = 1;
	const float AI_CHAOS                       = 0.9f;
	const int		MAX_COMBINED_WAR_MEMBERS       = 8; // Prevent world-war scale escalations }
	const int   EMERGENCY_DEPLOYMENT_THRESHOLD = 5; // If at war and fewer than this, panic deploy
	const int	  WAR_DEPLOY                     = 30;
	const int	  PEACE_DEPLOY                   = 10;

	CountryData country;

	Personality personality;

	int _lastDeclareFrame = -999999;
	int[] _neighborCache = [];
	bool _neighborsDirty = true;

	public CountryAI(CountryData _country) {
		this.country		= _country;
		float extremism = _GetExtremism();

		// Dictionary<string, float> personality = new Dictionary<string, float>{
		// 	{"economy_trade",									 (float) rand.NextDouble()},
		// 	{"economy_industry_amount_factor", 2.0f * (float) rand.NextDouble()},
		// 	{"economy_industry",							 (float) rand.NextDouble()},
		// 	{"economy_surplus",								 (float) rand.NextDouble()},
		// 	{"military_training_factor",			 (float) rand.NextDouble()},
		// 	{"military_max_economic_ratio",		 0.7f},
		// 	{"war_probability_base",					 (1 + extremism) * ((float) rand.NextDouble())},
		// 	{"war_probability_tension_factor", (2.0f + extremism * 5.0f) * (float) rand.NextDouble()},
		// 	{"war_score_strength",						 2.0f * (float) rand.NextDouble()},
		// 	{"war_score_money_factor",				 0.00001f * (float) rand.NextDouble()},
		// 	{"war_score_max_cities",					 3.0f * (float) rand.NextDouble()},
		// 	{"war_score_cities",							 (float) rand.NextDouble()},
		// 	{"war_combat_attack_weight",			 5.0f * (float) rand.NextDouble()},
		// 	{"war_combat_defense_weight",			 5.0f * (float) rand.NextDouble()},
		// 	{"war_combat_city_bonus",					 100.0f * (float) rand.NextDouble()},
		// 	{"war_min_strength_ratio",				 1.1f + (float) rand.NextDouble()},
		// 	{"war_min_economy",								 10000f * (float) rand.NextDouble()},
		// 	{"aggresion",											 (extremism * 2.0f) + (AI_CHAOS * (float) rand.NextDouble())},
		// };

		if (MapManager.Instance.IsInsideTree()) {
			MapManager.Instance.ProvinceOwnershipChanged += _OnProvinceOwnershipChanged;
		}
	}
	
	public void _OnProvinceOwnershipChanged(int _pID, string _OldOwner, string _newOwner) {
		this._neighborsDirty = true;
	}

	public void ThinkHour() {
		if (Engine.GetFramesDrawn() % (WarManager.Instance.GetEnemiesOf(country.country_name) ? TICK_RATE_WAR : TICK_RATE_PEACE) != 0) {
			return;
		}
		_ExecuteBest(
			[
				new Action(_ScoreFrontline(), _ExecuteFrontline),
			]
		);
	}
	

	public void ThinkDay() {
		_OptimizeEconomy();
		_ExecuteBest(
			[
				new Action(_ScoreFactory(), _ExecuteFactory),
				new Action(_ScoreTrain(), _ExecuteTrain),
				new Action(_ScoreWar(), _ExecuteWar),
				new Action(_ScoreCallToArms(), _ExecuteCallToArms),
			]
		);
	}

	private void _ExecuteBest(Action[] actions) {
		if (actions.Length == 0) {
			return;
		}
		actions = [.. actions.OrderBy(x => x.score)];

		foreach (Action action in actions) {
			if (action.score < 0 || action.action()) {
				break;
			}
		}
	}

	private float _ScoreFactory() {
		return (country.money < 1000) ? 0 : Math.Max(0.1f, 1f - (country.factoriesAmount * personality.economyIndustryAmountFactor) * personality.economyIndustry);
	}

	private float _ScoreTrain() {
		return (country.money < 1000 || country.manpower < 10_000) ? 0 : personality.militaryTrainingFactor;
	}

	private float _ScoreWar() {
		return (country.isPuppet) ? 0 : MapManager.Instance.worldTension * personality.aggresion;
	}

	private float _ScoreFrontline() {
		if (!WarManager.Instance.GetEnemiesOf(country.countryName).Length == 0) {
			int deployedCount = 0;
			foreach (TroopData troop in Troop.Instance.GetTroopsForCountry(country.countryName)) {
				deployedCount += troop.storedDivisions.Length;
				if (deployedCount < EMERGENCY_DEPLOYMENT_THRESHOLD) {
					return 10f;
				}
				return 1f;
			}
		}
	}

	private bool _ExecuteFactory() {
		if (!MapManager.Instance.countryToOwnedProvinces.ContainsKey(country.countryName)) {return false;}
		int[] provincesToDo = MapManager.Instance.countryToOwnedProvinces[country.countryName]
		.Select(
			pID => 
			 MapManager.Instance.provinceObjects[pID].buildings.Length < 4
			 && !EconomyManager.Instance.Contains(pID)
		);

		if (provincesToDo.Length == 0) {return false;}
		MapManager._ProvinceBuildIndustry(provincesToDo[personality.random.Next(provincesToDo.Length)]);
	}

	private bool _ExecuteTrain() {
		bool trainedAny = false;
		foreach (KeyValuePair<string, DivisionData.Template> type in DivisionData.TEMPLATES) {
			int maxAffordable = Math.Min(country.money / type.Value.cost, country.manpower / type.Value.manpower);

			int maxByEquip;
				if (country.stockpile.TryGetValue(type.Value.requiredResource, out int o_resourceCount)) {
						maxByEquip = o_resourceCount / type.Value.requiredResourceAmount;
				} else {
						maxByEquip = 0;
				}

			maxAffordable = Math.Max(maxAffordable, maxByEquip);

			// AI hallucination?
			// if (maxAffordable < 1) {
			// 	continue;
			// }

			int limit =  PEACE_DEPLOY + (WarManager.Instance.GetEnemiesOf(country.countryName).Length * WAR_DEPLOY);
			int trainCount = Math.Clamp(maxAffordable, 1, limit);

			if (country.TrainTroops(trainCount, type.Key)) {
			  trainedAny = true;
				break;
			}
		}
		return trainedAny;
	}

	private bool _ExecuteWar() {
		int frameNow = Engine.GetFramesDrawn();
		if (
			(MapManager.worldTension < (0.15 - _GetExtremism() * 0.1) && personality.aggression < 2.5)
			|| (personality.random.NextDouble() > (personality.warProbabilityBase + MapManager.Instance.worldTension * persY.warProbabilityTensionFactor))
			|| ((frameNow - _lastDeclareFrame) < DECLARE_WAR_COOLDOWN_FRAMES)
			|| (WarManager.Instance.GetEnemiesOf(country.countryName).Length >= MAX_PARALLEL_WARS)
			|| (country.money < personality.warMinEconomy)
		) {
			return false;
		}

		Dictionary<string, bool> ourFactions = new Dictionary<string, bool>();
		foreach (string faction in country.factions) {
		  ourFactions.Add(faction, true);
		}
		string[] candidates = [];
		foreach (String enemy in _GetNeighborCountries()) {
			CountryData enemyData = CountryManager.countries.TryGetValue(enemy, out CountryData o_enemyData) ? o_enemyData : null;
			if (enemyData == null) {
				continue;
			}
			if (country.GetRelationWith(enemy) > 20 && personality.aggression < 2.0) {
				continue;
			}
			foreach (string faction in enemyData.factions) {
				if (ourFactions.ContainsKey(faction)) {
				continue;
				}
			}
			candidates.Append(enemy);
		} 

		if (_EstimateCountryStrength(country.countryName, true) < MIN_TOTAL_POWER_FOR_WAR) {
			return false;
		}
		if (candidates.Length == 0) {
			return false;
		}
		float  bestScore  = float.MinValue;
		string bestTarget = "";

		foreach (string targetName in candidates) {
		  CountryData targetData = CountryManager.Instance.countries[targetName];
			if (
					FactionManager.Instance.InFaction(country, targetData)
					|| WarManager.Instance.IsAtWarNames(coountry.countryName, targetName)
					|| country.puppets.Contains(targetName)
				 ) {
				continue;
			}
			
		}
	}
}
