local UnLuaSmokeTestActor = UnLua.Class()

function UnLuaSmokeTestActor:RunLuaSmokeTest()
    print("UnLua smoke test: Lua callback executed")
    return true
end

return UnLuaSmokeTestActor
