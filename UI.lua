local addonName, GQT = ...
local icon = LibStub 'LibDBIcon-1.0'
local LDB = LibStub 'LibDataBroker-1.1'

GQT.UI = {}

function GQT.UI:ClearContent()
  local content = self.mainFrame.content
  if not content then return end
  
  local children = {}
  for i = 1, content:GetNumChildren() do
    local child = select(i, content:GetChildren())
    if child then
      table.insert(children, child)
    end
  end
  
  for _, child in ipairs(children) do
    child:Hide()
    child:SetParent(nil)
  end
  
  content:SetHeight(1)
  
  if self.mainFrame.UpdateScrollbar then
    self.mainFrame.UpdateScrollbar()
  end
end

function GQT.UI:DisplayQuests()
  if GQT.Config.debug then
    print('|cFFFFD700Gold Quest Tracker:|r Found ' .. #GQT.goldQuests .. ' gold quests.')
  end

  if #GQT.goldQuests == 0 then
    self:ShowEmptyState()
    return
  end

  table.sort(GQT.goldQuests, function(a, b)
    return a.goldReward > b.goldReward
  end)

  self:CreateMainFrame()

  self.mainFrame.title:SetText('Gold World Quests (' .. #GQT.goldQuests .. ')')

  self:ClearContent()
  local content = self.mainFrame.content

  local totalGold = 0
  for _, quest in ipairs(GQT.goldQuests) do
    totalGold = totalGold + quest.goldReward
  end

  self.mainFrame.totalGoldText:SetText('Total Gold: ' .. GQT.Utils:FormatMoney(totalGold))
  self.mainFrame.totalGoldText:Show()

  local yOffset = -10
  for i, quest in ipairs(GQT.goldQuests) do
    local questID = quest.id

    local entry = CreateFrame('Button', 'GQTQuestEntry' .. i, content, BackdropTemplateMixin and 'BackdropTemplate')
    entry:SetSize(content:GetWidth() - 20, 40)
    entry:SetPoint('TOPLEFT', content, 'TOPLEFT', 5, yOffset)

    local entryBackdrop = {
      bgFile = 'Interface\\Buttons\\WHITE8x8',
      edgeFile = 'Interface\\Buttons\\WHITE8x8',
      tile = false,
      tileSize = 0,
      edgeSize = 1,
      insets = { left = 0, right = 0, top = 0, bottom = 0 },
    }
    GQT.Utils:ApplyBackdrop(entry, entryBackdrop)
    GQT.Utils:SetBackdropColor(entry, 0.15, 0.15, 0.15, 0.7)
    GQT.Utils:SetBackdropBorderColor(entry, 0.3, 0.3, 0.3, 0.5)

    entry:SetScript('OnEnter', function(self)
      GQT.Utils:SetBackdropColor(self, 0.25, 0.25, 0.25, 0.9)
      GQT.Utils:SetBackdropBorderColor(self, 0.6, 0.6, 0.6, 0.8)

      GameTooltip:SetOwner(self, 'ANCHOR_RIGHT')
      GameTooltip:SetText(quest.title, 1, 0.8, 0)
      GameTooltip:AddLine(quest.zone, 0.7, 0.7, 1)
      GameTooltip:AddLine('Reward: ' .. GQT.Utils:FormatMoney(quest.goldReward), 1, 0.8, 0)
      GameTooltip:AddLine('Time remaining: ' .. quest.timeLeft, 1, 0.7, 0.7)
      GameTooltip:AddLine ' '
      GameTooltip:AddLine('Click to track this quest', 0, 1, 0)
      GameTooltip:Show()
    end)

    entry:SetScript('OnLeave', function(self)
      GQT.Utils:SetBackdropColor(self, 0.15, 0.15, 0.15, 0.7)
      GQT.Utils:SetBackdropBorderColor(self, 0.3, 0.3, 0.3, 0.5)
      GameTooltip:Hide()
    end)

    local title = entry:CreateFontString(nil, 'OVERLAY')
    title:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
    title:SetPoint('TOPLEFT', entry, 'TOPLEFT', 8, -5)
    title:SetText(quest.title)
    title:SetTextColor(1, 1, 1)

    local zone = entry:CreateFontString(nil, 'OVERLAY')
    zone:SetFont('Fonts\\ARIALN.TTF', 10, 'NONE')
    zone:SetPoint('BOTTOMLEFT', entry, 'BOTTOMLEFT', 8, 5)
    zone:SetText(quest.zone)
    zone:SetTextColor(0.7, 0.7, 1)

    local reward = entry:CreateFontString(nil, 'OVERLAY')
    reward:SetFont('Fonts\\FRIZQT__.TTF', 11, 'OUTLINE')
    reward:SetPoint('TOPRIGHT', entry, 'TOPRIGHT', -16, -5)
    reward:SetText(GQT.Utils:FormatMoney(quest.goldReward))
    reward:SetTextColor(1, 0.8, 0)

    local time = entry:CreateFontString(nil, 'OVERLAY')
    time:SetFont('Fonts\\ARIALN.TTF', 10, 'NONE')
    time:SetPoint('BOTTOMRIGHT', entry, 'BOTTOMRIGHT', -16, 5)
    time:SetText(quest.timeLeft)
    time:SetTextColor(1, 0.7, 0.7)

    entry:SetScript('OnMouseDown', function(self)
      GQT.Utils:SetBackdropColor(self, 0.1, 0.1, 0.1, 0.9)
    end)

    entry:SetScript('OnMouseUp', function(self)
      GQT.Utils:SetBackdropColor(self, 0.25, 0.25, 0.25, 0.9)
    end)

    entry:SetScript('OnClick', function(self)
      if questID then
        if GQT.Config.debug then
          print('|cFFFFD700Gold Quest Tracker:|r Tracking quest: ' .. quest.title .. ' (ID: ' .. questID .. ')')
        end

        C_QuestLog.AddWorldQuestWatch(questID)

        local waypoint = UiMapPoint.CreateFromCoordinates(quest.mapID, quest.location.x, quest.location.y)
        C_Map.SetUserWaypoint(waypoint)

        local r, g, b = 0.2, 0.8, 0.2
        GQT.Utils:SetBackdropColor(self, r, g, b, 0.3)

        C_Timer.After(0.3, function()
          if self:IsShown() then
            GQT.Utils:SetBackdropColor(self, 0.15, 0.15, 0.15, 0.7)
          end
        end)
      else
        print '|cFFFFD700Gold Quest Tracker:|r Unable to track quest: Missing quest ID'
      end
    end)

    yOffset = yOffset - 45
  end

  content:SetHeight(math.abs(yOffset) + 10)

  if self.mainFrame.UpdateScrollbar then
    self.mainFrame.UpdateScrollbar()
  end

  self.mainFrame:Show()
end

function GQT.UI:ShowEmptyState(loading)
  self:CreateMainFrame()

  self.mainFrame.title:SetText('Gold World Quests (0)')
  
  self.mainFrame.totalGoldText:Hide()

  self:ClearContent()
  local content = self.mainFrame.content

  local emptyFrame = CreateFrame('Frame', nil, content, BackdropTemplateMixin and 'BackdropTemplate')
  emptyFrame:SetSize(content:GetWidth() - 20, 80)
  emptyFrame:SetPoint('CENTER', content, 'CENTER', 0, 0)

  local emptyBackdrop = {
    bgFile = 'Interface\\Buttons\\WHITE8x8',
    edgeFile = 'Interface\\Buttons\\WHITE8x8',
    tile = false,
    tileSize = 0,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  }
  GQT.Utils:ApplyBackdrop(emptyFrame, emptyBackdrop)
  GQT.Utils:SetBackdropColor(emptyFrame, 0.1, 0.1, 0.1, 0.5)
  GQT.Utils:SetBackdropBorderColor(emptyFrame, 0.3, 0.3, 0.3, 0.3)

  local emptyText = emptyFrame:CreateFontString(nil, 'OVERLAY')
  emptyText:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
  emptyText:SetPoint('CENTER', emptyFrame, 'CENTER', 0, 0)
  
  if loading then
    emptyText:SetText 'Loading quest data...'
    emptyText:SetTextColor(1, 0.8, 0)
  else
    emptyText:SetText 'No gold quests found'
    emptyText:SetTextColor(0.7, 0.7, 0.7)
  end

  self.mainFrame:Show()

  content:SetHeight(100)
  if self.mainFrame.UpdateScrollbar then
    self.mainFrame.UpdateScrollbar()
  end
end

function GQT.UI:CreateMinimapIcon()
  local brokerObject = LDB:NewDataObject('GoldQuestTracker', {
    type = 'data source',
    text = 'Gold Quests',
    icon = 'Interface\\Icons\\INV_Misc_Coin_01',
    OnClick = function(_, button)
      if button == 'LeftButton' then
        if self.mainFrame and self.mainFrame:IsShown() then
          self.mainFrame:Hide()
        elseif self.mainFrame then
          GQT:ScanForGoldQuests()
          self.mainFrame:Show()
        end
      end
    end,
    OnTooltipShow = function(tooltip)
      tooltip:AddLine 'Gold Quest Tracker'
      tooltip:AddLine ' '
      tooltip:AddLine 'Left-click to scan for gold quests'
      tooltip:AddLine 'Right-click to toggle display'
    end,
  })

  icon:Register('GoldQuestTracker', brokerObject, GQT.db.minimap)
end

function GQT.UI:CreateMainFrame()
  if self.mainFrame then
    return
  end

  self.mainFrame = CreateFrame('Frame', 'GoldQuestTrackerFrame', UIParent, BackdropTemplateMixin and 'BackdropTemplate')
  self.mainFrame:SetSize(400, 250)
  self.mainFrame:SetPoint('CENTER', UIParent, 'CENTER', 0, 0)
  self.mainFrame:SetMovable(true)
  self.mainFrame:EnableMouse(true)
  self.mainFrame:RegisterForDrag 'LeftButton'
  self.mainFrame:SetScript('OnDragStart', self.mainFrame.StartMoving)
  self.mainFrame:SetScript('OnDragStop', self.mainFrame.StopMovingOrSizing)

  local mainBackdrop = {
    bgFile = 'Interface\\Buttons\\WHITE8x8',
    edgeFile = 'Interface\\Buttons\\WHITE8x8',
    tile = false,
    tileSize = 0,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  }
  GQT.Utils:ApplyBackdrop(self.mainFrame, mainBackdrop)
  GQT.Utils:SetBackdropColor(self.mainFrame, 0.1, 0.1, 0.1, 0.9)
  GQT.Utils:SetBackdropBorderColor(self.mainFrame, 0.6, 0.6, 0.6, 0.8)

  local headerBg = self.mainFrame:CreateTexture(nil, 'BACKGROUND')
  headerBg:SetPoint('TOPLEFT', 0, 0)
  headerBg:SetPoint('TOPRIGHT', 0, 0)
  headerBg:SetHeight(40)
  headerBg:SetColorTexture(0.15, 0.15, 0.15, 1)

  local closeButton = CreateFrame('Button', nil, self.mainFrame)
  closeButton:SetSize(20, 20)
  closeButton:SetPoint('TOPRIGHT', self.mainFrame, 'TOPRIGHT', -10, -10)

  closeButton.text = closeButton:CreateFontString(nil, 'OVERLAY')
  closeButton.text:SetFont('Fonts\\ARIALN.TTF', 24, 'OUTLINE')
  closeButton.text:SetPoint('CENTER', 0, 0)
  closeButton.text:SetText '×'
  closeButton.text:SetTextColor(0.7, 0.7, 0.7)

  closeButton:SetScript('OnEnter', function(self)
    self.text:SetTextColor(1, 0.3, 0.3)
  end)

  closeButton:SetScript('OnLeave', function(self)
    self.text:SetTextColor(0.7, 0.7, 0.7)
  end)

  closeButton:SetScript('OnClick', function()
    self.mainFrame:Hide()
  end)

  self.mainFrame.title = self.mainFrame:CreateFontString(nil, 'OVERLAY')
  self.mainFrame.title:SetFont('Fonts\\FRIZQT__.TTF', 14, 'OUTLINE')
  self.mainFrame.title:SetPoint('TOP', self.mainFrame, 'TOP', 0, -15)
  self.mainFrame.title:SetText 'Gold World Quests'
  self.mainFrame.title:SetTextColor(1, 0.8, 0)

  self.mainFrame.totalGoldText = self.mainFrame:CreateFontString(nil, 'OVERLAY')
  self.mainFrame.totalGoldText:SetFont('Fonts\\FRIZQT__.TTF', 12, 'OUTLINE')
  self.mainFrame.totalGoldText:SetPoint('BOTTOMRIGHT', self.mainFrame, 'BOTTOMRIGHT', -15, 15)
  self.mainFrame.totalGoldText:SetText 'Total Gold: 0g 0s 0c'
  self.mainFrame.totalGoldText:SetTextColor(1, 0.8, 0)

  local content = CreateFrame('Frame', nil, self.mainFrame)
  content:SetSize(380, 325)
  content:SetPoint('TOP', self.mainFrame.title, 'BOTTOM', 0, -10)
  content:SetPoint('BOTTOM', self.mainFrame, 'BOTTOM', 0, 50)

  local bg = content:CreateTexture(nil, 'BACKGROUND')
  bg:SetAllPoints()
  bg:SetColorTexture(0.05, 0.05, 0.05, 0.7)

  local scrollFrame = CreateFrame('ScrollFrame', nil, content)
  scrollFrame:SetPoint('TOPLEFT', content, 'TOPLEFT', 5, -5)
  scrollFrame:SetPoint('BOTTOMRIGHT', content, 'BOTTOMRIGHT', -5, 5)

  local scrollChild = CreateFrame('Frame', nil, scrollFrame)
  scrollFrame:SetScrollChild(scrollChild)
  scrollChild:SetWidth(scrollFrame:GetWidth())
  scrollChild:SetHeight(1)

  local scrollbar = CreateFrame('Slider', nil, scrollFrame, 'UIPanelScrollBarTemplate')
  scrollbar:SetPoint('TOPRIGHT', scrollFrame, 'TOPRIGHT', 20, 0)
  scrollbar:SetPoint('BOTTOMRIGHT', scrollFrame, 'BOTTOMRIGHT', 20, 0)
  scrollbar:SetMinMaxValues(0, 0)
  scrollbar:SetValueStep(1)
  scrollbar:SetValue(0)
  scrollbar:SetWidth(8)

  scrollbar.ScrollUpButton:SetSize(8, 8)
  scrollbar.ScrollDownButton:SetSize(8, 8)

  scrollbar.ThumbTexture:SetSize(8, 30)
  scrollbar.ThumbTexture:SetColorTexture(0.4, 0.4, 0.4, 0.6)

  local scrollBg = scrollbar:CreateTexture(nil, 'BACKGROUND')
  scrollBg:SetAllPoints()
  scrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.2)

  content:SetWidth(370)
  scrollFrame:SetPoint('BOTTOMRIGHT', content, 'BOTTOMRIGHT', -10, 5)
  local scrollBg = scrollbar:CreateTexture(nil, 'BACKGROUND')
  scrollBg:SetAllPoints()
  scrollBg:SetColorTexture(0.1, 0.1, 0.1, 0.4)

  scrollFrame:EnableMouseWheel(true)
  scrollFrame:SetScript('OnMouseWheel', function(_, delta)
    local current = scrollbar:GetValue()
    local min, max = scrollbar:GetMinMaxValues()

    if delta < 0 and current < max then
      scrollbar:SetValue(current + 20)
    elseif delta > 0 and current > min then
      scrollbar:SetValue(current - 20)
    end
  end)

  local function UpdateScrollbar()
    local height = scrollChild:GetHeight()
    local visible = scrollFrame:GetHeight()
    if height > visible then
      scrollbar:SetMinMaxValues(0, height - visible)
      scrollbar:Show()
    else
      scrollbar:SetMinMaxValues(0, 0)
      scrollbar:Hide()
    end
  end

  scrollChild:SetScript('OnSizeChanged', UpdateScrollbar)

  self.mainFrame.content = scrollChild
  self.mainFrame.scrollFrame = scrollFrame
  self.mainFrame.UpdateScrollbar = UpdateScrollbar

  local refreshButton = CreateFrame('Button', nil, self.mainFrame, BackdropTemplateMixin and 'BackdropTemplate')
  refreshButton:SetSize(100, 25)
  refreshButton:SetPoint('BOTTOMLEFT', self.mainFrame, 'BOTTOMLEFT', 15, 15)

  local buttonBackdrop = {
    bgFile = 'Interface\\Buttons\\WHITE8x8',
    edgeFile = 'Interface\\Buttons\\WHITE8x8',
    tile = false,
    tileSize = 0,
    edgeSize = 1,
    insets = { left = 0, right = 0, top = 0, bottom = 0 },
  }
  GQT.Utils:ApplyBackdrop(refreshButton, buttonBackdrop)
  GQT.Utils:SetBackdropColor(refreshButton, 0.2, 0.2, 0.2, 1)
  GQT.Utils:SetBackdropBorderColor(refreshButton, 0.7, 0.7, 0.7, 0.8)

  local btnText = refreshButton:CreateFontString(nil, 'OVERLAY')
  btnText:SetFont('Fonts\\FRIZQT__.TTF', 10, 'OUTLINE')
  btnText:SetPoint('CENTER', 0, 0)
  btnText:SetText 'Refresh'
  btnText:SetTextColor(0.9, 0.9, 0.9)

  refreshButton:SetScript('OnEnter', function(self)
    GQT.Utils:SetBackdropColor(self, 0.3, 0.3, 0.3, 1)
    btnText:SetTextColor(1, 1, 1)
  end)

  refreshButton:SetScript('OnLeave', function(self)
    GQT.Utils:SetBackdropColor(self, 0.2, 0.2, 0.2, 1)
    btnText:SetTextColor(0.9, 0.9, 0.9)
  end)

  refreshButton:SetScript('OnClick', function()
    GQT:ClearCache()
    GQT.lastScanTime = 0
    GQT:ScanForGoldQuests()
  end)

  self.mainFrame:Hide()
end
