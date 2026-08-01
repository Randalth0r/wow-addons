local addonName, addon = ...

local eventFrame = CreateFrame("Frame")
eventFrame:Hide()
eventFrame:RegisterEvent("ADDON_LOADED")

eventFrame:SetScript("OnEvent", function(self, event, name)
	if event == "ADDON_LOADED" and name == addonName then
		if RosterMailDB == nil then
			RosterMailDB = {}
		end

		print("RosterMail v1.0.0 loaded.")
		self:UnregisterEvent("ADDON_LOADED")
	end
end)
