require "NPCClient/NPCPostClient"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCPost = NPCLegacyGlobalsBridge.InstallAlias("Post", NPCPost, "NPCPost")

NPCPost.GuardToggle = NPCPostClient.GuardToggle
NPCPost.Update = NPCPostClient.Update
NPCPost.At = NPCPostClient.At
NPCPost.GetAll = NPCPostClient.GetAll
NPCPost.GetInRadius = NPCPostClient.GetInRadius
NPCPost.GetClosestFree = NPCPostClient.GetClosestFree
NPCPost.Get = NPCPostClient.Get
NPCPost.Render = NPCPostClient.Render
NPCPost.OnKeyPressed = NPCPostClient.OnKeyPressed
NPCPost.Install = NPCPostClient.Install

NPCPost.Install()
