-- NPCNamesBridge.lua
-- Neutral shared backend for NPC name generation.

require "NPCCore/NPCUtilityCore"

NPCNamesBridge = NPCNamesBridge or {}

NPCNamesBridge.GenerateName = function(female)
    local firstname
    if female then
        firstname = NPCUtilityCore.Choice(NPCNamesBridge.Female.FirstNames)
    else
        firstname = NPCUtilityCore.Choice(NPCNamesBridge.Male.FirstNames)
    end
    local surname = NPCUtilityCore.Choice(NPCNamesBridge.Surnames)

    return firstname .. " " .. surname
end

NPCNamesBridge.Male = NPCNamesBridge.Male or {}
NPCNamesBridge.Male.FirstNames = NPCNamesBridge.Male.FirstNames or {}

local maleFirstNames = {
    "Abel", "Amos", "Arlen", "Arlo", "Barrett", "Beck", "Bennett", "Boone", "Caleb", "Calvin",
    "Carson", "Clay", "Clyde", "Cole", "Conrad", "Dalton", "Dane", "Darius", "Dean", "Drew",
    "Ellis", "Emmett", "Everett", "Felix", "Finn", "Gareth", "Gideon", "Grant", "Griffin", "Harlan",
    "Hayes", "Heath", "Ira", "Jasper", "Jesse", "Joel", "Jonah", "Judah", "Kent", "Landon",
    "Lane", "Lawson", "Leander", "Malcolm", "Merrick", "Micah", "Miles", "Nolan", "Orson", "Otis",
    "Pierce", "Quentin", "Reed", "Rhett", "Rowan", "Sawyer", "Silas", "Tate", "Tobias", "Wade",
    "Walker", "Warren", "Wesley", "Wylder"
}

for _, name in ipairs(maleFirstNames) do
    table.insert(NPCNamesBridge.Male.FirstNames, name)
end

NPCNamesBridge.Female = NPCNamesBridge.Female or {}
NPCNamesBridge.Female.FirstNames = NPCNamesBridge.Female.FirstNames or {}

local femaleFirstNames = {
    "Ada", "Adeline", "Alma", "Anika", "Audra", "Bea", "Bonnie", "Briar", "Calla", "Cassidy",
    "Celia", "Clara", "Cora", "Dahlia", "Della", "Edie", "Elaine", "Eliza", "Elsie", "Ember",
    "Estelle", "Etta", "Faye", "Flora", "Greta", "Gwen", "Hattie", "Iris", "Ivy", "Jessa",
    "Jolene", "Josie", "June", "Keira", "Lena", "Lilah", "Liv", "Loretta", "Mae", "Mara",
    "Maren", "Mavis", "Mina", "Mira", "Nell", "Opal", "Paige", "Pearl", "Quinn", "Raina",
    "Reese", "Rhea", "Rory", "Sadie", "Selah", "Sienna", "Talia", "Vera", "Willa", "Winona",
    "Yara", "Zadie", "Zara", "Zora"
}

for _, name in ipairs(femaleFirstNames) do
    table.insert(NPCNamesBridge.Female.FirstNames, name)
end

NPCNamesBridge.Surnames = NPCNamesBridge.Surnames or {}

local surnames = {
    "Abernathy", "Alden", "Ashford", "Atwood", "Baines", "Barlow", "Beckett", "Bellamy", "Blackwell", "Blake",
    "Blythe", "Braddock", "Briar", "Briggs", "Brock", "Burke", "Callahan", "Carver", "Cassell", "Chandler",
    "Clayborne", "Cobb", "Colter", "Connelly", "Crowder", "Daley", "Davenport", "Delaney", "Denton", "Drake",
    "Durham", "Easton", "Eldridge", "Ellery", "Fairchild", "Farrow", "Fenwick", "Fletcher", "Galloway", "Gentry",
    "Granger", "Graves", "Hale", "Harding", "Hargrove", "Harper", "Hawthorne", "Haywood", "Hollis", "Huxley",
    "Ingram", "Keller", "Kendrick", "Kincaid", "Langford", "Lark", "Lawton", "Locke", "Maddox", "Marlow",
    "Mercer", "Merritt", "Milner", "Monroe", "Nash", "Nolan", "North", "Oakley", "Parker", "Pierce",
    "Prescott", "Quarry", "Ralston", "Redford", "Reeve", "Ridley", "Rook", "Roscoe", "Rowe", "Ryland",
    "Sable", "Sawyer", "Sloane", "Sterling", "Stone", "Stroud", "Sutter", "Tanner", "Thorne", "Tolliver",
    "Vance", "Vaughn", "Walker", "Ward", "Wayland", "Whitlock", "Wilder", "Winslow", "Wren", "Yates",
    "Keaton", "Lyndon", "Morrow", "Pike", "Ransom", "Vale", "Westbrook", "Whitaker", "Willow", "York"
}

for _, name in ipairs(surnames) do
    table.insert(NPCNamesBridge.Surnames, name)
end
