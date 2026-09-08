using System.Collections.Generic;
using Godot;
using GDictionary = Godot.Collections.Dictionary<string, Godot.Variant>;

public partial class DivisionData : Resource {

    public struct Template(
            float  hp,
            int    manpower,
            int    cost,
            int    days,
            float  attack,
            float  defense,
            float  speed,
            string requiredResource,
            int    requiredResourceAmount
        ) {
        public float  hp                       = hp;
        public int    manpower                 = manpower;
        public int    cost                     = cost;
        public int    days                     = days;
        public float  attack                   = attack;
        public float  defense                  = defense;
        public float  speed                    = speed;
        public string requiredResource         = requiredResource;
        public int    requiredResourceAmount   = requiredResourceAmount;
    }

    public static readonly Dictionary<string, Template> TEMPLATES = new Dictionary<string, Template> 
    {
        {
            "Infantry",
            new Template{
                hp                       = 100.0f,
                manpower                 = 10000,
                cost                     = 500,
                days                     = 9,
                attack                   = 1,
                defense                  = 1,
                speed                    = 1.0f,
                required_resource        = "Infantry_equipment",
                required_resource_amount = 100,
            }
        }, {
            "tank",
            new Template{
                hp                       = 280.0f,
                manpower                 = 20000,
                cost                     = 10000,
                days                     = 30,
                attack                   = 5,
                defense                  = 7,
                speed                    = 2.5f,
                required_resource        = "Tank_equipment",
                required_resource_amount = 50,
            }
        }, {
            "artillery",
            new Template{
                hp                       = 50.0f,
                manpower                 = 1000,
                cost                     = 10000,
                days                     = 15,
                attack                   = 5,
                defense                  = 0.3f,
                speed                    = 0.8f,
                required_resource        = "Artillery_equipment",
                required_resource_amount = 30,
            }
        }
    };

    [Export] public string name = "Infantry Division";
    [Export] string type = "infantry";
    [Export] public float HP = 100f;
    [Export] float maxHP = 100f;
    [Export] float experience = 0f;
    [Export] float maxManpower = 10000f;
    [Export] float manpowerPerHP = 100f;

    public static DivisionData FromDict(GDictionary a_dict) {
        DivisionData division = new()
        {
            name	= a_dict["name"].AsString(),
            type	= a_dict.TryGetValue("type", out Variant o_type) ? o_type.AsString() : "infantry",
            HP		= a_dict.TryGetValue("hp", out Variant o_HP) ? (float)o_HP : 100,
            maxHP       = a_dict.TryGetValue("max_hp", out Variant o_maxHP) ? (float)o_maxHP : 100,
            experience	= a_dict.TryGetValue("experience", out Variant o_experience) ? (float)o_experience : 0,
            maxManpower = a_dict.TryGetValue("max_manpower", out Variant o_maxManpower) ? (float)o_maxManpower : 10000
        };
        division.manpowerPerHP = division.maxManpower/division.maxHP;

        return division;
    }

    public GDictionary ToDict() {
        return new GDictionary {
            {"name", name},
            {"type", type},
            {"hp", HP},
            {"max_hp", maxHP},
            {"experience", experience},
            {"max_manpower", maxManpower},
        };
    }

    public float GetAttackPower() {
        return (TEMPLATES.TryGetValue(type, out Template o_template) ? o_template : TEMPLATES["infantry"]).attack * (1.0f + (experience * 0.5f));
    }

    public float GetDefensePower() {
        return (TEMPLATES.TryGetValue(type, out Template o_template) ? o_template : TEMPLATES["infantry"]).defense * (1.0f + (experience * 0.5f));
    }
}
