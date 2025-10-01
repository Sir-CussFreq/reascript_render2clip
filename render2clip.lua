--[[
DSG_Render time selection → Clipboard (with optional verification)
Author: ChatGPT
Behavior:
  - Renders ONLY the current time selection from selected tracks (or all, if none) by routing to a temp bus.
  - Copies the rendered item to the clipboard.
  - Cleans up temp tracks/routes. Originals untouched.
  - Optional VERIFY_PASTE: test-pastes onto a scratch track, then undoes it (clipboard preserved).

Requirements: None. (SWS optional; used if present to unselect folder children.)
-- Original script authors: DSG / X-Raym (ReaTeam ReaScripts)
]]

-- ======= user toggles =======
local VERIFY_PASTE = false       -- set true to sanity-check the clipboard copy (undo-safe)
local STEM_ACTION = 41716        -- Track: Render selected area of tracks to stereo post-fader stem tracks (and mute originals)
-- ============================

local function has_time_sel()
  local s, e = reaper.GetSet_LoopTimeRange(false, false, 0, 0, false)
  return s < e
end

local function ensure_tracks_selected_or_all()
  if reaper.CountSelectedTracks(0) == 0 then
    reaper.Main_OnCommand(40296, 0) -- Track: Select all tracks
  end
end

local function list_selected_tracks()
  local t = {}
  for i = 0, reaper.CountSelectedTracks(0) - 1 do
    t[#t + 1] = reaper.GetSelectedTrack(0, i)
  end
  return t
end

local function create_temp_track(name)
  local idx = reaper.CountTracks(0)
  reaper.InsertTrackAtIndex(idx, true)
  local tr = reaper.GetTrack(0, idx)
  if name then reaper.GetSetMediaTrackInfo_String(tr, "P_NAME", name, true) end
  return tr
end

local function create_sends(src_tracks, to_track)
  for _, tr in ipairs(src_tracks) do
    reaper.CreateTrackSend(tr, to_track)
  end
end

local function remove_all_sends(track)
  local n = reaper.GetTrackNumSends(track, 0)
  for s = n - 1, 0, -1 do
    reaper.RemoveTrackSend(track, 0, s)
  end
end

local function first_item_on_track(track) return reaper.GetTrackMediaItem(track, 0) end

local function err_abort(msg)
  reaper.ShowMessageBox(msg, "DSG_Render", 0)
end

-- Action constants
local ACT_ITEM_UNSEL_ALL     = 40289 -- Item: Unselect all items
local ACT_ITEM_COPY          = 40698 -- Item: Copy items
local ACT_DELETE_TRACKS      = 40005 -- Track: Remove tracks
local ACT_TRACK_SEL_NONE     = 40297 -- Track: Unselect all tracks
local ACT_SCROLL_SEL_INTO    = 40913 -- Track: Vertical scroll selected tracks into view
local ACT_EDIT_CURSOR_END    = 40042 -- Go to end of project
local ACT_ITEM_PASTE         = 40058 -- Item: Paste items/tracks
local ACT_EDIT_UNDO          = 40029 -- Edit: Undo

reaper.Undo_BeginBlock()
reaper.PreventUIRefresh(1)

local ok, msg = true, ""

repeat
  if not has_time_sel() then ok=false; msg="No time selection."; break end

  -- Optional SWS nicety: unselect children of selected folders
  local sws_unsel_children = reaper.NamedCommandLookup("_SWS_UNSELCHILDREN")
  if sws_unsel_children ~= 0 then reaper.Main_OnCommand(sws_unsel_children, 0) end

  ensure_tracks_selected_or_all()
  local sources = list_selected_tracks()
  if #sources == 0 then ok=false; msg="No tracks available to render."; break end

  -- Build temp bus and route
  local bus = create_temp_track("DSG_Render_TMP_BUS")
  create_sends(sources, bus)

  -- Render post-fader of the bus over the time selection to a new stem track
  reaper.SetOnlyTrackSelected(bus, true)
  reaper.Main_OnCommand(STEM_ACTION, 0)

  -- The stem track should now be selected
  local stem = reaper.GetSelectedTrack(0, 0)
  if not stem then ok=false; msg="Could not find rendered stem track."; break end

  -- Select its media item and copy
  reaper.Main_OnCommand(ACT_ITEM_UNSEL_ALL, 0)
  local it = first_item_on_track(stem)
  if not it then ok=false; msg="Rendered stem has no item."; break end
  reaper.SetMediaItemInfo_Value(it, "B_UISEL", 1)
  reaper.UpdateArrange()
  reaper.Main_OnCommand(ACT_ITEM_COPY, 0)

  -- Optional: verify clipboard by paste/undo on a scratch track
  if VERIFY_PASTE then
    local verify_tr = create_temp_track("DSG_Render_VERIFY")
    reaper.SetOnlyTrackSelected(verify_tr, true)
    -- paste at project end to avoid collisions
    reaper.Main_OnCommand(ACT_EDIT_CURSOR_END, 0)
    reaper.Main_OnCommand(ACT_ITEM_PASTE, 0)
    -- quick sanity: expect at least 1 item on verify track
    local pasted = first_item_on_track(verify_tr)
    if not pasted then ok=false; msg="Clipboard paste verification failed."; end
    -- Undo the paste to keep the project clean, then delete verify track
    reaper.Main_OnCommand(ACT_EDIT_UNDO, 0)
    reaper.SetOnlyTrackSelected(verify_tr, true)
    reaper.Main_OnCommand(ACT_DELETE_TRACKS, 0)
    if not ok then break end
  end

  -- Cleanup temp stem + bus
  reaper.SetOnlyTrackSelected(stem, true)
  reaper.Main_OnCommand(ACT_DELETE_TRACKS, 0)

  remove_all_sends(bus)
  reaper.SetOnlyTrackSelected(bus, true)
  reaper.Main_OnCommand(ACT_DELETE_TRACKS, 0)

  -- Restore a tidy view
  reaper.Main_OnCommand(ACT_TRACK_SEL_NONE, 0)
  reaper.Main_OnCommand(ACT_SCROLL_SEL_INTO, 0)

until true

reaper.PreventUIRefresh(-1)
reaper.UpdateArrange()
if ok then
  reaper.Undo_EndBlock("DSG_Render time selection → Clipboard", -1)
else
  reaper.Undo_EndBlock("DSG_Render time selection → Clipboard (aborted)", -1)
  err_abort(msg)
end
