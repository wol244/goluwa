local serializer = ...
local von = require("von")
serializer.AddLibrary("von", function(...) return von.serialize(...) end, function(...) return von.deserialize(...) end, von)
