using Godot;
using System;
using System.Collections.Generic;
using System.Linq;
using System.Text.Json;

public partial class MapManager : Node
{
	public static MapManager Instance { get; private set; }
	const string MAP_DATA_PATH = "res://map_data/MapData.tres";
	public Color SEA_MAIN   = new Color("#7e8e9e"); // Color cant be const WA
	public Color SEA_RASTER = new Color("#697684");

	bool DEBUG_MODE = false;

	// [Signal] public delegate void ProvinceHovered(int province_id, string country_name);
	// [Signal] public delegate void CountryClicked(string country_name);
	// [Signal] public delegate void ProvinceOwnershipChanged(int pid, string old_owner, string new_owner);
	// [Signal] public delegate void CloseSidemenu();
	
	string hoveredCountry		= "Sea";

	Image idMapImage;
	Image stateColorImage;
	ImageTexture stateColorTexture;

	Dictionary<string, Color> ethnicNameToColor						 = new Dictionary<string, Color>();
	Dictionary<string, int[]> countryToProvinces					 = new Dictionary<string, int[]>();
	public Dictionary<string, int[]> countryToOwnedProvinces		 	 = new Dictionary<string, int[]>();
	public Dictionary<string, int[]> countryToOccupiedProvinces 	 = new Dictionary<string, int[]>();
	Dictionary<string, int[]> countryToCities						 	 = new Dictionary<string, int[]>();
	public Dictionary<int, Province> provinceObjects		 	 = new Dictionary<int, Province>();
	Dictionary<string, BiomeData> biomes								 	 = new Dictionary<string, BiomeData>();
	Dictionary<string, ResourceData> resources					 	 = new Dictionary<string, ResourceData>();
	Dictionary<string, RecipeData> recipes							 	 = new Dictionary<string, RecipeData>();
	Dictionary<int, Vector2> provinceCenters						 	 = new Dictionary<int, Vector2>();
	Dictionary<string, int> uniqueRegions			 						 = new Dictionary<string, int>();
	Dictionary<string, int[]> globalClaimsRegistry			 	 = new Dictionary<string, int[]>();
	Dictionary<string, ImportantFigure> significantFigures = new Dictionary<string, ImportantFigure>(); // this has @onready in gdscript
	Dictionary<string, int> allowedPids										 = new Dictionary<string, int>();
	Dictionary<string, Variant>[] allCities								 = [];

	int maxProvinceId;
	int currentHoveredPid	 = -1;
	int lastHoveredPid		 = -1;
	int originalHoverColor = -1;
	float worldTension		 = 0.1f;

	SoiStar provinceGraph = new SoiStar();

	[Export] Texture2D regionTexture;
	[Export] Texture2D cultureTexture;
	[Export] Texture2D populationTexture;
	[Export] Texture2D cityTexture;
	[Export] Texture2D gdpTexture;
	[Export] Texture2D ethnicityTexture;
	[Export] Texture2D claimsTexture;

	[Export] int mapWidth  = 0;
	[Export] int mapHeight = 625;

	// Im not sure if the Value for this is Texture2D or string...
	Dictionary<string, Texture2D> iconCache = new Dictionary<string, Texture2D>();


	public void IncreaseWorldTension(float amount) {
		worldTension = Math.Clamp(worldTension + amount, 0.1f, 1.0f);
	}


	public void LoadBiomes(Godot.Collections.Dictionary[] a_biomeData) {
		biomes.Clear();
		foreach (Godot.Collections.Dictionary biome in a_biomeData) {
			this.biomes[biome["name"].As<string>()] = BiomeData.FromDict(biome);
		}
	}


	public void LoadResources(Godot.Collections.Dictionary[] a_resourceData) {
		resources.Clear();
		foreach (Godot.Collections.Dictionary resource in a_resourceData) {
			this.resources[resource["name"].As<string>()] = ResourceData.FromDict(resource);
			if (this.recipes.Count == 0 && resource.ContainsKey("production_reqs") && resource["production_reqs"].As<Godot.Collections.Array>().Count > 0){
				var recipeDict = new Godot.Collections.Dictionary {
					{"produced_resource", resource["name"]},
					{"resources_required", resource["production_reqs"]}
				};
				this.recipes[resource["name"].As<string>()] = RecipeData.FromDict(recipeDict);
			}
		}
	}

	public void LoadRecipes(Godot.Collections.Array a_recipesData) {
		recipes.Clear();
		foreach (Godot.Collections.Dictionary recipeDict in a_recipesData) {
			var recipe = RecipeData.FromDict(recipeDict);
			if (recipe.producedResource != "") {
				recipes[recipe.producedResource] = recipe;
			}
		}
	}

	private Texture2D FindResourceResource(string sub_path) {
		string full_default = "res://assets/icons/Resources/" + sub_path;
		if (ResourceLoader.Exists(full_default)) {
			return GD.Load<Texture2D>(full_default);
		}
		return null;
	}

	public Texture2D GetResourceIcon(string a_resourceType) {
		string cacheKey = a_resourceType;

		if (iconCache.ContainsKey(cacheKey)) {
			return iconCache[cacheKey];
		}

		if (!resources.ContainsKey(a_resourceType)) {
			Texture2D _iconTexture = FindResourceResource("Droplet.svg");
			iconCache[cacheKey] = _iconTexture;
			return _iconTexture;
		}
		
		Texture2D iconTexture = FindResourceResource(resources[a_resourceType].icon + ".svg");
		
		if (iconTexture == null) {
			iconTexture = FindResourceResource("Droplet.svg");
		}
		
		iconCache[cacheKey] = iconTexture;
		return iconTexture;
	}

	private void _ClearInternalData() {
		allCities = [];
		uniqueRegions.Clear();
		provinceObjects.Clear();
		countryToProvinces.Clear();
		countryToOwnedProvinces.Clear();
		countryToOccupiedProvinces.Clear();
		allowedPids.Clear();
		provinceCenters.Clear();
		// Clear graph and global registry
		globalClaimsRegistry.Clear();
		// Re-init significant figures if needed, but for now just clear
		significantFigures.Clear();
		// Reset state variables
		maxProvinceId = 0;
		currentHoveredPid = -1;
		lastHoveredPid = -1;
		hoveredCountry = "Sea";
	}

	public void Initialize(Texture2D a_map, Dictionary<string, Godot.Collections.Dictionary<string, Variant>> a_provinceData, float[] a_progress) {
		_ClearInternalData();
		
		int mapWidth = a_map.GetWidth();
		int mapHeight = a_map.GetHeight();
		int nextId = 2;
		float inc = 0.1f / (mapWidth * mapHeight);

		Image idMapImage = Image.CreateEmpty(mapWidth, mapHeight, false, Image.Format.Rgb8);
		Image mapImage = a_map.GetImage();

		GetNode<Sprite2D>("../Main/MapContainer/CultureSprite").Texture = a_map;

		for (int i = 0; i < mapWidth * mapHeight; i++) {
			// print("%d/%d -> %f" % [i, blink, a_progress[0]])
			a_progress[0] += inc;
			int x = i % mapWidth;

			// @warning_ignore("integer_division")
			int y = i / mapHeight;
			Color rColor = mapImage.GetPixel(x, y);
			string index = (rColor.ToRgba32() >> 8).ToString(); // I hate alpha.

			// Check for Borders/Grid (ID 1)
			if (rColor == Colors.Black) {
				idMapImage.SetPixel(x, y, Colors.White);
				continue;
			}

			// If this is a new region (Unique Sea Zone or Land Province)
			if (!uniqueRegions.ContainsKey(index)) {
				uniqueRegions[index] = nextId;
				var province_dict = a_provinceData[index];
				var province = Province.FromDict(province_dict);
				province.id = nextId;
				provinceObjects[nextId] = province;
				nextId += 1;
			}
			// Write the unique ID to your idMapImage
			idMapImage.SetPixel(x, y, new Color((uint) ((uniqueRegions[index] << 8) | 0x000000FF)));
		}

		
		maxProvinceId = nextId - 1;
		BuildLookupTexture();
		a_progress[0] += 0.015f;
		_CalculateProvinceCentroids();
		a_progress[0] += 0.01f;
		
		// Pass 2: Load troops now that centroids (positions) are definitely known
		foreach (string index in a_provinceData.Keys) {
			if (uniqueRegions.ContainsKey(index)) {
				var p_dict = a_provinceData[index];
				if (p_dict.ContainsKey("troops")) {
					// TroopManager.Instance.LoadTroopsForProvince(uniqueRegions[index], p_dict["troops"]);
				}
			}
		}

		a_progress[0] += 0.025f;
		_BuildCountryToProvinces();
		a_progress[0] += 0.025f;
		// _BuildAdjacencyList(a_progress);
		_BuildGlobalRegistry();
		RecalculateResourcePrices();
		a_progress[0] += 0.025f;

	}

	public void SaveMapData() {
		MapData mapData = new MapData();
		// these have a .duplicate method in the gdscript i cant seem to find the c# equivalent
		mapData.provinceCenters		 = this.provinceCenters;
		mapData.countryToProvinces = this.countryToProvinces;
		mapData.maxProvinceId			 = this.maxProvinceId;
		mapData.idMapImage				 = this.idMapImage;
		mapData.provinceObjects		 = this.provinceObjects;
		ResourceSaver.Save(mapData, MAP_DATA_PATH);
	}

	// public Dictionary<string, Godot.Collections.Dictionary<string, Variant>> SaveCountryData() {
	// 	Dictionary<string, Godot.Collections.Dictionary<string, Variant>> provinces = new();
	// 	foreach (string index in uniqueRegions.Keys) {
	// 		int nextId  = uniqueRegions[index];
	// 		Province province = provinceObjects[nextId];
	// 		var troops = TroopManager.Instance.GetSerializedTroopsForProvince();
	// 		provinces[index] = province.ToDict();
	// 	}
	// 	return provinces;
	// } 

	public Godot.Collections.Dictionary<string, Variant>[] SaveResourceData() {
		return resources.Values.Select(resource => resource.ToDict()).ToArray();
	}

	public Godot.Collections.Dictionary<string, Variant>[] SaveRecipeData() {
		return recipes.Values.Select(recipe => recipe.ToDict()).ToArray();
	}

	public Godot.Collections.Dictionary<string, Variant>[] SaveBiomeData() {
		return biomes.Values.Select(biome => biome.ToDict()).ToArray();
	}

	// public void ExportScenarioData(string path) {
	// 	Godot.Collections.Dictionary<string, Variant>	export = new Godot.Collections.Dictionary<string, Variant>{ 
	// 			{"clock", GameState.Instance.currentWorld.clock.ToDict()},
	// 			{"resources", SaveResourceData()},
	// 			{"recipes", SaveRecipeData()},
	// 			{"biomes", SaveBiomeData()},
	// 			{"provinces", SaveCountryData()},
	// 			{"ideologies", IdeologyManager.Instance.ideologies},
	// 			{"factions", FactionManager.Instance.SaveFactions()},
	// 			{"significant_figures", significantFigures.Values.Select(fig => fig.ToDict()).ToArray()},
	// 	};
	// 	File.WriteAllText(path, JsonSerializer.Serialize(export));
	//
	//
	//
	//
	//
	//
	// }

	public void ShowCountriesMap() {
		stateColorImage.SetPixel(0, 0, SEA_MAIN);
		stateColorImage.SetPixel(1, 0, new Color(0, 0, 0, 1));
		foreach (var pid in provinceObjects.Keys) {
			if (pid <= 1) {
				continue;
			}
			stateColorImage.SetPixel(
					pid,
					0,
					GetCountryDisplayColor(
						provinceObjects[pid].country
					)
			);
			stateColorImage.SetPixel(
					pid,
					1,
					GetCountryDisplayColor(
						provinceObjects[pid].GetFunctionalOwner()
					)
			);
		}
		stateColorTexture.Update(stateColorImage);
		KeyboardManager.Instance.currentView
	}
	public void BuildLookupTexture() {}
	public void _CalculateProvinceCentroids() {}
	public void _BuildAdjacencyList() {}
	public void _BuildGlobalRegistry() {}
	public void _BuildCountryToProvinces() {}
	public void RecalculateResourcePrices() {}



	public override void _Ready() {
		Instance = this;
	}
}
