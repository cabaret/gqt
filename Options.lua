local addonName, GQT = ...

GQT.Options = {}

local expansions = {
  {
    name = "The War Within",
    zones = {
      [2339] = 'Dornogal',
      [2248] = 'Isle of Dorn',
      [2214] = 'The Ringing Deeps',
      [2215] = 'Hallowfall',
      [2255] = 'Azj-Kahet',
      [2369] = 'Siren Isle',
      [2346] = 'Undermine',
    }
  },
  {
    name = "Dragonflight",
    zones = {
      [2022] = 'The Waking Shores',
      [2023] = 'Ohn\'ahran Plains',
      [2024] = 'The Azure Span',
      [2025] = 'Thaldraszus',
      [2133] = 'Zaralek Cavern',
      [2151] = 'Forbidden Reach',
      [2200] = 'Emerald Dream',
    }
  },
  {
    name = "Shadowlands",
    zones = {
      [1525] = 'Revendreth',
      [1533] = 'Bastion',
      [1536] = 'Maldraxxus',
      [1565] = 'Ardenweald',
      [1970] = 'Zereth Mortis',
    }
  },
  {
    name = "Battle for Azeroth",
    zones = {
      [1355] = 'Nazjatar',
      [1462] = 'Mechagon',
    }
  }
}

function GQT.Options:CreateOptionsPanel()
  local panel = CreateFrame("Frame")
  panel.name = "Gold Quest Tracker"
  
  local title = panel:CreateFontString(nil, "OVERLAY")
  title:SetFontObject("GameFontNormalLarge")
  title:SetPoint("TOPLEFT", 16, -16)
  title:SetText("Gold Quest Tracker Settings")
  
  local subtitle = panel:CreateFontString(nil, "OVERLAY")
  subtitle:SetFontObject("GameFontHighlightSmall")
  subtitle:SetPoint("TOPLEFT", title, "BOTTOMLEFT", 0, -8)
  subtitle:SetText("Configure which zones to scan for gold world quests")
  
  local minGoldLabel = panel:CreateFontString(nil, "OVERLAY")
  minGoldLabel:SetFontObject("GameFontNormal")
  minGoldLabel:SetPoint("TOPLEFT", subtitle, "BOTTOMLEFT", 0, -16)
  minGoldLabel:SetText("Minimum Gold Reward:")
  
  local minGoldSlider = CreateFrame("Slider", nil, panel, "OptionsSliderTemplate")
  minGoldSlider:SetPoint("TOPLEFT", minGoldLabel, "BOTTOMLEFT", 0, -8)
  minGoldSlider:SetMinMaxValues(0, 20000000)
  minGoldSlider:SetValueStep(500000)
  minGoldSlider:SetValue(GQT.Config.minimumGoldReward or 5000000)
  minGoldSlider:SetWidth(200)
  
  local minGoldValue = panel:CreateFontString(nil, "OVERLAY")
  minGoldValue:SetFontObject("GameFontHighlightSmall")
  minGoldValue:SetPoint("LEFT", minGoldSlider, "RIGHT", 10, 0)
  
  local function UpdateMinGoldText()
    local value = minGoldSlider:GetValue()
    local gold = math.floor(value / 10000)
    minGoldValue:SetText(gold .. "g")
  end
  
  UpdateMinGoldText()
  minGoldSlider:SetScript("OnValueChanged", UpdateMinGoldText)
  
  local scrollFrame = CreateFrame("ScrollFrame", nil, panel, "UIPanelScrollFrameTemplate")
  scrollFrame:SetPoint("TOPLEFT", minGoldSlider, "BOTTOMLEFT", 0, -20)
  scrollFrame:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", -40, 50)
  
  local scrollChild = CreateFrame("Frame", nil, scrollFrame)
  scrollFrame:SetScrollChild(scrollChild)
  scrollChild:SetWidth(600)
  scrollChild:SetHeight(400)
  
  local columnWidth = 280
  local columns = {
    {x = 10, expansions = {expansions[1], expansions[3]}},
    {x = columnWidth + 20, expansions = {expansions[2], expansions[4]}}
  }
  
  local maxYOffset = -35
  
  local testText = scrollChild:CreateFontString(nil, "OVERLAY")
  testText:SetFontObject("GameFontNormal")
  testText:SetPoint("TOPLEFT", 10, -10)
  testText:SetText("Expansions")
  
  for colIndex, column in ipairs(columns) do
    local yOffset = -35
    
    for _, expansion in ipairs(column.expansions) do
      if expansion then
        local expFrame = CreateFrame("Frame", nil, scrollChild, "BackdropTemplate")
        expFrame:SetPoint("TOPLEFT", column.x, yOffset)
        expFrame:SetSize(columnWidth, 40)
        
        local backdrop = {
          edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
          tile = false,
          edgeSize = 16,
          insets = {left = 8, right = 8, top = 8, bottom = 8}
        }
        expFrame:SetBackdrop(backdrop)
        expFrame:SetBackdropBorderColor(0.6, 0.6, 0.6, 1)
        
        local expHeader = expFrame:CreateFontString(nil, "OVERLAY")
        expHeader:SetFontObject("GameFontNormal")
        expHeader:SetPoint("TOPLEFT", 12, -12)
        expHeader:SetText(expansion.name)
        
        local expCheckAll = CreateFrame("CheckButton", nil, expFrame, "InterfaceOptionsCheckButtonTemplate")
        expCheckAll:SetPoint("TOPLEFT", 12, -30)
        expCheckAll.Text:SetText("Enable All")
        
        local zoneCheckboxes = {}
        local zoneYOffset = -55
        local maxZones = 0
        
        for zoneID, zoneName in pairs(expansion.zones) do
          local checkbox = CreateFrame("CheckButton", nil, expFrame, "InterfaceOptionsCheckButtonTemplate")
          checkbox:SetPoint("TOPLEFT", 16, zoneYOffset)
          checkbox.Text:SetText(zoneName)
          checkbox.zoneID = zoneID
          
          if GQT.Config.trackedZones[zoneID] then
            checkbox:SetChecked(true)
          end
          
          checkbox:SetScript("OnClick", function(self)
            if self:GetChecked() then
              GQT.Config.trackedZones[zoneID] = zoneName
            else
              GQT.Config.trackedZones[zoneID] = nil
            end
            GQT:ClearCache()
            
            local allChecked = true
            for _, cb in pairs(zoneCheckboxes) do
              if not cb:GetChecked() then
                allChecked = false
                break
              end
            end
            expCheckAll:SetChecked(allChecked)
          end)
          
          table.insert(zoneCheckboxes, checkbox)
          zoneYOffset = zoneYOffset - 25
          maxZones = maxZones + 1
        end
        
        expCheckAll:SetScript("OnClick", function(self)
          local checked = self:GetChecked()
          for _, checkbox in pairs(zoneCheckboxes) do
            checkbox:SetChecked(checked)
            if checked then
              GQT.Config.trackedZones[checkbox.zoneID] = expansion.zones[checkbox.zoneID]
            else
              GQT.Config.trackedZones[checkbox.zoneID] = nil
            end
          end
          GQT:ClearCache()
        end)
        
        local allChecked = true
        for zoneID, _ in pairs(expansion.zones) do
          if not GQT.Config.trackedZones[zoneID] then
            allChecked = false
            break
          end
        end
        expCheckAll:SetChecked(allChecked)
        
        local frameHeight = 70 + (maxZones * 25)
        expFrame:SetHeight(frameHeight)
        yOffset = yOffset - frameHeight - 20
        
        if yOffset < maxYOffset then
          maxYOffset = yOffset
        end
      end
    end
  end
  
  local finalHeight = math.max(400, math.abs(maxYOffset) + 50)
  scrollChild:SetHeight(finalHeight)
  
  local saveButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
  saveButton:SetPoint("BOTTOMLEFT", 16, 16)
  saveButton:SetSize(100, 22)
  saveButton:SetText("Save")
  saveButton:SetScript("OnClick", function()
    GQT.Config.minimumGoldReward = minGoldSlider:GetValue()
    GQT.db.trackedZones = GQT.Config.trackedZones
    GQT.db.minimumGoldReward = GQT.Config.minimumGoldReward
    _G.GoldQuestTrackerDB = GQT.db
    print("|cFFFFD700Gold Quest Tracker:|r Settings saved!")
  end)
  
  if Settings and Settings.RegisterCanvasLayoutCategory then
    local category = Settings.RegisterCanvasLayoutCategory(panel, "Gold Quest Tracker")
    Settings.RegisterAddOnCategory(category)
  else
    InterfaceOptions_AddCategory(panel)
  end
  
  GQT.optionsPanel = panel
end

function GQT.Options:OpenPanel()
  if Settings and Settings.OpenToCategory then
    Settings.OpenToCategory("Gold Quest Tracker")
  else
    InterfaceOptionsFrame_OpenToCategory("Gold Quest Tracker")
  end
end