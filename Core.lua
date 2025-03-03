local addonName, GQT = ...

GQT.pendingQuestData = {}
GQT.totalQuestsToLoad = 0
GQT.loadedQuests = {}
GQT.goldQuests = {}
GQT.isProcessing = false
GQT.zonesScanned = 0
GQT.totalZones = 0
GQT.scanActive = false
GQT.scanAttempt = 0
GQT.dataReady = false

function GQT:Initialize()
  self.db = _G.GoldQuestTrackerDB or CopyTable(defaults)
  _G.GoldQuestTrackerDB = self.db

  print '|cFFFFD700Gold Quest Tracker:|r Addon loaded.'

  GQT.UI:CreateMinimapIcon()
  GQT.UI:CreateMainFrame()

  self.frame = CreateFrame 'Frame'
  self.frame:RegisterEvent 'QUEST_DATA_LOAD_RESULT'
  self.frame:RegisterEvent 'PLAYER_ENTERING_WORLD'
  self.frame:SetScript('OnEvent', function(_, event, ...)
    if self[event] then
      self[event](self, ...)
    end
  end)
end

function GQT:PLAYER_ENTERING_WORLD()
  C_Timer.After(5, function()
    self.dataReady = true
    print '|cFFFFD700Gold Quest Tracker:|r World data loaded and ready.'

    self:PreCacheQuestData()
  end)
end

function GQT:PreCacheQuestData()
  for mapID, _ in pairs(GQT.Config.trackedZones) do
    local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
    for _, questData in ipairs(zoneQuests) do
      if questData.mapID == mapID and C_QuestLog.IsWorldQuest(questData.questID) then
        C_TaskQuest.RequestPreloadRewardData(questData.questID)
      end
    end
  end

  if GQT.Config.debug then
    print '|cFFFFD700Gold Quest Tracker:|r Pre-cached quest data for faster response.'
  end
end

function GQT:ScanForGoldQuests()
  if self.scanActive then
    print '|cFFFFD700Gold Quest Tracker:|r Scan already in progress. Please wait...'
    return
  end

  if not self.dataReady then
    print '|cFFFFD700Gold Quest Tracker:|r World data not fully loaded yet. Please try again in a few seconds.'
    return
  end

  self.scanActive = true
  self.pendingQuestData = {}
  self.loadedQuests = {}
  self.goldQuests = {}
  self.totalQuestsToLoad = 0
  self.isProcessing = false
  self.zonesScanned = 0
  self.totalZones = 0
  self.scanAttempt = 1

  if self.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Starting scan for gold quests (attempt ' .. self.scanAttempt .. ')...')
  end

  for _ in pairs(GQT.Config.trackedZones) do
    self.totalZones = self.totalZones + 1
  end

  self:PerformZoneScan()
end

function GQT:PerformZoneScan()
  for mapID, zoneName in pairs(GQT.Config.trackedZones) do
    self:ScanForGoldQuestsInZone(mapID, zoneName)
  end

  if self.totalQuestsToLoad == 0 and self.scanAttempt >= 3 then
    print '|cFFFFD700Gold Quest Tracker:|r No quests found.'
    GQT.UI:DisplayQuests()
    self.scanActive = false
  end
end

function GQT:ScanForGoldQuestsInZone(mapID, zoneName)
  local zoneQuests = C_TaskQuest.GetQuestsForPlayerByMapID(mapID) or {}
  local filteredQuests = {}

  for _, questData in ipairs(zoneQuests) do
    if questData.mapID == mapID and C_QuestLog.IsWorldQuest(questData.questID) then
      table.insert(filteredQuests, questData)
    end
  end

  if self.debug then
    print('|cFFFFD700GQT Debug:|r Found ' .. #filteredQuests .. ' quests in ' .. zoneName)
  end

  self.totalQuestsToLoad = self.totalQuestsToLoad + #filteredQuests
  self.zonesScanned = self.zonesScanned + 1

  if #filteredQuests > 0 then
    for _, questData in ipairs(filteredQuests) do
      local questID = questData.questID
      if C_QuestLog.IsWorldQuest(questID) then
        self.pendingQuestData[questID] = true
        if HaveQuestData(questID) then
          C_Timer.After(0.1, function()
            self:QUEST_DATA_LOAD_RESULT(questID, true)
          end)
        else
          C_TaskQuest.RequestPreloadRewardData(questID)
        end
      end
    end
  end

  if self.zonesScanned == self.totalZones and self.totalQuestsToLoad == 0 then
    self.isProcessing = true
    self:ProcessLoadedQuests()
  end
end

function GQT:QUEST_DATA_LOAD_RESULT(questID, success)
  if not self.pendingQuestData[questID] or not self.scanActive then
    return
  end

  if success then
    self.pendingQuestData[questID] = nil
    self.loadedQuests[questID] = true

    local loadedCount = 0
    for _ in pairs(self.loadedQuests) do
      loadedCount = loadedCount + 1
    end

    local allLoaded = loadedCount == self.totalQuestsToLoad
    local allZonesScanned = self.zonesScanned == self.totalZones

    if allLoaded and allZonesScanned and not self.isProcessing then
      self.isProcessing = true
      self:ProcessLoadedQuests()
    end
  else
    if self.debug then
      print('|cFFFFD700Gold Quest Tracker:|r Failed to load data for quest ID: ' .. questID)
    end
    self.pendingQuestData[questID] = nil

    local pendingCount = 0
    for _ in pairs(self.pendingQuestData) do
      pendingCount = pendingCount + 1
    end

    if pendingCount == 0 and self.zonesScanned == self.totalZones and not self.isProcessing then
      self.isProcessing = true
      self:ProcessLoadedQuests()
    end
  end
end

function GQT:ProcessLoadedQuests()
  if not self.scanActive then
    return
  end

  for questID in pairs(self.loadedQuests) do
    local questName = C_TaskQuest.GetQuestInfoByQuestID(questID)
    local mapID = C_TaskQuest.GetQuestZoneID(questID)
    local locationX, locationY = C_TaskQuest.GetQuestLocation(questID, mapID)
    local location = { x = locationX, y = locationY }

    if not questName or not mapID then
      if self.debug then
        print('|cFFFFD700Gold Quest Tracker:|r Missing data for quest ID: ' .. questID)
      end
    else
      local mapInfo = C_Map.GetMapInfo(mapID)
      local zoneName = mapInfo and mapInfo.name or 'Unknown Zone'
      local moneyReward = GetQuestLogRewardMoney(questID)

      if moneyReward and moneyReward > 0 then
        if self.debug then
          print('Processing quest: ' .. questName .. ' - Gold: ' .. moneyReward)
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

          table.insert(self.goldQuests, {
            id = questID,
            mapID = mapID,
            title = questName,
            zone = zoneName,
            gold = moneyReward,
            timeLeft = timeLeft,
            location = location,
            link = GetQuestLink(questID) or 'Quest Link',
          })
        end
      end
    end
  end

  self.scanActive = false

  GQT.UI:DisplayQuests()
end

local function SlashCommandHandler(msg)
  msg = msg and msg:lower() or ''

  if msg == '' then
    if GQT.UI.mainFrame and GQT.UI.mainFrame:IsShown() then
      GQT.UI.mainFrame:Hide()
      GQT:PreCacheQuestData()
    else
      GQT:ScanForGoldQuests()
      GQT.UI.mainFrame:Show()
    end
  elseif msg == 'help' then
    print '|cFFFFD700Gold Quest Tracker:|r Commands:'
    print '  /gqt - Scan for gold world quests'
    print '  /gqt help - Show this help message'
  else
    print '|cFFFFD700Gold Quest Tracker:|r Unknown command. Type /gqt help for available commands.'
  end

  if ChatFrameEditBox then
    ChatFrameEditBox:Hide()  -- For older versions of WoW
  elseif ChatFrame1EditBox then
    ChatFrame1EditBox:Hide() -- Alternative in case the previous doesn't work
  else
    ChatFrame_CloseChat()    -- Works for newer versions of WoW
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
