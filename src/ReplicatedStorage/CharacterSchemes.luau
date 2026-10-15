-- Shared immutable palette; only CharacterAppearanceServer owns player choices.
local function scheme(name, body, lips, feet, stalks, rings)
    return {Name=name,body=Color3.fromHex(body),lips=Color3.fromHex(lips),feet=Color3.fromHex(feet),stalks=Color3.fromHex(stalks),rings=Color3.fromHex(rings)}
end
return {
    scheme('Sickly green','91A866','AE6E82','566540','A9BC7D','735763'),
    scheme('Bruise purple','8C75A8','CA899E','514565','AE98C8','71507B'),
    scheme('Corpse blue','97C2CD','A77E9D','536D83','B7DCE0','677DAD'),
    scheme('Rust orange','C57D4E','DEA08A','744B3A','D8A16B','986055'),
    scheme('Bone white','DAD6BF','B18B8E','8F8E7C','ECE5CE','9A8C89'),
    scheme('Tar black','373942','8C657F','20222A','626573','665575'),
    scheme('Flesh pink','D8A19C','AC586E','906E78','E5BCB0','B76F83'),
    scheme('Mustard yellow','C3AA4E','AB766F','77632E','DAC778','8D6952'),
}

