if game:GetService("RunService"):IsServer() then
	return require(script.ReplicaService)
    
else
    local ReplicaService = script:FindFirstChild("ReplicaService")
	if ReplicaService then
		ReplicaService:Destroy()
	end
	return require(script.ReplicaController)
end