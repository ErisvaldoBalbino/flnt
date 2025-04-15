local httpService = game:GetService("HttpService")

local SaveManager = {} do
	SaveManager.Folder = "FluentSettings"
	SaveManager.Ignore = {}
	SaveManager.Parser = {
		Toggle = {
			Save = function(idx, object)
				return { type = "Toggle", idx = idx, value = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Slider = {
			Save = function(idx, object)
				return { type = "Slider", idx = idx, value = tostring(object.Value) }
			end,
			Load = function(idx, data)
				local numValue = tonumber(data.value)
				if SaveManager.Options[idx] then
					SaveManager.Options[idx]:SetValue(numValue ~= nil and numValue or data.value)
				end
			end,
		},
		Dropdown = {
			Save = function(idx, object)
				return { type = "Dropdown", idx = idx, value = object.Value, mutli = object.Multi }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then
					SaveManager.Options[idx]:SetValue(data.value)
				end
			end,
		},
		Colorpicker = {
			Save = function(idx, object)
				return { type = "Colorpicker", idx = idx, value = object.Value:ToHex(), transparency = object.Transparency }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then
					local success, color = pcall(Color3.fromHex, data.value)
					if success then
						SaveManager.Options[idx]:SetValueRGB(color, data.transparency)
					else
						warn("SaveManager:Load - Invalid hex color value for Colorpicker:", idx, data.value)
					end
				end
			end,
		},
		Keybind = {
			Save = function(idx, object)
				return { type = "Keybind", idx = idx, mode = object.Mode, key = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] then
					SaveManager.Options[idx]:SetValue(data.key, data.mode)
				end
			end,
		},
		Input = {
			Save = function(idx, object)
				return { type = "Input", idx = idx, text = object.Value }
			end,
			Load = function(idx, data)
				if SaveManager.Options[idx] and type(data.text) == "string" then
					SaveManager.Options[idx]:SetValue(data.text)
				end
			end,
		},
	}

	function SaveManager:SetIgnoreIndexes(list)
		for _, key in next, list do
			self.Ignore[key] = true
		end
	end

	function SaveManager:SetFolder(folder)
		self.Folder = folder;
		self:BuildFolderTree()
	end

	function SaveManager:Save(name)
		if (not name) then
			return false, "no config file is selected"
		end

		local fullPath = self.Folder .. "/settings/" .. name .. ".json"

		local data = {
			objects = {}
		}

		for idx, option in next, SaveManager.Options do
			if not self.Parser[option.Type] then continue end
			if self.Ignore[idx] then continue end

			local successSave, saveData = pcall(self.Parser[option.Type].Save, idx, option)
			if successSave and saveData then
				table.insert(data.objects, saveData)
			else
				warn("SaveManager:Save - Failed to save option:", idx, "Type:", option.Type, "Error:", tostring(saveData))
			end
		end

		local success, encoded = pcall(httpService.JSONEncode, httpService, data)
		if not success then
			return false, "failed to encode data"
		end

		writefile(fullPath, encoded)
		return true
	end

	function SaveManager:Load(name)
		if (not name) then
			return false, "no config file is selected"
		end

		local file = self.Folder .. "/settings/" .. name .. ".json"
		if not isfile(file) then return false, "invalid file" end

		local successRead, fileContent = pcall(readfile, file)
		if not successRead then return false, "read error: " .. tostring(fileContent) end

		local decodeStartTime = os.clock()
		local successDecode, decoded = pcall(httpService.JSONDecode, httpService, fileContent)
		local decodeEndTime = os.clock()
		--print(string.format("SaveManager: JSON Decode took %.4f seconds", decodeEndTime - decodeStartTime))

		if not successDecode then return false, "decode error: " .. tostring(decoded) end

		if not decoded or type(decoded.objects) ~= "table" then
			warn("SaveManager:Load - Invalid or missing 'objects' table in config file:", name)
			return false, "invalid config format"
		end

		task.spawn(function()
			local applyStartTime = os.clock()
			local loadedCount = 0
			local errorCount = 0
			local totalCount = #decoded.objects
			local itemsProcessedSinceWait = 0
			local ITEMS_PER_YIELD = 25

			--print(string.format("SaveManager: Starting background application of %d options for config '%s' (Batch size: %d)...", totalCount, name, ITEMS_PER_YIELD))

			for i, optionData in ipairs(decoded.objects) do
				if not optionData or type(optionData) ~= "table" or not optionData.type or not optionData.idx then
					warn(string.format("SaveManager:Load - Skipping invalid/incomplete option data at array index %d in config '%s'", i, name))
					errorCount = errorCount + 1
					continue
				end

				local optionType = optionData.type
				local optionIndex = optionData.idx

				local parser = self.Parser[optionType]
				local uiElement = SaveManager.Options[optionIndex]

				if not parser then
					warn(string.format("SaveManager:Load - No parser found for type '%s' (Index: '%s', Array Idx: %d) in '%s'", tostring(optionType), tostring(optionIndex), i, name))
					errorCount = errorCount + 1
					continue
				end
				if not uiElement then
					warn(string.format("SaveManager:Load - UI Element not found for index '%s' (Type: '%s', Array Idx: %d) in '%s'. Skipping.", tostring(optionIndex), tostring(optionType), i, name))
					errorCount = errorCount + 1
					continue
				end

				local loadSuccess = true
				local loadError = nil
				local shouldLoad = true

				if optionType == "Dropdown" then
					if uiElement.Value == optionData.value then
						shouldLoad = false
					end
				end

				if shouldLoad then
					loadSuccess, loadError = pcall(function()
						parser.Load(optionIndex, optionData)
					end)

					if loadSuccess then
						loadedCount = loadedCount + 1
					else
						errorCount = errorCount + 1
						warn(string.format("SaveManager:Load - Failed to load option '%s' (Type: %s, Array Idx: %d) in '%s'. Error: %s",
							tostring(optionIndex), tostring(optionType), i, name, tostring(loadError)))
					end
				else
					loadedCount = loadedCount + 1
				end

				itemsProcessedSinceWait = itemsProcessedSinceWait + 1
				if itemsProcessedSinceWait >= ITEMS_PER_YIELD then
					task.wait() 
					itemsProcessedSinceWait = 0 
				end
			end 

			local applyEndTime = os.clock() 
			local totalApplyTime = applyEndTime - applyStartTime 

			print(string.format("Processed: %d, Loaded OK: %d, Errors/Skipped: %d. Time: %.4f seconds.",
				totalCount, loadedCount, errorCount, totalApplyTime))

			if self.Library and self.Library.Notify then
				self.Library:Notify({
					Title = "Interface", Content = "Config loader",
					SubContent = string.format("Finished loading config %q (%d items, %d errors)", name, loadedCount, errorCount),
					Duration = 5
				})
			end
		end) 

		return true
	end

	function SaveManager:IgnoreThemeSettings()
		self:SetIgnoreIndexes({
			"InterfaceTheme", "AcrylicToggle", "TransparentToggle", "MenuKeybind"
		})
	end

	function SaveManager:BuildFolderTree()
		local paths = {
			self.Folder,
			self.Folder .. "/settings"
		}

		for i = 1, #paths do
			local str = paths[i]
			if not isfolder(str) then
				makefolder(str)
			end
		end
	end

	function SaveManager:RefreshConfigList()
		local list = listfiles(self.Folder .. "/settings")

		local out = {}
		for i = 1, #list do
			local file = list[i]
			if file:sub(-5) == ".json" then
				local pos = file:find(".json", 1, true)
				if pos then
					local start = pos
					local char = file:sub(pos, pos)
					while pos > 1 and char ~= "/" and char ~= "\\" do
						pos = pos - 1
						char = file:sub(pos, pos)
					end

					local name
					if char == "/" or char == "\\" then
						name = file:sub(pos + 1, start - 1)
					else
						name = file:sub(1, start - 1)
					end

					if name ~= "options" then
						table.insert(out, name)
					end
				end
			end
		end

		return out
	end


	function SaveManager:SetLibrary(library)
		self.Library = library
		self.Options = library.Options
	end

	function SaveManager:LoadAutoloadConfig()
		local autoloadFile = self.Folder .. "/settings/autoload.txt"
		if isfile(autoloadFile) then
			local name = readfile(autoloadFile)
			if name and name:gsub("%s", "") ~= "" then
				local success, err = self:Load(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to load autoload config: " .. err,
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Auto loaded config %q", name),
					Duration = 7
				})
			else
				warn("SaveManager: Autoload file is empty or invalid.")
			end
		end
	end

	function SaveManager:BuildConfigSection(tab)
		assert(self.Library, "Must set SaveManager.Library")

		local section = tab:AddSection("Configuration")

		section:AddInput("SaveManager_ConfigName",    { Title = "Config name" })
		section:AddDropdown("SaveManager_ConfigList", { Title = "Config list", Values = self:RefreshConfigList(), AllowNull = true })

		section:AddButton({
			Title = "Create config",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigName.Value

				if not name or name:gsub("%s", "") == "" then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Invalid config name (empty)",
						Duration = 7
					})
				end

				local success, err = self:Save(name)
				if not success then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "Failed to save config: " .. err,
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Created config %q", name),
					Duration = 7
				})

				SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
			end
		})

		section:AddButton({Title = "Load config", Callback = function()
			local name = SaveManager.Options.SaveManager_ConfigList.Value

			if not name then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "No config selected to load.",
					Duration = 7
				})
			end

			local success, err = self:Load(name)
			if not success then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "Failed to load config: " .. err,
					Duration = 7
				})
			end
		end})

		section:AddButton({
			Title = "Delete config",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value
				local AutoloadButton = SaveManager.Options.AutoloadButton

				if not name then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "No config selected to delete.",
						Duration = 7
					})
				end

				local filePath = self.Folder .. "/settings/" .. name .. ".json"
				local autoloadFilePath = self.Folder .. "/settings/autoload.txt"

				if not isfile(filePath) then
					SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
					SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = string.format("Config %q does not exist (list refreshed).", name),
						Duration = 7
					})
				end

				delfile(filePath)

				if isfile(filePath) then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = string.format("Failed to delete config %q. Check environment/permissions.", name),
						Duration = 7
					})
				end

				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Deleted config %q.", name),
					Duration = 7
				})

				if isfile(autoloadFilePath) then
					local autoloadName = readfile(autoloadFilePath)
					if autoloadName == name then
						delfile(autoloadFilePath)
						local autoloadBtn = tab:FindFirstChild("AutoloadButton", true)
						if autoloadBtn and autoloadBtn.SetDesc then
							autoloadBtn:SetDesc("Current autoload config: none")
						end
						self.Library:Notify({
							Title = "Interface",
							Content = "Config loader",
							SubContent = "Removed autoload setting as the config was deleted.",
							Duration = 7
						})
					end
				end

				SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
				SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
			end
		})


		section:AddButton({Title = "Overwrite config", Callback = function()
			local name = SaveManager.Options.SaveManager_ConfigList.Value

			if not name then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "No config selected to overwrite.",
					Duration = 7
				})
			end

			local success, err = self:Save(name)
			if not success then
				return self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = "Failed to overwrite config: " .. err,
					Duration = 7
				})
			end

			self.Library:Notify({
				Title = "Interface",
				Content = "Config loader",
				SubContent = string.format("Overwrote config %q", name),
				Duration = 7
			})
		end})

		section:AddButton({Title = "Refresh list", Callback = function()
			SaveManager.Options.SaveManager_ConfigList:SetValues(self:RefreshConfigList())
			SaveManager.Options.SaveManager_ConfigList:SetValue(nil)
		end})

		local AutoloadButton = section:AddButton({
			Title = "Set as autoload",
			Description = "Current autoload config: none",
			Callback = function()
				local name = SaveManager.Options.SaveManager_ConfigList.Value
				if not name then
					return self.Library:Notify({
						Title = "Interface",
						Content = "Config loader",
						SubContent = "No config selected to set as autoload.",
						Duration = 7
					})
				end
				writefile(self.Folder .. "/settings/autoload.txt", name)
				local thisButton = SaveManager.Options.AutoloadButton
				if thisButton and thisButton.SetDesc then
					thisButton:SetDesc("Current autoload config: " .. name)
				end
				self.Library:Notify({
					Title = "Interface",
					Content = "Config loader",
					SubContent = string.format("Set %q to auto load", name),
					Duration = 7
				})
			end
		})

		SaveManager.Options.AutoloadButton = AutoloadButton

		local autoloadFile = self.Folder .. "/settings/autoload.txt"
		if isfile(autoloadFile) then
			local name = readfile(autoloadFile)
			if name and name:gsub("%s", "") ~= "" then
				AutoloadButton:SetDesc("Current autoload config: " .. name)
			end
		end

		SaveManager:SetIgnoreIndexes({ "SaveManager_ConfigList", "SaveManager_ConfigName", "AutoloadButton" })
	end

	SaveManager:BuildFolderTree()
end

return SaveManager
