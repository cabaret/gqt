local addonName, GQT = ...

GQT.goldQuests = {}
GQT.isScanning = false
GQT.lastScanTime = 0
GQT.scanCooldown = 30
GQT.questCache = {}
GQT.eventFrame = nil

function GQT:Initialize()
  self.db = _G.GoldQuestTrackerDB or CopyTable(GQT.Config.defaults)
  _G.GoldQuestTrackerDB = self.db
  
  if self.db.trackedZones then
    GQT.Config.trackedZones = self.db.trackedZones
  end
  if self.db.minimumGoldReward then
    GQT.Config.minimumGoldReward = self.db.minimumGoldReward
  end

  print '|cFFFFD700Gold Quest Tracker:|r Addon loaded.'

  GQT.UI:CreateMinimapIcon()
  GQT.UI:CreateMainFrame()
  GQT.Options:CreateOptionsPanel()

  self.eventFrame = CreateFrame 'Frame'
  self.eventFrame:RegisterEvent 'PLAYER_ENTERING_WORLD'
  self.eventFrame:RegisterEvent 'QUEST_LOG_UPDATE'
  self.eventFrame:RegisterEvent 'WORLD_QUEST_COMPLETED_BY_SPELL'
  self.eventFrame:SetScript('OnEvent', function(_, event, ...)
    if self[event] then
      self[event](self, ...)
    end
  end)
end

function GQT:PLAYER_ENTERING_WORLD()
  C_Timer.After(3, function()
    print '|cFFFFD700Gold Quest Tracker:|r World data loaded and ready.'
    self:ScanForGoldQuests()
  end)
end

function GQT:QUEST_LOG_UPDATE()
  if not self.isScanning then
    return
  end
  
  local currentTime = GetTime()
  if currentTime - self.lastScanTime > 2 then
    self:ProcessQuestData()
  end
end

function GQT:WORLD_QUEST_COMPLETED_BY_SPELL()
  C_Timer.After(1, function()
    if not self.isScanning then
      self:ScanForGoldQuests()
    end
  end)
end

function GQT:ScanForGoldQuests()
  local currentTime = GetTime()
  
  if self.isScanning or (currentTime - self.lastScanTime < self.scanCooldown) then
    if GQT.Config.debug then
      print('|cFFFFD700Gold Quest Tracker:|r Scan already in progress or on cooldown.')
    end
    return
  end
  
  self.isScanning = true
  self.lastScanTime = currentTime
  self.goldQuests = {}
  
  if self.UI then
    self.UI:ShowEmptyState(true)
  end
  
  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Starting quest scan...')
  end
  
  self:PreloadQuestData()
  C_Timer.After(3, function()
    if self.isScanning then
      self:ProcessQuestData()
      self.isScanning = false
      self.UI:DisplayQuests()
    end
  end)
end

function GQT:PreloadQuestData()
  local preloadCount = 0
  
  for mapID, zoneName in pairs(GQT.Config.trackedZones) do
    local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    
    for _, questData in ipairs(zoneQuests) do
      if questData.questID and C_QuestLog.IsWorldQuest(questData.questID) then
        C_TaskQuest.RequestPreloadRewardData(questData.questID)
        preloadCount = preloadCount + 1
      end
    end
  end
  
end

function GQT:ProcessQuestData()
  local foundQuests = 0
  local totalQuests = 0
  local worldQuests = 0
  
  for mapID, zoneName in pairs(GQT.Config.trackedZones) do
    local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    totalQuests = totalQuests + #zoneQuests
    
    
    for _, questData in ipairs(zoneQuests) do
      if questData.questID and C_QuestLog.IsWorldQuest(questData.questID) then
        worldQuests = worldQuests + 1
        
        
        local questInfo = self:GetQuestRewardInfo(questData.questID, mapID)
        if questInfo and questInfo.goldReward >= GQT.Config.minimumGoldReward then
          local alreadyExists = false
          for _, existingQuest in ipairs(self.goldQuests) do
            if existingQuest.id == questData.questID then
              alreadyExists = true
              break
            end
          end
          
          if not alreadyExists then
            table.insert(self.goldQuests, questInfo)
            foundQuests = foundQuests + 1
          end
        end
      end
    end
  end
  
  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Scanned ' .. totalQuests .. ' total quests, ' .. worldQuests .. ' world quests, found ' .. foundQuests .. ' gold quests.')
  end
end

function GQT:GetQuestRewardInfo(questID, mapID)
  local cacheKey = questID .. "_" .. mapID
  
  if self.questCache[cacheKey] and (GetTime() - self.questCache[cacheKey].timestamp) < 300 then
    return self.questCache[cacheKey]
  end
  
  if not HaveQuestData(questID) then
    return nil
  end
  
  local questName = C_TaskQuest.GetQuestInfoByQuestID(questID)
  if not questName then 
    return nil 
  end
  
  if not mapID then
    mapID = C_TaskQuest.GetQuestZoneID(questID)
    if not mapID then 
      return nil 
    end
  end
  
  local mapInfo = C_Map.GetMapInfo(mapID)
  local zoneName = mapInfo and mapInfo.name or 'Unknown Zone'
  
  local locationX, locationY = C_TaskQuest.GetQuestLocation(questID, mapID)
  local location = { x = locationX or 0.5, y = locationY or 0.5 }
  
  local moneyReward = 0
  
  if C_QuestLog.IsQuestFlaggedCompleted(questID) then
    return nil
  end
  
  if not HaveQuestRewardData(questID) then
    C_TaskQuest.RequestPreloadRewardData(questID)
  end
  
  local oldSelectedQuest = C_QuestLog.GetSelectedQuest()
  
  C_QuestLog.SetSelectedQuest(questID)
  moneyReward = GetQuestLogRewardMoney() or 0
  
  if moneyReward <= 0 then
    moneyReward = GetQuestLogRewardMoney(questID) or 0
  end
  
  if oldSelectedQuest then
    C_QuestLog.SetSelectedQuest(oldSelectedQuest)
  end
  
  
  if moneyReward < GQT.Config.minimumGoldReward then
    return nil
  end
  
  local timeLeft = 'Unknown'
  local timeLeftMinutes = C_TaskQuest.GetQuestTimeLeftMinutes(questID)
  
  if timeLeftMinutes then
    if timeLeftMinutes <= 60 then
      timeLeft = string.format('%d mins', timeLeftMinutes)
    else
      local hours = math.floor(timeLeftMinutes / 60)
      local mins = timeLeftMinutes % 60
      timeLeft = string.format('%dh %dm', hours, mins)
    end
  end
  
  local questInfo = {
    id = questID,
    mapID = mapID,
    title = questName,
    zone = zoneName,
    goldReward = moneyReward,
    timeLeft = timeLeft,
    location = location,
    link = GetQuestLink(questID) or 'Quest Link',
    timestamp = GetTime()
  }
  
  self.questCache[cacheKey] = questInfo
  
  
  return questInfo
end

function GQT:FormatMoney(copper)
  local gold = math.floor(copper / 10000)
  local silver = math.floor((copper % 10000) / 100)
  return gold .. "g " .. silver .. "s"
end

function GQT:ClearCache()
  self.questCache = {}
  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Cache cleared.')
  end
end

local function SlashCommandHandler(msg)
  msg = msg and msg:lower() or ''

  if msg == '' then
    if GQT.UI.mainFrame and GQT.UI.mainFrame:IsShown() then
      GQT.UI.mainFrame:Hide()
    else
      GQT:ScanForGoldQuests()
      GQT.UI.mainFrame:Show()
    end
  elseif msg == 'scan' then
    GQT:ScanForGoldQuests()
  elseif msg == 'clear' then
    GQT:ClearCache()
  elseif msg == 'debug' then
    GQT.Config.debug = not GQT.Config.debug
    print('|cFFFFD700Gold Quest Tracker:|r Debug mode ' .. (GQT.Config.debug and 'enabled' or 'disabled'))
  elseif msg == 'options' or msg == 'config' then
    GQT.Options:OpenPanel()
  elseif msg == 'help' then
    print '|cFFFFD700Gold Quest Tracker:|r Commands:'
    print '  /gqt - Toggle addon window'
    print '  /gqt scan - Force scan for gold world quests'
    print '  /gqt clear - Clear quest cache'
    print '  /gqt debug - Toggle debug mode'
    print '  /gqt options - Open options panel'
    print '  /gqt help - Show this help message'
  else
    print '|cFFFFD700Gold Quest Tracker:|r Unknown command. Type /gqt help for available commands.'
  end

  if ChatFrameEditBox then
    ChatFrameEditBox:Hide()
  elseif ChatFrame1EditBox then
    ChatFrame1EditBox:Hide()
  else
    ChatFrame_CloseChat()
  end
end

SLASH_GOLDQUESTTRACKER1 = '/gqt'
SLASH_GOLDQUESTTRACKER2 = '/goldquest'
SlashCmdList['GOLDQUESTTRACKER'] = SlashCommandHandler

local initFrame = CreateFrame 'Frame'
initFrame:RegisterEvent 'ADDON_LOADED'
initFrame:SetScript('OnEvent', function(self, event, ...)
  if event == 'ADDON_LOADED' and ... == addonName then
    GQT:Initialize()
    self:UnregisterEvent 'ADDON_LOADED'
  end
end)
