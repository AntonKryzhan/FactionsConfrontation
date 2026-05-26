require "NPCClient/NPCBaseCaptureUIBridge"
require "NPCCore/NPCLegacyGlobalsBridge"

NPCBaseCaptureUIBridge = NPCLegacyGlobalsBridge.InstallAlias("BaseCaptureUI", NPCBaseCaptureUIBridge, "NPCBaseCaptureUI")
NPCBaseCaptureUI = NPCBaseCaptureUIBridge

NPCLegacyGlobalsBridge.InstallAlias("BaseCapturePanel", NPCBaseCapturePanelBridge, "NPCBaseCapturePanel")
NPCBaseCapturePanel = NPCBaseCapturePanelBridge
