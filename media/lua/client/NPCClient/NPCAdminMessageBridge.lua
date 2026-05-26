NPCAdminMessageBridge = NPCAdminMessageBridge or {}

function NPCAdminMessageBridge.AdminMessage(text, x, y, z)
	-- print (text)
end

function NPCAdminMessageBridge.Install()
	if Events and Events.OnAdminMessage and Events.OnAdminMessage.Add then
		Events.OnAdminMessage.Add(NPCAdminMessageBridge.AdminMessage)
	end
end
