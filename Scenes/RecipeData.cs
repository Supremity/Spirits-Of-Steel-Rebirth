using Godot;
using System;

[GlobalClass] public partial class RecipeData : Node
{
	[Export] public string resource_produced;
	[Export] public string[] resources_required;

	public static RecipeData FromDict(Godot.Collections.Dictionary<string, Godot.Variant> a_data) {
		RecipeData recipe = new RecipeData();
		recipe.resource_produced  = (string)a_data["resource_produced"];  //, out "");
		recipe.resources_required = (string[])a_data["resources_required"];//, out new string[] );
		return recipe;
	}

	public Godot.Collections.Dictionary<string, Godot.Variant> ToDict() {
		return new Godot.Collections.Dictionary<string, Godot.Variant>(){
			{"resource_produced", resource_produced},
			{"resources_required", resources_required},
		};
	}
}
