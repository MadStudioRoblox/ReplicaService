--[[
[Game]

-[TestWriteLib]---------------------------------------
	(AbstractExample)
	
--]]

local TestWriteLib = {
	
	-- Write libs allow you to create actions that will be performed both
	--   on server and client-side with the benefit of the server only having
	--   to tell the client which function to run; Additionally, the client
	--   can listen to specific functions being called by the server to also
	--   address bulk data changes as if it was a single change.
	
	SetMessage = function(replica, message_name, text)
		replica:SetValue({"Messages", message_name}, text)
	end,
	
	SetAllMessages = function(replica, text)
		for message_name in pairs(replica.Data.Messages) do
			replica:SetValue({"Messages", message_name}, text)
		end
	end,
	
	DestroyAllMessages = function(replica)
		for message_name in pairs(replica.Data.Messages) do
			replica:SetValue({"Messages", message_name}, nil)
		end
	end,
	
}

return TestWriteLib