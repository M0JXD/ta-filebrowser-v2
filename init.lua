-- Copyright 2007-2021 Mitchell. See LICENSE.
-- Copyright 2025 Jamie Drinkell. MIT License.

local M = {}

--[[ This comment is for LuaDoc.
---
-- Text-based file browser for the textadept module.
-- Pressing the spacebar activates the item on the current line.
-- Other keys are: 'p' and 'n' to navigate up or down by item, 'P' and 'N' to
-- navigate up or down by level, and 'f' and 'b' to navigate within a directory
-- by its first and last files.
module('file_browser')]]

---
-- Map of directory paths to filters used by the file browser.
-- @class table
-- @name dir_filters
M.dir_filters = {}
-- Configurable options
M.hide_dot_folders = false
M.hide_dot_files = false
M.force_folders_first = false
M.case_insensitive_sort = false
M.strip_leading_path = false

local current_dir

-- Change "keyword", "annotation" and "default" to adjust colours
-- You can find options under "Tags" in the API manual
local function highlight_folder(start_line)
  if not (buffer._type or ''):match('^%[File Browser') then return end
  local expanded_style = buffer:style_of_name('keyword')
  local collapsed_style = buffer:style_of_name('annotation')

  for i = start_line and start_line or 1, buffer.line_count do
    local line = buffer:get_line(i)
    if line:find('[/\\][\r\n]*$') then
      -- Folder detected
      local is_expanded = buffer.line_indentation[i + 1] > buffer.line_indentation[i]
      local style = is_expanded and expanded_style or collapsed_style
      buffer:start_styling(buffer:position_from_line(i), 0)
      buffer:set_styling(#line, style)
    else
      -- Files are unstyled
      buffer:start_styling(buffer:position_from_line(i), 0)
      buffer:set_styling(#line, buffer:style_of_name('default'))
    end
  end
end


-- Prints a styled list of the contents of directory path *dir*.
local function print_listing(dir)
  buffer.read_only = false

  -- Retrieve listing for dir.
  local listing = {}
  for path in lfs.walk(dir, buffer._filter, 0, true) do
    listing[#listing + 1] = path
  end

  -- Case-insensitive sorting function
  local function case_insensitive_sort_fn(a, b)
    return a:lower() < b:lower()
  end

  -- Sort the entire list of files and folders first if case_insensitive_sort is enabled
  if M.case_insensitive_sort then
    table.sort(listing, case_insensitive_sort_fn)
  else
    table.sort(listing)
  end

  -- Separate folders and files after sorting
  local folders = {}
  local files = {}

  -- Split into folders and files
  for _, path in ipairs(listing) do
    if path:sub(-1, -1) == '/' then
      table.insert(folders, path)
    else
      table.insert(files, path)
    end
  end

  -- Final listing will be folders first or combined depending on `force_folders_first`
  local final_listing = {}

  if M.force_folders_first then
    -- Move folders first
    for _, folder in ipairs(folders) do
      -- Skip dot folders if configured to hide them
      if M.hide_dot_folders and folder:match("/%..*") then
        -- Skip dot folder
      else
        table.insert(final_listing, folder)
      end
    end
    -- Then append files
    for _, file in ipairs(files) do
      -- Skip dot files if configured to hide them
      if M.hide_dot_files and file:match("/%..*") then
        -- Skip dot file
      else
        table.insert(final_listing, file)
      end
    end
  else
    -- Use the original `listing` for non-folder-first order and apply hiding of dot files/folders
    for _, path in ipairs(listing) do
      if path:sub(-1, -1) == '/' then
        -- Folder handling: Skip dot folders if configured to hide them
        if M.hide_dot_folders and path:match("/%..*") then
          -- Skip dot folder
        else
          table.insert(final_listing, path)
        end
      else
        -- File handling: Skip dot files if configured to hide them
        if M.hide_dot_files and path:match("/%..*") then
          -- Skip dot file
        else
          table.insert(final_listing, path)
        end
      end
    end
  end

  -- Print listing for dir, styling directories, symlinks, etc.
  local line_num = buffer:line_from_position(buffer.current_pos)
  local indent = buffer.line_indentation[line_num] + buffer.tab_width
  
  -- Iterate through the final listing and apply the configured filters
  for i = 1, #final_listing do
    local path = final_listing[i]
    local name = path:match('[^/\\]*[/\\]?$')

    buffer:insert_text(buffer.line_end_position[line_num + i - 1], '\n')
    buffer.line_indentation[line_num + i] = indent
    local pos = buffer.line_indent_position[line_num + i]
    buffer:insert_text(pos, name)
  end

  buffer.read_only = true
  buffer:set_save_point()
  highlight_folder(line_num)
end

---
-- Displays a textual file browser for a directory.
-- Files shown in the browser do not match any pattern in either string or table
-- *filter* (lfs.default_filter if *filter* is nil). A filter table contains
-- lUa patterns that match filenames to exclude, an optional folders sub-table
-- that contains patterns matching directories to exclude, and an optional
-- extensions sub-table that contains raw file extensions to exclude. Any
-- patterns starting with '!' exclude files and directories that do not match
-- the pattern that follows.
-- @param dir Directory to show initially. The user is prompted for one if none
--   is given.
-- @param filter Optional filter for files and directories to exclude. The
--   default value comes from M.dir_filters.
-- @name init
function M.init(dir, filter)
  dir = dir or ui.dialogs.open{
    title = 'Open Directory', only_dirs = true
  }
  if not dir then return end
  if not filter then filter = M.dir_filters[dir] end
  if #_VIEWS == 1 then ui.goto_view(view:split(true)) end
  local buffer = buffer.new()
  
  local dir_path
  if M.strip_leading_path then
    dir_path = dir:match('[^/\\]+[/\\]?$')
  else
    dir_path = dir
  end
  
  buffer._type = string.format(
    '[File Browser - %s%s]', dir_path, not WIN32 and '/' or '\\')
  buffer._filter = filter
  buffer:insert_text(-1, dir_path .. (not WIN32 and '/' or '\\'))
  print_listing(dir)
  lfs.chdir(dir) -- for features like io.get_project_root()
end

local function raw_init(dir)
  buffer._filter = M.dir_filters[dir]
  buffer:insert_text(-1, dir)
  print_listing(dir)
end

-- Returns the full path of the file on line number *line_num*.
-- @param line_num The line number of the file to get the full path of.
local function get_path(line_num)
  -- Determine parent directories of the tail all the way up to the root.
  -- Subdirectories are indented.
  local parts = {}
  local indent = buffer.line_indentation[line_num]
  local level = indent
  for i = line_num, 1, -1 do
    local j = buffer.line_indentation[i]
    if j < level then
      table.insert(parts, 1, buffer:get_line(i):match('^%s*([^\r\n]+)'))
      level = j
    end
    if j == 0 then break end
  end
  parts[#parts + 1] = buffer:get_line(line_num):match('^%s*([^\r\n]+)')
  return table.concat(parts)
end

-- Expand/contract directory or open file.
events.connect('char_added', function(code)
  if not (buffer._type or ''):match('^%[File Browser.-%]') or
     not buffer.read_only then
    return
  end
  local line_num = buffer:line_from_position(buffer.current_pos)
  local indent = buffer.line_indentation[line_num]
  if code == string.byte(' ') then
    -- Open/Close the directory or open the file.
    local path = get_path(line_num)
    if path:sub(-1, -1) == (not WIN32 and '/' or '\\') then
      if buffer.line_indentation[line_num + 1] <= indent then
        print_listing(path)
      else
        -- Collapse directory contents.
        local first_visible_line = buffer.first_visible_line
        local s, e = buffer:position_from_line(line_num + 1), nil
        level = indent
        for i = line_num + 1, buffer.line_count do
          if buffer:get_line(i):match('^[^\r\n]') and
             buffer.line_indentation[i] <= indent then break end
          e = buffer:position_from_line(i + 1)
        end
        buffer.read_only = false
        buffer:set_sel(s, e)
        buffer:replace_sel('')
        buffer.read_only = true
        buffer:set_save_point()
        buffer:line_up()
        buffer:line_scroll(0, first_visible_line - buffer.first_visible_line)
        highlight_folder(line_num)
      end
    else
      -- Open file in a new split or other existing split.
      if #_VIEWS == 1 then
        _, new_view = view:split(true)
        ui.goto_view(new_view)
      else
        for i, other_view in ipairs(_VIEWS) do
          if view ~= other_view then ui.goto_view(other_view) break end
        end
      end
      io.open_file(path)
    end
  elseif code == string.byte('n') then
    buffer:line_down()
  elseif code == string.byte('p') then
    buffer:line_up()
  elseif code == string.byte('N') then
    for i = line_num + 1, buffer.line_count do
      buffer:line_down()
      if buffer.line_indentation[i] <= indent then break end
    end
  elseif code == string.byte('P') then
    for i = line_num - 1, 1, -1 do
      buffer:line_up()
      if buffer.line_indentation[i] <= indent then break end
    end
  elseif code == string.byte('f') then
    for i = line_num + 1, buffer.line_count do
      if buffer.line_indentation[i] < indent then break end
      buffer:line_down()
    end
  elseif code == string.byte('b') then
    for i = line_num - 1, 1, -1 do
      if buffer.line_indentation[i] < indent then break end
      buffer:line_up()
    end
  end
end)

-- Initialize when restoring a File Browser session
-- Note that stripping leading path breaks this functionality!!
events.connect(events.FILE_OPENED, function (filename)
  if filename then
    local filepath = filename:match('^%[File Browser %- (.+)%]$')
    if filepath then raw_init(filepath) end
  end
end)

events.connect(events.BUFFER_AFTER_SWITCH, highlight_folder)
events.connect(events.VIEW_AFTER_SWITCH, highlight_folder)

return M
