commands.RunString("mount csgo")
commands.RunString("map gm_old_flatgrass")

local ent = entities.CreateEntity("visual")
ent:SetModelPath("models/dragon.obj")
ent:SetPosition(Vec3(0,0,0))

local mat = render.CreateMaterial("model")
mat:SetTranslucent(true)
mat:SetColor(Color(1,1,1,0.1))
mat:SetAlbedoTexture(render.GetWhiteTexture())

ent:SetMaterialOverride(mat)