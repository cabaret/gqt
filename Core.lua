local addonName, GQT = ...

GQT.pendingQuestData = {}
GQT.totalQuestsToLoad = 0
GQT.loadedQuests = {}
GQT.goldQuests = {}
GQT.isProcessing = false
GQT.zonesScanned = 0
GQT.totalZones = 0
GQT.scanActive = false
GQT.forceRefresh = false

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
  local questCount = 0

  for mapID, _ in pairs(GQT.Config.trackedZones) do
    -- Use GetQuestsOnMap which returns QuestPOIMapInfo with location data included
    local zoneQuests = C_TaskQuest.GetQuestsOnMap(mapID) or {}
    for _, questInfo in ipairs(zoneQuests) do
      local questID = questInfo.questID
      if questID and C_QuestLog.IsWorldQuest(questID) then
        questCount = questCount + 1
        C_TaskQuest.RequestPreloadRewardData(questID)
      end
    end
  end

  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Pre-cached ' .. questCount .. ' quests for faster response.')
  end
end

-- Completely revamped ScanForGoldQuests function with direct approach and safeguards
function GQT:ScanForGoldQuests()
  -- STRICT safety check - allow force refresh
  if self.scanActive then
    -- Force clear the scanning state to avoid getting stuck
    if self.forceRefresh or (self.scanStartTime and GetTime() - self.scanStartTime > 10) then
      print('|cFFFFD700Gold Quest Tracker:|r Forcing scan reset...')
      self.scanActive = false
      self.forceRefresh = false
    else
      print('|cFFFFD700Gold Quest Tracker:|r Scan already in progress. Please wait...')
      return
    end
  end

  -- Reset state
  self.scanActive = true
  self.scanStartTime = GetTime()
  self.goldQuests = {}
  self.processedQuests = {} -- Clear processed quests between scans

  -- Set a loading state in the UI
  if self.UI then
    self.UI:ShowEmptyState(true)
  end

  -- Simple and direct zone scan
  self:DirectScan()

  -- Guaranteed completion safety timeout
  C_Timer.After(6, function()
    if self.scanActive then
      print('|cFFFFD700Gold Quest Tracker:|r Scan safety timeout reached.')
      self.scanActive = false
      self.UI:DisplayQuests()
    end
  end)
end

-- Optimized direct scanning using GetQuestsOnMap API
function GQT:DirectScan()
  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Directly scanning for gold quests...')
  end

  -- Process each zone using optimized API
  for mapID, zoneName in pairs(GQT.Config.trackedZones) do
    -- GetQuestsOnMap returns QuestPOIMapInfo with questID, x, y, mapID included
    local zoneQuests = C_TaskQuest.GetQuestsOnMap(mapID) or {}

    if GQT.Config.debug then
      print('|cFFFFD700GQT Debug:|r Zone ' .. zoneName .. ' (ID: ' .. mapID .. ') has ' .. #zoneQuests .. ' quests')
    end

    for _, questInfo in ipairs(zoneQuests) do
      local questID = questInfo.questID

      -- Only process world quests
      if questID and C_QuestLog.IsWorldQuest(questID) and HaveQuestData(questID) then
        -- Request reward data preload (critical - must happen before checking gold)
        C_TaskQuest.RequestPreloadRewardData(questID)

        if GQT.Config.debug then
          local hasRewardData = HaveQuestRewardData(questID)
          print('|cFFFFD700GQT Debug:|r Quest ' .. questID .. ' hasRewardData=' .. tostring(hasRewardData))
        end

        -- Try to process if reward data already available
        if HaveQuestRewardData(questID) then
          self:ProcessQuestOptimized(questID, mapID, questInfo)
        end
      end
    end
  end

  -- Wait for async data to load, then process remaining quests
  C_Timer.After(1.0, function()
    if not self.scanActive then return end

    print('|cFFFFD700Gold Quest Tracker:|r Processing quest data...')

    -- Second pass with loaded reward data
    for mapID, _ in pairs(GQT.Config.trackedZones) do
      local zoneQuests = C_TaskQuest.GetQuestsOnMap(mapID) or {}

      for _, questInfo in ipairs(zoneQuests) do
        local questID = questInfo.questID

        -- Now check HaveQuestRewardData since we requested preload earlier
        if questID and C_QuestLog.IsWorldQuest(questID) and HaveQuestRewardData(questID) then
          self:ProcessQuestOptimized(questID, mapID, questInfo)
        end
      end
    end

    -- Complete the scan
    C_Timer.After(0.3, function()
      if not self.scanActive then return end

      self.scanActive = false
      print('|cFFFFD700Gold Quest Tracker:|r Scan complete, found ' .. #self.goldQuests .. ' gold quests.')
      self.UI:DisplayQuests()
    end)
  end)

  -- Progress update for long scans
  C_Timer.After(2.5, function()
    if self.scanActive and #self.goldQuests > 0 then
      print('|cFFFFD700Gold Quest Tracker:|r Still scanning... Found ' .. #self.goldQuests .. ' gold quests so far.')
      self.UI:DisplayQuests()
    end
  end)
end

-- Optimized quest processing using pre-fetched QuestPOIMapInfo data
function GQT:ProcessQuestOptimized(questID, mapID, questInfo)
  -- Skip if already processed
  if self.processedQuests and self.processedQuests[questID] then
    return
  end

  -- Initialize the processed quests table if needed
  if not self.processedQuests then
    self.processedQuests = {}
  end

  -- Mark as processed
  self.processedQuests[questID] = true

  -- Must have reward data loaded to check gold (different from HaveQuestData!)
  if not HaveQuestRewardData(questID) then
    if GQT.Config.debug then
      print('|cFFFFD700GQT Debug:|r Quest ' .. questID .. ' - reward data not loaded yet')
    end
    return
  end

  -- Check for gold reward
  local moneyReward = GetQuestLogRewardMoney(questID)

  if GQT.Config.debug then
    print('|cFFFFD700GQT Debug:|r Quest ' .. questID .. ' gold=' .. tostring(moneyReward or 0))
  end

  -- Filter out quests with 500g or less (500g = 5,000,000 copper)
  if not moneyReward or moneyReward <= 5000000 then
    return
  end

  -- Get quest title using the more reliable API
  local questName = C_QuestLog.GetTitleForQuestID(questID)
    or C_TaskQuest.GetQuestInfoByQuestID(questID)
  if not questName then
    if GQT.Config.debug then
      print('|cFFFFD700Gold Quest Tracker:|r Missing quest info for ID ' .. questID)
    end
    return
  end

  -- Use location from questInfo if available (already fetched), otherwise fallback
  local locationX, locationY
  if questInfo and questInfo.x and questInfo.y then
    locationX, locationY = questInfo.x, questInfo.y
  else
    locationX, locationY = C_TaskQuest.GetQuestLocation(questID, mapID)
  end
  local location = { x = locationX or 0, y = locationY or 0 }

  -- Get the zone name
  local mapInfo = C_Map.GetMapInfo(mapID)
  local zoneName = mapInfo and mapInfo.name or 'Unknown Zone'

  -- Get time left using seconds API for more precision
  local timeLeft = 'Unknown'
  local timeLeftSeconds = C_TaskQuest.GetQuestTimeLeftSeconds(questID)

  if timeLeftSeconds and timeLeftSeconds > 0 then
    local totalMinutes = math.floor(timeLeftSeconds / 60)
    if totalMinutes <= 60 then
      timeLeft = string.format('%d mins', totalMinutes)
    else
      local hours = math.floor(totalMinutes / 60)
      local mins = totalMinutes % 60
      timeLeft = string.format('%dh %dm', hours, mins)
    end

    -- Add to results
    table.insert(self.goldQuests, {
      id = questID,
      mapID = mapID,
      title = questName,
      zone = zoneName,
      gold = moneyReward,
      timeLeft = timeLeft,
      timeLeftSeconds = timeLeftSeconds, -- Store for potential sorting
      location = location,
      link = GetQuestLink(questID) or 'Quest Link',
    })

    if GQT.Config.debug then
      print('|cFFFFD700Gold Quest Tracker:|r Found gold quest: ' .. questName .. ' (' .. GQT.Utils:FormatMoney(moneyReward) .. ')')
    end
  end
end

-- Legacy function for backward compatibility with QUEST_DATA_LOAD_RESULT event
function GQT:ProcessQuest(questID, mapID)
  self:ProcessQuestOptimized(questID, mapID, nil)
end

-- Event handler for async quest data loading
function GQT:QUEST_DATA_LOAD_RESULT(questID, success)
  -- If scanning and data loaded successfully, try to process this quest
  if self.scanActive and success and C_QuestLog.IsWorldQuest(questID) and HaveQuestRewardData(questID) then
    local mapID = C_TaskQuest.GetQuestZoneID(questID)
    if mapID and GQT.Config.trackedZones[mapID] then
      self:ProcessQuest(questID, mapID)
    end
  end
end

local function SlashCommandHandler(msg)
  msg = msg and msg:lower() or ''

  if msg == '' then
    if GQT.UI.mainFrame and GQT.UI.mainFrame:IsShown() then
      GQT.UI.mainFrame:Hide()
      GQT:PreCacheQuestData()
    else
      GQT.forceRefresh = true
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
